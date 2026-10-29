//! The screenshot and screen-recording dialogs (SUPER SHIFT S / R), their
//! state and their OSD windows. Two big keys (whole screen, region), a
//! monitor picker when there is more than one, the recorder's audio
//! switches, and the ScreenShot.sh / ScreenRecord.sh calls.

use std::time::Duration;

use smithay_client_toolkit::shell::WaylandSurface;

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{lamp, lamp_tinted, Ui, UiState};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::osd::{self, OpenParams, OsdKind};
use crate::services::{self, Services};
use crate::theme;

const FADE_MS: u64 = 160;
const UI: f32 = 1.35;

fn px(v: f32) -> f32 {
    (v * UI).round()
}

pub const FULL: u32 = 1;
pub const REGION: u32 = 2;
pub const AUDIO_SYS: u32 = 3;
pub const AUDIO_MIC: u32 = 4;
pub const MON: u32 = 0x10;

#[derive(Clone, Default)]
pub struct Monitor {
    pub name: String,
    pub width: i64,
    pub height: i64,
    pub refresh: i64,
}

#[derive(Default)]
pub struct Capture {
    pub monitors: Vec<Monitor>,
    pub shot_open: bool,
    pub shot_target: String,
    pending_shot: String,
    pub rec_open: bool,
    pub rec_target: String,
    pub recording: bool,
    pub audio_sys: bool,
    pub audio_mic: bool,
    open_pending: bool,
    /// The last left press on a dialog (event time, x, y), for Qt's double click.
    last_press: Option<(u32, f32, f32)>,
}

fn script(name: &str) -> String {
    format!("{}/.config/hypr/scripts/{name}", services::home())
}

fn audio_file() -> String {
    format!("{}/.cache/screenrecord_audio", services::home())
}

impl Capture {
    fn audio_mode(&self) -> &'static str {
        match (self.audio_sys, self.audio_mic) {
            (true, true) => "both",
            (true, false) => "system",
            (false, true) => "mic",
            _ => "none",
        }
    }
    fn multiple(&self) -> bool {
        self.monitors.len() > 1
    }
}

/// The monitor to capture: `name` while it is enabled, else the focused
/// one, else the first.
fn resolve_target(app: &App, name: &str) -> String {
    if !name.is_empty() && app.svc.capture.monitors.iter().any(|m| m.name == name) {
        return name.into();
    }
    app.svc.mango.focused().map(|m| m.name.clone()).filter(|n| !n.is_empty()).or(app.svc.capture.monitors.first().map(|m| m.name.clone())).unwrap_or_default()
}

/// Reads wlr-randr's enabled outputs and their current modes.
fn refresh_monitors(app: &mut App) {
    let cmd = "wlr-randr --json | jq -c '[.[] | select(.enabled) | . as $o | ($o.modes[] | select(.current)) as $m | {name: $o.name, width: $m.width, height: $m.height, refresh: ($m.refresh|round), description: $o.description}]'";
    app.spawn("monitors", &["sh", "-c", cmd], |app, d| {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(d.stdout.trim()) else { return };
        let Some(list) = v.as_array() else { return };
        app.svc.capture.monitors = list
            .iter()
            .map(|m| Monitor {
                name: m.get("name").and_then(|x| x.as_str()).unwrap_or("").into(),
                width: m.get("width").and_then(|x| x.as_i64()).unwrap_or(0),
                height: m.get("height").and_then(|x| x.as_i64()).unwrap_or(0),
                refresh: m.get("refresh").and_then(|x| x.as_i64()).unwrap_or(0),
            })
            .collect();
        reshow(app);
    });
}

/// The recording's saved audio choice, at start. The monitors are asked for
/// only when a dialog opens: nothing needs them before.
pub fn start(app: &mut App) {
    let mode = std::fs::read_to_string(audio_file()).unwrap_or_default();
    let m = mode.trim();
    app.svc.capture.audio_sys = m == "system" || m == "both";
    app.svc.capture.audio_mic = m == "mic" || m == "both";
}

// ---- screenshot ----

