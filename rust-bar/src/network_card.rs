//! NetworkPanel.qml: the Wi-Fi widget's details card (right click) - the
//! link, addresses, traffic and latency from network-status.sh every 3 s,
//! the radio switch, the DNS picker, the speed test and the share-by-QR view,
//! with the same scripts and nmcli calls.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use crate::app::App;
use crate::bar::ac;
use crate::cards::{caption, info_grid_height, info_grid_of, lamp_tinted, plate, GridPair, Ui};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::services::{self, js_num, to_fixed, Services};
use crate::text::{Fonts, Line};
use crate::theme::{self, FONT_SIZE};

const LABEL: f32 = FONT_SIZE - 3.0;
const HEADER: f32 = FONT_SIZE - 5.0;
const BTN_FONT: f32 = FONT_SIZE - 6.0;

pub const RADIO: u32 = 1;
pub const QR: u32 = 2;
pub const SPEED: u32 = 3;
pub const PORTAL: u32 = 4;
pub const START: u32 = 5;
pub const STOP: u32 = 6;
pub const DNS: u32 = 0x10;

const DNS_CHOICES: [(&str, &str); 3] = [("DHCP", ""), ("Cloudflare", "1.1.1.1 1.0.0.1"), ("Google", "8.8.8.8 8.8.4.4")];

/// The InfoGrids' ids (cards::info_grid_of): each plate's GLabels and
/// GValues are items of their own, the speed view's too.
const GRID_CHANNEL: u32 = 0x8100;
const GRID_CONNECTION: u32 = 0x8200;
const GRID_TRAFFIC: u32 = 0x8300;
const GRID_SPEED: u32 = 0x8400;

#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub enum View {
    #[default]
    Info,
    Speed,
    Qr,
}

pub struct NetPanel {
    pub info: HashMap<String, String>,
    rx_rate: f64,
    tx_rate: f64,
    last_rx: f64,
    last_tx: f64,
    last_sample: Option<Instant>,
    pub connectivity: String,
    pub radio_on: bool,
    pub active_conn: String,
    pub busy: String,
    pub view: View,
    speed_phase: &'static str,
    speed_down: f64,
    speed_up: f64,
    speed_now: f64,
    speed_run: u32,
    speed_pending: bool,
    speed_error: String,
    proc_phase: &'static str,
    proc_gen: u32,
    qr_rows: Vec<String>,
    qr_ssid: String,
    qr_security: String,
    qr_error: String,
}

impl Default for NetPanel {
    fn default() -> Self {
        NetPanel {
            info: HashMap::new(),
            rx_rate: -1.0,
            tx_rate: -1.0,
            last_rx: -1.0,
            last_tx: -1.0,
            last_sample: None,
            connectivity: String::new(),
            radio_on: true,
            active_conn: String::new(),
            busy: String::new(),
            view: View::Info,
            speed_phase: "",
            speed_down: 0.0,
            speed_up: 0.0,
            speed_now: 0.0,
            speed_run: 0,
            speed_pending: false,
            speed_error: String::new(),
            proc_phase: "",
            proc_gen: 0,
            qr_rows: Vec::new(),
            qr_ssid: String::new(),
            qr_security: String::new(),
            qr_error: String::new(),
        }
    }
}

impl NetPanel {
    /// num(): NaN when the key is missing or empty.
    fn num(&self, key: &str) -> f64 {
        match self.info.get(key) {
            None => f64::NAN,
            Some(v) if v.is_empty() => f64::NAN,
            Some(v) => js_number(v),
        }
    }
    fn field(&self, key: &str, fallback: &str) -> String {
        match self.info.get(key) {
            Some(v) if !v.is_empty() => v.clone(),
            _ => fallback.into(),
        }
    }
    fn captive(&self) -> bool {
        self.connectivity == "portal" || self.connectivity == "limited"
    }
    fn dns_is_active(&self, servers: &str) -> bool {
        let current = self.field("dns", "");
        if servers.is_empty() {
            if DNS_CHOICES[1..].iter().any(|c| current.contains(c.1.split(' ').next().unwrap_or(""))) {
                return false;
            }
            return !current.is_empty();
        }
        current.contains(servers.split(' ').next().unwrap_or(""))
    }
    fn band(&self) -> &'static str {
        let f = self.num("freq");
        if f.is_nan() {
            "—"
        } else if f >= 5925.0 {
            "6 ГГц"
        } else if f >= 4900.0 {
            "5 ГГц"
        } else {
            "2.4 ГГц"
        }
    }
    fn speed_busy(&self) -> bool {
        self.speed_phase == "down" || self.speed_phase == "up"
    }
}

