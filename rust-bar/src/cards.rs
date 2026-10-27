//! The strip's dropdown cards (DropdownWidget + CardSurface + CardKeys).
//!
//! The QML card is a full-screen transparent layer surface with the card drawn
//! in it. Here the card is a layer surface of the card's own size - mango fades
//! layers in and out, which looks the same either way - and a full-screen
//! "catcher" backed by one transparent pixel (wp_viewporter) takes the click
//! outside it. A full-screen buffer per card was ~15 MB; this is a few KB plus
//! the card.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use smithay_client_toolkit::{
    reexports::protocols::wp::viewporter::client::wp_viewport::WpViewport,
    seat::keyboard::Keysym,
    shell::{
        wlr_layer::{Anchor, KeyboardInteractivity, Layer, LayerSurface},
        WaylandSurface,
    },
    shm::slot::SlotPool,
};
use wayland_client::protocol::wl_shm;

use crate::anim::{Animated, Easing};
use crate::app::{App, Win, WinRef};
use crate::bar::{ac, Action, Hit};
use crate::color::Color;
use crate::gpu::{Gpu, Scene, TextStyle};
use crate::services::{self, Services};
use crate::text::{Fonts, Line};
use crate::theme::{self, Theme, FONT_SIZE};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CardKind {
    Power,
    Calendar,
    Weather,
    Audio,
    Pult,
    Vpn,
    Agent,
}

/// A fixed origin for animations that run on the clock (Spinner).
pub static EPOCH: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();

#[derive(Clone, Copy, PartialEq, Eq)]
enum Stem {
    Left,
    Center,
    Right,
}

pub struct Catcher {
    pub layer: LayerSurface,
    viewport: Option<WpViewport>,
    pool: Option<SlotPool>,
}

pub struct OpenCard {
    pub kind: CardKind,
    pub strip: usize,
    pub win: Win,
    pub catcher: Catcher,
    pub hits: Vec<Hit>,
    pub pointer: Option<(f32, f32)>,
    pub shift: bool,
    /// Index into the card's focus chain (CardKeys), None = nothing focused.
    pub(crate) focus: Option<usize>,
    /// The focus chain of the last draw: each focusable control's code.
    pub(crate) focus_codes: Vec<u32>,
    width: f32,
    height: f32,
    /// x of the stem's centre inside the card.
    stem_cx: f32,
    stem_w: f32,
    notch: Option<(u32, u32, u32, i32)>,
    colors: HashMap<u32, Animated<Color>>,
    /// Calendar: the month shown (year, month 1-12) and the wheel's remainder.
    month: (i32, u32),
    wheel_acc: f32,
    /// Sliders of the last draw: (code, x, width, maximum).
    pub(crate) sliders: Vec<(u32, f32, f32, f32)>,
    /// LevelMeter: (level, hold, hold ticks left).
    pub(crate) meter: (f32, f32, i32),
    /// ConsoleButton.tint for the next button: colAlert (the mute buttons).
    pub(crate) tint_alert: bool,
    numbers: HashMap<u32, Animated<f32>>,
    /// Flickable.contentY and the content height.
    scroll: f32,
    content_h: f32,
    notch_stale: bool,
    /// The card's x on screen is fractional in QML (the icon centre is); the
    /// surface sits at the whole pixel and the content is drawn this far in.
    frac: f32,
}

impl OpenCard {
    /// The palette changed: repaint the notch in the new colBg.
    pub fn invalidate_notch(&mut self) {
        self.notch_stale = true;
    }

    /// An animated number (Behavior on opacity { NumberAnimation }).
    pub(crate) fn number(&mut self, id: u32, target: f32, ms: u64, now: Instant) -> (f32, bool) {
        let a = self.numbers.entry(id).or_insert_with(|| Animated::new(target, ms, Easing::Linear));
        a.set(target, now);
        (a.get(now), a.running(now))
    }

    /// A control's animated colour (Behavior on color { ColorAnimation { duration } }).
    pub(crate) fn color(&mut self, id: u32, target: Color, ms: u64, now: Instant) -> (Color, bool) {
        let a = self.colors.entry(id).or_insert_with(|| Animated::new(target, ms, Easing::Linear));
        a.set(target, now);
        (a.get(now), a.running(now))
    }
}

const STEM_H: f32 = 12.0;
const NOTCH_R: f32 = 10.0;
const CARD_R: f32 = 12.0;

/// popupWidth, popupHeight, stem alignment of each card.
fn geometry(kind: CardKind) -> (f32, f32, Stem) {
    match kind {
        // PowerWidget: 210 wide; four 42 px buttons, spacing 6, + 28.
        CardKind::Power => (210.0, (4.0 * 42.0 + 3.0 * 6.0f32).ceil() + 28.0, Stem::Left),
        // CalendarPopup: 400 wide; header 38 + 8 + plate (8 + 24 + 4 + 240 + 8) + 12 + 24.
        CardKind::Calendar => (400.0, 38.0 + 8.0 + 284.0 + 12.0 + 24.0, Stem::Center),
        // CenterInfo's weather card: 340 wide, its height is measured from the content.
        CardKind::Weather => (340.0, 0.0, Stem::Center),
        // VolumeWidget: 330 wide, max(120, min(content + 30, 560)) high.
        CardKind::Audio => (330.0, 0.0, Stem::Center),
        // PultWidget: 360 wide, content + 28 high, stem on the right.
        CardKind::Pult => (360.0, 0.0, Stem::Right),
        // VpnWidget: 260 wide, content + 28 high.
        CardKind::Vpn => (260.0, 0.0, Stem::Center),
        // AgentWidget: 420 wide, max(160, min(content + 30, 85% of the screen)).
        CardKind::Agent => (420.0, 0.0, Stem::Center),
    }
}

pub fn toggle(app: &mut App, strip: usize, kind: CardKind, icon: &Hit, keyboard: bool) {
    let was = app.card.as_ref().map(|c| (c.kind, c.strip));
    close(app);
    if was == Some((kind, strip)) {
        return;
    }
    open(app, strip, kind, icon, keyboard);
}

