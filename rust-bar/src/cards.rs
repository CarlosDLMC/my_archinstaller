//! The strip's dropdown cards (DropdownWidget + CardSurface + CardKeys).
//!
//! As CardSurface.qml: one full-screen transparent layer surface with the card
//! drawn in it at its place under the bar. A press anywhere outside the card
//! closes it. The surface keeps its size while the card grows and shrinks:
//! mango animates a layer whose size changes (a move, with the fade-in played
//! again), and a card-sized surface flickered on every view change. mango
//! blurs only under visible pixels, so only the card is blurred.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use smithay_client_toolkit::{
    seat::keyboard::Keysym,
    shell::{
        wlr_layer::{Anchor, KeyboardInteractivity, Layer},
        WaylandSurface,
    },
};

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
    Wifi,
    Battery,
    Network,
}

/// A fixed origin for animations that run on the clock (Spinner).
pub static EPOCH: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();

#[derive(Clone, Copy, PartialEq, Eq)]
enum Stem {
    Left,
    Center,
    Right,
}

pub struct OpenCard {
    pub kind: CardKind,
    pub strip: usize,
    pub win: Win,
    pub hits: Vec<Hit>,
    pub pointer: Option<(f32, f32)>,
    pub shift: bool,
    /// Index into the card's focus chain (CardKeys), None = nothing focused.
    /// Code that sets it names the control at that place in the next draw's
    /// chain; after a draw it is where `focus_code` is.
    pub(crate) focus: Option<usize>,
    /// The focus chain of the last draw: each focusable control's code.
    pub(crate) focus_codes: Vec<u32>,
    /// The focused control (the window's activeFocusItem): it keeps the focus
    /// while the chain changes around it. Gone from the chain (disabled,
    /// hidden), the keys go to the card's scope until it comes back.
    focus_code: Option<u32>,
    /// `focus` as the last draw left it: a change since is an index set by code.
    focus_seen: Option<usize>,
    /// The keys moved the focus since the last draw: a list shows that row.
    focus_moved: bool,
    /// The Wi-Fi card's password view at the last draw.
    wifi_password: bool,
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
    /// The meter's segment count at the last draw (it follows the width).
    pub(crate) meter_cells: i32,
    /// Where the last draw put the meter on the card's surface (x, y, width),
    /// None out of view; whether it has a node; and its own surface.
    pub(crate) meter_at: Option<(f32, f32, f32)>,
    pub(crate) meter_node: bool,
    pub(crate) meter_win: Option<crate::audio_card::MeterWin>,
    /// ConsoleButton.tint for the next button: colAlert (the mute buttons).
    pub(crate) tint_alert: bool,
    numbers: HashMap<u32, Animated<f32>>,
    /// The card's Flickable and ListViews: where each is scrolled to.
    flicks: Vec<Flick>,
    /// Hover is cut to this (a Flickable's clip) while one is drawn.
    hover_clip: Option<[f32; 4]>,
    /// The Flickable's content height.
    content_h: f32,
    notch_stale: bool,
    /// The anchoring icon's centre on screen (for cards whose width changes).
    icon_center: f32,
    /// The card's place on the screen: CardSurface's card.x and cardY (QML's
    /// card x can be fractional, but it lands on whole pixels - measured).
    left: f32,
    top: f32,
    /// Which of the card's Texts have changed since it opened.
    pub texts: crate::text::TextMemo,
}

impl OpenCard {
    /// The card's top-left corner on its surface.
    pub(crate) fn origin(&self) -> (f32, f32) {
        (self.left, self.top)
    }

    /// The card's height.
    pub(crate) fn card_height(&self) -> f32 {
        self.height
    }

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

    /// CardKeys.step: the next (or previous) control of the chain, wrapping
    /// around; from the card's scope (nothing focused) the first (or last).
    fn step_focus(&mut self, forward: bool) {
        let n = self.focus_codes.len();
        if n == 0 {
            return;
        }
        let i = match self.focus.filter(|f| *f < n) {
            Some(f) if forward => (f + 1) % n,
            Some(f) => (f + n - 1) % n,
            None if forward => 0,
            None => n - 1,
        };
        self.focus = Some(i);
        self.focus_seen = self.focus;
        self.focus_code = Some(self.focus_codes[i]);
        self.focus_moved = true;
        self.win.dirty = true;
    }

    /// The card's Flickable or ListView `id`, made at contentY 0 the first time.
    fn flick(&mut self, id: u32, sig: u64) -> &mut Flick {
        let i = match self.flicks.iter().position(|f| f.id == id) {
            Some(i) => i,
            None => {
                self.flicks.push(Flick { id, glide: Animated::new(0.0, 300, Easing::OutExpo), rest: 0.0, max: 0.0, sig, rect: None });
                self.flicks.len() - 1
            }
        };
        &mut self.flicks[i]
    }

    /// A ListView's model was replaced by different data: Qt makes its rows
    /// anew. A focused row's focus goes to the card's scope, and the rows'
    /// colours and texts start fresh (no fade from the old row at that place;
    /// subpixel text). Its rows are the codes base .. base + 0x100.
    fn list_replaced(&mut self, base: u32) {
        let rows = base..base + 0x100;
        if self.focus_code.map_or(false, |c| rows.contains(&c)) {
            self.focus_code = None;
            self.focus = None;
            self.focus_seen = None;
        }
        // ConsoleRow's background (0x5_0000), ConsoleLamp's dot (0x4_0000) and halo (0x3_0000).
        let row_key = |k: u32, kinds: &[u32]| kinds.contains(&(k >> 16)) && rows.contains(&(k & 0xFFFF));
        self.colors.retain(|k, _| !row_key(*k, &[4, 5]));
        self.numbers.retain(|k, _| !row_key(*k, &[3]));
        // ConsoleRow's texts (text_of parts 0xC1-0xC4): the list cards have no other rows.
        self.texts.forget_parts(&[0xC1, 0xC2, 0xC3, 0xC4]);
    }
}

