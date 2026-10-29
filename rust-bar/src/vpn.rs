//! The VPN widget's card (VpnWidget.qml): the tunnel, the time/weather sync
//! keys and the WireGuard configs, with the same helper scripts.

use std::time::{Duration, Instant};

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{plate, Ui};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::services::{self, Services};
use crate::theme::{self, FONT_SIZE};

#[derive(Default)]
pub struct Vpn {
    pub configs: Vec<String>,
    pub connecting: bool,
    /// The 450 ms spinner floors (timeSpinFloor / weatherSpinFloor).
    pub time_floor: Option<Instant>,
    pub weather_floor: Option<Instant>,
    /// What the card asked of vpnActionProc while it still ran (its
    /// targetRunning, see tunnel()): Some(None) = ВЫКЛ, Some(Some(name)) = go there.
    queued: Option<Option<String>>,
}

pub const OFF: u32 = 1;
pub const TIME: u32 = 2;
pub const WEATHER: u32 = 3;
pub const ROW: u32 = 0x100;

const FLOOR: Duration = Duration::from_millis(450);

fn scripts() -> String {
    format!("{}/.config/quickshell/bar/scripts", services::home())
}

pub fn time_busy(app: &App) -> bool {
    app.is_running("vpn-time") || app.svc.vpn_card.time_floor.map_or(false, |t| t.elapsed() < FLOOR)
}

pub fn weather_busy(app: &App) -> bool {
    app.is_running("vpn-weather") || app.svc.vpn_card.weather_floor.map_or(false, |t| t.elapsed() < FLOOR)
}

/// onOpened: the configs, as root can list them.
pub fn opened(app: &mut App) {
    app.spawn("vpn-list", &["sh", "-c", "sudo find /etc/wireguard -name '*.conf' -exec basename {} .conf \\; 2>/dev/null | sort"], |app, d| {
        let list: Vec<String> = d.stdout.lines().map(str::trim).filter(|l| !l.is_empty()).map(String::from).collect();
        if !list.is_empty() {
            app.svc.vpn_card.configs = list;
        }
        app.mark_all_dirty();
    });
}

fn flag(name: &str) -> &'static str {
    match name.get(..2).unwrap_or("").to_lowercase().as_str() {
        "de" => "🇩🇪",
        "pl" => "🇵🇱",
        "ge" => "🇬🇪",
        "es" => "🇪🇸",
        "ua" => "🇺🇦",
        "lt" => "🇱🇹",
        "id" => "🇮🇩",
        _ => "",
    }
}

struct M {
    head: f32,
    btn: f32,
    row: f32,
}

fn metrics(fonts: &mut crate::text::Fonts, active: bool) -> M {
    let name_h = fonts.layout("Н", theme::bar_font(true), FONT_SIZE - 2.0, 0.0).height();
    let btn = ((FONT_SIZE - 6.0) * 2.1).round();
    M { head: name_h.max(if active { btn } else { 0.0 }), btn, row: ((FONT_SIZE - 3.0) * 1.75).round() }
}

pub fn card_height(fonts: &mut crate::text::Fonts, svc: &Services) -> f32 {
    let active = !svc.vpn.is_empty();
    let m = metrics(fonts, active);
    let mut parts = vec![m.head];
    if active {
        parts.push(m.btn);
    }
    if !svc.vpn_card.configs.is_empty() {
        let n = svc.vpn_card.configs.len().min(8) as f32;
        parts.push(n * (m.row + 2.0) - 2.0 + 8.0);
    }
    let h = parts.iter().sum::<f32>() + 8.0 * (parts.len() - 1) as f32;
    h.ceil() + 28.0
}

