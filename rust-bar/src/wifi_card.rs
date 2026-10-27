//! The Wi-Fi widget's network list (WifiWidget.qml, panelMode "networks"):
//! the link, the scanned networks, password entry, connect/disconnect - the
//! same nmcli calls and timings.

use std::time::{Duration, Instant};

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{plate, Ui};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::services::{split_terse, Services};
use crate::theme::{self, FONT_SIZE};

#[derive(Default)]
pub struct WifiCard {
    pub networks: Vec<(String, i64, String)>,
    pub saved: Vec<String>,
    pub scanning: bool,
    pub password_mode: bool,
    pub selected_ssid: String,
    pub selected_security: String,
    pub password: String,
    pub failed: bool,
    /// When the password field took focus (the cursor blinks from there).
    pub input_since: Option<Instant>,
}

pub const DISCONNECT: u32 = 1;
pub const INPUT: u32 = 2;
pub const CANCEL: u32 = 3;
pub const CONNECT: u32 = 4;
pub const ROW: u32 = 0x100;

pub fn connecting(app: &App) -> bool {
    app.is_running("wifi-connect")
}

fn scan(app: &mut App) {
    app.spawn("wifi-scan", &["sh", "-c", "nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan no | grep -v '^:' | sort -t: -k2 -nr | head -30"], |app, d| {
        if d.stdout.trim().is_empty() {
            return;
        }
        let mut seen = Vec::new();
        let mut nets = Vec::new();
        for line in d.stdout.trim().lines() {
            let p = split_terse(line);
            if p.len() >= 2 && !p[0].is_empty() && !seen.contains(&p[0]) {
                seen.push(p[0].clone());
                nets.push((p[0].clone(), p[1].parse().unwrap_or(0), p.get(2).cloned().unwrap_or_default()));
            }
        }
        app.svc.wifi_card.networks = nets;
        app.mark_all_dirty();
    });
}

/// onOpened: list from the cache now, rescan, read again at 1.4 s and 3.2 s,
/// "scanning" until 3.4 s.
pub fn opened(app: &mut App) {
    scan(app);
    app.spawn("wifi-saved", &["sh", "-c", "nmcli -t -f NAME,TYPE connection show | grep ':802-11-wireless$' | cut -d: -f1 | while IFS= read -r n; do nmcli -g 802-11-wireless.ssid connection show \"$n\"; done"], |app, d| {
        app.svc.wifi_card.saved = d.stdout.lines().map(str::trim).filter(|l| !l.is_empty()).map(String::from).collect();
    });
    app.exec_detached(&["nmcli", "device", "wifi", "rescan"]);
    app.debounce("wifi-rescan1", Duration::from_millis(1400), scan);
    app.debounce("wifi-rescan2", Duration::from_millis(3200), scan);
    app.svc.wifi_card.scanning = true;
    app.debounce("wifi-settle", Duration::from_millis(3400), |app| {
        app.svc.wifi_card.scanning = false;
        app.mark_all_dirty();
    });
    cancel_password(app);
}

fn cancel_password(app: &mut App) {
    let w = &mut app.svc.wifi_card;
    w.password_mode = false;
    w.selected_ssid.clear();
    w.selected_security.clear();
    w.password.clear();
    w.failed = false;
    app.mark_all_dirty();
}

fn run_connect(app: &mut App, argv: &[&str]) {
    app.spawn("wifi-connect", argv, |app, d| {
        app.debounce("wifi-watchdog", Duration::from_secs(3600), |_| {});
        crate::services::wifi_refresh(app);
        let out = d.stdout.to_lowercase();
        let failed = out.contains("error") || out.contains("secrets were required") || out.contains("no suitable connection") || out.contains("failed");
        let w = &mut app.svc.wifi_card;
        if failed && !w.selected_ssid.is_empty() && !w.selected_security.is_empty() && !w.password_mode {
            w.failed = true;
            enter_password(app);
        } else if !failed && !app.svc.wifi_card.selected_ssid.is_empty() {
            crate::cards::close(app);
            cancel_password(app);
        }
        app.mark_all_dirty();
    });
    // The 8 s watchdog: a stalled attempt falls back to the password view.
    app.debounce("wifi-watchdog", Duration::from_secs(8), |app| {
        if connecting(app) {
            app.kill("wifi-connect");
            let w = &app.svc.wifi_card;
            if !w.selected_ssid.is_empty() && !w.selected_security.is_empty() {
                app.svc.wifi_card.failed = true;
                enter_password(app);
            }
        }
    });
    app.mark_all_dirty();
}