/// The Flickable of the Agent, Battery, Network and Audio cards.
const BODY: u32 = 0;

/// A Flickable's contentY (clip: true, boundsBehavior: StopAtBounds), a
/// ListView's too, kept from draw to draw.
struct Flick {
    /// BODY, or a ListView's first row code.
    id: u32,
    /// The wheel's glide (300 ms OutExpo) towards its target.
    glide: Animated<f32>,
    /// Where contentY comes to rest when no glide runs.
    rest: f32,
    /// contentHeight - height at the last draw.
    max: f32,
    /// A ListView's model at the last draw (see model_sig).
    sig: u64,
    /// The viewport in the card's coordinates, if the last draw showed it.
    rect: Option<[f32; 4]>,
}

impl Flick {
    /// contentY now.
    fn y(&self, now: Instant) -> f32 {
        if self.glide.running(now) { self.glide.get(now) } else { self.rest }
    }

    /// setContentY / positionViewAtIndex: there at once; a glide stops.
    fn jump(&mut self, y: f32) {
        self.glide.snap(y);
        self.rest = y;
    }

    /// QQuickFlickable::wheelEvent (Qt 6.12, wheelDeceleration 15000 > 14999):
    /// a fixed wheelScrollLines (3) x 24 px per 120 of angleDelta, glided over
    /// 3/4 of fixupDuration (300 ms) OutExpo from where the content is now,
    /// cut at the bounds (StopAtBounds). At a bound in that direction it does
    /// not take the wheel (false).
    fn wheel(&mut self, angle_delta_y: f32, now: Instant) -> bool {
        let y = self.y(now);
        let step = -angle_delta_y / 120.0 * 72.0;
        if step == 0.0 || (step < 0.0 && y <= 0.0) || (step > 0.0 && y >= self.max) {
            return false;
        }
        let to = (y + step).clamp(0.0, self.max);
        self.glide.snap(y);
        self.glide.set(to, now);
        // fixup() when the glide ends: between the bounds, contentY goes to a
        // whole pixel - the nearest within a quarter, else back against the
        // motion (the sign of smoothVelocity). A glide started mid-glide ends
        // off the pixel grid.
        self.rest = if to <= 0.0 || to >= self.max || to.fract() == 0.0 {
            to
        } else if (to.round() - to).abs() < 0.25 {
            to.round()
        } else if step > 0.0 {
            to.floor()
        } else {
            to.ceil()
        };
        self.rest = self.rest.clamp(0.0, self.max);
        true
    }
}

/// A Flickable or ListView being drawn into the card, from view_begin() or
/// list_begin() to view_end().
pub(crate) struct View {
    rect: [f32; 4],
    /// contentY: the content is drawn this far up.
    pub off: f32,
    /// A ListView's row pitch (row height + spacing).
    pitch: f32,
    hits: usize,
    hover: Option<[f32; 4]>,
}

impl View {
    /// Where a ListView's row i is drawn.
    pub fn row_y(&self, i: usize) -> f32 {
        self.rect[1] - self.off + i as f32 * self.pitch
    }
}

/// A ListView model's value: QQuickItemView::setModel compares a new array
/// with the old one and only a different one replaces the rows.
pub(crate) fn model_sig<T: std::hash::Hash>(items: &[T]) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    items.hash(&mut h);
    h.finish()
}

pub(crate) const STEM_H: f32 = 12.0;
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
        // WifiWidget (networks): as wide as the longest SSID needs.
        CardKind::Wifi => (300.0, 0.0, Stem::Center),
        // BatteryWidget: 440 wide, max(200, min(content + 30, 620)).
        CardKind::Battery => (440.0, 0.0, Stem::Center),
        // WifiWidget's details view (NetworkPanel): 520 wide, max(200,
        // min(content + 30, 85% of the screen)).
        CardKind::Network => (520.0, 0.0, Stem::Center),
    }
}

/// The widget a card belongs to: the Wi-Fi widget's two views are one.
fn widget(kind: CardKind) -> CardKind {
    if kind == CardKind::Network { CardKind::Wifi } else { kind }
}

pub fn toggle(app: &mut App, strip: usize, kind: CardKind, icon: &Hit, keyboard: bool) {
    let was = app.card.as_ref().map(|c| (widget(c.kind), c.strip));
    close(app);
    if was == Some((widget(kind), strip)) {
        return;
    }
    open(app, strip, kind, icon, keyboard);
}

/// WifiWidget.onOtherClicked (right click): the details view closes itself,
/// the networks view turns into it in place, otherwise it opens.
pub fn wifi_details(app: &mut App, strip: usize, icon: &Hit) {
    match app.card.as_ref().map(|c| (c.kind, c.strip)) {
        Some((CardKind::Network, s)) if s == strip => close(app),
        Some((CardKind::Wifi, s)) if s == strip => {
            let w = geometry(CardKind::Network).0;
            let screen_h = app.strips.get(strip).map_or(1440.0, |s| s.screen_height);
            let card = app.card.as_mut().unwrap();
            card.kind = CardKind::Network;
            card.focus = None;
            card.focus_code = None;
            card.focus_seen = None;
            // NetworkPanel is new content: its Flickable starts at the top.
            card.flicks.clear();
            card.hits.clear();
            card.colors.clear();
            card.numbers.clear();
            card.texts = Default::default();
            crate::network_card::opened(app);
            let h = crate::network_card::card_height(&mut app.fonts, &app.svc, w, screen_h);
            let screen_w = app.strips.get(strip).map_or(2560.0, |s| s.screen_width);
            let card = app.card.as_mut().unwrap();
            let x = (card.icon_center - w / 2.0).min(screen_w - w).max(0.0).round();
            card.width = w;
            card.stem_cx = w / 2.0;
            card.height = h;
            card.left = x;
            card.win.dirty = true;
        }
        _ => {
            close(app);
            open(app, strip, CardKind::Network, icon, false);
        }
    }
}