pub fn shot_open(app: &mut App) {
    refresh_monitors(app);
    let t = app.svc.capture.shot_target.clone();
    app.svc.capture.shot_target = resolve_target(app, &t);
    app.svc.capture.shot_open = true;
    show(app, OsdKind::Shot);
}

fn shot_close(app: &mut App) {
    app.svc.capture.shot_open = false;
    osd::hide(app, OsdKind::Shot);
}

/// Close, then ScreenShot.sh once the dialog has faded (300 ms).
fn shot_run(app: &mut App, args: String) {
    app.svc.capture.pending_shot = args;
    shot_close(app);
    app.debounce("shot-settle", Duration::from_millis(300), |app| {
        let cmd = format!("{} {} >/dev/null 2>&1 &", script("ScreenShot.sh"), app.svc.capture.pending_shot);
        app.exec_detached(&["sh", "-c", &cmd]);
    });
}

fn shot_full(app: &mut App) {
    let t = app.svc.capture.shot_target.clone();
    let mon = resolve_target(app, &t);
    shot_run(app, format!("--monitor {mon} --edit"));
}

// ---- recording ----

/// open(): a recording running is stopped instead; else the dialog.
pub fn rec_open(app: &mut App) {
    app.svc.capture.open_pending = true;
    rec_status(app);
}

fn rec_status(app: &mut App) {
    let cmd = format!("{} --status", script("ScreenRecord.sh"));
    app.spawn("rec-status", &["sh", "-c", &cmd], |app, d| {
        let c = &mut app.svc.capture;
        c.recording = d.stdout.trim() == "recording";
        if c.open_pending {
            c.open_pending = false;
            if c.recording {
                rec_stop(app);
            } else {
                refresh_monitors(app);
                let t = app.svc.capture.rec_target.clone();
                app.svc.capture.rec_target = resolve_target(app, &t);
                app.svc.capture.rec_open = true;
                show(app, OsdKind::Record);
            }
        }
    });
}

fn rec_close(app: &mut App) {
    app.svc.capture.rec_open = false;
    osd::hide(app, OsdKind::Record);
}

fn rec_run(app: &mut App, args: &str) {
    let cmd = format!("{} {args} --audio={} >/dev/null 2>&1 &", script("ScreenRecord.sh"), app.svc.capture.audio_mode());
    app.exec_detached(&["sh", "-c", &cmd]);
    app.debounce("rec-status", Duration::from_millis(900), rec_status);
}

fn rec_full(app: &mut App) {
    let t = app.svc.capture.rec_target.clone();
    let mon = resolve_target(app, &t);
    rec_close(app);
    rec_run(app, &format!("--fullscreen {mon}"));
}

fn rec_region(app: &mut App) {
    rec_close(app);
    app.debounce("rec-delay", Duration::from_millis(180), |app| rec_run(app, "--area"));
}

fn rec_window(app: &mut App) {
    rec_close(app);
    app.debounce("rec-delay", Duration::from_millis(180), |app| rec_run(app, "--active"));
}

pub fn rec_stop(app: &mut App) {
    rec_close(app);
    rec_run(app, "--stop");
}

fn persist_audio(app: &mut App) {
    let cmd = format!("printf '%s' {} > {}", app.svc.capture.audio_mode(), audio_file());
    app.exec_detached(&["sh", "-c", &cmd]);
    reshow(app);
}

// ---- the dialog ----

struct M {
    btn_w: f32,
    btn_h: f32,
    btn_r: f32,
    icon: f32,
    text: f32,
    mon_w: f32,
    mon_h: f32,
    title: f32,
    label: f32,
    sub: f32,
    pad: f32,
    radius: f32,
    gap: f32,
}

fn met() -> M {
    M { btn_w: px(210.0), btn_h: px(150.0), btn_r: px(5.0), icon: px(52.0), text: px(17.0), mon_w: px(150.0), mon_h: px(58.0), title: px(14.0), label: px(15.0), sub: px(12.0), pad: px(28.0), radius: px(12.0), gap: px(14.0) }
}