fn open(app: &mut App, strip: usize, kind: CardKind, icon: &Hit, keyboard: bool) {
    let s = &app.strips[strip];
    let ui = crate::bar::ui_scale(s.screen_width);
    let (w, mut h, stem) = geometry(kind);
    if kind == CardKind::Weather {
        h = weather_height(&mut app.fonts, &app.svc, w);
    }
    let mut content_h = 0.0;
    if kind == CardKind::Audio {
        if let Some(pw) = app.svc.pw.as_mut() {
            pw.track_all(true);
            let src = pw.source().1.map(|n| n.id);
            pw.monitor_peak(src);
            pw.dispatch();
        }
        content_h = crate::audio_card::content_height(&mut app.fonts, &app.svc);
        h = 120f32.max((content_h.ceil() + 30.0).min(560.0));
        app.every(Duration::from_millis(33), crate::audio_card::meter_tick);
    }
    if kind == CardKind::Pult {
        let scanning = crate::pult::scanning(app);
        h = crate::pult::card_height(&mut app.fonts, &app.svc, scanning);
    }
    if kind == CardKind::Vpn {
        h = crate::vpn::card_height(&mut app.fonts, &app.svc);
    }
    if kind == CardKind::Agent {
        content_h = crate::agent::content_height(&mut app.fonts, &app.svc, w, false);
        h = 160f32.max((content_h.ceil() + 30.0).min(s.screen_height * 0.85));
    }
    // DropdownWidget.cardX: from the icon's centre on the screen.
    let icon_w = icon.w / ui;
    let icon_center = icon.x + icon.w / 2.0;
    let mut stem_w = (icon_w + 16.0).floor().min(w - 60.0);
    let mut card_x = match stem {
        Stem::Right => icon_center - w + stem_w / 2.0 + 10.0,
        Stem::Left => icon_center - stem_w / 2.0 - 10.0,
        Stem::Center => icon_center - w / 2.0,
    };
    if kind == CardKind::Calendar {
        // CalendarPopup: a fixed 60 px stem, cardX = anchorX (int) - 200.
        stem_w = 60.0;
        card_x = icon_center.trunc() - 200.0;
    }
    if kind == CardKind::Weather {
        // The stem is the weather pill's width (int); centred on the pill.
        stem_w = icon_w.trunc();
        card_x = icon_center - w / 2.0;
    }
    let x = card_x.min(s.screen_width - w).max(0.0);
    let y = crate::bar::strip_height(s.screen_width) as f32 + 2.0;
    let stem_cx = match stem {
        Stem::Right => w - stem_w / 2.0 - 10.0,
        Stem::Left => stem_w / 2.0 + 10.0,
        Stem::Center => w / 2.0,
    };
    let output = s.output.clone();

    // The catcher first, so the card stacks above it.
    let surface = app.compositor.create_surface(&app.qh);
    let catcher = app.layer_shell.create_layer_surface(&app.qh, surface, Layer::Top, Some("rust-bar:catcher"), Some(&output));
    catcher.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
    catcher.set_exclusive_zone(-1);
    catcher.set_keyboard_interactivity(KeyboardInteractivity::None);
    catcher.commit();

    let surface = app.compositor.create_surface(&app.qh);
    let layer = app.layer_shell.create_layer_surface(&app.qh, surface, Layer::Top, Some("quickshell:card"), Some(&output));
    // QML's card x can be fractional, but it lands on whole pixels (measured).
    let x = x.round();
    let frac = 0.0f32;
    let sw = (w + frac).ceil() as u32;
    layer.set_anchor(Anchor::TOP | Anchor::LEFT);
    layer.set_margin(y.round() as i32, 0, 0, x.floor() as i32);
    layer.set_size(sw, h as u32);
    layer.set_exclusive_zone(-1);
    layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
    layer.commit();

    app.card = Some(OpenCard {
        kind,
        strip,
        win: Win::new(layer, sw, h as u32),
        catcher: Catcher { layer: catcher, viewport: None, pool: None },
        hits: Vec::new(),
        pointer: None,
        shift: false,
        focus: if keyboard { Some(0) } else { None },
        focus_codes: Vec::new(),
        width: w,
        height: h,
        stem_cx,
        stem_w,
        notch: None,
        colors: HashMap::new(),
        month: { let (y, m, _) = crate::cal::today(); (y, m) },
        wheel_acc: 0.0,
        sliders: Vec::new(),
        meter: (0.0, 0.0, 0),
        tint_alert: false,
        numbers: HashMap::new(),
        scroll: 0.0,
        content_h,
        frac,
        notch_stale: false,
    });
    app.strips[strip].win.dirty = true;
    if kind == CardKind::Pult {
        crate::pult::opened(app);
    }
    if kind == CardKind::Vpn {
        crate::vpn::opened(app);
    }
    if kind == CardKind::Agent {
        crate::agent::opened(app);
    }
}

pub fn close(app: &mut App) {
    if app.card.as_ref().map(|c| c.kind) == Some(CardKind::Pult) {
        crate::pult::closed(app);
    }
    let Some(card) = app.card.take() else { return };
    if card.kind == CardKind::Audio {
        if let Some(pw) = app.svc.pw.as_mut() {
            pw.track_all(false);
            pw.monitor_peak(None);
        }
    }
    if let (Some(gpu), Some((id, ..))) = (app.gpu.as_mut(), card.notch) {
        gpu.drop_image(id);
    }
    if let Some(s) = app.strips.get_mut(card.strip) {
        s.win.dirty = true;
    }
    drop(card);
    // Freed card memory goes back to the system now, not at the next allocation.
    unsafe { libc::malloc_trim(0) };
}

/// A card whose height is a binding (the lists in it change): resize the
/// surface when the content asks for a different height.
pub fn update_height(app: &mut App) {
    let Some(card) = app.card.as_ref() else { return };
    let h = match card.kind {
        CardKind::Pult => {
            let scanning = crate::pult::scanning(app);
            crate::pult::card_height(&mut app.fonts, &app.svc, scanning)
        }
        CardKind::Vpn => crate::vpn::card_height(&mut app.fonts, &app.svc),
        CardKind::Agent => {
            let busy = app.is_running("agent-usage");
            let w = app.card.as_ref().unwrap().width;
            let screen_h = app.strips.get(app.card.as_ref().unwrap().strip).map_or(1440.0, |s| s.screen_height);
            let content = crate::agent::content_height(&mut app.fonts, &app.svc, w, busy);
            if let Some(c) = app.card.as_mut() {
                c.content_h = content;
            }
            160f32.max((content.ceil() + 30.0).min(screen_h * 0.85))
        }
        CardKind::Audio => {
            let content = crate::audio_card::content_height(&mut app.fonts, &app.svc);
            if let Some(c) = app.card.as_mut() {
                c.content_h = content;
            }
            120f32.max((content.ceil() + 30.0).min(560.0))
        }
        _ => return,
    };
    let card = app.card.as_mut().unwrap();
    if (h - card.height).abs() < 0.5 {
        return;
    }
    card.height = h;
    card.win.layer.set_size(card.win.width, h as u32);
    card.win.layer.commit();
}

