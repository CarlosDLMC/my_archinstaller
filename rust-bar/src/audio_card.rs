//! The volume widget's card (AudioPanel.qml): output and input with their
//! faders and device lists, the live mic meter, per-application faders.

use std::time::Instant;

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{plate, Ui};
use crate::color::Color;
use crate::gpu::{Scene, TextStyle};
use crate::pw::{Audio, NodeInfo};
use crate::services::Services;
use crate::text::Line;
use crate::theme::{self, Theme, FONT_SIZE};
use wayland_client::protocol::{wl_subsurface::WlSubsurface, wl_surface::WlSurface};

pub const OUT_MUTE: u32 = 1;
pub const OUT_SLIDER: u32 = 2;
pub const IN_MUTE: u32 = 3;
pub const IN_SLIDER: u32 = 4;
pub const SINK_ROW: u32 = 0x100;
pub const SOURCE_ROW: u32 = 0x200;
pub const STREAM_MUTE: u32 = 0x300;
pub const STREAM_SLIDER: u32 = 0x400;

const LABEL: f32 = FONT_SIZE - 2.0;
const HEADER: f32 = FONT_SIZE - 4.0;
const ROW_FONT: f32 = FONT_SIZE - 3.0;

/// What the card lists: VolumeWidget's sinkList / sourceList / streamList.
pub struct Lists {
    pub sink: (Audio, Option<NodeInfo>),
    pub source: (Audio, Option<NodeInfo>),
    pub sinks: Vec<NodeInfo>,
    pub sources: Vec<NodeInfo>,
    pub streams: Vec<(NodeInfo, Audio)>,
}

pub fn lists(svc: &Services) -> Lists {
    let Some(pw) = svc.pw.as_ref() else {
        return Lists { sink: Default::default(), source: Default::default(), sinks: vec![], sources: vec![], streams: vec![] };
    };
    let nodes = pw.nodes();
    let sink = pw.default_node(true);
    let source = pw.default_node(false);
    let mut sinks: Vec<NodeInfo> = nodes.iter().filter(|n| n.0.is_sink()).map(|n| n.0.clone()).collect();
    if let Some(s) = &sink.1 {
        if !sinks.iter().any(|n| n.id == s.id) {
            sinks.insert(0, s.clone());
        }
    }
    let mut sources: Vec<NodeInfo> = nodes.iter().filter(|n| n.0.is_source()).map(|n| n.0.clone()).collect();
    if let Some(s) = &source.1 {
        if !sources.iter().any(|n| n.id == s.id) {
            sources.insert(0, s.clone());
        }
    }
    let streams = nodes.into_iter().filter(|n| n.0.is_playback_stream() && n.1.ready).collect();
    Lists { sink, source, sinks, sources, streams }
}

/// nodeLabel(): nick, then profile description, description, name.
fn node_label(n: &NodeInfo) -> String {
    [&n.nick, &n.profile_description, &n.description, &n.name].into_iter().find(|s| !s.is_empty()).cloned().unwrap_or_else(|| "Unknown".into())
}

fn blob(n: &NodeInfo) -> String {
    format!("{} {} {} {} {} {}", n.name, n.description, n.nick, n.icon_name, n.product_name, n.description).to_lowercase()
}

fn sink_glyph(n: &NodeInfo) -> &'static str {
    let b = blob(n);
    if ["headphone", "headset", "earbud", "earphone", "airpod"].iter().any(|k| b.contains(k)) {
        "\u{f02cb}"
    } else if b.contains("bluetooth") || b.contains("bluez") {
        "\u{f00af}"
    } else if b.contains("hdmi") || b.contains("displayport") || b.contains("display") {
        "\u{f0379}"
    } else {
        "\u{f057e}"
    }
}

fn source_glyph(n: &NodeInfo) -> &'static str {
    let b = blob(n);
    if b.contains("headset") {
        "\u{f02cb}"
    } else if b.contains("bluetooth") || b.contains("bluez") {
        "\u{f00af}"
    } else {
        "\u{f036c}"
    }
}