/// The content Column's blocks and its size.
fn content_size(fonts: &mut crate::text::Fonts, svc: &Services, record: bool) -> (f32, f32) {
    let m = met();
    let c = &svc.capture;
    let mut w: f32 = 0.0;
    let mut hs: Vec<f32> = Vec::new();
    let cap = fonts.layout(if record { "ЗАПИСЬ ЭКРАНА" } else { "СНИМОК ЭКРАНА" }, theme::bar_font(true), m.title, 1.0);
    w = w.max(10.0 + 12.0 + cap.width);
    hs.push(cap.height().max(10.0));
    w = w.max(2.0 * m.btn_w + m.gap);
    hs.push(m.btn_h);
    if c.multiple() {
        let n = c.monitors.len() as f32;
        let mcap = fonts.layout("МОНИТОР", theme::bar_font(true), m.title, 1.0);
        w = w.max(mcap.width).max(n * m.mon_w + (n - 1.0) * (m.gap * 0.6).round());
        hs.push(mcap.height() + (m.gap * 0.5).round() + m.mon_h);
    }
    if record {
        hs.push(1.0);
        hs.push((m.label * 2.6).round());
        hs.push((m.label * 2.6).round());
    }
    let (kw, kh) = keycaps_size(fonts, m.sub, record);
    w = w.max(kw);
    hs.push(kh);
    let h = hs.iter().sum::<f32>() + m.gap * (hs.len() - 1) as f32;
    (w, h)
}

fn keycap_parts(fonts: &mut crate::text::Fonts, keys: &str, label: &str, size: f32) -> (crate::text::Line, crate::text::Line, f32, f32) {
    let k = fonts.layout(keys, theme::bar_font(true), size, 0.0);
    let l = fonts.layout(label, theme::bar_font(true), size, 1.0);
    let (rw, rh) = (k.width + 12.0, k.height() + 4.0);
    (k, l, rw, rh)
}

fn keycaps(record: bool) -> [(&'static str, &'static str); 2] {
    [("W", if record { "АКТИВНОЕ ОКНО" } else { "АКТИВНОЕ ОКНО · В РЕДАКТОР" }), ("ESC", "ОТМЕНА")]
}

fn keycaps_size(fonts: &mut crate::text::Fonts, size: f32, record: bool) -> (f32, f32) {
    let mut w = 0.0;
    let mut h: f32 = 0.0;
    for (i, (k, l)) in keycaps(record).iter().enumerate() {
        let (_, ll, rw, rh) = keycap_parts(fonts, k, l, size);
        w += rw + 6.0 + ll.width + if i > 0 { met().gap } else { 0.0 };
        h = h.max(rh).max(ll.height());
    }
    (w, h)
}

pub(crate) fn show(app: &mut App, kind: OsdKind) {
    let Some((_, sw, sh)) = osd::focused_output(app) else { return };
    let m = met();
    let (cw, ch) = content_size(&mut app.fonts, &app.svc, kind == OsdKind::Record);
    let (pw, ph) = (cw + 2.0 * m.pad, ch + 2.0 * m.pad);
    let (x, y) = (ac(sw, pw), ac(sh, ph));
    osd::show(app, OpenParams { kind, size: (pw.ceil() as u32, ph.ceil() as u32), panel: (0.0, 0.0, pw, ph), dim: Some(Color::qt_rgba(0.0, 0.0, 0.0, 0.5)), keyboard: true, namespace: "rust-bar", fade_ms: FADE_MS, min_scale: 0.96, fade_easing: crate::anim::Easing::OutCubic, pos: Some((x as i32, y as i32)), fill: false, output: None });
}