/// The catcher's one transparent pixel, stretched over the screen.
pub fn configure_catcher(app: &mut App, size: (u32, u32)) {
    let (Some(card), Some(vp)) = (app.card.as_mut(), app.viewporter.as_ref()) else { return };
    let c = &mut card.catcher;
    if c.pool.is_none() {
        c.pool = SlotPool::new(4, &app.shm).ok();
    }
    let Some(pool) = c.pool.as_mut() else { return };
    let Ok((buffer, canvas)) = pool.create_buffer(1, 1, 4, wl_shm::Format::Argb8888) else { return };
    canvas.fill(0);
    let wl = c.layer.wl_surface();
    if c.viewport.is_none() {
        c.viewport = Some(vp.get_viewport(wl, &app.qh, ()));
    }
    c.viewport.as_ref().unwrap().set_destination(size.0.max(1) as i32, size.1.max(1) as i32);
    let _ = buffer.attach_to(wl);
    wl.damage_buffer(0, 0, 1, 1);
    c.layer.commit();
}

// ---- drawing ----

/// The card outline, as DropdownWidget's Canvas paints it: HTML canvas
/// arcTo corners, filled with Theme.colBg, anti-aliased like QPainter.
fn notch_mask(w: f32, h: f32, cx: f32, sw: f32) -> (Vec<u8>, u32, u32) {
    let mut p = CanvasPath::default();
    let (sh, nr, r) = (STEM_H, NOTCH_R, CARD_R);
    let (sl, sr) = (cx - sw / 2.0, cx + sw / 2.0);
    p.move_to(sl + r, 0.0);
    p.line_to(sr - r, 0.0);
    p.arc_to(sr, 0.0, sr, r, r);
    p.line_to(sr, sh - nr);
    p.arc_to(sr, sh, sr + nr, sh, nr);
    p.line_to(w - r, sh);
    p.arc_to(w, sh, w, sh + r, r);
    p.line_to(w, h - r);
    p.arc_to(w, h, w - r, h, r);
    p.line_to(r, h);
    p.arc_to(0.0, h, 0.0, h - r, r);
    p.line_to(0.0, sh + r);
    p.arc_to(0.0, sh, r, sh, r);
    p.line_to(sl - nr, sh);
    p.arc_to(sl, sh, sl, sh - nr, nr);
    p.line_to(sl, r);
    p.arc_to(sl, 0.0, sl + r, 0.0, r);
    p.close();
    let (iw, ih) = (w.ceil() as u32, h.ceil() as u32);
    let mut mask = vec![0u8; (iw * ih) as usize];
    zeno::Mask::new(&p.cmds[..]).size(iw, ih).style(zeno::Fill::NonZero).render_into(&mut mask, None);
    (mask, iw, ih)
}

#[derive(Default)]
struct CanvasPath {
    cmds: Vec<zeno::Command>,
    cur: (f32, f32),
}

impl CanvasPath {
    fn move_to(&mut self, x: f32, y: f32) {
        self.cmds.push(zeno::Command::MoveTo([x, y].into()));
        self.cur = (x, y);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.cmds.push(zeno::Command::LineTo([x, y].into()));
        self.cur = (x, y);
    }
    fn close(&mut self) {
        self.cmds.push(zeno::Command::Close);
    }
    /// CanvasRenderingContext2D.arcTo: a line to the first tangent point, then
    /// the arc of radius r tangent to both lines, as a cubic (QPainterPath's
    /// approximation for a quarter turn).
    fn arc_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, r: f32) {
        let (x0, y0) = self.cur;
        let v1 = (x0 - x1, y0 - y1);
        let v2 = (x2 - x1, y2 - y1);
        let (l1, l2) = (v1.0.hypot(v1.1), v2.0.hypot(v2.1));
        let cross = v1.0 * v2.1 - v1.1 * v2.0;
        if r == 0.0 || l1 == 0.0 || l2 == 0.0 || cross.abs() < 1e-6 {
            self.line_to(x1, y1);
            return;
        }
        let (u1, u2) = ((v1.0 / l1, v1.1 / l1), (v2.0 / l2, v2.1 / l2));
        let cos = (u1.0 * u2.0 + u1.1 * u2.1).clamp(-1.0, 1.0);
        let theta = cos.acos();
        let d = r / (theta / 2.0).tan();
        let t1 = (x1 + u1.0 * d, y1 + u1.1 * d);
        let t2 = (x1 + u2.0 * d, y1 + u2.1 * d);
        self.line_to(t1.0, t1.1);
        let sweep = std::f32::consts::PI - theta;
        let k = 4.0 / 3.0 * (sweep / 4.0).tan() * r;
        let c1 = (t1.0 - u1.0 * k, t1.1 - u1.1 * k);
        let c2 = (t2.0 - u2.0 * k, t2.1 - u2.1 * k);
        self.cmds.push(zeno::Command::CurveTo([c1.0, c1.1].into(), [c2.0, c2.1].into(), [t2.0, t2.1].into()));
        self.cur = t2;
    }
}

pub(crate) struct Ui<'a> {
    pub card: &'a mut OpenCard,
    pub scene: &'a mut Scene,
    pub fonts: &'a mut Fonts,
    pub theme: &'a Theme,
    pub now: Instant,
    pub animating: bool,
    pub hits: Vec<Hit>,
    pub focus_codes: Vec<u32>,
}