/// JS Number(): whitespace-trimmed, "" is 0, junk is NaN.
fn js_number(s: &str) -> f64 {
    let t = s.trim();
    if t.is_empty() {
        return 0.0;
    }
    t.parse().unwrap_or(f64::NAN)
}

fn human_rate(bytes_per_sec: f64) -> String {
    if bytes_per_sec < 0.0 || bytes_per_sec.is_nan() {
        return "—".into();
    }
    let bits = bytes_per_sec * 8.0;
    if bits >= 1e9 {
        format!("{} Gb/s", to_fixed(bits / 1e9, 1))
    } else if bits >= 1e6 {
        format!("{} Мбит/с", to_fixed(bits / 1e6, 1))
    } else if bits >= 1000.0 {
        format!("{} kb/s", to_fixed(bits / 1000.0, 0))
    } else {
        format!("{} b/s", js_num((bits + 0.5).floor()))
    }
}

fn human_bytes(b: f64) -> String {
    if b.is_nan() {
        "—".into()
    } else if b >= 1073741824.0 {
        format!("{} ГБ", to_fixed(b / 1073741824.0, 2))
    } else if b >= 1048576.0 {
        format!("{} МБ", to_fixed(b / 1048576.0, 1))
    } else if b >= 1024.0 {
        format!("{} kB", to_fixed(b / 1024.0, 0))
    } else {
        format!("{} Б", js_num(b))
    }
}

fn ms(v: f64) -> String {
    if v.is_nan() { "—".into() } else { format!("{} мс", to_fixed(v, 0)) }
}