fn stream_label(n: &NodeInfo) -> String {
    [&n.app_name, &n.media_name, &n.description, &n.name].into_iter().find(|s| !s.is_empty()).cloned().unwrap_or_else(|| "Stream".into())
}

fn pct(a: &Audio) -> String {
    if a.ready {
        format!("{}%", (a.volume * 100.0).round() as i64)
    } else {
        "—".into()
    }
}

/// The heights everything is laid out with (shared by measuring and drawing).
struct Metrics {
    cap_h: f32,
    btn_w: f32,
    btn_h: f32,
    row_h: f32,
    name_h: f32,
}

fn metrics(fonts: &mut crate::text::Fonts) -> Metrics {
    let font = HEADER - 2.0;
    Metrics {
        cap_h: (HEADER * 1.6).round(),
        btn_w: (font + 2.0) + 26.0,
        btn_h: (font * 2.1).round(),
        row_h: (ROW_FONT * 1.75).round(),
        name_h: fonts.layout("Ag", theme::bar_font(false), HEADER + 1.0, 0.0).height(),
    }
}

/// Column { spacing 8: out plate, in plate, apps plate, empty text }.
pub fn content_height(fonts: &mut crate::text::Fonts, svc: &Services) -> f32 {
    let l = lists(svc);
    let m = metrics(fonts);
    let mut parts = Vec::new();
    // out plate: header, fader row, device rows (spacing 6), pad 10
    let out_inner = m.cap_h + 6.0 + m.btn_h + l.sinks.len() as f32 * (6.0 + m.row_h);
    parts.push(out_inner + 20.0);
    if !l.sources.is_empty() || l.source.0.ready {
        let in_inner = m.cap_h + 6.0 + m.btn_h + 6.0 + 6.0 + l.sources.len() as f32 * (6.0 + m.row_h);
        parts.push(in_inner + 20.0);
    }
    if !l.streams.is_empty() {
        let row = m.btn_h.max(m.name_h + 2.0 + 20.0);
        let apps_inner = m.cap_h + l.streams.len() as f32 * (8.0 + row);
        parts.push(apps_inner + 20.0);
    }
    if l.sinks.is_empty() && l.streams.is_empty() {
        parts.push(fonts.layout("Нет", theme::bar_font(false), LABEL, 0.0).height());
    }
    parts.iter().sum::<f32>() + 8.0 * (parts.len().saturating_sub(1)) as f32
}