impl Ui<'_> {
    pub fn hovered(&self, x: f32, y: f32, w: f32, h: f32) -> bool {
        self.card.pointer.map_or(false, |(px, py)| px >= x && px < x + w && py >= y && py < y + h)
    }

    /// Adds a control to the focus chain (activeFocusOnTab); true if it has focus.
    pub fn focusable(&mut self, code: u32) -> bool {
        let i = self.focus_codes.len();
        self.focus_codes.push(code);
        self.card.focus == Some(i)
    }

    pub fn text(&mut self, line: &Line, x: f32, y: f32, color: Color, style: TextStyle) {
        self.scene.text(self.fonts, line, x, y + line.ascent, color, style);
    }

    /// ConsoleButton: a key on the console - plate colour, white focus ring,
    /// shadow lip, icon + bold caption centred one pixel high.
    #[allow(clippy::too_many_arguments)]
    pub fn console_button(&mut self, id: u32, x: f32, y: f32, w: f32, icon: &str, icon_color: Color, label: &str, current: bool) {
        self.console_button_sized(id, x, y, w, FONT_SIZE - 4.0, icon, icon_color, label, current);
    }

    /// ConsoleButton.implicitWidth: max(minWidth, face + 26).
    pub fn console_button_width(&mut self, font: f32, icon: &str, label: &str, min_width: f32) -> f32 {
        let icon_box = font + 2.0;
        let cap = if label.is_empty() { 0.0 } else { self.fonts.layout(label, theme::bar_font(true), font, 0.0).width };
        let face = match (icon.is_empty(), label.is_empty()) {
            (true, _) => cap,
            (false, true) => icon_box,
            (false, false) => icon_box + 6.0 + cap,
        };
        min_width.max(face + 26.0)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn console_button_sized(&mut self, id: u32, x: f32, y: f32, w: f32, font: f32, icon: &str, icon_color: Color, label: &str, current: bool) {
        self.console_button_ex(id, x, y, w, font, icon, icon_color, label, current, false, true);
    }

    /// ConsoleButton with busy (a Spinner where the icon is) and enabled
    /// (opacity .45, not in the focus chain, not clickable).
    #[allow(clippy::too_many_arguments)]
    pub fn console_button_ex(&mut self, id: u32, x: f32, y: f32, w: f32, font: f32, icon: &str, icon_color: Color, label: &str, current: bool, busy: bool, enabled: bool) {
        self.scene.save();
        if !enabled {
            self.scene.multiply_opacity(0.45);
        }
        self.console_button_inner(id, x, y, w, font, icon, icon_color, label, current, busy, enabled);
        self.scene.restore();
    }

    #[allow(clippy::too_many_arguments)]
    fn console_button_inner(&mut self, id: u32, x: f32, y: f32, w: f32, font: f32, icon: &str, icon_color: Color, label: &str, current: bool, busy: bool, enabled: bool) {
        let h = (font * 2.1).round();
        let focused = enabled && self.focusable(id);
        let hot = (enabled && self.hovered(x, y, w, h)) || focused;
        let t = self.theme;
        let target = if current {
            if self.card.tint_alert { t.col_alert } else { t.col_accent }
        } else if hot {
            t.col_plate.lighter(1.6)
        } else {
            t.col_plate.lighter(1.25)
        };
        let (bg, running) = self.card.color(id, target, 130, self.now);
        self.animating |= running;
        let border = if focused { 2.0 } else { 0.0 };
        self.scene.rect(x, y, w, h, bg, 4.0, border, t.col_white, true);
        if !current {
            self.scene.rect(x, y + h - 3.0, w, 3.0, Color::qt_rgba(0.0, 0.0, 0.0, 0.45), 4.0, 0.0, Color::TRANSPARENT, true);
        }
        let icon_box = font + 2.0;
        let icon_line = self.fonts.layout(icon, theme::bar_font(false), font + 2.0, 0.0);
        let cap = self.fonts.layout(label, theme::bar_font(true), font, 0.0);
        // Row skips an invisible child and its spacing; busy keeps the icon slot.
        let icon = if busy && icon.is_empty() { " " } else { icon };
        let row_w = match (icon.is_empty(), label.is_empty()) {
            (true, _) => cap.width,
            (false, true) => icon_box,
            (false, false) => icon_box + 6.0 + cap.width,
        };
        let row_h = if label.is_empty() { icon_box } else if icon.is_empty() { cap.height() } else { icon_box.max(cap.height()) };
        let rx = x + ac(w, row_w);
        // anchors.centerIn with verticalCenterOffset -1 when raised
        let ry = y + ac(h, row_h) + if current { 0.0 } else { -1.0 };
        if busy {
            let s = font - 2.0;
            let sy = ry + ac(row_h, icon_box) + ac(icon_box, s);
            crate::pult::spinner(self, rx + ac(icon_box, s), sy, s, if current { t.col_bg } else { t.col_white });
        } else if !icon.is_empty() {
            let ic = if current { t.col_bg } else if hot { t.col_white } else { icon_color };
            let ix = rx + ac(icon_box, icon_line.width);
            let iy = ry + ac(row_h, icon_box) + ac(icon_box, icon_line.height());
            self.text(&icon_line, ix, iy, ic, TextStyle::Normal);
        }
        if !label.is_empty() {
            let cx = if icon.is_empty() { rx } else { rx + icon_box + 6.0 };
            let cy = ry + ac(row_h, cap.height());
            self.text(&cap, cx, cy, if current { t.col_bg } else { t.col_grey }, TextStyle::Normal);
        }
        if enabled {
            self.hits.push(Hit { x, y, w, h, action: Action::Card(id) });
        }
    }
}

