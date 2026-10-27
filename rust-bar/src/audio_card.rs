//! The volume widget's card (AudioPanel.qml): output and input with their
//! faders and device lists, the live mic meter, per-application faders.

use std::time::Instant;

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{plate, Ui};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::pw::{Audio, NodeInfo};
use crate::services::Services;
use crate::text::Line;
use crate::theme::{self, FONT_SIZE};

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
    let sink = pw.sink();
    let source = pw.source();
    let mut sinks: Vec<NodeInfo> = nodes.iter().filter(|n| n.0.is_sink()).map(|n| n.0.clone()).collect();
    if let Some(s) = &sink.1 {
        if !sinks.iter().any(|n| n.id == s.id) {
            sinks.insert(0, s.clone());
        }
    }
    let mut sources: Vec<NodeInfo> = nodes.iter().filter(|n| n.0.is_source() && n.0.name != "quickshell" && n.0.name != "mic_denoise").map(|n| n.0.clone()).collect();
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

fn qround(v: f32) -> f32 {
    (v + 0.5).floor()
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
        let (c, run) = ui.card.color(0x1_0000 + code * 64 + i as u32, target, 200, ui.now);
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

/// ConsoleLamp, centred in its 10 x 10 slot at (x, y).
fn lamp(ui: &mut Ui, id: u32, x: f32, y: f32, lit: bool) {
    let t = ui.theme;
    let (halo, r1) = ui.card.number(0x3_0000 + id, if lit { 0.22 } else { 0.0 }, 160, ui.now);
    let (dot, r2) = ui.card.color(0x4_0000 + id, if lit { t.col_accent } else { t.col_plate.darker(1.3) }, 160, ui.now);
    ui.animating |= r1 || r2;
    if halo > 0.0 {
        ui.scene.save();
        ui.scene.multiply_opacity(halo);
        ui.scene.rect(x - 4.0, y - 4.0, 18.0, 18.0, t.col_accent, 9.0, 0.0, Color::TRANSPARENT, true);
        ui.scene.restore();
    }
    let border = if lit { t.col_accent.lighter(1.25) } else { Color::qt_rgba(1.0, 1.0, 1.0, 0.12) };
    ui.scene.rect(x + 1.0, y + 1.0, 9.0, 9.0, dot, 4.5, 1.0, border, true);
}

/// ConsoleRow: lamp, icon, label; hot while hovered or focused.
fn console_row(ui: &mut Ui, code: u32, x: f32, y: f32, w: f32, h: f32, icon: &str, label: &str, lit: bool) {
    let t = ui.theme;
    let interactive = !lit;
    let focused = if interactive { ui.focusable(code) } else { false };
    let hot = (interactive && ui.hovered(x, y, w, h)) || focused;
    let (bg, run) = ui.card.color(0x5_0000 + code, if hot { t.col_plate.lighter(1.6) } else { Color::TRANSPARENT }, 110, ui.now);
    ui.animating |= run;
    ui.scene.rect(x, y, w, h, bg, 4.0, if focused { 2.0 } else { 0.0 }, t.col_white, true);
    let lx = x + 6.0;
    lamp(ui, code, lx, y + qround((h - 10.0) / 2.0), lit);
    let fg = if lit || hot { t.col_white } else { t.col_grey };
    let icon_w = ROW_FONT + 2.0;
    let ix = lx + 10.0 + 8.0;
    let il = ui.fonts.layout(icon, theme::bar_font(false), ROW_FONT, 0.0);
    ui.text(&il, ix + (icon_w - il.adv) / 2.0, y + qround((h - il.height()) / 2.0), fg, TextStyle::Normal);
    let tx = ix + icon_w + 8.0;
    let tw = x + w - 6.0 - tx;
    let key = theme::bar_font(lit);
    let full = ui.fonts.layout(label, key, ROW_FONT, 0.0);
    let line = ui.fonts.elide_right(&full, label, key, tw, 0.0);
    ui.text(&line, tx, y + qround((h - line.height()) / 2.0), fg, TextStyle::Normal);
    if interactive {
        ui.hits.push(Hit { x, y, w, h, action: Action::Card(code) });
    }
}

pub fn draw(ui: &mut Ui, w: f32, svc: &Services, top: f32) {
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

/// LevelMeter: dB-scaled live level with a falling bar and a peak hold.
fn level_meter(ui: &mut Ui, x: f32, y: f32, w: f32, has_node: bool) {
    let t = ui.theme;
    let n = 12.max((w / 12.0).round() as i32);
    let cell = (w - 2.0 * (n - 1) as f32) / n as f32;
    let (level, hold) = if has_node { (ui.card.meter.0, ui.card.meter.1) } else { (0.0, 0.0) };
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
        ui.scene.rect(x + i as f32 * (cell + 2.0), y, cell, 6.0, c, 1.0, 0.0, Color::TRANSPARENT, true);
    }
    if hold > 0.02 {
        let hx = (w - cell.max(2.0)).min((hold * n as f32).floor() * (cell + 2.0));
        ui.scene.rect(x + hx, y, cell.max(2.0), 6.0, t.col_white, 1.0, 0.0, Color::TRANSPARENT, true);
    }
}

/// The meter's 33 ms tick: level falls 0.025 a tick, the hold stays 30 ticks
/// then falls 0.02 a tick.
pub fn meter_tick(app: &mut App) -> bool {
    let Some(card) = app.card.as_mut() else { return false };
    if card.kind != crate::cards::CardKind::Audio {
        return false;
    }
    let (audio, _) = app.svc.pw.as_ref().map(|p| p.source()).unwrap_or_default();
    let peak = app.svc.pw.as_ref().map_or(0.0, |p| p.peak());
    let target = if audio.muted || !audio.ready || !(peak > 0.0) {
        0.0
    } else {
        let db = 20.0 * peak.log10();
        ((db + 60.0) / 60.0).clamp(0.0, 1.0)
    };
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
    card.win.dirty = true;
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