fn section_header(ui: &mut Ui, x: f32, y: f32, w: f32, h: f32, label: &str, detail: &str) {
    let t = ui.theme;
    let cap = ui.fonts.layout(label, theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
    ui.text(&cap, x, y + ac(h, cap.height()), t.col_dim, TextStyle::Normal);
    if !detail.is_empty() {
        let d = ui.fonts.layout(detail, theme::bar_font(true), HEADER + 2.0, 0.0);
        ui.text(&d, x + w - d.width, y + ac(h, d.height()), t.col_white, TextStyle::Normal);
    }
}

/// VolumeSlider: a SegmentGauge under a 6 x 20 handle; max > 1 marks 100%.
#[allow(clippy::too_many_arguments)]
fn slider(ui: &mut Ui, code: u32, x: f32, y: f32, w: f32, value: f32, max: f32, muted: bool, enabled: bool) {
    let t = ui.theme;
    let focused = if enabled { ui.focusable(code) } else { false };
    ui.scene.save();
    if !enabled {
        ui.scene.multiply_opacity(0.4);
    }
    if focused {
        ui.scene.rect(x - 3.0, y - 3.0, w + 6.0, 26.0, Color::TRANSPARENT, 4.0, 2.0, t.col_white, true);
    }
    let ratio = if max > 0.0 { (value / max).clamp(0.0, 1.0) } else { 0.0 };
    // SegmentGauge, 10 high, centred in the 20 px slider
    let gy = y + 5.0;
    let n = 12.max((w / 12.0).round() as i32);
    let cell = (w - 2.0 * (n - 1) as f32) / n as f32;
    let lit = ((ratio * 100.0).clamp(0.0, 100.0) / 100.0 * n as f32).round() as i32;
    let tint = if muted { t.col_muted } else { t.col_accent };
    for i in 0..n {
        let target = if i < lit { tint } else { Color::qt_rgba(1.0, 1.0, 1.0, 0.07) };
        // A range of its own: code * 64 for an app's slider (code 1024 and up)
        // ran into the handles' 0x2_0000 + code, and the two colours took turns
        // restarting each other - the card redrew at the screen's refresh rate.
        let (c, run) = ui.card.color(0x100_0000 + code * 64 + i as u32, target, 200, ui.now);
        ui.animating |= run;
        ui.scene.rect(x + i as f32 * (cell + 2.0), gy, cell, 10.0, c, 1.0, 0.0, Color::TRANSPARENT, true);
    }
    if max > 1.0 {
        let marker = 100.0 / max * 100.0;
        if marker > 0.0 && marker < 100.0 {
            let mx = (w * marker / 100.0).round() - 1.0;
            ui.scene.fill(x + mx, gy + ac(10.0, 18.0), 2.0, 18.0, t.col_white);
        }
    }
    let hx = x + ((w - 6.0) * ratio).round();
    let (hc, run) = ui.card.color(0x2_0000 + code, if muted { t.col_grey } else { t.col_white }, 130, ui.now);
    ui.animating |= run;
    ui.scene.rect(hx, y, 6.0, 20.0, hc, 2.0, 1.0, t.col_bg, true);
    ui.scene.restore();
    if enabled {
        ui.hits.push(Hit { x, y, w, h: 20.0, action: Action::Card(code) });
        ui.card.sliders.push((code, x, w, max));
    }
}

/// ConsoleRow (AudioPanel's device rows: interactive: !lit): the shared
/// one, whose lamp dot sits where Qt's anchors.centerIn puts it.
fn console_row(ui: &mut Ui, code: u32, x: f32, y: f32, w: f32, h: f32, icon: &str, label: &str, lit: bool) {
    crate::cards::console_row(ui, code, x, y, w, h, icon, label, lit, !lit, None, None);
}

pub fn draw(ui: &mut Ui, w: f32, svc: &Services, top: f32) {
    // The meter's place is this draw's: none if the ВХОД plate went away
    // (its LevelMeter goes with it), or the meter surface stayed live there.
    ui.card.meter_at = None;
    ui.card.meter_node = false;
    let t = ui.theme;
    let l = lists(svc);
    let m = metrics(ui.fonts);
    let (x0, cw) = (8.0, w - 16.0);
    let (ix, iw) = (x0 + 10.0, cw - 20.0);
    let mut y = top;
    let font = HEADER - 2.0;
    let mute_icon = |muted: bool| if muted { "\u{f075f}" } else { "\u{f057e}" };

    // ВЫХОД
    let out_h = m.cap_h + 6.0 + m.btn_h + l.sinks.len() as f32 * (6.0 + m.row_h) + 20.0;
    plate(ui, x0, y, cw, out_h);
    let mut cy = y + 10.0;
    section_header(ui, ix, cy, iw, m.cap_h, "ВЫХОД", &pct(&l.sink.0));
    cy += m.cap_h + 6.0;
    let muted = l.sink.0.muted;
    ui.card.tint_alert = true;
    ui.console_button_sized(OUT_MUTE, ix, cy, m.btn_w, font, mute_icon(muted), t.col_grey, "", muted);
    ui.card.tint_alert = false;
    slider(ui, OUT_SLIDER, ix + m.btn_w + 10.0, cy + ac(m.btn_h, 20.0), iw - m.btn_w - 10.0, l.sink.0.volume, 1.0, muted, l.sink.0.ready);
    cy += m.btn_h;
    for (i, n) in l.sinks.iter().enumerate() {
        cy += 6.0;
        let lit = l.sink.1.as_ref().map_or(false, |s| s.id == n.id);
        console_row(ui, SINK_ROW + i as u32, ix, cy, iw, m.row_h, sink_glyph(n), &node_label(n), lit);
        cy += m.row_h;
    }
    y += out_h + 8.0;

    // ВХОД
    if !l.sources.is_empty() || l.source.0.ready {
        let in_h = m.cap_h + 6.0 + m.btn_h + 6.0 + 6.0 + l.sources.len() as f32 * (6.0 + m.row_h) + 20.0;
        plate(ui, x0, y, cw, in_h);
        let mut cy = y + 10.0;
        section_header(ui, ix, cy, iw, m.cap_h, "ВХОД", &pct(&l.source.0));
        cy += m.cap_h + 6.0;
        let muted = l.source.0.muted;
        ui.card.tint_alert = true;
        ui.console_button_sized(IN_MUTE, ix, cy, m.btn_w, font, if muted { "\u{f036d}" } else { "\u{f036c}" }, t.col_grey, "", muted);
        ui.card.tint_alert = false;
        slider(ui, IN_SLIDER, ix + m.btn_w + 10.0, cy + ac(m.btn_h, 20.0), iw - m.btn_w - 10.0, l.source.0.volume, 1.0, muted, l.source.0.ready);
        cy += m.btn_h + 6.0;
        level_meter(ui, ix + m.btn_w + 10.0, cy, iw - m.btn_w - 10.0, l.source.0.ready);
        cy += 6.0;
        for (i, n) in l.sources.iter().enumerate() {
            cy += 6.0;
            let lit = l.source.1.as_ref().map_or(false, |s| s.id == n.id);
            console_row(ui, SOURCE_ROW + i as u32, ix, cy, iw, m.row_h, source_glyph(n), &node_label(n), lit);
            cy += m.row_h;
        }
        y += in_h + 8.0;
    }

    // ПРИЛОЖЕНИЯ
    if !l.streams.is_empty() {
        let row = m.btn_h.max(m.name_h + 2.0 + 20.0);
        let apps_h = m.cap_h + l.streams.len() as f32 * (8.0 + row) + 20.0;
        plate(ui, x0, y, cw, apps_h);
        let mut cy = y + 10.0;
        section_header(ui, ix, cy, iw, m.cap_h, "ПРИЛОЖЕНИЯ", "");
        cy += m.cap_h;
        for (i, (n, a)) in l.streams.iter().enumerate() {
            cy += 8.0;
            let i = i as u32;
            ui.card.tint_alert = true;
            ui.console_button_sized(STREAM_MUTE + i, ix, cy + ac(row, m.btn_h), m.btn_w, font, mute_icon(a.muted), t.col_grey, "", a.muted);
            ui.card.tint_alert = false;
            let colx = ix + m.btn_w + 10.0;
            let colw = iw - m.btn_w - 10.0;
            let col_y = cy + ac(row, (m.name_h + 2.0 + 20.0));
            let pl = ui.fonts.layout(&format!("{}%", (a.volume * 100.0).round() as i64), theme::bar_font(true), HEADER + 1.0, 0.0);
            ui.text(&pl, colx + colw - pl.width, col_y, t.col_white, TextStyle::Normal);
            let name = stream_label(n);
            let nk = theme::bar_font(false);
            let full = ui.fonts.layout(&name, nk, HEADER + 1.0, 0.0);
            let line: Line = ui.fonts.elide_right(&full, &name, nk, colw - pl.width - 8.0, 0.0);
            ui.text(&line, colx, col_y, t.col_grey, TextStyle::Normal);
            slider(ui, STREAM_SLIDER + i, colx, col_y + m.name_h + 2.0, colw, a.volume, 1.5, a.muted, true);
            cy += row;
        }
        y += apps_h + 8.0;
    }
    if l.sinks.is_empty() && l.streams.is_empty() {
        let e = ui.fonts.layout("Нет аудиоустройств", theme::bar_font(false), LABEL, 0.0);
        ui.text(&e, x0 + (cw - e.adv) / 2.0, y, t.col_grey, TextStyle::Normal);
    }
}

/// The meter on a surface of its own, redrawn alone while only the level
/// moves: a few hundred pixels instead of the card's full-screen surface. It
/// is a subsurface BELOW the card's, seen through a hole the card leaves at
/// the meter (Scene::hole), and paints the plate under its segments itself.
/// Below, not above: mango blurs behind a layer through the last buffer of
/// its tree (iter_layer_scene_buffers), and the meter's 230 x 6 px stretched
/// over the screen blurred all of it but the gaps between the segments.
/// Clicks go through it (an empty input region).
pub struct MeterWin {
    pub surface: WlSurface,
    sub: WlSubsurface,
    pub gpu: Option<(wgpu::Surface<'static>, wgpu::SurfaceConfiguration)>,
    /// Its place on the card's surface and the meter's fraction of a pixel in it.
    pos: (i32, i32),
    pub frac: (f32, f32),
    pub size: (u32, u32),
    pub width: f32,
    /// The card leaves the segments to this surface.
    pub live: bool,
    /// What its last frame was painted with besides the level (meter_look).
    pub look: Option<MeterLook>,
    pub dirty: bool,
    pub frame_pending: bool,
}

/// The palette a meter frame paints (plate, accent, alert, white) and
/// whether the meter had a node.
pub type MeterLook = (Color, Color, Color, Color, bool);

pub fn meter_look(t: &Theme, node: bool) -> MeterLook {
    (t.col_plate, t.col_accent, t.col_alert, t.col_white, node)
}

impl MeterWin {
    pub fn new(app: &App, parent: &WlSurface) -> Option<MeterWin> {
        let (sub, surface) = app.subcompositor.as_ref()?.create_subsurface(parent.clone(), &app.qh);
        sub.place_below(parent);
        sub.set_desync();
        if let Ok(region) = smithay_client_toolkit::compositor::Region::new(&app.compositor) {
            surface.set_input_region(Some(region.wl_region()));
        }
        surface.commit();
        Some(MeterWin { surface, sub, gpu: None, pos: (i32::MIN, i32::MIN), frac: (0.0, 0.0), size: (0, 0), width: 0.0, live: false, look: None, dirty: true, frame_pending: false })
    }

    /// Puts the surface's corner at the whole pixel under (x, y) of the
    /// card's surface; it takes effect with the card's next commit. True if
    /// it moved.
    pub fn move_to(&mut self, x: f32, y: f32) -> bool {
        let pos = (x.floor() as i32, y.floor() as i32);
        if self.pos == pos {
            return false;
        }
        self.pos = pos;
        self.sub.set_position(pos.0, pos.1);
        true
    }

    /// Follows the card's last draw: the meter at (x, y), w wide on the card's
    /// surface, or out of view. True when the card must be drawn again (the
    /// segments move between the two surfaces, or the new place needs the
    /// card's next commit). Its own frame is redrawn only if it changes.
    pub fn place(&mut self, at: Option<(f32, f32, f32)>) -> bool {
        let Some((x, y, w)) = at else {
            let was = self.live;
            self.live = false;
            self.dirty |= was;
            return was;
        };
        let (ix, iy) = (x.floor(), y.floor());
        let frac = (x - ix, y - iy);
        let size = ((w + frac.0).ceil() as u32, (6.0 + frac.1).ceil() as u32);
        let moved = self.move_to(x, y);
        let card = !self.live || moved;
        if (frac, size, w, true) != (self.frac, self.size, self.width, self.live) {
            (self.frac, self.size, self.width, self.live) = (frac, size, w, true);
            self.dirty = true;
        }
        card
    }
}

impl Drop for MeterWin {
    fn drop(&mut self) {
        // The swapchain goes before the surface it presents to.
        self.gpu = None;
        self.sub.destroy();
        self.surface.destroy();
    }
}

/// LevelMeter's segments and hold marker, w wide at (x, y): on the card, or
/// on the meter's own surface.
pub fn meter_cells(scene: &mut Scene, t: &Theme, x: f32, y: f32, w: f32, level: f32, hold: f32) {
    let n = 12.max((w / 12.0).round() as i32);
    let cell = (w - 2.0 * (n - 1) as f32) / n as f32;
    let lit = (level * n as f32).round() as i32;
    let hot_from = ((-6.0f32 + 60.0) / 60.0 * n as f32).round() as i32;
    for i in 0..n {
        let c = if i >= lit {
            Color::qt_rgba(1.0, 1.0, 1.0, 0.07)
        } else if i >= hot_from {
            t.col_alert
        } else {
            t.col_accent
        };
        scene.rect(x + i as f32 * (cell + 2.0), y, cell, 6.0, c, 1.0, 0.0, Color::TRANSPARENT, true);
    }
    if hold > 0.02 {
        let hx = (w - cell.max(2.0)).min((hold * n as f32).floor() * (cell + 2.0));
        scene.rect(x + hx, y, cell.max(2.0), 6.0, t.col_white, 1.0, 0.0, Color::TRANSPARENT, true);
    }
}

/// LevelMeter: dB-scaled live level with a falling bar and a peak hold.
fn level_meter(ui: &mut Ui, x: f32, y: f32, w: f32, has_node: bool) {
    ui.card.meter_cells = 12.max((w / 12.0).round() as i32);
    let (level, hold) = if has_node { (ui.card.meter.0, ui.card.meter.1) } else { (0.0, 0.0) };
    ui.card.meter_node = has_node;
    // Fully inside the Flickable's clip: on its own surface (MeterWin).
    let inside = y >= crate::cards::STEM_H + 8.0 && y + 6.0 <= ui.card.card_height() - 8.0;
    let (ox, oy) = ui.card.origin();
    ui.card.meter_at = inside.then_some((ox + x, oy + y, w));
    if let Some(m) = ui.card.meter_win.as_mut().filter(|m| inside && m.live) {
        // Moved now, so the card's commit that cuts the hole at the new place
        // also brings the meter there - moved after it, the hole showed what
        // is behind the card for a frame.
        m.move_to(ox + x, oy + y);
        // The whole pixels MeterWin covers (see place()).
        let (hx, hy) = (x.floor(), y.floor());
        ui.scene.hole(hx, hy, (x + w).ceil() - hx, (y + 6.0).ceil() - hy);
        return;
    }
    let t = ui.theme;
    meter_cells(ui.scene, t, x, y, w, level, hold);
}

/// The meter's 33 ms tick: level falls 0.025 a tick, the hold stays 30 ticks
/// then falls 0.02 a tick. The card is redrawn only when that moves a lit
/// segment or the hold marker - Qt repaints only what changed, and a silent
/// mic redrew the card (and mango re-composited it) 30 times a second.
pub fn meter_tick(app: &mut App) -> bool {
    let Some(card) = app.card.as_mut() else { return false };
    if card.kind != crate::cards::CardKind::Audio {
        return false;
    }
    let audio = app.svc.pw.as_ref().map(|p| p.source_audio()).unwrap_or_default();
    let peak = app.svc.pw.as_ref().map_or(0.0, |p| p.peak());
    let target = if audio.muted || !audio.ready || !(peak > 0.0) {
        0.0
    } else {
        let db = 20.0 * peak.log10();
        ((db + 60.0) / 60.0).clamp(0.0, 1.0)
    };
    let n = card.meter_cells as f32;
    let shown = |level: f32, hold: f32| ((level * n).round() as i32, hold > 0.02, (hold * n).floor() as i32);
    let before = shown(card.meter.0, card.meter.1);
    let (level, hold, ticks) = &mut card.meter;
    *level = target.max(*level - 0.025);
    if target >= *hold {
        *hold = target;
        *ticks = 30;
    } else if *ticks > 0 {
        *ticks -= 1;
    } else {
        *hold = level.max(*hold - 0.02);
    }
    if shown(card.meter.0, card.meter.1) != before {
        match card.meter_win.as_mut().filter(|m| m.live) {
            Some(m) => m.dirty = true,
            None => card.win.dirty = true,
        }
    }
    true
}

/// A press: mute buttons and device rows act on release (activate); a
/// slider jumps to the pointer and follows it while dragged.
pub fn slider_to(app: &mut App, code: u32, x: f32) {
    let Some(card) = app.card.as_ref() else { return };
    let Some(&(_, sx, sw, max)) = card.sliders.iter().find(|s| s.0 == code) else { return };
    let v = ((x - sx) / sw.max(1.0)).clamp(0.0, 1.0) * max;
    set_volume(app, code, v);
}

fn target_of(app: &App, code: u32) -> Option<(u32, Audio)> {
    let l = lists(&app.svc);
    match code {
        OUT_SLIDER | OUT_MUTE => l.sink.1.map(|n| (n.id, l.sink.0.clone())),
        IN_SLIDER | IN_MUTE => l.source.1.map(|n| (n.id, l.source.0.clone())),
        c if (STREAM_MUTE..STREAM_MUTE + 0x100).contains(&c) => l.streams.get((c - STREAM_MUTE) as usize).map(|(n, a)| (n.id, a.clone())),
        c if (STREAM_SLIDER..STREAM_SLIDER + 0x100).contains(&c) => l.streams.get((c - STREAM_SLIDER) as usize).map(|(n, a)| (n.id, a.clone())),
        _ => None,
    }
}

fn set_volume(app: &mut App, code: u32, v: f32) {
    let max = if code >= STREAM_SLIDER { 1.5 } else { 1.0 };
    if let (Some((id, _)), Some(pw)) = (target_of(app, code), app.svc.pw.as_ref()) {
        pw.set_volume(id, v.clamp(0.0, max));
    }
}

fn toggle_mute(app: &mut App, code: u32) {
    if let (Some((id, a)), Some(pw)) = (target_of(app, code), app.svc.pw.as_ref()) {
        pw.set_mute(id, !a.muted);
    }
}

pub fn is_slider(code: u32) -> bool {
    code == OUT_SLIDER || code == IN_SLIDER || (STREAM_SLIDER..STREAM_SLIDER + 0x100).contains(&code)
}

pub fn activate(app: &mut App, code: u32) {
    let l = lists(&app.svc);
    match code {
        OUT_MUTE | IN_MUTE => toggle_mute(app, code),
        c if (SINK_ROW..SINK_ROW + 0x100).contains(&c) => {
            if let (Some(n), Some(pw)) = (l.sinks.get((c - SINK_ROW) as usize), app.svc.pw.as_ref()) {
                pw.set_default(true, &n.name);
            }
        }
        c if (SOURCE_ROW..SOURCE_ROW + 0x100).contains(&c) => {
            if let (Some(n), Some(pw)) = (l.sources.get((c - SOURCE_ROW) as usize), app.svc.pw.as_ref()) {
                pw.set_default(false, &n.name);
            }
        }
        c if (STREAM_MUTE..STREAM_MUTE + 0x100).contains(&c) => toggle_mute(app, c),
        c if is_slider(c) => {}
        _ => {}
    }
}

/// A slider's right click / Return / Space / M: its mute (rightClicked).
pub fn slider_mute(app: &mut App, code: u32) {
    let mute = match code {
        OUT_SLIDER => OUT_MUTE,
        IN_SLIDER => IN_MUTE,
        c => STREAM_MUTE + (c - STREAM_SLIDER),
    };
    toggle_mute(app, mute);
}

/// Left/Right on a focused slider, or a wheel notch over it: 5% of its range.
pub fn slider_step(app: &mut App, code: u32, up: bool) {
    let max = if code >= STREAM_SLIDER { 1.5 } else { 1.0 };
    if let Some((_, a)) = target_of(app, code) {
        let step = max * 0.05;
        set_volume(app, code, a.volume + if up { step } else { -step });
    }
}

pub fn now() -> Instant {
    Instant::now()
}