/// Draws the open card; true while something in it animates.
pub fn draw(card: &mut OpenCard, scene: &mut Scene, fonts: &mut Fonts, gpu: &mut Gpu, theme: &Theme, svc: &Services) -> bool {
    let (w, h) = (card.width, card.height);
    let key = (w.ceil() as u32, h.ceil() as u32, (card.stem_cx * 4.0) as i32);
    if card.notch_stale || card.notch.map_or(true, |n| (n.1, n.2, n.3) != key) {
        card.notch_stale = false;
        if let Some((id, ..)) = card.notch {
            gpu.drop_image(id);
        }
        let (mask, iw, ih) = notch_mask(w, h, card.stem_cx, card.stem_w);
        // Premultiplied colBg through the coverage.
        let bg = theme.col_bg;
        let mut rgba = Vec::with_capacity(mask.len() * 4);
        for m in mask {
            let a = m as f32 / 255.0 * bg.a;
            rgba.extend_from_slice(&[(bg.r * a * 255.0).round() as u8, (bg.g * a * 255.0).round() as u8, (bg.b * a * 255.0).round() as u8, (a * 255.0).round() as u8]);
        }
        let id = gpu.add_image(iw, ih, &rgba, false);
        card.notch = Some((id, key.0, key.1, key.2));
    }
    let (id, iw, ih, _) = card.notch.unwrap();
    let frac = card.frac;
    scene.save();
    scene.translate(frac, 0.0);
    scene.image(id, 0.0, 0.0, iw as f32, ih as f32, [0.0, 0.0, 1.0, 1.0]);
    // Hover is tested in content coordinates.
    let pointer = card.pointer;
    card.pointer = pointer.map(|(px, py)| (px - frac, py));

    let mut ui = Ui { card, scene, fonts, theme, now: Instant::now(), animating: false, hits: Vec::new(), focus_codes: Vec::new() };
    // The Loader's margins: top stemHeight + 8, 8 around.
    let (cx, cy, cw) = (8.0, STEM_H + 8.0, w - 16.0);
    match ui.card.kind {
        CardKind::Power => {
            let rows: [(&str, Color, &str); 4] = [
                ("\u{f033e}", theme.col_grey, "БЛОКИРОВКА"),
                ("\u{f0343}", theme.col_grey, "ВЫХОД"),
                ("\u{f0709}", theme.col_grey, "ПЕРЕЗАГРУЗКА"),
                ("\u{f0425}", theme.col_alert, "ВЫКЛЮЧЕНИЕ"),
            ];
            let mut y = cy;
            for (i, (icon, ic, label)) in rows.iter().enumerate() {
                ui.console_button(i as u32, cx, y, cw, icon, *ic, label, false);
                y += 42.0 + 6.0;
            }
        }
        CardKind::Calendar | CardKind::Weather | CardKind::Audio | CardKind::Pult | CardKind::Vpn | CardKind::Agent => {}
    }
    if ui.card.kind == CardKind::Calendar {
        draw_calendar(&mut ui, w);
    }
    if ui.card.kind == CardKind::Weather {
        draw_weather(&mut ui, w, svc);
    }
    if ui.card.kind == CardKind::Pult {
        crate::pult::draw(&mut ui, w, svc, svc.pult_scanning);
    }
    if ui.card.kind == CardKind::Agent {
        let scroll = ui.card.scroll;
        ui.scene.save();
        ui.scene.clip_rect(8.0, STEM_H + 8.0, w - 16.0, h - 28.0);
        crate::agent::draw(&mut ui, w, svc, svc.agent_busy, STEM_H + 8.0 - scroll);
        ui.scene.restore();
    }
    if ui.card.kind == CardKind::Vpn {
        crate::vpn::draw(&mut ui, w, svc, svc.vpn_busy);
        if svc.vpn_busy.0 || svc.vpn_busy.1 {
            ui.animating = true;
        }
    }
    if ui.card.kind == CardKind::Audio {
        // The Loader's area, clipped like the Flickable, scrolled by contentY.
        ui.card.sliders.clear();
        let scroll = ui.card.scroll;
        ui.scene.save();
        ui.scene.clip_rect(8.0, STEM_H + 8.0, w - 16.0, h - 28.0);
        crate::audio_card::draw(&mut ui, w, svc, STEM_H + 8.0 - scroll);
        ui.scene.restore();
    }
    let _ = svc;
    let (hits, codes, animating) = (std::mem::take(&mut ui.hits), std::mem::take(&mut ui.focus_codes), ui.animating);
    scene.restore();
    card.pointer = pointer;
    card.hits = hits.into_iter().map(|h| Hit { x: h.x + frac, ..h }).collect();
    card.sliders.iter_mut().for_each(|s| s.1 += frac);
    card.focus_codes = codes;
    animating
}

/// ConsolePlate: the recessed plate, with its 1 px highlight along the bottom.
/// ConsoleLamp in its 10 x 10 slot at (x, y): halo and dot fade over 160 ms.
pub(crate) fn lamp(ui: &mut Ui, id: u32, x: f32, y: f32, lit: bool) {
    let t = ui.theme;
    let (halo, r1) = ui.card.number(0x3_0000 + id, if lit { 0.22 } else { 0.0 }, 160, ui.now);
    let (dot, r2) = ui.card.color(0x4_0000 + id, if lit { t.col_accent } else { t.col_plate.darker(1.3) }, 160, ui.now);
    ui.animating |= r1 || r2;
    if halo > 0.0 {
        ui.scene.save();
        ui.scene.multiply_opacity(halo);
        ui.scene.rect(x + ac(10.0, 18.0), y + ac(10.0, 18.0), 18.0, 18.0, t.col_accent, 9.0, 0.0, Color::TRANSPARENT, true);
        ui.scene.restore();
    }
    let border = if lit { t.col_accent.lighter(1.25) } else { Color::qt_rgba(1.0, 1.0, 1.0, 0.12) };
    ui.scene.rect(x + ac(10.0, 9.0), y + ac(10.0, 9.0), 9.0, 9.0, dot, 4.5, 1.0, border, true);
}

/// ConsoleRow: lamp, optional icon, label (elided), optional detail and a
/// trailing text (an emoji flag), laid out by its RowLayout.
#[allow(clippy::too_many_arguments)]
pub(crate) fn console_row(ui: &mut Ui, code: u32, x: f32, y: f32, w: f32, h: f32, icon: &str, label: &str, lit: bool, interactive: bool, detail: Option<(&str, Color)>, trailing: Option<&str>) {
    let t = ui.theme;
    let font = FONT_SIZE - 3.0;
    let focused = interactive && ui.focusable(code);
    let hot = (interactive && ui.hovered(x, y, w, h)) || focused;
    let (bg, run) = ui.card.color(0x5_0000 + code, if hot { t.col_plate.lighter(1.6) } else { Color::TRANSPARENT }, 110, ui.now);
    ui.animating |= run;
    ui.scene.rect(x, y, w, h, bg, 4.0, if focused { 2.0 } else { 0.0 }, t.col_white, true);
    let mut cx = x + 6.0;
    lamp(ui, code, cx, y + qround((h - 10.0) / 2.0), lit);
    cx += 10.0 + 8.0;
    let fg = if lit || hot { t.col_white } else { t.col_grey };
    if !icon.is_empty() {
        let il = ui.fonts.layout(icon, theme::bar_font(false), font, 0.0);
        ui.text(&il, cx + (font + 2.0 - il.adv) / 2.0, y + qround((h - il.height()) / 2.0), fg, TextStyle::Normal);
        cx += font + 2.0 + 8.0;
    }
    let mut right = x + w - 6.0;
    if let Some(tr) = trailing {
        let tl = ui.fonts.layout(tr, theme::FontKey { family: "Fira Code:medium", bold: false }, FONT_SIZE + 2.0, 0.0);
        right -= tl.width;
        ui.text(&tl, right, y + qround((h - tl.height()) / 2.0), t.col_white, TextStyle::Normal);
        right -= 8.0;
    }
    if let Some((d, dc)) = detail.filter(|d| !d.0.is_empty()) {
        let dl = ui.fonts.layout(d, theme::bar_font(false), font - 2.0, 0.0);
        right -= dl.width;
        ui.text(&dl, right, y + qround((h - dl.height()) / 2.0), dc, TextStyle::Normal);
        right -= 8.0;
    }
    let key = theme::bar_font(lit);
    let full = ui.fonts.layout(label, key, font, 0.0);
    let line = ui.fonts.elide_right(&full, label, key, right - cx, 0.0);
    ui.text(&line, cx, y + qround((h - line.height()) / 2.0), fg, TextStyle::Normal);
    if interactive {
        ui.hits.push(Hit { x, y, w, h, action: Action::Card(code) });
    }
}

