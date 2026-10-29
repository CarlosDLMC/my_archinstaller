//! The Wi-Fi widget's network list (WifiWidget.qml, panelMode "networks"):
//! the link, the scanned networks, password entry, connect/disconnect - the
//! same nmcli calls and timings.

use std::time::{Duration, Instant};

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{plate, CardKind, Ui};
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
    /// The field's cursorPosition, in chars of `password`.
    pub cursor: usize,
    /// How far the field's text is scrolled left (QQuickTextInput's hscroll).
    pub hscroll: f32,
    pub failed: bool,
    /// When the password field took focus (the cursor blinks from there).
    pub input_since: Option<Instant>,
    /// wifiConnectProc.output: its stdout and stderr lines as they come.
    connect_out: String,
    /// The bar whose card started the connect (or disconnect) that runs or
    /// ran last: every bar has its own WifiWidget and wifiConnectProc
    /// (shell.qml), so only that bar's widget is `connecting`.
    pub strip: Option<usize>,
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

/// savedProfilesProc (WifiWidget.qml:219-239): the saved Wi-Fi profiles'
/// 802-11-wireless.ssid values, not their names. QML runs one nmcli per
/// profile name; one nmcli for all of them by UUID gives the same set. A
/// name with ':' or '\' comes out of `nmcli -t` escaped, and the name
/// QML's `cut -d: -f1` makes of it finds no profile: those are left out
/// here as well.
pub fn load_saved(app: &mut App) {
    app.spawn("wifi-saved", &["nmcli", "-t", "-f", "NAME,UUID,TYPE", "connection", "show"], |app, d| {
        let uuids: Vec<&str> = d.stdout.lines().filter(|l| l.ends_with(":802-11-wireless") && !l.contains('\\')).filter_map(|l| l.split(':').nth(1)).collect();
        if uuids.is_empty() {
            app.svc.wifi_card.saved.clear();
            return;
        }
        let mut argv = vec!["nmcli", "-g", "802-11-wireless.ssid", "connection", "show"];
        for u in uuids {
            argv.extend(["uuid", u]);
        }
        app.spawn("wifi-saved", &argv, |app, d| {
            app.svc.wifi_card.saved = d.stdout.lines().map(str::trim).filter(|l| !l.is_empty()).map(String::from).collect();
        });
    });
}

/// onOpened: list from the cache now, rescan, read again at 1.4 s and 3.2 s,
/// "scanning" until 3.4 s.
pub fn opened(app: &mut App) {
    scan(app);
    load_saved(app);
    // wifiRescanProc, fire and forget: one at a time, as its Process.
    app.spawn("wifi-rescan", &["nmcli", "device", "wifi", "rescan"], |_, _| {});
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
    clear_password(w);
    w.failed = false;
    app.mark_all_dirty();
}

fn clear_password(w: &mut WifiCard) {
    w.password.clear();
    w.cursor = 0;
    w.hscroll = 0.0;
}

/// wifiConnectProc (WifiWidget.qml:330-369). Process.running = true on a
/// Process that runs already does nothing.
fn run_connect(app: &mut App, argv: &[&str]) {
    if connecting(app) {
        return;
    }
    app.svc.wifi_card.connect_out.clear();
    app.svc.wifi_card.strip = app.card.as_ref().map(|c| c.strip);
    app.spawn_stream("wifi-connect", argv, connect_line, Some(connect_line), Some(connect_done));
    app.mark_all_dirty();
}

/// The SplitParsers on stdout and stderr: `output += data`. nmcli says why a
/// connect failed on stderr only.
fn connect_line(app: &mut App, data: &str) {
    app.svc.wifi_card.connect_out.push_str(data);
}

/// onRunningChanged, not running: the watchdog stops and the status is read
/// again; a failure on a secured network brings up the password view, a
/// success closes the card - the widget's own (`dropdownOpen = false`):
/// either view, on the bar the connect came from, not a card of another
/// widget or bar opened since.
fn connect_done(app: &mut App) {
    app.cancel_timer("wifi-watchdog");
    crate::services::wifi_refresh(app);
    let out = std::mem::take(&mut app.svc.wifi_card.connect_out).to_lowercase();
    let failed = out.contains("error") || out.contains("secrets were required") || out.contains("no suitable connection") || out.contains("failed");
    let own = app.card.as_ref().map_or(false, |c| matches!(c.kind, CardKind::Wifi | CardKind::Network) && Some(c.strip) == app.svc.wifi_card.strip);
    let w = &mut app.svc.wifi_card;
    if failed && !w.selected_ssid.is_empty() && !w.selected_security.is_empty() && !w.password_mode {
        w.failed = true;
        enter_password(app);
    } else if !failed && !app.svc.wifi_card.selected_ssid.is_empty() {
        if own {
            crate::cards::close(app);
        }
        cancel_password(app);
    }
    app.mark_all_dirty();
}