fn open(app: &mut App, strip: usize, kind: CardKind, icon: &Hit, keyboard: bool) {
    let (mut w, mut h, stem) = geometry(kind);
    if kind == CardKind::Wifi {
        crate::wifi_card::opened(app);
        w = crate::wifi_card::card_width(&mut app.fonts, &app.svc);
        h = crate::wifi_card::card_height(&mut app.fonts, &app.svc);
    }
    let mut content_h = 0.0;
    if kind == CardKind::Network {
        let screen_h = app.strips[strip].screen_height;
        content_h = crate::network_card::content_height(&mut app.fonts, &app.svc, w);
        h = crate::network_card::card_height(&mut app.fonts, &app.svc, w, screen_h);
    }
    if kind == CardKind::Battery {
        crate::battery::opened(app);
        content_h = crate::battery::content_height(&mut app.fonts, &app.svc, w);
        h = crate::battery::card_height(&mut app.fonts, &app.svc, w);
    }
    let s = &app.strips[strip];
    let ui = crate::bar::ui_scale(s.screen_width);
    if kind == CardKind::Weather {
        h = weather_height(&mut app.fonts, &app.svc, w);
    }
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
    let (screen_w, screen_h) = (s.screen_width as u32, s.screen_height as u32);

    let surface = app.compositor.create_surface(&app.qh);
    let layer = app.layer_shell.create_layer_surface(&app.qh, surface, Layer::Top, Some("quickshell:card"), Some(&output));
    layer.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
    layer.set_exclusive_zone(-1);
    layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
    layer.commit();

    app.card = Some(OpenCard {
        kind,
        strip,
        win: Win::new(layer, screen_w, screen_h),
        hits: Vec::new(),
        pointer: None,
        shift: false,
        focus: if keyboard { Some(0) } else { None },
        focus_codes: Vec::new(),
        focus_code: None,
        focus_seen: None,
        focus_moved: false,
        wifi_password: false,
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
        meter_cells: 12,
        meter_at: None,
        meter_node: false,
        meter_win: None,
        tint_alert: false,
        numbers: HashMap::new(),
        flicks: Vec::new(),
        hover_clip: None,
        content_h,
        texts: Default::default(),
        notch_stale: false,
        icon_center,
        left: x.round(),
        top: y.round(),
    });
    app.strips[strip].win.dirty = true;
    if kind == CardKind::Weather {
        // CenterInfo's weather card is not a Loader: Qt makes its Texts' nodes
        // the first time it is shown and keeps them, so what changed since the
        // last opening is gray (the palette load at startup came before any node).
        if let Some(m) = app.weather_texts.take() {
            app.card.as_mut().unwrap().texts = m;
        }
    }
    if kind == CardKind::Pult {
        crate::pult::opened(app);
    }
    if kind == CardKind::Vpn {
        crate::vpn::opened(app);
    }
    if kind == CardKind::Agent {
        crate::agent::opened(app);
    }
    if kind == CardKind::Network {
        crate::network_card::opened(app);
        // The first status may change the height; the card follows.
        update_height(app);
    }
}