fn shq(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

fn scripts() -> String {
    format!("{}/.config/quickshell/bar/scripts", services::home())
}

fn is_open(app: &App) -> bool {
    app.card.as_ref().map(|c| c.kind) == Some(crate::cards::CardKind::Network)
}

/// What NetworkPanel shows changed: the details card redraws, not the
/// strips (WifiWidget's icon reads the status read alone).
fn redraw(app: &mut App) {
    app.mark_card_dirty(&[crate::cards::CardKind::Network]);
}

// ---- the processes ----

/// A new NetworkPanel: QML makes one with every opening, in the card's
/// Loader (WifiWidget.qml:429-439, DropdownWidget.qml:174-176), so every
/// reading starts at its declared default (NetworkPanel.qml:28-33, 147-151,
/// 281-298, 391-394) - dashes, no gauge, Готов / СТАРТ, no QR - until the
/// first answers land. The speed test's generation goes on, so the exit of
/// a test still dying from the last opening stays ignored, and an action
/// still running keeps its spinner until it ends. Then onActiveChanged(true):
/// every source once, the status every 3 s (triggeredOnStart).
pub fn opened(app: &mut App) {
    let old = std::mem::take(&mut app.svc.net);
    let busy = if app.is_running("net-action") { old.busy } else { String::new() };
    app.svc.net = NetPanel { speed_run: old.speed_run, proc_gen: old.proc_gen, proc_phase: old.proc_phase, busy, ..NetPanel::default() };
    refresh(app);
    status_tick(app);
}

/// onActiveChanged(false): the speed test stops, the view goes back to info.
pub fn closed(app: &mut App) {
    stop_speed_test(app);
    app.svc.net.view = View::Info;
}

fn status_tick(app: &mut App) {
    if !is_open(app) {
        return;
    }
    run_status(app);
    app.debounce("net-status", Duration::from_secs(3), status_tick);
}

fn run_status(app: &mut App) {
    let cmd = format!("{}/network-status.sh", scripts());
    app.spawn("net-status", &["sh", "-c", &cmd], |app, d| {
        if d.stdout.is_empty() {
            return;
        }
        apply_status(app, &d.stdout);
    });
}

fn apply_status(app: &mut App, out: &str) {
    let n = &mut app.svc.net;
    let next: HashMap<String, String> = out.lines().filter_map(|l| l.split_once('\t')).map(|(k, v)| (k.to_string(), v.to_string())).collect();
    let now = Instant::now();
    let rx = next.get("rx_bytes").map_or(f64::NAN, |v| js_number(v));
    let tx = next.get("tx_bytes").map_or(f64::NAN, |v| js_number(v));
    if !rx.is_nan() && !tx.is_nan() && n.last_rx >= 0.0 {
        if let Some(last) = n.last_sample {
            let dt = now.duration_since(last).as_millis() as f64 / 1000.0;
            if dt > 0.2 && rx >= n.last_rx && tx >= n.last_tx {
                n.rx_rate = (rx - n.last_rx) / dt;
                n.tx_rate = (tx - n.last_tx) / dt;
            }
        }
    }
    if !rx.is_nan() {
        n.last_rx = rx;
    }
    if !tx.is_nan() {
        n.last_tx = tx;
    }
    n.last_sample = Some(now);
    n.info = next;
    redraw(app);
}

/// refresh(): the status, connectivity / radio / active profile.
fn refresh(app: &mut App) {
    if !is_open(app) {
        return;
    }
    run_status(app);
    let cmd = "printf 'connectivity\\t%s\\n' \"$(nmcli -t -f CONNECTIVITY general 2>/dev/null)\"; \
               printf 'radio\\t%s\\n' \"$(nmcli -t -f WIFI radio 2>/dev/null)\"; \
               printf 'active\\t%s\\n' \"$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep ':802-11-wireless$' | head -1 | sed 's/:802-11-wireless$//')\"";
    app.spawn("net-general", &["sh", "-c", cmd], |app, d| {
        let n = &mut app.svc.net;
        for (k, v) in d.stdout.lines().filter_map(|l| l.split_once('\t')) {
            let v = v.trim();
            match k {
                "connectivity" => n.connectivity = v.into(),
                "radio" => n.radio_on = v == "enabled",
                "active" => n.active_conn = v.into(),
                _ => {}
            }
        }
        redraw(app);
    });
}

/// run(): one nmcli action at a time; refresh when it is done.
fn run(app: &mut App, what: &str, cmd: &str) {
    if app.is_running("net-action") {
        return;
    }
    app.svc.net.busy = what.into();
    app.spawn("net-action", &["sh", "-c", cmd], |app, _| {
        app.svc.net.busy.clear();
        refresh(app);
        redraw(app);
    });
    redraw(app);
}

fn set_dns(app: &mut App, servers: &str) {
    if app.svc.net.active_conn.is_empty() {
        return;
    }
    let n = shq(&app.svc.net.active_conn);
    let cmd = if servers.is_empty() {
        format!("nmcli connection modify {n} ipv4.ignore-auto-dns no ipv4.dns ''")
    } else {
        format!("nmcli connection modify {n} ipv4.ignore-auto-dns yes ipv4.dns {}", shq(servers))
    };
    run(app, "dns", &format!("{cmd} && nmcli connection up {n}"));
}

fn launch_speed_phase(app: &mut App, phase: &'static str) {
    app.svc.net.proc_phase = phase;
    app.svc.net.proc_gen = app.svc.net.speed_run;
    let cmd = format!("{}/network-speedtest.sh {phase} 8", scripts());
    app.spawn_stream("net-speed", &["sh", "-c", &cmd], speed_out, Some(speed_err), Some(speed_exit));
}

fn speed_out(app: &mut App, data: &str) {
    let n = &mut app.svc.net;
    if data.is_empty() || n.proc_gen != n.speed_run {
        return;
    }
    let v = js_number(data);
    if v.is_nan() {
        return;
    }
    n.speed_now = v;
    match n.proc_phase {
        "down" => n.speed_down = n.speed_down.max(v),
        "up" => n.speed_up = n.speed_up.max(v),
        _ => {}
    }
    redraw(app);
}

fn speed_err(app: &mut App, data: &str) {
    let n = &mut app.svc.net;
    if data.is_empty() || n.proc_gen != n.speed_run {
        return;
    }
    let line = data.trim();
    if !line.is_empty() {
        let l = line.strip_prefix("error:").map_or(line, |r| r.trim_start());
        n.speed_error = l.into();
        redraw(app);
    }
}

fn speed_exit(app: &mut App) {
    if app.svc.net.speed_pending {
        app.svc.net.speed_pending = false;
        launch_speed_phase(app, "down");
        return;
    }
    let n = &mut app.svc.net;
    if n.proc_gen != n.speed_run {
        return;
    }
    match n.proc_phase {
        "down" => {
            n.speed_now = 0.0;
            n.speed_phase = "up";
            launch_speed_phase(app, "up");
        }
        "up" => {
            n.speed_phase = "done";
            n.speed_now = 0.0;
        }
        _ => {}
    }
    redraw(app);
}

fn start_speed_test(app: &mut App) {
    let n = &mut app.svc.net;
    n.speed_run += 1;
    n.speed_down = 0.0;
    n.speed_up = 0.0;
    n.speed_now = 0.0;
    n.speed_error.clear();
    n.speed_phase = "down";
    n.view = View::Speed;
    if app.is_running("net-speed") {
        app.svc.net.speed_pending = true;
        app.kill("net-speed");
    } else {
        app.svc.net.speed_pending = false;
        launch_speed_phase(app, "down");
    }
    redraw(app);
}

fn stop_speed_test(app: &mut App) {
    let n = &mut app.svc.net;
    n.speed_run += 1;
    n.speed_pending = false;
    if app.is_running("net-speed") {
        app.kill("net-speed");
    }
    let n = &mut app.svc.net;
    n.speed_phase = "";
    n.speed_now = 0.0;
    redraw(app);
}

fn show_qr(app: &mut App) {
    app.svc.net.view = View::Qr;
    app.svc.net.qr_error.clear();
    let cmd = format!("{}/network-qr.sh", scripts());
    app.spawn("net-qr", &["sh", "-c", &cmd], |app, d| {
        let n = &mut app.svc.net;
        let mut rows = Vec::new();
        n.qr_error.clear();
        for line in d.stdout.lines().filter(|l| !l.is_empty()) {
            if let Some(e) = line.strip_prefix("error\t") {
                n.qr_error = e.into();
                n.qr_rows.clear();
                redraw(app);
                return;
            }
            if line.starts_with("meta\t") {
                let m: Vec<&str> = line.split('\t').collect();
                n.qr_security = m.get(2).copied().unwrap_or("").into();
                n.qr_ssid = m.get(3).copied().unwrap_or("").into();
                continue;
            }
            if line.bytes().all(|b| b == b'0' || b == b'1') {
                rows.push(line.to_string());
            }
        }
        n.qr_rows = rows;
        redraw(app);
    });
    redraw(app);
}

pub fn activate(app: &mut App, code: u32) {
    match code {
        RADIO => {
            let cmd = format!("nmcli radio wifi {}", if app.svc.net.radio_on { "off" } else { "on" });
            run(app, "radio", &cmd);
        }
        QR => {
            if app.svc.net.view == View::Qr {
                app.svc.net.view = View::Info;
                redraw(app);
            } else {
                show_qr(app);
            }
        }
        SPEED => {
            if app.svc.net.view == View::Speed {
                stop_speed_test(app);
                app.svc.net.view = View::Info;
            } else {
                app.svc.net.view = View::Speed;
            }
            redraw(app);
        }
        PORTAL => app.exec_detached(&["xdg-open", "http://ping.archlinux.org/nm-check.txt"]),
        START => start_speed_test(app),
        STOP => stop_speed_test(app),
        c if (DNS..DNS + 3).contains(&c) => set_dns(app, DNS_CHOICES[(c - DNS) as usize].1),
        _ => {}
    }
}

// ---- the card ----

fn btn_h() -> f32 {
    (BTN_FONT * 2.1).round()
}

/// The body Column's blocks (spacing 8) and their heights.
enum Block {
    Header,
    Captive(Vec<Line>),
    Channel,
    Connection,
    Traffic,
    DnsRow,
    NoProfile,
    SpeedPlate(Vec<Line>),
    SpeedButton,
    QrPlate(Vec<Line>),
}

fn line_h(fonts: &mut Fonts, size: f32, bold: bool) -> f32 {
    fonts.layout("Н", theme::bar_font(bold), size, 0.0).height()
}

fn blocks(fonts: &mut Fonts, n: &NetPanel, cw: f32) -> Vec<(Block, f32)> {
    let iw = cw - 20.0;
    let cap = caption(fonts, "Н").height();
    let mut out = vec![(Block::Header, btn_h())];
    if n.captive() {
        let lines = fonts.wrap("Сеть просит войти или принять условия, прежде чем пропустит трафик.", theme::bar_font(false), HEADER, 0.0, iw);
        let h = line_h(fonts, LABEL, true) + 6.0 + lines.iter().map(|l| l.height()).sum::<f32>() + 6.0 + btn_h() + 20.0;
        out.push((Block::Captive(lines), h));
    }
    match n.view {
        View::Info => {
            let gauge = if n.num("signal_pct").is_nan() { 0.0 } else { 12.0 + 6.0 };
            out.push((Block::Channel, cap + 6.0 + gauge + info_grid_height(fonts, 1) + 20.0));
            out.push((Block::Connection, cap + 6.0 + info_grid_height(fonts, 3) + 20.0));
            out.push((Block::Traffic, cap + 6.0 + info_grid_height(fonts, 3) + 20.0));
            out.push((Block::DnsRow, btn_h()));
            if n.active_conn.is_empty() {
                out.push((Block::NoProfile, line_h(fonts, HEADER, false)));
            }
        }
        View::Speed => {
            let mut h = cap + 6.0 + info_grid_height(fonts, 1);
            let err = if n.speed_error.is_empty() {
                h += 6.0 + line_h(fonts, HEADER, false);
                Vec::new()
            } else {
                let lines = fonts.wrap(&n.speed_error, theme::bar_font(false), HEADER, 0.0, iw);
                h += 6.0 + lines.iter().map(|l| l.height()).sum::<f32>();
                lines
            };
            if n.speed_busy() {
                h += 6.0 + line_h(fonts, HEADER, false);
            }
            out.push((Block::SpeedPlate(err), h + 20.0));
            out.push((Block::SpeedButton, btn_h()));
        }
        View::Qr => {
            let mut h = cap;
            let err = if n.qr_error.is_empty() {
                Vec::new()
            } else {
                let lines = fonts.wrap(&n.qr_error, theme::bar_font(false), LABEL, 0.0, iw);
                h += 8.0 + lines.iter().map(|l| l.height()).sum::<f32>();
                lines
            };
            if !n.qr_rows.is_empty() {
                let cell = qr_cell(n);
                h += 8.0 + line_h(fonts, LABEL, true);
                h += 8.0 + cell * n.qr_rows.len() as f32;
                h += 8.0 + line_h(fonts, HEADER, false);
            }
            out.push((Block::QrPlate(err), h + 20.0));
        }
    }
    out
}

fn qr_cell(n: &NetPanel) -> f32 {
    if n.qr_rows.is_empty() { 2.0 } else { 2f32.max((260.0 / n.qr_rows.len() as f32).floor()) }
}

pub fn content_height(fonts: &mut Fonts, svc: &Services, w: f32) -> f32 {
    let bl = blocks(fonts, &svc.net, w - 16.0);
    bl.iter().map(|b| b.1).sum::<f32>() + 8.0 * (bl.len() as f32 - 1.0)
}

/// popupHeight: max(200, min(ceil(content) + 30, 85% of the screen)).
pub fn card_height(fonts: &mut Fonts, svc: &Services, w: f32, screen_h: f32) -> f32 {
    200f32.max((content_height(fonts, svc, w).ceil() + 30.0).min(screen_h * 0.85))
}

fn elide_middle(fonts: &mut Fonts, text: &str, size: f32, bold: bool, max: f32) -> Line {
    fonts.elide_middle(text, theme::bar_font(bold), size, 0.0, max)
}

/// The КАНАЛ plate's SegmentGauge exists from the panel's start, hidden at
/// value 0 while no signal is known (NetworkPanel.qml:649-655), and its
/// cells follow the signal in every view: the first reading fades the lit
/// cells in (Behavior on color, 200 ms), and a change made while another
/// view was up has faded by the time the readings come back. The targets
/// cards::gauge gives its 28 cells, set without drawing them.
fn gauge_follows(ui: &mut Ui, n: &NetPanel) {
    let pct = n.num("signal_pct");
    let value = if pct.is_nan() { 0.0 } else { pct as f32 };
    let tint = if !pct.is_nan() && pct < 30.0 { ui.theme.col_alert } else { ui.theme.col_accent };
    let lit = ((value.clamp(0.0, 100.0) / 100.0 * 28.0) + 0.5).floor() as u32;
    for i in 0..28 {
        let target = if i < lit { tint } else { Color::qt_rgba(1.0, 1.0, 1.0, 0.07) };
        ui.card.color(0x6_0000 + i, target, 200, ui.now);
    }
}

pub fn draw(ui: &mut Ui, w: f32, svc: &Services, top: f32) {
    let n = &svc.net;
    let t = ui.theme;
    let (x0, cw) = (8.0, w - 16.0);
    let (ix, iw) = (x0 + 10.0, cw - 20.0);
    let bh = btn_h();
    if !n.busy.is_empty() {
        ui.animating = true;
    }
    gauge_follows(ui, n);
    let mut y = top;
    for (block, h) in blocks(ui.fonts, n, cw) {
        match block {
            Block::Header => {
                // The radio key, the SSID, the QR and speed-test keys.
                let icon = if n.radio_on { "\u{f0928}" } else { "\u{f092e}" };
                let rw = ui.console_button_width(BTN_FONT, icon, "", 0.0);
                ui.console_button_ex(RADIO, x0, y, rw, BTN_FONT, icon, t.col_grey, "", n.radio_on, !n.busy.is_empty(), true);
                let kw = ui.console_button_width(BTN_FONT, "\u{f0432}", "", 0.0);
                let actions_x = x0 + cw - (2.0 * kw + 6.0);
                let sx = x0 + rw + 10.0;
                let ssid = n.field("ssid", "НЕТ ПОДКЛЮЧЕНИЯ");
                let line = elide_middle(ui.fonts, &ssid, LABEL + 1.0, true, actions_x - 10.0 - sx);
                ui.text(&line, sx, y + ac(bh, line.height()), if n.radio_on { t.col_white } else { t.col_grey }, TextStyle::Normal);
                ui.console_button_sized(QR, actions_x, y, kw, BTN_FONT, "\u{f0432}", t.col_grey, "", n.view == View::Qr);
                ui.console_button_sized(SPEED, actions_x + kw + 6.0, y, kw, BTN_FONT, "\u{f04c5}", t.col_grey, "", n.view == View::Speed);
            }
            Block::Captive(lines) => {
                plate(ui, x0, y, cw, h);
                let mut cy = y + 10.0;
                let title = ui.fonts.layout(if n.connectivity == "portal" { "ТРЕБУЕТСЯ ВХОД" } else { "ОГРАНИЧЕННОЕ ПОДКЛЮЧЕНИЕ" }, theme::bar_font(true), LABEL, 0.0);
                let th = title.height();
                lamp_tinted(ui, 0x7200, ix, cy + ac(th, 10.0), true, t.col_alert);
                ui.text(&title, ix + 20.0, cy, t.col_alert, TextStyle::Normal);
                cy += th + 6.0;
                for l in &lines {
                    ui.text(l, ix, cy, t.col_grey, TextStyle::Normal);
                    cy += l.height();
                }
                cy += 6.0;
                let label = "ОТКРЫТЬ СТРАНИЦУ ВХОДА";
                let bw = ui.console_button_width(BTN_FONT, "\u{f059f}", label, 58.0);
                ui.card.tint_alert = true;
                ui.console_button_sized(PORTAL, ix, cy, bw, BTN_FONT, "\u{f059f}", t.col_grey, label, true);
                ui.card.tint_alert = false;
            }
            Block::Channel => {
                plate(ui, x0, y, cw, h);
                let cap = caption(ui.fonts, "КАНАЛ");
                ui.text(&cap, ix, y + 10.0, t.col_dim, TextStyle::Normal);
                let mut cy = y + 10.0 + cap.height() + 6.0;
                let pct = n.num("signal_pct");
                let weak = !pct.is_nan() && pct < 30.0;
                if !pct.is_nan() {
                    crate::cards::gauge(ui, ix, cy, iw, pct as f32, -1.0, if weak { t.col_alert } else { t.col_accent });
                    cy += 12.0 + 6.0;
                }
                let dbm = n.num("signal_dbm");
                let band = n.band();
                let signal = if pct.is_nan() {
                    band.to_string()
                } else {
                    let v = if dbm.is_nan() { format!("{}%", js_num(pct)) } else { format!("{}% ({})", js_num(pct), js_num(dbm)) };
                    if band == "—" { v } else { format!("{v} · {band}") }
                };
                let rows: [Vec<GridPair>; 1] = [vec![("СИГНАЛ", signal, if weak { t.col_alert } else { t.col_white }), ("СКОРОСТЬ", n.field("bitrate", "—"), t.col_white)]];
                info_grid_of(ui, GRID_CHANNEL, ix, cy, iw, &rows);
            }
            Block::Connection => {
                plate(ui, x0, y, cw, h);
                let cap = caption(ui.fonts, "ПОДКЛЮЧЕНИЕ");
                ui.text(&cap, ix, y + 10.0, t.col_dim, TextStyle::Normal);
                let iface = format!("{}{}", n.field("iface", "—"), if n.info.get("type").map(String::as_str) == Some("vpn") { " (vpn)" } else { "" });
                let ip = if n.info.get("prefix").map_or(false, |p| !p.is_empty()) { format!("{}/{}", n.field("ip", "—"), n.field("prefix", "—")) } else { n.field("ip", "—") };
                let rows: [Vec<GridPair>; 3] = [
                    vec![("ИНТЕРФЕЙС", iface, t.col_white), ("IP", ip, t.col_white)],
                    vec![("ШЛЮЗ", n.field("gateway", "—"), t.col_white), ("РОУТЕР", ms(n.num("router_ping_ms")), t.col_white)],
                    vec![("DNS", n.field("dns", "—"), t.col_white)],
                ];
                info_grid_of(ui, GRID_CONNECTION, ix, y + 10.0 + cap.height() + 6.0, iw, &rows);
            }
            Block::Traffic => {
                plate(ui, x0, y, cw, h);
                let cap = caption(ui.fonts, "ТРАФИК");
                ui.text(&cap, ix, y + 10.0, t.col_dim, TextStyle::Normal);
                let ping = n.num("internet_ping_ms");
                let loss = n.num("loss_pct");
                let rows: [Vec<GridPair>; 3] = [
                    vec![("ПРИЁМ", human_rate(n.rx_rate), t.col_white), ("ПЕРЕДАЧА", human_rate(n.tx_rate), t.col_white)],
                    vec![("ПОЛУЧЕНО", human_bytes(n.num("rx_bytes")), t.col_white), ("ОТПРАВЛЕНО", human_bytes(n.num("tx_bytes")), t.col_white)],
                    vec![
                        ("ПИНГ", ms(ping), if !ping.is_nan() && ping > 250.0 { t.col_alert } else { t.col_white }),
                        ("ПОТЕРИ", if loss.is_nan() { "—".into() } else { format!("{}%", js_num(loss)) }, if !loss.is_nan() && loss > 0.0 { t.col_alert } else { t.col_white }),
                    ],
                ];
                info_grid_of(ui, GRID_TRAFFIC, ix, y + 10.0 + cap.height() + 6.0, iw, &rows);
            }
            Block::DnsRow => {
                let cap = caption(ui.fonts, "DNS");
                ui.text(&cap, x0, y + ac(h, cap.height()), t.col_dim, TextStyle::Normal);
                let labels: Vec<String> = DNS_CHOICES.iter().map(|c| c.0.to_uppercase()).collect();
                let widths: Vec<f32> = labels.iter().map(|l| ui.console_button_width(BTN_FONT, "", l, 58.0)).collect();
                let mut bx = x0 + cw - (widths.iter().sum::<f32>() + 6.0 * (widths.len() - 1) as f32);
                for (i, l) in labels.iter().enumerate() {
                    let current = n.dns_is_active(DNS_CHOICES[i].1);
                    ui.console_button_sized(DNS + i as u32, bx, y, widths[i], BTN_FONT, "", t.col_grey, l, current);
                    bx += widths[i] + 6.0;
                }
            }
            Block::NoProfile => {
                let l = ui.fonts.layout("Нет активного профиля Wi-Fi", theme::bar_font(false), HEADER, 0.0);
                ui.text(&l, x0 + cw - l.adv, y, t.col_grey, TextStyle::Normal);
            }
            Block::SpeedPlate(err) => {
                plate(ui, x0, y, cw, h);
                let cap = caption(ui.fonts, "ТЕСТ СКОРОСТИ");
                ui.text(&cap, ix, y + 10.0, t.col_dim, TextStyle::Normal);
                let mut cy = y + 10.0 + cap.height() + 6.0;
                let rows: [Vec<GridPair>; 1] = [vec![
                    ("ПРИЁМ", if n.speed_down > 0.0 { format!("{} Мбит/с", js_num(n.speed_down)) } else { "—".into() }, if n.speed_phase == "down" { t.col_alert } else { t.col_white }),
                    ("ПЕРЕДАЧА", if n.speed_up > 0.0 { format!("{} Мбит/с", js_num(n.speed_up)) } else { "—".into() }, if n.speed_phase == "up" { t.col_alert } else { t.col_white }),
                ]];
                info_grid_of(ui, GRID_SPEED, ix, cy, iw, &rows);
                cy += info_grid_height(ui.fonts, 1) + 6.0;
                if n.speed_error.is_empty() {
                    let status = match n.speed_phase {
                        "" if n.speed_down > 0.0 || n.speed_up > 0.0 => "Остановлен".to_string(),
                        "" => "Готов".into(),
                        "done" => "Готово - пик в каждую сторону".into(),
                        _ if n.speed_now == 0.0 => "Запуск…".into(),
                        "down" => format!("Измерение приёма…  {} Мбит/с", js_num(n.speed_now)),
                        _ => format!("Измерение передачи…  {} Мбит/с", js_num(n.speed_now)),
                    };
                    let l = ui.fonts.layout(&status, theme::bar_font(false), HEADER, 0.0);
                    ui.text(&l, ix, cy, t.col_grey, TextStyle::Normal);
                    cy += l.height();
                } else {
                    for l in &err {
                        ui.text(l, ix, cy, t.col_alert, TextStyle::Normal);
                        cy += l.height();
                    }
                }
                if n.speed_busy() {
                    cy += 6.0;
                    let l = ui.fonts.layout("Пока идёт тест, канал занят полностью.", theme::bar_font(false), HEADER, 0.0);
                    ui.text(&l, ix, cy, t.col_grey, TextStyle::Normal);
                }
            }
            Block::SpeedButton => {
                if n.speed_busy() {
                    let bw = ui.console_button_width(BTN_FONT, "\u{f04db}", "СТОП", 58.0);
                    ui.console_button_sized(STOP, x0 + cw - bw, y, bw, BTN_FONT, "\u{f04db}", t.col_grey, "СТОП", false);
                } else {
                    let label = if n.speed_phase == "done" || n.speed_down > 0.0 || n.speed_up > 0.0 { "ЕЩЁ РАЗ" } else { "СТАРТ" };
                    let bw = ui.console_button_width(BTN_FONT, "\u{f040a}", label, 58.0);
                    ui.console_button_sized(START, x0 + cw - bw, y, bw, BTN_FONT, "\u{f040a}", t.col_grey, label, true);
                }
            }
            Block::QrPlate(err) => {
                plate(ui, x0, y, cw, h);
                let cap = caption(ui.fonts, "ПОДЕЛИТЬСЯ СЕТЬЮ");
                ui.text(&cap, ix, y + 10.0, t.col_dim, TextStyle::Normal);
                let mut cy = y + 10.0 + cap.height();
                if !err.is_empty() {
                    cy += 8.0;
                    for l in &err {
                        ui.text(l, ix, cy, t.col_alert, TextStyle::Normal);
                        cy += l.height();
                    }
                }
                if !n.qr_rows.is_empty() {
                    cy += 8.0;
                    let name = format!("{}{}", n.qr_ssid, if n.qr_security == "nopass" { "  (открытая)" } else { "" });
                    let l = elide_middle(ui.fonts, &name, LABEL, true, iw);
                    ui.text(&l, ix + (iw - l.adv) / 2.0, cy, t.col_white, TextStyle::Normal);
                    cy += l.height() + 8.0;
                    let cell = qr_cell(n);
                    let cols = n.qr_rows[0].len() as f32;
                    let qx = ix + ac(iw, cell * cols);
                    ui.scene.fill(qx, cy, cell * cols, cell * n.qr_rows.len() as f32, Color::qt_rgba(1.0, 1.0, 1.0, 1.0));
                    for (r, row) in n.qr_rows.iter().enumerate() {
                        for (c, b) in row.bytes().enumerate() {
                            if b == b'1' {
                                ui.scene.fill(qx + c as f32 * cell, cy + r as f32 * cell, cell, cell, Color::qt_rgba(0.0, 0.0, 0.0, 1.0));
                            }
                        }
                    }
                    cy += cell * n.qr_rows.len() as f32 + 8.0;
                    let hint = ui.fonts.layout("Наведите камеру, чтобы подключиться", theme::bar_font(false), HEADER, 0.0);
                    ui.text(&hint, ix + (iw - hint.adv) / 2.0, cy, t.col_grey, TextStyle::Normal);
                }
            }
        }
        y += h + 8.0;
    }
}