/// connectWatchdog (WifiWidget.qml:314-327): nmcli still connecting after 8 s
/// is stopped, and on a secured network the password view comes up.
fn watchdog(app: &mut App) {
    if connecting(app) {
        app.kill("wifi-connect");
        let w = &app.svc.wifi_card;
        if !w.selected_ssid.is_empty() && !w.selected_security.is_empty() {
            app.svc.wifi_card.failed = true;
            enter_password(app);
        }
    }
}

fn enter_password(app: &mut App) {
    app.svc.wifi_card.password_mode = true;
    // forceActiveFocus on the field, the first control in password mode - a
    // field only the Wi-Fi card has (passwordMode is the widget's state; any
    // other card open by now keeps its focus).
    if let Some(c) = app.card.as_mut().filter(|c| c.kind == CardKind::Wifi) {
        c.focus = Some(0);
        c.win.dirty = true;
    }
    blink_restart(app);
}

/// The cursor shows again and blinks from now (QQuickTextInput's
/// updateCursorBlinking: on focus in, on every key it takes).
fn blink_restart(app: &mut App) {
    app.svc.wifi_card.input_since = Some(Instant::now());
    app.debounce("wifi-blink", Duration::from_millis(500), blink);
}

/// TextInput's cursor blink (cursorFlashTime 1000: 500 ms on, 500 ms off):
/// the card redraws at each flip only, while the password view is up and
/// the field has the focus.
fn blink(app: &mut App) {
    if !app.svc.wifi_card.password_mode {
        return;
    }
    let Some(c) = app.card.as_mut().filter(|c| c.kind == CardKind::Wifi) else { return };
    if c.focus.and_then(|f| c.focus_codes.get(f)) == Some(&INPUT) {
        c.win.dirty = true;
    }
    let since = app.svc.wifi_card.input_since.map_or(0, |s| s.elapsed().as_millis() as u64);
    app.debounce("wifi-blink", Duration::from_millis(500 - since % 500), blink);
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
    // Only this connect is watched (connectWatchdog.restart() in tryConnect):
    // connectWithPassword starts none.
    app.debounce("wifi-watchdog", Duration::from_secs(8), watchdog);
}

fn connect_with_password(app: &mut App) {
    let w = &app.svc.wifi_card;
    if w.selected_ssid.is_empty() || w.password.is_empty() {
        return;
    }
    let (ssid, pass) = (w.selected_ssid.clone(), w.password.clone());
    app.svc.wifi_card.password_mode = false;
    clear_password(&mut app.svc.wifi_card);
    run_connect(app, &["nmcli", "device", "wifi", "connect", &ssid, "password", &pass]);
}

// ---- the password field (TextInput, echoMode Password) ----

/// TextInput.maxLength, in UTF-16 units.
const MAX_LENGTH: usize = 32767;

/// The byte where char `i` of `s` starts (its end for i past the last).
fn byte_at(s: &str, i: usize) -> usize {
    s.char_indices().nth(i).map_or(s.len(), |(b, _)| b)
}

/// The field's dots and the cursor's x in them (QTextLine::cursorToX). Each
/// UTF-16 unit is a dot: QQuickTextInput fills its displayed text with the
/// mask character.
fn field_text(fonts: &mut crate::text::Fonts, w: &WifiCard) -> (crate::text::Line, f32) {
    let dots = "●".repeat(w.password.encode_utf16().count());
    let line = fonts.layout(&dots, theme::bar_font(false), FONT_SIZE - 1.0, 0.0);
    let k: usize = w.password.chars().take(w.cursor).map(char::len_utf16).sum();
    let cx = line.glyphs.get(k).map_or(line.adv, |g| g.x);
    (line, cx)
}

/// QQuickTextInputPrivate::updateHorizontalScroll (autoScroll): the text
/// moves only as far as it must to keep the cursor in a field `width` wide;
/// typing past the end leaves the cursor just outside the clip, as in Qt.
fn scroll(prev: f32, cx: f32, text_w: f32, width: f32) -> f32 {
    let used = text_w.max(cx);
    if used <= width {
        0.0
    } else if cx - prev >= width {
        cx - width
    } else if cx - prev < 0.0 && prev < used {
        cx
    } else if used - prev < width {
        used - width
    } else if width - prev > used {
        width - used
    } else {
        prev
    }
}

/// The field's width: popupWidth less the Loader's and the TextInput's margins.
fn field_width(app: &mut App) -> f32 {
    card_width(&mut app.fonts, &app.svc) - 32.0
}