/// The panel's size follows its content (monitors arrive, a switch flips).
fn reshow(app: &mut App) {
    for (kind, open) in [(OsdKind::Shot, app.svc.capture.shot_open), (OsdKind::Record, app.svc.capture.rec_open)] {
        if !open || app.osd(kind).is_none() {
            continue;
        }
        let m = met();
        let (cw, ch) = content_size(&mut app.fonts, &app.svc, kind == OsdKind::Record);
        let (pw, ph) = (cw + 2.0 * m.pad, ch + 2.0 * m.pad);
        let Some(o) = app.osd_mut(kind) else { continue };
        // anchors.centerIn on the dialog's own screen, which focus may have left.
        let (sw, sh) = o.screen;
        if (o.panel.2 - pw).abs() >= 0.5 || (o.panel.3 - ph).abs() >= 0.5 {
            o.panel = (0.0, 0.0, pw, ph);
            o.win.width = pw.ceil() as u32;
            o.win.height = ph.ceil() as u32;
            o.win.layer.set_size(pw.ceil() as u32, ph.ceil() as u32);
            o.win.layer.set_margin(ac(sh, ph) as i32, 0, 0, ac(sw, pw) as i32);
            o.win.layer.commit();
        }
        o.win.dirty = true;
    }
}

pub fn draw_osd<S: UiState>(ui: &mut Ui<S>, record: bool, panel: (f32, f32, f32, f32), svc: &Services, pressed: Option<u32>) {
    let m = met();
    let t = ui.theme;
    let c = &svc.capture;
    let (px0, py0, pw, ph) = panel;
    ui.scene.rect(px0, py0, pw, ph, t.col_bg, m.radius, 0.0, Color::TRANSPARENT, true);
    let (cw, ch) = content_size(ui.fonts, svc, record);
    let (x0, mut y) = (px0 + ac(pw, cw), py0 + ac(ph, ch));

    // Lamp + caption.
    let cap = ui.fonts.layout(if record { "ЗАПИСЬ ЭКРАНА" } else { "СНИМОК ЭКРАНА" }, theme::bar_font(true), m.title, 1.0);
    let rh = cap.height().max(10.0);
    lamp_tinted(ui, 0x7000, x0, y + ac(rh, 10.0), true, if record { t.col_alert } else { t.col_accent });
    ui.text(&cap, x0 + 22.0, y + ac(rh, cap.height()), t.col_dim, TextStyle::Normal);
    y += rh + m.gap;

    // The two big keys.
    let target = if record { &c.rec_target } else { &c.shot_target };
    let hint = if c.multiple() { target.as_str() } else { "" };
    big_button(ui, FULL, x0, y, &m, "\u{f0379}", "ВЕСЬ ЭКРАН", "F", hint, pressed == Some(FULL));
    big_button(ui, REGION, x0 + m.btn_w + m.gap, y, &m, "\u{f019e}", "ОБЛАСТЬ", "R", "выделите мышью", pressed == Some(REGION));
    y += m.btn_h + m.gap;

    if c.multiple() {
        let mcap = caption_at(ui, "МОНИТОР", m.title);
        ui.text(&mcap, x0, y, t.col_dim, TextStyle::Normal);
        y += mcap.height() + (m.gap * 0.5).round();
        let sp = (m.gap * 0.6).round();
        for (i, mon) in c.monitors.iter().enumerate() {
            let tx = x0 + i as f32 * (m.mon_w + sp);
            let is_target = mon.name == *target;
            let (bg, run) = ui.card.color(0x300 + i as u32, if is_target { t.col_accent } else { t.col_plate.lighter(1.25) }, 110, ui.now);
            ui.animating |= run;
            ui.scene.rect(tx, y, m.mon_w, m.mon_h, bg, m.btn_r, 0.0, Color::TRANSPARENT, true);
            let n = ui.fonts.layout(&mon.name, theme::bar_font(is_target), m.sub + 2.0, 0.0);
            let spec = ui.fonts.layout(&format!("{}x{}  {} Гц", mon.width, mon.height, mon.refresh), theme::bar_font(false), m.sub, 0.0);
            let colw = n.width.max(spec.width);
            let colh = n.height() + 2.0 + spec.height();
            let (cx, cy) = (tx + ac(m.mon_w, colw), y + ac(m.mon_h, colh));
            ui.text_of(i as u32, 0xA1, &n, cx + ac(colw, n.width), cy, if is_target { t.col_bg } else { t.col_white });
            ui.text_of(i as u32, 0xA2, &spec, cx + ac(colw, spec.width), cy + n.height() + 2.0, if is_target { t.col_bg } else { t.col_dim });
            ui.hits.push(Hit { x: tx, y, w: m.mon_w, h: m.mon_h, action: Action::Card(MON + i as u32) });
        }
        y += m.mon_h + m.gap;
    }

    if record {
        let w = t.col_white;
        ui.scene.fill(x0, y, cw, 1.0, Color { a: 0.10, ..w });
        y += 1.0 + m.gap;
        toggle_row(ui, AUDIO_SYS, x0, y, cw, &m, "\u{f057e}", "ЗВУК СИСТЕМЫ", "S", c.audio_sys);
        y += (m.label * 2.6).round() + m.gap;
        toggle_row(ui, AUDIO_MIC, x0, y, cw, &m, "\u{f036c}", "МИКРОФОН", "M", c.audio_mic);
        y += (m.label * 2.6).round() + m.gap;
    }

    // Keycap hints.
    let (_, kh) = keycaps_size(ui.fonts, m.sub, record);
    let mut kx = x0;
    for (i, (k, l)) in keycaps(record).iter().enumerate() {
        if i > 0 {
            kx += m.gap;
        }
        let (kl, ll, rw, rhh) = keycap_parts(ui.fonts, k, l, m.sub);
        let ry = y + ac(kh, rhh);
        ui.scene.rect(kx, ry, rw, rhh, t.col_plate.lighter(1.4), 3.0, 0.0, Color::TRANSPARENT, true);
        ui.scene.rect(kx, ry + rhh - 2.0, rw, 2.0, Color::qt_rgba(0.0, 0.0, 0.0, 0.45), 3.0, 0.0, Color::TRANSPARENT, true);
        ui.text(&kl, kx + ac(rw, kl.width), ry + ac(rhh, kl.height()) - 1.0, t.col_white, TextStyle::Normal);
        kx += rw + 6.0;
        ui.text(&ll, kx, y + ac(kh, ll.height()), t.col_grey, TextStyle::Normal);
        kx += ll.width;
    }
    // MouseArea { anchors.fill: parent }: clicks on the panel never close it.
    ui.hits.insert(0, Hit { x: px0, y: py0, w: pw, h: ph, action: Action::Hover(0) });
}

