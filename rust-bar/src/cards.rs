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
use crate::bar::{Action, Hit};
use crate::color::Color;
use crate::gpu::{Gpu, Scene, TextStyle};
use crate::services::{self, Services};
use crate::text::{Fonts, Line};
use crate::theme::{self, Theme, FONT_SIZE};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CardKind {
    Power,
    Calendar,
}

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
    focus: Option<usize>,
    focus_count: usize,
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
}

impl OpenCard {
    /// A control's animated colour (Behavior on color { ColorAnimation { duration } }).
    fn color(&mut self, id: u32, target: Color, ms: u64, now: Instant) -> (Color, bool) {
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
    let (w, h, stem) = geometry(kind);
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
    layer.set_anchor(Anchor::TOP | Anchor::LEFT);
    layer.set_margin(y.round() as i32, 0, 0, x.round() as i32);
    layer.set_size(w as u32, h as u32);
    layer.set_exclusive_zone(-1);
    layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
    layer.commit();

    app.card = Some(OpenCard {
        kind,
        strip,
        win: Win::new(layer, w as u32, h as u32),
        catcher: Catcher { layer: catcher, viewport: None, pool: None },
        hits: Vec::new(),
        pointer: None,
        shift: false,
        focus: if keyboard { Some(0) } else { None },
        focus_count: 0,
        width: w,
        height: h,
        stem_cx,
        stem_w,
        notch: None,
        colors: HashMap::new(),
        month: { let (y, m, _) = crate::cal::today(); (y, m) },
        wheel_acc: 0.0,
    });
    app.strips[strip].win.dirty = true;
}

pub fn close(app: &mut App) {
    let Some(card) = app.card.take() else { return };
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

struct Ui<'a> {
    card: &'a mut OpenCard,
    scene: &'a mut Scene,
    fonts: &'a mut Fonts,
    theme: &'a Theme,
    now: Instant,
    animating: bool,
    hits: Vec<Hit>,
    focus_n: usize,
}

impl Ui<'_> {
    fn hovered(&self, x: f32, y: f32, w: f32, h: f32) -> bool {
        self.card.pointer.map_or(false, |(px, py)| px >= x && px < x + w && py >= y && py < y + h)
    }

    /// The next control in the focus chain: (its index, has focus).
    fn focusable(&mut self) -> (usize, bool) {
        let i = self.focus_n;
        self.focus_n += 1;
        (i, self.card.focus == Some(i))
    }

    fn text(&mut self, line: &Line, x: f32, y: f32, color: Color, style: TextStyle) {
        self.scene.text(self.fonts, line, x, y + line.ascent, color, style);
    }

    /// ConsoleButton: a key on the console - plate colour, white focus ring,
    /// shadow lip, icon + bold caption centred one pixel high.
    #[allow(clippy::too_many_arguments)]
    fn console_button(&mut self, id: u32, x: f32, y: f32, w: f32, icon: &str, icon_color: Color, label: &str, current: bool) {
        self.console_button_sized(id, x, y, w, FONT_SIZE - 4.0, icon, icon_color, label, current);
    }