pub fn close(app: &mut App) {
    if app.card.as_ref().map(|c| c.kind) == Some(CardKind::Pult) {
        crate::pult::closed(app);
    }
    if app.card.as_ref().map(|c| c.kind) == Some(CardKind::Network) {
        crate::network_card::closed(app);
    }
    let Some(mut card) = app.card.take() else { return };
    // The meter's subsurface goes before the card's surface.
    card.meter_win = None;
    if card.kind == CardKind::Weather {
        app.weather_texts = Some(std::mem::take(&mut card.texts));
    }
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

/// A card whose height is a binding (the lists in it change): the card is
/// drawn at the new height; the surface stays as it is.
pub fn update_height(app: &mut App) {
    let Some(card) = app.card.as_ref() else { return };
    let h = match card.kind {
        CardKind::Pult => {
            let scanning = crate::pult::scanning(app);
            crate::pult::card_height(&mut app.fonts, &app.svc, scanning)
        }
        CardKind::Vpn => crate::vpn::card_height(&mut app.fonts, &app.svc),
        CardKind::Wifi => {
            let w = crate::wifi_card::card_width(&mut app.fonts, &app.svc);
            let h = crate::wifi_card::card_height(&mut app.fonts, &app.svc);
            let card = app.card.as_mut().unwrap();
            if (w - card.width).abs() >= 0.5 {
                // popupWidth moved: the centred card moves with it.
                let screen_w = app.strips.get(card.strip).map_or(2560.0, |s| s.screen_width);
                let x = (card.icon_center - w / 2.0).min(screen_w - w).max(0.0).round();
                card.width = w;
                card.stem_cx = w / 2.0;
                card.left = x;
                card.win.dirty = true;
            }
            h
        }
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
        CardKind::Network => {
            let w = app.card.as_ref().unwrap().width;
            let screen_h = app.strips.get(app.card.as_ref().unwrap().strip).map_or(1440.0, |s| s.screen_height);
            let content = crate::network_card::content_height(&mut app.fonts, &app.svc, w);
            if let Some(c) = app.card.as_mut() {
                c.content_h = content;
            }
            crate::network_card::card_height(&mut app.fonts, &app.svc, w, screen_h)
        }
        CardKind::Battery => {
            let w = app.card.as_ref().unwrap().width;
            let content = crate::battery::content_height(&mut app.fonts, &app.svc, w);
            if let Some(c) = app.card.as_mut() {
                c.content_h = content;
            }
            crate::battery::card_height(&mut app.fonts, &app.svc, w)
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
    card.win.dirty = true;
}

/// Whether a point of the card's surface is on the card (CardSurface's card
/// item, whose MouseArea takes every click on it) rather than around it.
pub fn inside(app: &App, x: f32, y: f32) -> bool {
    app.card.as_ref().map_or(false, |c| x >= c.left && x < c.left + c.width && y >= c.top && y < c.top + c.height)
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

/// What the shared controls need from the surface they are drawn on: hover,
/// focus, animated values and the text memo. A card is one; an OSD another.
pub(crate) trait UiState {
    fn color(&mut self, id: u32, target: Color, ms: u64, now: Instant) -> (Color, bool);
    fn number(&mut self, id: u32, target: f32, ms: u64, now: Instant) -> (f32, bool);
    fn pointer(&self) -> Option<(f32, f32)>;
    fn focus(&self) -> Option<usize>;
    fn tint_alert(&self) -> bool;
    fn texts(&mut self) -> &mut crate::text::TextMemo;
    /// Whether the control `code`, `index`-th in this draw's focus chain, has the focus.
    fn has_focus(&self, index: usize, _code: u32) -> bool {
        self.focus() == Some(index)
    }
    /// Hover stays inside this rect: a Flickable's clip, while it is drawn.
    fn hover_clip(&self) -> Option<[f32; 4]> {
        None
    }
}

impl UiState for OpenCard {
    fn has_focus(&self, index: usize, code: u32) -> bool {
        if self.focus != self.focus_seen {
            self.focus == Some(index)
        } else {
            self.focus_code == Some(code)
        }
    }
    fn hover_clip(&self) -> Option<[f32; 4]> {
        self.hover_clip
    }
    fn color(&mut self, id: u32, target: Color, ms: u64, now: Instant) -> (Color, bool) {
        OpenCard::color(self, id, target, ms, now)
    }
    fn number(&mut self, id: u32, target: f32, ms: u64, now: Instant) -> (f32, bool) {
        OpenCard::number(self, id, target, ms, now)
    }
    fn pointer(&self) -> Option<(f32, f32)> {
        self.pointer
    }
    fn focus(&self) -> Option<usize> {
        self.focus
    }
    fn tint_alert(&self) -> bool {
        self.tint_alert
    }
    fn texts(&mut self) -> &mut crate::text::TextMemo {
        &mut self.texts
    }
}

pub(crate) struct Ui<'a, S: UiState = OpenCard> {
    pub card: &'a mut S,
    pub scene: &'a mut Scene,
    pub fonts: &'a mut Fonts,
    pub theme: &'a Theme,
    pub now: Instant,
    pub animating: bool,
    pub hits: Vec<Hit>,
    pub focus_codes: Vec<u32>,
}

impl<S: UiState> Ui<'_, S> {
    pub fn hovered(&self, x: f32, y: f32, w: f32, h: f32) -> bool {
        let inside = |px: f32, py: f32, r: [f32; 4]| px >= r[0] && px < r[0] + r[2] && py >= r[1] && py < r[1] + r[3];
        self.card.pointer().map_or(false, |(px, py)| inside(px, py, [x, y, w, h]) && self.card.hover_clip().map_or(true, |c| inside(px, py, c)))
    }

    /// Adds a control to the focus chain (activeFocusOnTab); true if it has focus.
    pub fn focusable(&mut self, code: u32) -> bool {
        let i = self.focus_codes.len();
        self.focus_codes.push(code);
        self.card.has_focus(i, code)
    }

    /// A Text at (x, y): subpixel until it changes while the card is open
    /// (TextMemo), as Qt draws it.
    #[track_caller]
    pub fn text(&mut self, line: &Line, x: f32, y: f32, color: Color, style: TextStyle) {
        let site = crate::text::TextMemo::site(std::panic::Location::caller());
        let style = self.card.texts().style(site, line, color, style);
        self.scene.text(self.fonts, line, x, y + line.ascent, color, style);
    }

    /// A wrapped Text: its lines, one under the other, judged as one item.
    pub fn text_block(&mut self, id: u32, part: u64, lines: &[Line], x: f32, y: f32, color: Color) -> f32 {
        let style = self.card.texts().style_lines((part, id), lines, color, TextStyle::Normal);
        let mut ly = y;
        for l in lines {
            self.scene.text(self.fonts, l, x, ly + l.ascent, color, style);
            ly += l.height();
        }
        ly - y
    }

    /// A control's own Text (`part` of control `id`).
    pub fn text_of(&mut self, id: u32, part: u64, line: &Line, x: f32, y: f32, color: Color) {
        let style = self.card.texts().style_keyed((part, id), line, color, TextStyle::Normal);
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
            if self.card.tint_alert() { t.col_alert } else { t.col_accent }
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
            self.text_of(id, 0xB1, &icon_line, ix, iy, ic);
        }
        if !label.is_empty() {
            let cx = if icon.is_empty() { rx } else { rx + icon_box + 6.0 };
            let cy = ry + ac(row_h, cap.height());
            self.text_of(id, 0xB2, &cap, cx, cy, if current { t.col_bg } else { t.col_grey });
        }
        if enabled {
            self.hits.push(Hit { x, y, w, h, action: Action::Card(id) });
        }
    }
}

impl Ui<'_, OpenCard> {
    /// Flickable { clip: true; boundsBehavior: Flickable.StopAtBounds } at
    /// (x, y, w, h) over content `content_h` high: its content goes `off` up,
    /// is clipped to it, and only its visible part takes hover and clicks
    /// (Qt's pointerTargets stops at a clipping item), until view_end().
    pub fn view_begin(&mut self, id: u32, x: f32, y: f32, w: f32, h: f32, content_h: f32) -> View {
        let now = self.now;
        let f = self.card.flick(id, 0);
        f.max = (content_h - h).max(0.0);
        // A content or view size change puts it back inside: at once when it
        // rests (fixupMode Immediate), and a running glide ends at the new
        // bound (ExtentChanged).
        if f.glide.running(now) {
            if f.glide.target() > f.max {
                let y = f.glide.get(now);
                f.glide.snap(y);
                f.glide.set(f.max, now);
                f.rest = f.max;
            }
        } else if f.rest > f.max {
            f.jump(f.max);
        }
        f.rect = Some([x, y, w, h]);
        let off = f.y(now);
        self.animating |= f.glide.running(now);
        self.scene.save();
        self.scene.clip_rect(x, y, w, h);
        let hover = self.card.hover_clip;
        let r = [x, y, w, h];
        self.card.hover_clip = Some(match hover {
            Some(c) => {
                let (x0, y0) = (c[0].max(r[0]), c[1].max(r[1]));
                [x0, y0, ((c[0] + c[2]).min(r[0] + r[2]) - x0).max(0.0), ((c[1] + c[3]).min(r[1] + r[3]) - y0).max(0.0)]
            }
            None => r,
        });
        View { rect: r, off, pitch: 0.0, hits: self.hits.len(), hover }
    }

    /// ListView { clip: true; spacing; boundsBehavior: Flickable.StopAtBounds }
    /// at (x, y, w), `shown` rows high, over `count` rows of `row_h`: row i is
    /// the control base + i and is drawn at row_y(i); `pickable` says which
    /// rows take the keys' focus. `sig` is the model's value (model_sig): a
    /// different one is a new model, scrolled back to the top. When the keys
    /// move to a row, the list scrolls it into view (ConsoleRow:
    /// positionViewAtIndex(index, ListView.Contain)). Every row stays in the
    /// focus chain, in order, which is how ConsoleRow.stepInList/entryRow walk
    /// it. Ends with view_end().
    #[allow(clippy::too_many_arguments)]
    pub fn list_begin(&mut self, base: u32, x: f32, y: f32, w: f32, shown: usize, count: usize, row_h: f32, spacing: f32, sig: u64, pickable: impl Fn(usize) -> bool) -> View {
        let now = self.now;
        let pitch = row_h + spacing;
        let view_h = (shown as f32 * pitch - spacing).max(0.0);
        let content_h = if count == 0 { 0.0 } else { count as f32 * pitch - spacing };
        let chain_start = self.focus_codes.len();
        let card = &mut *self.card;
        let f = card.flick(base, sig);
        if f.sig != sig {
            f.sig = sig;
            f.jump(0.0);
            card.list_replaced(base);
        }
        // The row the focus moved to: an index set by code counts the
        // pickable rows from here; the keys name the row by its code.
        let row = if card.focus != card.focus_seen {
            card.focus.and_then(|p| p.checked_sub(chain_start)).and_then(|k| (0..count).filter(|i| pickable(*i)).nth(k))
        } else if card.focus_moved {
            card.focus_code.and_then(|c| c.checked_sub(base)).map(|i| i as usize).filter(|i| *i < count.min(0x100))
        } else {
            None
        };
        if let Some(i) = row {
            let f = card.flick(base, sig);
            let (top, y0) = (i as f32 * pitch, f.y(now));
            let mut p = y0;
            if top + row_h >= p + view_h {
                p = top + row_h - view_h;
            }
            if top < p {
                p = top;
            }
            f.jump(p.min((content_h - view_h).max(0.0)).max(0.0));
        }
        let mut v = self.view_begin(base, x, y, w, view_h, content_h);
        v.pitch = pitch;
        v
    }

    /// The end of view_begin()/list_begin(): the clip goes, and the controls
    /// drawn in the view take clicks only where it shows them.
    pub fn view_end(&mut self, v: View) {
        self.scene.restore();
        self.card.hover_clip = v.hover;
        let [vx, vy, vw, vh] = v.rect;
        let shown: Vec<Hit> = self
            .hits
            .drain(v.hits.min(self.hits.len())..)
            .filter_map(|h| {
                let (x0, y0) = (h.x.max(vx), h.y.max(vy));
                let (x1, y1) = ((h.x + h.w).min(vx + vw), (h.y + h.h).min(vy + vh));
                (x1 > x0 && y1 > y0).then_some(Hit { x: x0, y: y0, w: x1 - x0, h: y1 - y0, action: h.action })
            })
            .collect();
        self.hits.extend(shown);
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
        let id = gpu.add_image(iw, ih, rgba, false);
        card.notch = Some((id, key.0, key.1, key.2));
    }
    let (id, iw, ih, _) = card.notch.unwrap();
    let (ox, oy) = (card.left, card.top);
    scene.save();
    scene.translate(ox, oy);
    scene.image(id, 0.0, 0.0, iw as f32, ih as f32, [0.0, 0.0, 1.0, 1.0]);
    // Hover is tested in content coordinates.
    let pointer = card.pointer;
    card.pointer = pointer.map(|(px, py)| (px - ox, py - oy));

    card.texts.begin_frame();
    if card.kind == CardKind::Wifi && card.wifi_password != svc.wifi_card.password_mode {
        card.wifi_password = svc.wifi_card.password_mode;
        if card.wifi_password {
            // WifiWidget: passwordInput.forceActiveFocus() - enter_password
            // set the field's index in the chain this draw makes.
            card.focus_seen = None;
        } else {
            // The field and its keys hide: the keys go to the card's scope.
            card.focus = None;
            card.focus_seen = None;
            card.focus_code = None;
        }
    }
    // Only what this draw shows takes the wheel.
    card.flicks.iter_mut().for_each(|f| f.rect = None);
    card.hover_clip = None;
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
        CardKind::Calendar | CardKind::Weather | CardKind::Audio | CardKind::Pult | CardKind::Vpn | CardKind::Agent | CardKind::Wifi | CardKind::Battery | CardKind::Network => {}
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
    if ui.card.kind == CardKind::Wifi {
        crate::wifi_card::draw(&mut ui, w, svc, svc.wifi_connecting);
    }
    // The Flickable cards: the Loader's area, clipped, scrolled by contentY.
    let content_h = ui.card.content_h;
    if ui.card.kind == CardKind::Agent {
        let body = ui.view_begin(BODY, 8.0, STEM_H + 8.0, w - 16.0, h - 28.0, content_h);
        crate::agent::draw(&mut ui, w, svc, svc.agent_busy, STEM_H + 8.0 - body.off);
        ui.view_end(body);
    }
    if ui.card.kind == CardKind::Network {
        let body = ui.view_begin(BODY, 8.0, STEM_H + 8.0, w - 16.0, h - 28.0, content_h);
        crate::network_card::draw(&mut ui, w, svc, STEM_H + 8.0 - body.off);
        ui.view_end(body);
    }
    if ui.card.kind == CardKind::Battery {
        let body = ui.view_begin(BODY, 8.0, STEM_H + 8.0, w - 16.0, h - 28.0, content_h);
        crate::battery::draw(&mut ui, w, svc, STEM_H + 8.0 - body.off);
        ui.view_end(body);
    }
    if ui.card.kind == CardKind::Vpn {
        crate::vpn::draw(&mut ui, w, svc, svc.vpn_busy);
        if svc.vpn_busy.0 || svc.vpn_busy.1 {
            ui.animating = true;
        }
    }
    if ui.card.kind == CardKind::Audio {
        ui.card.sliders.clear();
        let body = ui.view_begin(BODY, 8.0, STEM_H + 8.0, w - 16.0, h - 28.0, content_h);
        crate::audio_card::draw(&mut ui, w, svc, STEM_H + 8.0 - body.off);
        ui.view_end(body);
    }
    let _ = svc;
    let (hits, codes, animating) = (std::mem::take(&mut ui.hits), std::mem::take(&mut ui.focus_codes), ui.animating);
    scene.restore();
    card.pointer = pointer;
    card.hits = hits.into_iter().map(|h| Hit { x: h.x + ox, y: h.y + oy, ..h }).collect();
    card.sliders.iter_mut().for_each(|s| s.1 += ox);
    // CardKeys' focus is on a control, not a place in the chain: it follows
    // its control when the chain changes; a control that left the chain
    // (disabled, hidden) leaves the keys with the card's scope until it is
    // back. An index set by code since the last draw names the control at
    // that place in this chain.
    if card.focus != card.focus_seen {
        card.focus_code = card.focus.and_then(|i| codes.get(i).copied());
    }
    card.focus = card.focus_code.and_then(|c| codes.iter().position(|x| *x == c));
    card.focus_seen = card.focus;
    card.focus_moved = false;
    card.focus_codes = codes;
    animating
}