fn caption_at<S: UiState>(ui: &mut Ui<S>, text: &str, size: f32) -> crate::text::Line {
    ui.fonts.layout(text, theme::bar_font(true), size, 1.0)
}

/// A big key with an icon, a bold label and a hint, its key letter in the
/// corner; lighter on hover, accent while held.
#[allow(clippy::too_many_arguments)]
fn big_button<S: UiState>(ui: &mut Ui<S>, id: u32, x: f32, y: f32, m: &M, icon: &str, label: &str, key: &str, hint: &str, down: bool) {
    let t = ui.theme;
    let active = ui.hovered(x, y, m.btn_w, m.btn_h);
    let ink = if down { t.col_bg } else if active { t.col_white } else { t.col_grey };
    let target = if down { t.col_accent } else if active { t.col_plate.lighter(1.6) } else { t.col_plate.lighter(1.25) };
    let (bg, run) = ui.card.color(id, target, 90, ui.now);
    ui.animating |= run;
    ui.scene.rect(x, y, m.btn_w, m.btn_h, bg, m.btn_r, 0.0, Color::TRANSPARENT, true);
    if !down {
        ui.scene.rect(x, y + m.btn_h - 4.0, m.btn_w, 4.0, Color::qt_rgba(0.0, 0.0, 0.0, 0.45), m.btn_r, 0.0, Color::TRANSPARENT, true);
    }
    let k = ui.fonts.layout(key, theme::bar_font(true), m.sub, 0.0);
    ui.text_of(id, 0xB1, &k, x + m.btn_w - 10.0 - k.width, y + 10.0, if down { t.col_bg } else { t.col_dim });
    let il = ui.fonts.layout(icon, theme::bar_font(false), m.icon, 0.0);
    let ll = ui.fonts.layout(label, theme::bar_font(true), m.text, 1.0);
    let hl = (!hint.is_empty()).then(|| ui.fonts.layout(hint, theme::bar_font(false), m.sub, 0.0));
    let colw = il.width.max(ll.width).max(hl.as_ref().map_or(0.0, |h| h.width));
    let colh = il.height() + 6.0 + ll.height() + hl.as_ref().map_or(0.0, |h| 6.0 + h.height());
    let cx = x + ac(m.btn_w, colw);
    let mut cy = y + ac(m.btn_h, colh) + if down { 0.0 } else { -2.0 };
    ui.text_of(id, 0xB2, &il, cx + ac(colw, il.width), cy, ink);
    cy += il.height() + 6.0;
    ui.text_of(id, 0xB3, &ll, cx + ac(colw, ll.width), cy, ink);
    cy += ll.height() + 6.0;
    if let Some(h) = hl {
        ui.text_of(id, 0xB4, &h, cx + ac(colw, h.width), cy, if down { t.col_bg } else { t.col_dim });
    }
    ui.hits.push(Hit { x, y, w: m.btn_w, h: m.btn_h, action: Action::Card(id) });
}