/// The scroll the field shows now: a width changed since the last edit runs
/// updateHorizontalScroll again (geometryChange), before an edit's own.
fn shown_scroll(app: &mut App, width: f32) -> f32 {
    let (line, cx) = field_text(&mut app.fonts, &app.svc.wifi_card);
    scroll(app.svc.wifi_card.hscroll, cx, line.adv, width)
}

/// After an edit or a cursor move: scrolled from `prev` to keep the cursor in.
fn rescroll(app: &mut App, prev: f32, width: f32) {
    let (line, cx) = field_text(&mut app.fonts, &app.svc.wifi_card);
    app.svc.wifi_card.hscroll = scroll(prev, cx, line.adv, width);
}

/// QQuickTextInputPrivate::insert at the cursor, cut at maxLength.
fn insert(w: &mut WifiCard, s: &str) {
    let mut room = MAX_LENGTH.saturating_sub(w.password.encode_utf16().count());
    let text: String = s
        .chars()
        .take_while(|c| match room.checked_sub(c.len_utf16()) {
            Some(r) => {
                room = r;
                true
            }
            None => false,
        })
        .collect();
    w.cursor = w.cursor.min(w.password.chars().count());
    let b = byte_at(&w.password, w.cursor);
    w.password.insert_str(b, &text);
    w.cursor += text.chars().count();
}

/// QKeySequence::Paste (Ctrl+V, Shift+Insert): the clipboard's text goes
/// in at the cursor as it is, newlines and all. wl-paste reads it through
/// the compositor's data-control, as the clipboard history does.
fn paste(app: &mut App) {
    app.spawn("wifi-paste", &["wl-paste", "--no-newline", "--type", "text"], |app, d| {
        let open = app.card.as_ref().map_or(false, |c| c.kind == CardKind::Wifi);
        if d.stdout.is_empty() || !open || !app.svc.wifi_card.password_mode {
            return;
        }
        let width = field_width(app);
        let prev = shown_scroll(app, width);
        insert(&mut app.svc.wifi_card, &d.stdout);
        rescroll(app, prev, width);
        if let Some(c) = app.card.as_mut() {
            c.win.dirty = true;
        }
    });
}

/// A press in the field puts the cursor at the gap between two dots
/// nearest to it (positionAt, CursorBetweenCharacters); `x` is from the
/// field's left edge.
fn place_cursor(app: &mut App, x: f32) {
    let width = field_width(app);
    let prev = shown_scroll(app, width);
    let (line, _) = field_text(&mut app.fonts, &app.svc.wifi_card);
    let (x, n) = (x + prev, line.glyphs.len());
    let gap = |k: usize| line.glyphs.get(k).map_or(line.adv, |g| g.x);
    let unit = (0..n).find(|&k| x < (gap(k) + gap(k + 1)) / 2.0).unwrap_or(n);
    // A dot is a UTF-16 unit; the cursor stays off the middle of a character.
    let w = &mut app.svc.wifi_card;
    let mut units = 0;
    w.cursor = w.password.chars().take_while(|c| {
        let before = units;
        units += c.len_utf16();
        before < unit
    }).count();
    rescroll(app, prev, width);
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
    // `connecting` is this bar's widget's: its own connect runs.
    let busy = busy && wc.strip == Some(ui.card.strip);

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
        // The field: plate, accent border while focused, bullets and a
        // blinking cursor; the TextInput is the plate less 8 px around.
        let focused = ui.focusable(INPUT);
        ui.scene.rect(x0, y, cw, 36.0, t.col_plate, 4.0, 1.0, if focused { t.col_accent } else { Color::TRANSPARENT }, true);
        let fw = cw - 16.0;
        let (fl, cur) = field_text(ui.fonts, wc);
        let hs = scroll(wc.hscroll, cur, fl.adv, fw);
        let ty = y + 8.0 + ac(20.0, fl.height());
        ui.scene.save();
        ui.scene.clip_rect(x0 + 8.0, y + 8.0, fw, 20.0);
        ui.text(&fl, x0 + 8.0 - hs, ty, t.col_white, TextStyle::Normal);
        if focused {
            // TextInput's cursor: 1 px, the text colour, 500 ms on / 500 ms
            // off; blink() redraws the card at each flip.
            let on = wc.input_since.map_or(true, |s| (s.elapsed().as_millis() / 500) % 2 == 0);
            if on {
                ui.scene.fill(x0 + 8.0 + cur - hs, ty, 1.0, fl.height(), t.col_white);
            }
        }
        ui.scene.restore();
        ui.hits.push(Hit { x: x0 + 8.0, y: y + 8.0, w: fw, h: 20.0, action: Action::Card(INPUT) });
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
    // networkListView: 8 rows in view, the rest (up to 30) scrolled to.
    let sig = crate::cards::model_sig(&wc.networks);
    let list = ui.list_begin(ROW, x0 + 4.0, y + 4.0, cw - 8.0, rows, wc.networks.len(), m.row, 2.0, sig, |_| true);
    for (i, (ssid, signal, security)) in wc.networks.iter().enumerate() {
        let ry = list.row_y(i);
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
            // The lock Text is there for open networks too, empty.
            Some((if security.is_empty() { "" } else { "\u{f033e}" }, t.col_grey)),
        );
    }
    ui.view_end(list);
}