    /// ConsoleButton.implicitWidth: max(minWidth, face + 26).
    fn console_button_width(&mut self, font: f32, icon: &str, label: &str, min_width: f32) -> f32 {
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
    fn console_button_sized(&mut self, id: u32, x: f32, y: f32, w: f32, font: f32, icon: &str, icon_color: Color, label: &str, current: bool) {
        let h = (font * 2.1).round();
        let (fi, focused) = self.focusable();
        let hot = self.hovered(x, y, w, h) || focused;
        let t = self.theme;
        let target = if current {
            t.col_accent
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
        // Row skips an invisible child and its spacing.
        let row_w = match (icon.is_empty(), label.is_empty()) {
            (true, _) => cap.width,
            (false, true) => icon_box,
            (false, false) => icon_box + 6.0 + cap.width,
        };
        let row_h = if label.is_empty() { icon_box } else if icon.is_empty() { cap.height() } else { icon_box.max(cap.height()) };
        let rx = x + ((w - row_w) / 2.0 + 0.5).floor();
        let ry = y + ((h - row_h) / 2.0 + if current { 0.0 } else { -1.0 } + 0.5).floor();
        if !icon.is_empty() {
            let ic = if current { t.col_bg } else if hot { t.col_white } else { icon_color };
            let ix = rx + ((icon_box - icon_line.width) / 2.0 + 0.5).floor();
            let iy = ry + ((row_h - icon_box) / 2.0 + 0.5).floor() + ((icon_box - icon_line.height()) / 2.0 + 0.5).floor();
            self.text(&icon_line, ix, iy, ic, TextStyle::Normal);
        }
        if !label.is_empty() {
            let cx = if icon.is_empty() { rx } else { rx + icon_box + 6.0 };
            let cy = ry + ((row_h - cap.height()) / 2.0 + 0.5).floor();
            self.text(&cap, cx, cy, if current { t.col_bg } else { t.col_grey }, TextStyle::Normal);
        }
        self.hits.push(Hit { x, y, w, h, action: Action::Card(fi as u32) });
    }
}

/// Draws the open card; true while something in it animates.
pub fn draw(card: &mut OpenCard, scene: &mut Scene, fonts: &mut Fonts, gpu: &mut Gpu, theme: &Theme, svc: &Services) -> bool {
    let (w, h) = (card.width, card.height);
    let key = (w.ceil() as u32, h.ceil() as u32, (card.stem_cx * 4.0) as i32);
    if card.notch.map_or(true, |n| (n.1, n.2, n.3) != key) {
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
    scene.image(id, 0.0, 0.0, iw as f32, ih as f32, [0.0, 0.0, 1.0, 1.0]);

    let mut ui = Ui { card, scene, fonts, theme, now: Instant::now(), animating: false, hits: Vec::new(), focus_n: 0 };
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
        CardKind::Calendar => {}
    }
    if ui.card.kind == CardKind::Calendar {
        draw_calendar(&mut ui, w);
    }
    let _ = svc;
    let (hits, n, animating) = (std::mem::take(&mut ui.hits), ui.focus_n, ui.animating);
    card.hits = hits;
    card.focus_count = n;
    animating
}

/// ConsolePlate: the recessed plate, with its 1 px highlight along the bottom.
fn plate(ui: &mut Ui, x: f32, y: f32, w: f32, h: f32) {
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
    ui.console_button_sized(100 + CAL_PREV, x0, y0 + ((head_h - bh) / 2.0 + 0.5).floor(), bw, font, "\u{f0141}", t.col_grey, "", false);
    let tw = cw - 2.0 * bw;
    let tx = x0 + bw + (tw - tl.width) / 2.0;
    ui.text(&tl, tx, y0 + ((head_h - tl.height()) / 2.0 + 0.5).floor(), t.col_white, TextStyle::Normal);
    ui.console_button_sized(100 + CAL_NEXT, x0 + cw - bw, y0 + ((head_h - bh) / 2.0 + 0.5).floor(), bw, font, "\u{f0142}", t.col_grey, "", false);

    // The plate: weekday captions, then the 7 x 6 grid.
    let py = y0 + head_h + 8.0;
    plate(ui, x0, py, cw, 8.0 + 24.0 + 4.0 + 240.0 + 8.0);
    let (ix, iw) = (x0 + 8.0, cw - 16.0);
    let col = iw / 7.0;
    let first = crate::cal::first_weekday();
    for i in 0..7 {
        let name = crate::cal::day_name_short((first + i) % 7).to_uppercase();
        let l = ui.fonts.layout(&name, theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
        let cx = ix + col * i as f32 + ((col - l.width) / 2.0 + 0.5).floor();
        let cy = py + 8.0 + ((24.0 - l.height()) / 2.0 + 0.5).floor();
        ui.text(&l, cx, cy, t.col_dim, TextStyle::Normal);
    }
    let gy = py + 8.0 + 24.0 + 4.0;
    let today = crate::cal::today();
    let start = crate::cal::grid_start(year, month, first);
    for k in 0..42u32 {
        let (dy, dm, dd) = crate::cal::add_days(start, k as i64);
        let (cx, cy) = (ix + col * (k % 7) as f32, gy + 40.0 * (k / 7) as f32);
        let side = (col - 4.0).min(40.0 - 4.0).min(42.0);
        let (rx, ry) = (cx + ((col - side) / 2.0 + 0.5).floor(), cy + ((40.0 - side) / 2.0 + 0.5).floor());
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
        ui.text(&l, rx + ((side - l.width) / 2.0 + 0.5).floor(), ry + ((side - l.height()) / 2.0 + 0.5).floor(), color, TextStyle::Normal);
        ui.hits.push(Hit { x: cx, y: cy, w: col, h: 40.0, action: Action::Card(1000 + k) });
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

pub fn activate(app: &mut App, action: Action, keyboard: bool) {
    let Some(card) = app.card.as_ref() else { return };
    let Action::Card(i) = action else { return };
    match card.kind {
        CardKind::Power => power_pick(app, i, keyboard),
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
    let n = card.focus_count.max(1);
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
            if let Some(f) = card.focus {
                activate(app, Action::Card(f as u32), true);
            }
        }
        _ => {}
    }
}

pub fn focused(app: &App) -> Option<WinRef> {
    app.card.as_ref().map(|_| WinRef::Card)
}