/// ConsolePlate: the recessed plate, with its 1 px highlight along the bottom.
/// ConsoleLamp in its 10 x 10 slot at (x, y): halo and dot fade over 160 ms.
pub(crate) fn lamp<S: UiState>(ui: &mut Ui<S>, id: u32, x: f32, y: f32, lit: bool) {
    let tint = ui.theme.col_accent;
    lamp_tinted(ui, id, x, y, lit, tint);
}

pub(crate) fn lamp_tinted<S: UiState>(ui: &mut Ui<S>, id: u32, x: f32, y: f32, lit: bool, tint: Color) {
    let t = ui.theme;
    let (halo, r1) = ui.card.number(0x3_0000 + id, if lit { 0.22 } else { 0.0 }, 160, ui.now);
    let (dot, r2) = ui.card.color(0x4_0000 + id, if lit { tint } else { t.col_plate.darker(1.3) }, 160, ui.now);
    ui.animating |= r1 || r2;
    if halo > 0.0 {
        ui.scene.save();
        ui.scene.multiply_opacity(halo);
        ui.scene.rect(x + ac(10.0, 18.0), y + ac(10.0, 18.0), 18.0, 18.0, tint, 9.0, 0.0, Color::TRANSPARENT, true);
        ui.scene.restore();
    }
    let border = if lit { tint.lighter(1.25) } else { Color::qt_rgba(1.0, 1.0, 1.0, 0.12) };
    ui.scene.rect(x + ac(10.0, 9.0), y + ac(10.0, 9.0), 9.0, 9.0, dot, 4.5, 1.0, border, true);
}