pub fn draw(ui: &mut Ui, w: f32, svc: &Services, busy: (bool, bool)) {
    let t = ui.theme;
    let active = !svc.vpn.is_empty();
    let m = metrics(ui.fonts, active);
    let (x0, cw) = (8.0, w - 16.0);
    let mut y = 12.0 + 8.0;

    // ТУННЕЛЬ: lamp, caption, the tunnel's name, the off key.
    crate::cards::lamp(ui, 0x7000, x0 + 4.0, y + ac(m.head, 10.0), active);
    let cap = ui.fonts.layout("ТУННЕЛЬ", theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
    let cx = x0 + 4.0 + 10.0 + 10.0;
    ui.text(&cap, cx, y + ac(m.head, cap.height()), t.col_dim, TextStyle::Normal);
    let font = FONT_SIZE - 6.0;
    let off_w = ui.console_button_width(font, "\u{f0156}", "", 0.0);
    let nx = cx + cap.width + 10.0;
    let right = if active { x0 + cw - off_w } else { x0 + cw };
    let name = if active { svc.vpn.as_str() } else { "ОТКЛЮЧЁН" };
    let key = theme::bar_font(true);
    let full = ui.fonts.layout(name, key, FONT_SIZE - 2.0, 0.0);
    let line = ui.fonts.elide_right(&full, name, key, right - 8.0 - nx, 0.0);
    ui.text(&line, nx, y + ac(m.head, line.height()), if active { t.col_white } else { t.col_grey }, TextStyle::Normal);
    if active {
        ui.console_button_sized(OFF, x0 + cw - off_w, y + ac(m.head, m.btn), off_w, font, "\u{f0156}", t.col_grey, "", false);
    }
    y += m.head + 8.0;

    // ВРЕМЯ / ПОГОДА: follow the tunnel's place, or come back home.
    if active {
        let bw = (cw - 6.0) / 2.0;
        let time_away = !svc.timezone.is_empty();
        let weather_away = !svc.weather.city.is_empty();
        ui.console_button_ex(TIME, x0, y, bw, font, "\u{f0954}", t.col_grey, "ВРЕМЯ", time_away, busy.0, !busy.0);
        ui.console_button_ex(WEATHER, x0 + bw + 6.0, y, bw, font, "\u{f0590}", t.col_grey, "ПОГОДА", weather_away, busy.1, !busy.1);
        y += m.btn + 8.0;
    }

    // The configs, a flag after each.
    if !svc.vpn_card.configs.is_empty() {
        let configs = &svc.vpn_card.configs;
        let n = configs.len().min(8);
        let h = n as f32 * (m.row + 2.0) - 2.0 + 8.0;
        plate(ui, x0, y, cw, h);
        // vpnListView: 8 rows in view, the rest scrolled to; the tunnel in
        // use is lit and not pickable.
        let pickable = |i: usize| configs.get(i).map_or(false, |c| *c != svc.vpn);
        let list = ui.list_begin(ROW, x0 + 4.0, y + 4.0, cw - 8.0, n, configs.len(), m.row, 2.0, crate::cards::model_sig(configs), pickable);
        for (i, name) in configs.iter().enumerate() {
            let lit = *name == svc.vpn;
            // The flag Text is there for every config, empty for an unknown country.
            crate::cards::console_row(ui, ROW + i as u32, x0 + 4.0, list.row_y(i), cw - 8.0, m.row, "", name, lit, !lit, None, Some(flag(name)));
        }
        ui.view_end(list);
    }
}

pub fn activate(app: &mut App, code: u32) {
    let active = app.svc.vpn.clone();
    match code {
        OFF => {
            app.svc.vpn_card.connecting = true;
            tunnel(app, None);
            let cmd = format!("{}/vpn-reset.sh all --forget", scripts());
            app.spawn("vpn-reset-card", &["sh", "-c", &cmd], |app, _| {
                services::vpn_check(app);
            });
            crate::cards::close(app);
        }
        TIME => {
            app.svc.vpn_card.time_floor = Some(Instant::now());
            let cmd = if !app.svc.timezone.is_empty() { format!("{}/vpn-reset.sh time", scripts()) } else { format!("{}/vpn-sync.sh \"$1\" time", scripts()) };
            app.spawn("vpn-time", &["sh", "-c", &cmd, "sh", &active], |app, _| app.mark_all_dirty());
            spin_redraw(app);
        }
        WEATHER => {
            app.svc.vpn_card.weather_floor = Some(Instant::now());
            let cmd = if !app.svc.weather.city.is_empty() { format!("{}/vpn-reset.sh weather", scripts()) } else { format!("{}/vpn-sync.sh \"$1\" weather", scripts()) };
            app.spawn("vpn-weather", &["sh", "-c", &cmd, "sh", &active], |app, _| app.mark_all_dirty());
            spin_redraw(app);
        }
        c if (ROW..ROW + 0x100).contains(&c) => {
            let Some(target) = app.svc.vpn_card.configs.get((c - ROW) as usize).cloned() else { return };
            app.svc.vpn_card.connecting = true;
            tunnel(app, Some(target));
            crate::cards::close(app);
        }
        _ => {}
    }
}

/// vpnActionProc.running = true: down the tunnel in use (`to` None, ВЫКЛ),
/// or go to `to` - up from none, through vpn-switch.sh from another
/// (VpnWidget.qml:98-128). Asked while an action still runs, it runs once
/// that one has ended, the last request winning: Process keeps `running =
/// true` on a process still running (targetRunning) and starts it again
/// from onFinished (quickshell process.cpp:274-287), where spawn() dropped
/// it - ВЫКЛ during a connect left the tunnel up. It is then taken against
/// the tunnel up by that time; QML's re-run keeps the name ВЫКЛ saw, and
/// its end handler has cleared switchFrom, so a pick made meanwhile comes
/// up beside the tunnel already up. That part is not copied.
fn tunnel(app: &mut App, to: Option<String>) {
    if app.is_running("vpn-action") {
        app.svc.vpn_card.queued = Some(to);
        return;
    }
    let active = app.svc.vpn.clone();
    match to {
        None if active.is_empty() => {}
        None => app.spawn("vpn-action", &["sudo", "wg-quick", "down", &active], |app, _| {
            // isDisconnect: activeVpn = "" (VpnWidget.qml:121-123) - the
            // strip's icon goes grey now; the check below finds "" == "".
            if !app.svc.vpn.is_empty() {
                app.svc.vpn.clear();
                app.mark_all_dirty();
            }
            tunnel_done(app);
        }),
        Some(to) if to == active => {}
        Some(to) if active.is_empty() => app.spawn("vpn-action", &["sudo", "wg-quick", "up", &to], |app, _| tunnel_done(app)),
        Some(to) => {
            let cmd = format!("{}/vpn-switch.sh \"$1\" \"$2\"", scripts());
            app.spawn("vpn-action", &["sh", "-c", &cmd, "sh", &active, &to], |app, _| tunnel_done(app));
        }
    }
}

/// vpnActionProc's end (VpnWidget.qml:116-127): the status again 500 ms
/// later (statusUpdateTimer.restart()), then what was asked meanwhile,
/// against the tunnel the status shows now.
fn tunnel_done(app: &mut App) {
    app.svc.vpn_card.connecting = false;
    app.debounce("vpn-status", Duration::from_millis(500), services::vpn_check);
    if let Some(to) = app.svc.vpn_card.queued.take() {
        services::vpn_check(app);
        tunnel(app, to);
    }
}

/// The floor ends without an event: redraw when it does.
fn spin_redraw(app: &mut App) {
    app.after(FLOOR + Duration::from_millis(10), |app| app.mark_all_dirty());
    app.mark_all_dirty();
}

pub fn unused(_: Color, _: Hit, _: Action) {}