pub fn activate(app: &mut App, code: u32) {
    match code {
        DISCONNECT => {
            // Through wifiConnectProc, as WifiWidget.qml:515-523 runs it: the
            // widget is `connecting` while it runs (ПОДКЛЮЧЕНИЕ, the icon
            // blinks), it is skipped while a connect runs, and the same exit
            // handler follows.
            run_connect(app, &["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2 == \"wifi\" && $3 == \"connected\" { print $1 }' | while IFS= read -r d; do nmcli device disconnect \"$d\"; done"]);
        }
        INPUT => {
            // A press gives the field the focus and puts the cursor where it
            // was; coming in, the cursor shows and blinks anew (focusInEvent).
            let Some(c) = app.card.as_mut() else { return };
            let had = c.focus.and_then(|f| c.focus_codes.get(f)) == Some(&INPUT);
            c.focus = c.focus_codes.iter().position(|x| *x == INPUT);
            c.win.dirty = true;
            // The field starts at the Loader's 8 px plus its own 8 px margin.
            if let Some(x) = c.pointer.map(|(px, _)| px - c.origin().0 - 16.0) {
                place_cursor(app, x);
            }
            if !had {
                blink_restart(app);
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

/// Keys while the password field has focus (WifiWidget.qml:545-557, Qt's
/// TextInput): Return submits and Esc cancels (its Keys handlers); text goes
/// in at the cursor; Backspace, Delete, Left, Right, Home and End edit and
/// move it; Ctrl+V and Shift+Insert paste. Returns true when the key was the
/// field's - checked against Qt 6.12 offscreen.
pub fn input_key(app: &mut App, sym: smithay_client_toolkit::seat::keyboard::Keysym, utf8: Option<&str>) -> bool {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    let Some(card) = app.card.as_ref() else { return false };
    let focused = card.focus.and_then(|f| card.focus_codes.get(f).copied());
    if focused != Some(INPUT) {
        return false;
    }
    let shift = card.shift;
    let w = &app.svc.wifi_card;
    let len = w.password.chars().count();
    let at = w.cursor.min(len);
    match sym {
        Keysym::Return => {
            connect_with_password(app);
            return true;
        }
        Keysym::Escape => {
            cancel_password(app);
            return true;
        }
        // Keypad Enter is Key_Enter: TextInput emits accepted() and lets it
        // go, and nothing up to CardKeys takes it.
        Keysym::KP_Enter => return true,
        // CardKeys' Tab shortcuts; and what QQuickTextInput::keyPressEvent
        // leaves to it: Up, Down, Left at the start, Right at the end.
        Keysym::Tab | Keysym::ISO_Left_Tab | Keysym::Up | Keysym::Down | Keysym::KP_Up | Keysym::KP_Down => return false,
        Keysym::Left | Keysym::KP_Left if at == 0 => return false,
        Keysym::Right | Keysym::KP_Right if at >= len => return false,
        _ => {}
    }
    // Ctrl+V's text is U+0016 (Ctrl+Shift+V is no paste in Qt).
    let paste_key = (utf8 == Some("\u{16}") && !shift) || (sym == Keysym::Insert && shift) || sym == Keysym::XF86_Paste;
    let width = field_width(app);
    let prev = shown_scroll(app, width);
    let w = &mut app.svc.wifi_card;
    match sym {
        Keysym::BackSpace => {
            if at > 0 {
                w.password.remove(byte_at(&w.password, at - 1));
                w.cursor = at - 1;
            }
        }
        Keysym::Delete | Keysym::KP_Delete => {
            if at < len {
                w.password.remove(byte_at(&w.password, at));
            }
        }
        Keysym::Left | Keysym::KP_Left => w.cursor = at - 1,
        Keysym::Right | Keysym::KP_Right => w.cursor = at + 1,
        Keysym::Home | Keysym::KP_Home => w.cursor = 0,
        Keysym::End | Keysym::KP_End => w.cursor = len,
        _ if paste_key => paste(app),
        _ => match utf8 {
            Some(s) if !s.is_empty() && !s.chars().any(char::is_control) => insert(w, s),
            _ => return false,
        },
    }
    rescroll(app, prev, width);
    blink_restart(app);
    if let Some(c) = app.card.as_mut() {
        c.win.dirty = true;
    }
    true
}