/// ConsoleRow: lamp, optional icon, label (elided), optional detail and a
/// trailing text (an emoji flag), laid out by its RowLayout.
#[allow(clippy::too_many_arguments)]
pub(crate) fn console_row<S: UiState>(ui: &mut Ui<S>, code: u32, x: f32, y: f32, w: f32, h: f32, icon: &str, label: &str, lit: bool, interactive: bool, detail: Option<(&str, Color)>, trailing: Option<&str>) {
    let tint = ui.theme.col_accent;
    console_row_inner(ui, code, x, y, w, h, icon, label, lit, interactive, tint, detail, trailing.map(|t| (t, None)));
}

/// ConsoleRow with a lamp tint and a trailing glyph in the bar font (the lock).
#[allow(clippy::too_many_arguments)]
pub(crate) fn console_row_full<S: UiState>(ui: &mut Ui<S>, code: u32, x: f32, y: f32, w: f32, h: f32, icon: &str, label: &str, lit: bool, interactive: bool, tint: Color, detail: Option<(&str, Color)>, trailing: Option<(&str, Color)>) {
    console_row_inner(ui, code, x, y, w, h, icon, label, lit, interactive, tint, detail, trailing.map(|(s, c)| (s, Some(c))));
}

#[allow(clippy::too_many_arguments)]
fn console_row_inner<S: UiState>(ui: &mut Ui<S>, code: u32, x: f32, y: f32, w: f32, h: f32, icon: &str, label: &str, lit: bool, interactive: bool, tint: Color, detail: Option<(&str, Color)>, trailing: Option<(&str, Option<Color>)>) {
    let t = ui.theme;
    let font = FONT_SIZE - 3.0;
    let focused = interactive && ui.focusable(code);
    let hot = (interactive && ui.hovered(x, y, w, h)) || focused;
    let (bg, run) = ui.card.color(0x5_0000 + code, if hot { t.col_plate.lighter(1.6) } else { Color::TRANSPARENT }, 110, ui.now);
    ui.animating |= run;
    ui.scene.rect(x, y, w, h, bg, 4.0, if focused { 2.0 } else { 0.0 }, t.col_white, true);
    let mut cx = x + 6.0;
    lamp_tinted(ui, code, cx, y + qround((h - 10.0) / 2.0), lit, tint);
    cx += 10.0 + 8.0;
    let fg = if lit || hot { t.col_white } else { t.col_grey };
    if !icon.is_empty() {
        let il = ui.fonts.layout(icon, theme::bar_font(false), font, 0.0);
        ui.text_of(code, 0xC1, &il, cx + (font + 2.0 - il.adv) / 2.0, y + qround((h - il.height()) / 2.0), fg);
        cx += font + 2.0 + 8.0;
    }
    // The RowLayout's fixed cells are qCeil(implicitWidth) wide, on whole
    // pixels from the right edge; each Text starts at its cell. The trailing
    // Row is a cell (and a spacing) even when its Text is empty.
    let mut right = x + w - 6.0;
    match trailing {
        // The VPN card's flag: a Text with the app font at fontSize + 2.
        Some((tr, None)) => {
            let tl = ui.fonts.layout(tr, theme::FontKey { family: "Fira Code:medium", bold: false, plain: false }, FONT_SIZE + 2.0, 0.0);
            right -= tl.width.ceil();
            ui.text_of(code, 0xC2, &tl, right, y + qround((h - tl.height()) / 2.0), t.col_white);
            right -= 8.0;
        }
        // The Wi-Fi lock: Terminess at fontSize - 4.
        Some((tr, Some(col))) => {
            let tl = ui.fonts.layout(tr, theme::bar_font(false), FONT_SIZE - 4.0, 0.0);
            right -= tl.width.ceil();
            ui.text_of(code, 0xC2, &tl, right, y + qround((h - tl.height()) / 2.0), col);
            right -= 8.0;
        }
        None => {}
    }
    if let Some((d, dc)) = detail.filter(|d| !d.0.is_empty()) {
        let dl = ui.fonts.layout(d, theme::bar_font(false), font - 2.0, 0.0);
        right -= dl.width.ceil();
        ui.text_of(code, 0xC3, &dl, right, y + qround((h - dl.height()) / 2.0), dc);
        right -= 8.0;
    }
    let key = theme::bar_font(lit);
    let full = ui.fonts.layout(label, key, font, 0.0);
    let line = ui.fonts.elide_right(&full, label, key, right - cx, 0.0);
    ui.text_of(code, 0xC4, &line, cx, y + qround((h - line.height()) / 2.0), fg);
    if interactive {
        ui.hits.push(Hit { x, y, w, h, action: Action::Card(code) });
    }
}