/// A toggle row: lamp, icon, bold label, key letter, and the ВКЛ/ВЫКЛ key
/// on the right; the whole row is the hit area.
#[allow(clippy::too_many_arguments)]
fn toggle_row<S: UiState>(ui: &mut Ui<S>, id: u32, x: f32, y: f32, w: f32, m: &M, icon: &str, label: &str, key: &str, checked: bool) {
    let t = ui.theme;
    let h = (m.label * 2.6).round();
    let hot = ui.hovered(x, y, w, h);
    let fg = if checked { t.col_white } else { t.col_grey };
    let il = ui.fonts.layout(icon, theme::bar_font(false), m.label + 3.0, 0.0);
    let ll = ui.fonts.layout(label, theme::bar_font(true), m.label, 1.0);
    let kl = ui.fonts.layout(key, theme::bar_font(true), m.label - 3.0, 0.0);
    let row_h = 10f32.max(il.height()).max(ll.height()).max(kl.height());
    let ry = y + ac(h, row_h);
    let mut rx = x;
    lamp(ui, 0x7100 + id, rx, ry + ac(row_h, 10.0), checked);
    rx += 10.0 + 12.0;
    ui.text_of(id, 0xC1, &il, rx, ry + ac(row_h, il.height()), fg);
    rx += il.width + 12.0;
    ui.text_of(id, 0xC2, &ll, rx, ry + ac(row_h, ll.height()), fg);
    rx += ll.width + 12.0;
    ui.text_of(id, 0xC3, &kl, rx, ry + ac(row_h, kl.height()), t.col_dim);
    let (kw, khh) = ((m.label * 4.2).round(), (m.label * 1.9).round());
    let (kx, ky) = (x + w - kw, y + ac(h, khh));
    let target = if checked { t.col_accent } else if hot { t.col_plate.lighter(1.6) } else { t.col_plate.lighter(1.25) };
    let (bg, run) = ui.card.color(0x400 + id, target, 130, ui.now);
    ui.animating |= run;
    ui.scene.rect(kx, ky, kw, khh, bg, 4.0, 0.0, Color::TRANSPARENT, true);
    if !checked {
        ui.scene.rect(kx, ky + khh - 3.0, kw, 3.0, Color::qt_rgba(0.0, 0.0, 0.0, 0.45), 4.0, 0.0, Color::TRANSPARENT, true);
    }
    let vl = ui.fonts.layout(if checked { "ВКЛ" } else { "ВЫКЛ" }, theme::bar_font(true), m.label - 2.0, 0.0);
    ui.text_of(id, 0xC4, &vl, kx + ac(kw, vl.width), ky + ac(khh, vl.height()) + if checked { 0.0 } else { -1.0 }, if checked { t.col_bg } else { t.col_grey });
    ui.hits.push(Hit { x, y, w, h, action: Action::Card(id) });
}