fn enter_password(app: &mut App) {
    app.svc.wifi_card.password_mode = true;
    app.svc.wifi_card.input_since = Some(Instant::now());
    if let Some(c) = app.card.as_mut() {
        // forceActiveFocus on the field: the first control in password mode.
        c.focus = Some(0);
        c.win.dirty = true;
    }
}

fn try_connect(app: &mut App, ssid: &str, security: &str) {
    let w = &mut app.svc.wifi_card;
    w.selected_ssid = ssid.to_string();
    w.selected_security = security.to_string();
    w.failed = false;
    if !security.is_empty() && !w.saved.iter().any(|s| s == ssid) {
        enter_password(app);
        return;
    }
    run_connect(app, &["nmcli", "device", "wifi", "connect", ssid]);
}

fn connect_with_password(app: &mut App) {
    let w = &app.svc.wifi_card;
    if w.selected_ssid.is_empty() || w.password.is_empty() {
        return;
    }
    let (ssid, pass) = (w.selected_ssid.clone(), w.password.clone());
    app.svc.wifi_card.password_mode = false;
    app.svc.wifi_card.password.clear();
    run_connect(app, &["nmcli", "device", "wifi", "connect", &ssid, "password", &pass]);
}

fn signal_icon(s: i64) -> &'static str {
    match s {
        s if s >= 80 => "\u{f0928}",
        s if s >= 60 => "\u{f0925}",
        s if s >= 40 => "\u{f0922}",
        s if s >= 20 => "\u{f091f}",
        _ => "\u{f092f}",
    }
}

/// popupWidth in networks mode: fits the longest SSID.
pub fn card_width(fonts: &mut crate::text::Fonts, svc: &Services) -> f32 {
    let mut longest = svc.wifi.ssid.clone();
    for n in &svc.wifi_card.networks {
        if n.0.chars().count() > longest.chars().count() {
            longest = n.0.clone();
        }
    }
    let w = fonts.layout(&longest, theme::bar_font(true), FONT_SIZE - 1.0, 0.0).adv;
    300f32.max(600f32.min(w.ceil() + 170.0))
}

struct M {
    head: f32,
    btn: f32,
    row: f32,
    cap: f32,
    note: f32,
}

fn metrics(fonts: &mut crate::text::Fonts, svc: &Services) -> M {
    let name = fonts.layout("Н", theme::bar_font(true), FONT_SIZE - 2.0, 0.0).height();
    let btn = ((FONT_SIZE - 6.0) * 2.1).round();
    let disc = svc.wifi.connected && !svc.wifi_card.password_mode;
    M {
        head: name.max(if disc { btn } else { 0.0 }),
        btn,
        row: ((FONT_SIZE - 3.0) * 1.75).round(),
        cap: fonts.layout("К", theme::bar_font(true), FONT_SIZE - 5.0, 1.0).height(),
        note: fonts.layout("П", theme::bar_font(false), FONT_SIZE - 4.0, 0.0).height(),
    }
}

fn list_rows(svc: &Services) -> usize {
    (if svc.wifi_card.scanning { 3 } else { 1 }).max(svc.wifi_card.networks.len()).min(8)
}

pub fn card_height(fonts: &mut crate::text::Fonts, svc: &Services) -> f32 {
    let m = metrics(fonts, svc);
    let w = &svc.wifi_card;
    let mut parts = vec![m.head];
    if w.password_mode {
        parts.push(m.cap + 8.0 + 36.0 + 8.0 + m.btn);
    }
    if w.scanning && w.networks.len() <= 1 && !w.password_mode {
        parts.push(m.note);
    }
    if !w.password_mode {
        parts.push(list_rows(svc) as f32 * (m.row + 2.0) - 2.0 + 8.0);
    }
    let h = parts.iter().sum::<f32>() + 8.0 * (parts.len() - 1) as f32;
    h.ceil() + 28.0
}