fn qround(v: f32) -> f32 {
    (v + 0.5).floor()
}

/// ConsoleCaption: bold, fontSize - 5, letterSpacing 1.
pub(crate) fn caption(fonts: &mut Fonts, text: &str) -> crate::text::Line {
    fonts.layout(text, theme::bar_font(true), FONT_SIZE - 5.0, 1.0)
}

/// SegmentGauge: 28 cells, 2 px apart, the lit ones fading over 200 ms;
/// a white 2 px marker (when 0 < marker < 100).
pub(crate) fn gauge<S: UiState>(ui: &mut Ui<S>, x: f32, y: f32, w: f32, value: f32, marker: f32, tint: Color) {
    const SEGMENTS: u32 = 28;
    let lit = ((value.clamp(0.0, 100.0) / 100.0 * SEGMENTS as f32) + 0.5).floor() as u32;
    let cell = (w - 2.0 * (SEGMENTS - 1) as f32) / SEGMENTS as f32;
    for i in 0..SEGMENTS {
        let target = if i < lit { tint } else { Color::qt_rgba(1.0, 1.0, 1.0, 0.07) };
        let (c, run) = ui.card.color(0x6_0000 + i, target, 200, ui.now);
        ui.animating |= run;
        ui.scene.rect(x + i as f32 * (cell + 2.0), y, cell, 12.0, c, 1.0, 0.0, Color::TRANSPARENT, true);
    }
    if marker > 0.0 && marker < 100.0 {
        let mx = (w * marker / 100.0).round() - 1.0;
        ui.scene.fill(x + mx, y + ac(12.0, 20.0), 2.0, 20.0, ui.theme.col_white);
    }
}

/// An InfoGrid label/value pair: GLabel text, GValue text and colour.
pub(crate) type GridPair<'a> = (&'a str, String, Color);

const GRID_LABEL: f32 = FONT_SIZE - 4.0;
const GRID_VALUE: f32 = FONT_SIZE - 3.0;

fn grid_row_h(fonts: &mut Fonts) -> f32 {
    let l = fonts.layout("Ё", theme::bar_font(false), GRID_LABEL, 1.0).height();
    let v = fonts.layout("0", theme::bar_font(true), GRID_VALUE, 0.0).height();
    l.max(v)
}

pub(crate) fn info_grid_height(fonts: &mut Fonts, rows: usize) -> f32 {
    rows as f32 * grid_row_h(fonts) + rows.saturating_sub(1) as f32 * 4.0
}