pub fn click(app: &mut App, kind: OsdKind, action: Action) {
    let Action::Card(code) = action else { return };
    let record = kind == OsdKind::Record;
    match code {
        FULL => {
            if record { rec_full(app) } else { shot_full(app) }
        }
        REGION => {
            if record { rec_region(app) } else { shot_run(app, "--area --edit".into()) }
        }
        AUDIO_SYS => {
            app.svc.capture.audio_sys = !app.svc.capture.audio_sys;
            persist_audio(app);
        }
        AUDIO_MIC => {
            app.svc.capture.audio_mic = !app.svc.capture.audio_mic;
            persist_audio(app);
        }
        c if c >= MON => {
            let Some(name) = app.svc.capture.monitors.get((c - MON) as usize).map(|m| m.name.clone()) else { return };
            if record { app.svc.capture.rec_target = name } else { app.svc.capture.shot_target = name }
            reshow(app);
        }
        _ => {}
    }
}

/// A press on the dialog, before the click machinery. Qt turns a second
/// left press within 400 ms and 5 px of the first (MouseDoubleClickInterval
/// and -Distance; another button in between breaks it) into a double
/// click, delivered with that press: a double click on a monitor tile
/// picks it and shoots, and no click follows on the release. True when
/// it did.
pub fn press(app: &mut App, kind: OsdKind, button: u32, time: u32, x: f32, y: f32) -> bool {
    let c = &mut app.svc.capture;
    let double = button == 0x110 && c.last_press.map_or(false, |(t, px, py)| time.wrapping_sub(t) < 400 && (x - px).abs() <= 5.0 && (y - py).abs() <= 5.0);
    c.last_press = (button == 0x110 && !double).then_some((time, x, y));
    if !double {
        return false;
    }
    let hit = app.osd(kind).and_then(|o| o.hits.iter().rev().find(|h| h.contains(x, y)).map(|h| h.action));
    let Some(Action::Card(code)) = hit.filter(|a| matches!(a, Action::Card(c) if *c >= MON)) else { return false };
    let Some(name) = app.svc.capture.monitors.get((code - MON) as usize).map(|m| m.name.clone()) else { return false };
    if kind == OsdKind::Record {
        app.svc.capture.rec_target = name;
        rec_full(app);
    } else {
        app.svc.capture.shot_target = name;
        shot_full(app);
    }
    true
}

pub fn dim_clicked(app: &mut App, kind: OsdKind) {
    if kind == OsdKind::Record { rec_close(app) } else { shot_close(app) }
}

/// Esc, Enter, and the letters by key or scan code (F 41, R 27, W 25, S 39, M 58).
pub fn key(app: &mut App, kind: OsdKind, sym: smithay_client_toolkit::seat::keyboard::Keysym, scan: u32) {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    let record = kind == OsdKind::Record;
    let is = |k: Keysym, lower: Keysym, upper: Keysym, sc: u32| k == lower || k == upper || scan == sc;
    if sym == Keysym::Escape {
        if record { rec_close(app) } else { shot_close(app) }
    } else if sym == Keysym::Return || sym == Keysym::KP_Enter || is(sym, Keysym::f, Keysym::F, 41) {
        if record { rec_full(app) } else { shot_full(app) }
    } else if is(sym, Keysym::r, Keysym::R, 27) {
        if record { rec_region(app) } else { shot_run(app, "--area --edit".into()) }
    } else if is(sym, Keysym::w, Keysym::W, 25) {
        if record { rec_window(app) } else { shot_run(app, "--active --edit".into()) }
    } else if record && is(sym, Keysym::s, Keysym::S, 39) {
        app.svc.capture.audio_sys = !app.svc.capture.audio_sys;
        persist_audio(app);
    } else if record && is(sym, Keysym::m, Keysym::M, 58) {
        app.svc.capture.audio_mic = !app.svc.capture.audio_mic;
        persist_audio(app);
    }
}