fn qround(v: f32) -> f32 {
    (v + 0.5).floor()
}

pub(crate) fn plate(ui: &mut Ui, x: f32, y: f32, w: f32, h: f32) {
    ui.scene.rect(x, y, w, h, ui.theme.col_plate, 5.0, 0.0, Color::TRANSPARENT, true);
    ui.scene.fill(x + 5.0, y + h - 1.0, w - 10.0, 1.0, Color::qt_rgba(1.0, 1.0, 1.0, 0.07));
}

const CAL_PREV: u32 = 0;
const CAL_NEXT: u32 = 1;

fn draw_calendar(ui: &mut Ui, w: f32) {
    let t = ui.theme;
    let (x0, y0, cw) = (12.0, STEM_H + 12.0, w - 24.0);
    // Header: prev, month + year (28 px bold, letterSpacing 1, centred), next.
    let font = FONT_SIZE - 6.0;
    let bw = ui.console_button_width(font, "\u{f0141}", "", 0.0);
    let bh = (font * 2.1).round();
    let (year, month) = ui.card.month;
    let title = format!("{} {}", crate::cal::month_name(month).to_uppercase(), year);
    let tl = ui.fonts.layout(&title, theme::bar_font(true), FONT_SIZE + 4.0, 1.0);
    let head_h = tl.height().max(bh);
    ui.console_button_sized(CAL_PREV, x0, y0 + ac(head_h, bh), bw, font, "\u{f0141}", t.col_grey, "", false);
    let tw = cw - 2.0 * bw;
    let tx = x0 + bw + (tw - tl.adv) / 2.0;
    ui.text(&tl, tx, y0 + ac(head_h, tl.height()), t.col_white, TextStyle::Normal);
    ui.console_button_sized(CAL_NEXT, x0 + cw - bw, y0 + ac(head_h, bh), bw, font, "\u{f0142}", t.col_grey, "", false);

    // The plate: weekday captions, then the 7 x 6 grid.
    let py = y0 + head_h + 8.0;
    plate(ui, x0, py, cw, 8.0 + 24.0 + 4.0 + 240.0 + 8.0);
    let (ix, iw) = (x0 + 8.0, cw - 16.0);
    let col = iw / 7.0;
    let first = crate::cal::first_weekday();
    for i in 0..7 {
        let name = crate::cal::day_name_short((first + i) % 7).to_uppercase();
        let l = ui.fonts.layout(&name, theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
        let cx = ix + col * i as f32 + ac(col, l.width);
        let cy = py + 8.0 + ac(24.0, l.height());
        ui.text(&l, cx, cy, t.col_dim, TextStyle::Normal);
    }
    let gy = py + 8.0 + 24.0 + 4.0;
    let today = crate::cal::today();
    let start = crate::cal::grid_start(year, month, first);
    for k in 0..42u32 {
        let (dy, dm, dd) = crate::cal::add_days(start, k as i64);
        let (cx, cy) = (ix + col * (k % 7) as f32, gy + 40.0 * (k / 7) as f32);
        let side = (col - 4.0).min(40.0 - 4.0).min(42.0);
        let (rx, ry) = (cx + ac(col, side), cy + ac(40.0, side));
        let is_today = (dy, dm, dd) == today;
        let hover = ui.hovered(cx, cy, col, 40.0);
        let target = if is_today { t.col_accent } else if hover { t.col_plate.lighter(1.6) } else { Color::TRANSPARENT };
        let (bg, running) = ui.card.color(200 + k, target, 110, ui.now);
        ui.animating |= running;
        ui.scene.rect(rx, ry, side, side, bg, 4.0, 0.0, Color::TRANSPARENT, true);
        let l = ui.fonts.layout(&dd.to_string(), theme::bar_font(is_today), FONT_SIZE - 2.0, 0.0);
        let color = if is_today {
            t.col_bg
        } else if dm == month {
            t.col_white
        } else {
            t.col_white.with_alpha(0.3)
        };
        ui.text(&l, rx + ac(side, l.width), ry + ac(side, l.height()), color, TextStyle::Normal);
        ui.hits.push(Hit { x: cx, y: cy, w: col, h: 40.0, action: Action::Card(1000 + k) });
    }
}

/// CenterInfo.getConditionColor
fn condition_color(cond: &str, t: &Theme) -> Color {
    let c = cond.to_lowercase();
    let hex = if c.contains("sun") || c.contains("clear") {
        "#f1fa8c"
    } else if c.contains("cloud") || c.contains("overcast") {
        "#94a3b8"
    } else if c.contains("rain") || c.contains("drizzle") || c.contains("shower") {
        "#8be9fd"
    } else if c.contains("thunder") || c.contains("storm") {
        "#bd93f9"
    } else if c.contains("snow") || c.contains("sleet") || c.contains("ice") {
        "#f8f8f2"
    } else if c.contains("fog") || c.contains("mist") || c.contains("haze") {
        "#6272a4"
    } else if c.contains("wind") {
        "#50fa7b"
    } else {
        return t.pal_fg;
    };
    Color::parse(hex).unwrap()
}

/// The weather card's lines and plate heights, shared by measuring and drawing.
struct WeatherLayout {
    sky: Line,
    temp: Line,
    cond: Vec<Line>,
    place: Vec<Line>,
    row_h: f32,
    read_h: f32,
    read_x: f32,
    p1: f32,
    p2: f32,
    p3: f32,
}

fn weather_layout(fonts: &mut Fonts, svc: &Services, w: f32) -> WeatherLayout {
    let wx = &svc.weather;
    let (x0, cw) = (12.0, w - 24.0);
    let icon = if wx.icon.is_empty() { "\u{f0590}".to_string() } else { wx.icon.clone() };
    let sky = fonts.layout(&icon, theme::bar_font(false), 52.0, 0.0);
    let num = first_number(&wx.text);
    let temp = fonts.layout(&if num.is_empty() { String::new() } else { format!("{num}°C") }, theme::bar_font(true), 34.0, 0.0);
    let read_x = x0 + 12.0 + sky.width + 16.0;
    let read_w = (x0 + cw - 12.0) - read_x;
    let cond = fonts.wrap(&wx.alt_display.to_uppercase(), theme::bar_font(true), FONT_SIZE - 5.0, 1.0, read_w);
    let place = if wx.location.is_empty() { Vec::new() } else { fonts.wrap(&wx.location, theme::bar_font(false), FONT_SIZE - 6.0, 0.0, read_w) };
    let cond_h: f32 = cond.iter().map(|l| l.height()).sum();
    let place_h: f32 = place.iter().map(|l| l.height()).sum();
    let read_h = temp.height() + 2.0 + cond_h + if place.is_empty() { 0.0 } else { 2.0 + place_h };
    let row_h = sky.height().max(read_h);
    let p2 = if wx.min_temp.is_empty() && wx.max_temp.is_empty() && wx.feels_like.is_empty() {
        0.0
    } else {
        let r1 = fonts.layout("М", theme::bar_font(true), FONT_SIZE - 5.0, 1.0).height();
        let r2 = fonts.layout("0", theme::bar_font(true), FONT_SIZE, 0.0).height();
        10.0 + r1 + 2.0 + r2 + 10.0
    };
    let p3 = if wx.hourly_rain.is_empty() {
        0.0
    } else {
        let cap_h = fonts.layout(" ДОЖДЬ", theme::bar_font(true), FONT_SIZE - 5.0, 1.0).height();
        let pct_h = fonts.layout("0%", theme::bar_font(true), FONT_SIZE - 8.0, 0.0).height();
        10.0 + cap_h + 6.0 + 40.0 + 4.0 + pct_h + 10.0
    };
    WeatherLayout { sky, temp, cond, place, row_h, read_h, read_x, p1: row_h + 24.0, p2, p3 }
}

/// The first (possibly negative) integer in s, as /-?\d+/ finds it.
fn first_number(s: &str) -> String {
    let b: Vec<char> = s.chars().collect();
    for i in 0..b.len() {
        let neg = b[i] == '-' && b.get(i + 1).map_or(false, |c| c.is_ascii_digit());
        if b[i].is_ascii_digit() || neg {
            let mut j = i + 1;
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
            return b[i..j].iter().collect();
        }
    }
    String::new()
}

fn weather_height(fonts: &mut Fonts, svc: &Services, w: f32) -> f32 {
    let l = weather_layout(fonts, svc, w);
    let plates = [l.p1, l.p2, l.p3];
    let shown: Vec<f32> = plates.iter().copied().filter(|h| *h > 0.0).collect();
    let content = shown.iter().sum::<f32>() + 8.0 * (shown.len().saturating_sub(1)) as f32;
    // Column (from STEM_H + 12) + bottom margin 12; cardHeight = implicitHeight + 12 + 24.
    (content + 12.0 + 24.0).ceil()
}

/// The weather card's content.
fn draw_weather(ui: &mut Ui, w: f32, svc: &Services) {
    let t = ui.theme;
    let wx = &svc.weather;
    let (x0, cw) = (12.0, w - 24.0);
    let l = weather_layout(ui.fonts, svc, w);
    let temp_color = |s: &str| crate::bar::temp_color(s, t);
    let mut y = STEM_H + 12.0;

    // Plate 1 (pad 12): the sky glyph, temperature, condition, place.
    plate(ui, x0, y, cw, l.p1);
    let iy = y + 12.0;
    ui.text(&l.sky, x0 + 12.0, iy + ac(l.row_h, l.sky.height()), condition_color(&wx.alt, t), TextStyle::Normal);
    let mut ry = iy + ac(l.row_h, l.read_h);
    ui.text(&l.temp, l.read_x, ry, temp_color(&wx.text), TextStyle::Normal);
    ry += l.temp.height() + 2.0;
    for line in &l.cond {
        ui.text(line, l.read_x, ry, t.col_white, TextStyle::Normal);
        ry += line.height();
    }
    ry += 2.0;
    for line in &l.place {
        ui.text(line, l.read_x, ry, t.col_grey, TextStyle::Normal);
        ry += line.height();
    }
    y += l.p1 + 8.0;

    // Plate 2: МИН / МАКС / ОЩУЩАЕТСЯ, three equal columns.
    if l.p2 > 0.0 {
        plate(ui, x0, y, cw, l.p2);
        let colw = (cw - 20.0 - 16.0) / 3.0;
        let caps = ["МИН", "МАКС", "ОЩУЩАЕТСЯ"];
        let vals = [&wx.min_temp, &wx.max_temp, &wx.feels_like];
        let r1 = ui.fonts.layout("М", theme::bar_font(true), FONT_SIZE - 5.0, 1.0).height();
        let r2 = ui.fonts.layout("0", theme::bar_font(true), FONT_SIZE, 0.0).height();
        for i in 0..3 {
            let cx = x0 + 10.0 + i as f32 * (colw + 8.0);
            let cl = ui.fonts.layout(caps[i], theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
            ui.text(&cl, cx + (colw - cl.adv) / 2.0, y + 10.0 + ac(r1, cl.height()), t.col_dim, TextStyle::Normal);
            let v = if vals[i].is_empty() { "—" } else { vals[i].as_str() };
            let vl = ui.fonts.layout(v, theme::bar_font(true), FONT_SIZE, 0.0);
            ui.text(&vl, cx + (colw - vl.adv) / 2.0, y + 10.0 + r1 + 2.0 + ac(r2, vl.height()), temp_color(vals[i]), TextStyle::Normal);
        }
        y += l.p2 + 8.0;
    }

    // Plate 3: rain chance for the next hours, six segments each.
    if l.p3 > 0.0 {
        plate(ui, x0, y, cw, l.p3);
        let cap = ui.fonts.layout(" ДОЖДЬ", theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
        ui.text(&cap, x0 + 10.0, y + 10.0, t.col_dim, TextStyle::Normal);
        let n = wx.hourly_rain.len() as f32;
        let colw = (cw - 20.0 - 8.0 * (n - 1.0)) / n;
        let by = y + 10.0 + cap.height() + 6.0;
        for (i, v) in wx.hourly_rain.iter().enumerate() {
            let lit = ((*v).clamp(0, 100) as f32 / 100.0 * 6.0).round() as i64;
            let cx = x0 + 10.0 + i as f32 * (colw + 8.0);
            for k in 0..6i64 {
                let c = if (5 - k) < lit { t.col_accent } else { Color::qt_rgba(1.0, 1.0, 1.0, 0.07) };
                ui.scene.rect(cx, by + k as f32 * 7.0, colw, 5.0, c, 1.0, 0.0, Color::TRANSPARENT, true);
            }
            let pl = ui.fonts.layout(&format!("{v}%"), theme::bar_font(true), FONT_SIZE - 8.0, 0.0);
            ui.text(&pl, cx + (colw - pl.adv) / 2.0, by + 44.0, if lit > 0 { t.col_white } else { t.col_grey }, TextStyle::Normal);
        }
    }
}

fn calendar_step(app: &mut App, delta: i32) {
    if let Some(c) = app.card.as_mut() {
        let (y, m) = c.month;
        let idx = y * 12 + m as i32 - 1 + delta;
        c.month = (idx.div_euclid(12), (idx.rem_euclid(12) + 1) as u32);
        c.win.dirty = true;
    }
}

/// A wheel turn over the card (QML angleDelta: +120 per notch away from you).
pub fn wheel(app: &mut App, angle_delta_y: f32) {
    let Some(c) = app.card.as_mut() else { return };
    if c.kind == CardKind::Agent {
        let view = c.height - 28.0;
        let max = (c.content_h - view).max(0.0);
        c.scroll = (c.scroll - angle_delta_y / 120.0 * 3.0 * 20.0).clamp(0.0, max);
        c.win.dirty = true;
        return;
    }
    if c.kind == CardKind::Audio {
        let over = c.pointer.and_then(|(px, py)| c.sliders.iter().find(|s| px >= s.1 && px < s.1 + s.2 && py >= 0.0).map(|s| s.0));
        let over = over.filter(|code| c.hits.iter().any(|h| h.action == Action::Card(*code) && c.pointer.map_or(false, |(px, py)| h.contains(px, py))));
        if let Some(code) = over {
            crate::audio_card::slider_step(app, code, angle_delta_y > 0.0);
        } else {
            let view = c.height - 28.0;
            let max = (c.content_h - view).max(0.0);
            c.scroll = (c.scroll - angle_delta_y / 120.0 * 3.0 * 20.0).clamp(0.0, max);
            c.win.dirty = true;
        }
        return;
    }
    if c.kind != CardKind::Calendar {
        return;
    }
    c.wheel_acc += angle_delta_y;
    let mut steps = 0;
    while c.wheel_acc >= 120.0 {
        c.wheel_acc -= 120.0;
        steps -= 1;
    }
    while c.wheel_acc <= -120.0 {
        c.wheel_acc += 120.0;
        steps += 1;
    }
    if steps != 0 {
        calendar_step(app, steps);
    }
}

// ---- input ----

/// A button went down on a card control: a slider jumps to the pointer.
pub fn press(app: &mut App, action: Action, x: f32, button: u32) {
    if let (Action::Card(code), Some(card)) = (action, app.card.as_ref()) {
        if card.kind == CardKind::Audio && button == 0x110 && crate::audio_card::is_slider(code) {
            crate::audio_card::slider_to(app, code, x);
        }
    }
}

/// The pointer moved with the left button held on a slider.
pub fn drag(app: &mut App, action: Action, x: f32) {
    press(app, action, x, 0x110);
}

/// A click (release over the pressed control) with a button.
pub fn click(app: &mut App, action: Action, button: u32) {
    let Action::Card(code) = action else { return };
    let Some(card) = app.card.as_ref() else { return };
    if card.kind == CardKind::Audio && crate::audio_card::is_slider(code) {
        if button == 0x111 {
            crate::audio_card::slider_mute(app, code);
        }
        return;
    }
    if button == 0x110 {
        activate(app, action, false);
    }
}

pub fn activate(app: &mut App, action: Action, keyboard: bool) {
    let Some(card) = app.card.as_ref() else { return };
    let Action::Card(i) = action else { return };
    match card.kind {
        CardKind::Power => power_pick(app, i, keyboard),
        CardKind::Weather => {}
        CardKind::Audio => crate::audio_card::activate(app, i),
        CardKind::Pult => crate::pult::activate(app, i),
        CardKind::Vpn => crate::vpn::activate(app, i),
        CardKind::Agent => {}
        CardKind::Calendar => match i {
            // the focus chain: prev, next; day cells are mouse-only
            CAL_PREV => calendar_step(app, -1),
            CAL_NEXT => calendar_step(app, 1),
            _ => {}
        },
    }
}

fn power_pick(app: &mut App, i: u32, keyboard: bool) {
    let crt = format!("{}/.config/hypr/scripts/CrtOff.sh ", services::home());
    let cmd = match i {
        0 => {
            close(app);
            app.exec_detached(&["loginctl", "lock-session"]);
            return;
        }
        1 => "mmsg dispatch quit",
        2 => "systemctl reboot",
        _ => "systemctl poweroff",
    };
    if keyboard {
        // By keyboard these arm the power menu's countdown (PowerOsd) - that
        // dialog is not ported yet, so the keyboard does not end the session.
        close(app);
        return;
    }
    close(app);
    // endSession(): the card closes, the CRT effect starts 250 ms later.
    let full = format!("{crt}{cmd}");
    app.svc.pending_end = full;
    app.after(Duration::from_millis(250), |app| {
        let cmd = std::mem::take(&mut app.svc.pending_end);
        app.exec_detached(&["sh", "-c", &cmd]);
    });
}

/// CardKeys: Esc closes, Tab/arrows walk the focus chain, Return/Enter/Space press.
pub fn key(app: &mut App, sym: Keysym, _utf8: Option<&str>) {
    let Some(card) = app.card.as_mut() else { return };
    // A focused VolumeSlider takes Left/Right and its mute keys first.
    let focused = card.focus.and_then(|f| card.focus_codes.get(f).copied());
    if card.kind == CardKind::Audio {
        if let Some(code) = focused.filter(|c| crate::audio_card::is_slider(*c)) {
            match sym {
                Keysym::Left => return crate::audio_card::slider_step(app, code, false),
                Keysym::Right => return crate::audio_card::slider_step(app, code, true),
                Keysym::Return | Keysym::KP_Enter | Keysym::space | Keysym::m | Keysym::M => return crate::audio_card::slider_mute(app, code),
                _ => {}
            }
        }
    }
    let Some(card) = app.card.as_mut() else { return };
    let n = card.focus_codes.len().max(1);
    let back = card.shift;
    match sym {
        Keysym::Escape => close(app),
        Keysym::Tab | Keysym::Down | Keysym::Right if !(sym == Keysym::Tab && back) => {
            card.focus = Some(card.focus.map_or(0, |f| (f + 1) % n));
            card.win.dirty = true;
        }
        Keysym::ISO_Left_Tab | Keysym::Tab | Keysym::Up | Keysym::Left => {
            card.focus = Some(card.focus.map_or(n - 1, |f| (f + n - 1) % n));
            card.win.dirty = true;
        }
        Keysym::Return | Keysym::KP_Enter | Keysym::space => {
            if let Some(code) = card.focus.and_then(|f| card.focus_codes.get(f).copied()) {
                activate(app, Action::Card(code), true);
            }
        }
        _ => {}
    }
}

pub fn focused(app: &App) -> Option<WinRef> {
    app.card.as_ref().map(|_| WinRef::Card)
}