/// InfoGrid: four columns (label, value, label, value), spacing 14 x 4; the
/// values (preferredWidth 0, fillWidth) share what the labels leave and are
/// right-aligned, elided. A row of one pair spans its value over the rest.
pub(crate) fn info_grid<S: UiState>(ui: &mut Ui<S>, x: f32, y: f32, w: f32, rows: &[Vec<GridPair>]) {
    let t = ui.theme;
    let lkey = theme::bar_font(false);
    let vkey = theme::bar_font(true);
    let mut label_w = [0f32; 2];
    for row in rows {
        for (c, cell) in row.iter().enumerate().take(2) {
            label_w[c] = label_w[c].max(ui.fonts.layout(cell.0, lkey, GRID_LABEL, 1.0).width.ceil());
        }
    }
    let value_w = ((w - 3.0 * 14.0 - label_w[0] - label_w[1]) / 2.0).max(0.0);
    let (cx, cw) = snap_columns([label_w[0], value_w, label_w[1], value_w], 14.0, w, [label_w[0], 0.0, label_w[1], 0.0]);
    let row_h = grid_row_h(ui.fonts);
    let mut ry = y;
    for row in rows {
        for (c, (label, value, vc)) in row.iter().enumerate().take(2) {
            let l = ui.fonts.layout(label, lkey, GRID_LABEL, 1.0);
            ui.text(&l, x + cx[2 * c], ry + ac(row_h, l.height()), t.col_dim, TextStyle::Normal);
            // A lone pair's value spans columns 1-3.
            let (vx, vw) = if row.len() == 1 { (cx[1], cx[3] + cw[3] - cx[1]) } else { (cx[2 * c + 1], cw[2 * c + 1]) };
            let full = ui.fonts.layout(value, vkey, GRID_VALUE, 0.0);
            let v = ui.fonts.elide_right(&full, value, vkey, vw, 0.0);
            ui.text(&v, x + vx + vw - v.adv, ry + ac(row_h, v.height()), *vc, TextStyle::Normal);
        }
        ry += row_h + 4.0;
    }
}

/// QGridLayoutRowData::calculateGeometries with snapToPixelGrid: each cell's
/// start is qRound()ed, its neighbours absorb the difference, the last one
/// ends at the layout's edge, then every size is qRound()ed (not below its
/// minimum).
fn snap_columns<const N: usize>(sizes: [f32; N], spacing: f32, target: f32, minimum: [f32; N]) -> ([f32; N], [f32; N]) {
    let mut pos = [0f32; N];
    let mut size = sizes;
    for i in 1..N {
        pos[i] = pos[i - 1] + size[i - 1] + spacing;
    }
    let qround = |v: f32| (v + 0.5).floor();
    for i in 0..N {
        let old = pos[i];
        pos[i] = qround(old);
        let delta = pos[i] - old;
        size[i] -= delta;
        if i > 0 {
            size[i - 1] += delta;
        }
    }
    size[N - 1] = target - pos[N - 1];
    for i in 0..N {
        size[i] = minimum[i].max(qround(size[i]));
    }
    (pos, size)
}

pub(crate) fn plate<S: UiState>(ui: &mut Ui<S>, x: f32, y: f32, w: f32, h: f32) {
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
    if c.kind == CardKind::Audio {
        // A VolumeSlider under the pointer takes it first: 5% a notch.
        let over = c.pointer.and_then(|(px, py)| c.sliders.iter().find(|s| px >= s.1 && px < s.1 + s.2 && py >= 0.0).map(|s| s.0));
        let over = over.filter(|code| c.hits.iter().any(|h| h.action == Action::Card(*code) && c.pointer.map_or(false, |(px, py)| h.contains(px, py))));
        if let Some(code) = over {
            crate::audio_card::slider_step(app, code, angle_delta_y > 0.0);
            return;
        }
    }
    // Then the Flickable under the pointer, a ListView before the card's
    // own; one at its end that way lets the wheel go on to what is under it.
    // The card's margins and stem are no Flickable: nothing scrolls there.
    let now = Instant::now();
    let at = c.pointer.map(|(px, py)| (px - c.left, py - c.top));
    let under = |f: &Flick| match (f.rect, at) {
        (Some(r), Some((x, y))) => x >= r[0] && x < r[0] + r[2] && y >= r[1] && y < r[1] + r[3],
        _ => false,
    };
    for body in [false, true] {
        if let Some(i) = c.flicks.iter().position(|f| (f.id == BODY) == body && under(f)) {
            if c.flicks[i].wheel(angle_delta_y, now) {
                c.win.dirty = true;
                return;
            }
        }
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
        CardKind::Wifi => crate::wifi_card::activate(app, i),
        CardKind::Battery => crate::battery::activate(app, i),
        CardKind::Network => crate::network_card::activate(app, i),
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
        // armEnd(): by keyboard these arm the power menu's countdown on that
        // order (a stray "Up, Enter" used to power off on the spot).
        close(app);
        let k = ["L", "E", "R", "S"][i.min(3) as usize];
        app.after(Duration::from_millis(0), match k {
            "E" => |app: &mut App| crate::power::arm_end(app, "E"),
            "R" => |app: &mut App| crate::power::arm_end(app, "R"),
            _ => |app: &mut App| crate::power::arm_end(app, "S"),
        });
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
pub fn key(app: &mut App, sym: Keysym, utf8: Option<&str>) {
    if app.card.as_ref().map(|c| c.kind) == Some(CardKind::Wifi) && crate::wifi_card::input_key(app, sym, utf8) {
        return;
    }
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
    let back = card.shift;
    match sym {
        Keysym::Escape => close(app),
        Keysym::Tab | Keysym::Down | Keysym::Right if !(sym == Keysym::Tab && back) => card.step_focus(true),
        Keysym::ISO_Left_Tab | Keysym::Tab | Keysym::Up | Keysym::Left => card.step_focus(false),
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