pub fn draw(ui: &mut Ui, w: f32, svc: &Services, busy: bool) {
    let t = ui.theme;
    let wc = &svc.wifi_card;
    let m = metrics(ui.fonts, svc);
    let (x0, cw) = (8.0, w - 16.0);
    let mut y = 12.0 + 8.0;

    // The link: lamp, caption, name, scan spinner, disconnect.
    let tint = if busy { t.col_alert } else { t.col_accent };
    crate::cards::lamp_tinted(ui, 0x7100, x0 + 4.0, y + ac(m.head, 10.0), svc.wifi.connected || busy, tint);
    let cap_text = if busy { "ПОДКЛЮЧЕНИЕ" } else if wc.password_mode { "СЕТЬ" } else { "WI-FI" };
    let cap = ui.fonts.layout(cap_text, theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
    let cx = x0 + 4.0 + 10.0 + 10.0;
    ui.text(&cap, cx, y + ac(m.head, cap.height()), t.col_dim, TextStyle::Normal);
    let font = FONT_SIZE - 6.0;
    let disc = svc.wifi.connected && !wc.password_mode;
    let disc_w = ui.console_button_width(font, "\u{f0156}", "", 0.0);
    let mut right = x0 + cw;
    if disc {
        ui.console_button_sized(DISCONNECT, right - disc_w, y + ac(m.head, m.btn), disc_w, font, "\u{f0156}", t.col_grey, "", false);
        right -= disc_w + 8.0;
    }
    if wc.scanning && !wc.password_mode && !busy {
        let s = FONT_SIZE - 4.0;
        right -= s;
        crate::pult::spinner(ui, right, y + ac(m.head, s), s, t.col_dim);
        right -= 8.0;
    } else if disc {
        right += 0.0;
    }
    let name = if busy {
        format!("{}…", wc.selected_ssid)
    } else if wc.password_mode {
        wc.selected_ssid.clone()
    } else if svc.wifi.connected {
        svc.wifi.ssid.clone()
    } else {
        "НЕТ ПОДКЛЮЧЕНИЯ".into()
    };
    let color = if busy {
        t.col_alert
    } else if svc.wifi.connected || wc.password_mode {
        t.col_white
    } else {
        t.col_grey
    };
    let nx = cx + cap.width + 10.0;
    let key = theme::bar_font(true);
    let full = ui.fonts.layout(&name, key, FONT_SIZE - 2.0, 0.0);
    let right_edge = if disc || (wc.scanning && !wc.password_mode && !busy) { right } else { x0 + cw - 8.0 };
    let line = ui.fonts.elide_right(&full, &name, key, right_edge - nx, 0.0);
    ui.text(&line, nx, y + ac(m.head, line.height()), color, TextStyle::Normal);
    y += m.head + 8.0;

    if wc.password_mode {
        let cap = ui.fonts.layout("КОД ДОСТУПА", theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
        ui.text(&cap, x0, y, t.col_dim, TextStyle::Normal);
        y += cap.height() + 8.0;
        // The field: plate, accent border while focused, bullets and a blinking cursor.
        let focused = ui.focusable(INPUT);
        ui.scene.rect(x0, y, cw, 36.0, t.col_plate, 4.0, 1.0, if focused { t.col_accent } else { Color::TRANSPARENT }, true);
        let dots: String = "●".repeat(wc.password.chars().count());
        let fl = ui.fonts.layout(&dots, theme::bar_font(false), FONT_SIZE - 1.0, 0.0);
        let ty = y + 8.0 + ac(20.0, fl.height());
        ui.scene.save();
        ui.scene.clip_rect(x0 + 8.0, y + 8.0, cw - 16.0, 20.0);
        ui.text(&fl, x0 + 8.0, ty, t.col_white, TextStyle::Normal);
        if focused {
            // TextInput's cursor: 1 px, the text colour, 500 ms on / 500 ms off.
            let on = wc.input_since.map_or(true, |s| (s.elapsed().as_millis() / 500) % 2 == 0);
            if on {
                ui.scene.fill(x0 + 8.0 + fl.adv, ty, 1.0, fl.height(), t.col_white);
            }
            ui.animating = true;
        }
        ui.scene.restore();
        ui.hits.push(Hit { x: x0, y, w: cw, h: 36.0, action: Action::Card(INPUT) });
        y += 36.0 + 8.0;
        let bw = (cw - 8.0) / 2.0;
        ui.console_button_sized(CANCEL, x0, y, bw, font, "", t.col_grey, "ОТМЕНА", false);
        ui.console_button_sized(CONNECT, x0 + bw + 8.0, y, bw, font, "", t.col_grey, "ПОДКЛЮЧИТЬ", true);
        return;
    }
    if wc.scanning && wc.networks.len() <= 1 {
        let l = ui.fonts.layout("Поиск сетей…", theme::bar_font(false), FONT_SIZE - 4.0, 0.0);
        ui.text(&l, x0, y, t.col_grey, TextStyle::Normal);
        y += m.note + 8.0;
    }
    let rows = list_rows(svc);
    let h = rows as f32 * (m.row + 2.0) - 2.0 + 8.0;
    plate(ui, x0, y, cw, h);
    let mut ry = y + 4.0;
    for (i, (ssid, signal, security)) in wc.networks.iter().take(8).enumerate() {
        let is_connecting = busy && *ssid == wc.selected_ssid;
        let lit = *ssid == svc.wifi.ssid || is_connecting;
        let tint = if is_connecting { t.col_alert } else { t.col_accent };
        crate::cards::console_row_full(
            ui,
            ROW + i as u32,
            x0 + 4.0,
            ry,
            cw - 8.0,
            m.row,
            signal_icon(*signal),
            ssid,
            lit,
            true,
            tint,
            Some(("подключение…", t.col_alert)).filter(|_| is_connecting),
            if security.is_empty() { None } else { Some(("\u{f033e}", t.col_grey)) },
        );
        ry += m.row + 2.0;
    }
}

pub fn activate(app: &mut App, code: u32) {
    match code {
        DISCONNECT => {
            app.spawn("wifi-disconnect", &["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2 == \"wifi\" && $3 == \"connected\" { print $1 }' | while IFS= read -r d; do nmcli device disconnect \"$d\"; done"], |app, _| crate::services::wifi_refresh(app));
        }
        INPUT => {
            if let Some(c) = app.card.as_mut() {
                c.focus = c.focus_codes.iter().position(|x| *x == INPUT);
            }
        }
        CANCEL => cancel_password(app),
        CONNECT => connect_with_password(app),
        c if (ROW..ROW + 0x100).contains(&c) => {
            if let Some((ssid, _, sec)) = app.svc.wifi_card.networks.get((c - ROW) as usize).cloned() {
                try_connect(app, &ssid, &sec);
            }
        }
        _ => {}
    }
}

/// Keys while the password field has focus: text, Backspace, Return, Escape.
/// Returns true when the key was the field's.
pub fn input_key(app: &mut App, sym: smithay_client_toolkit::seat::keyboard::Keysym, utf8: Option<&str>) -> bool {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    let Some(card) = app.card.as_ref() else { return false };
    let focused = card.focus.and_then(|f| card.focus_codes.get(f).copied());
    if focused != Some(INPUT) {
        return false;
    }
    match sym {
        Keysym::Return | Keysym::KP_Enter => connect_with_password(app),
        Keysym::Escape => cancel_password(app),
        Keysym::BackSpace => {
            app.svc.wifi_card.password.pop();
        }
        Keysym::Tab | Keysym::ISO_Left_Tab | Keysym::Up | Keysym::Down => return false,
        _ => match utf8 {
            Some(s) if !s.is_empty() && !s.chars().any(char::is_control) => app.svc.wifi_card.password.push_str(s),
            _ => return false,
        },
    }
    app.svc.wifi_card.input_since = Some(Instant::now());
    if let Some(c) = app.card.as_mut() {
        c.win.dirty = true;
    }
    true
}
