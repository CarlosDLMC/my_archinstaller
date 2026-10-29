//! ПУЛЬТ (PultWidget.qml): Bluetooth, night light, НЕ ЗАСЫПАТЬ, the stats
//! switch and the power profile - its state, the same helper commands, and
//! its card. KeepAwake and the stats switch live here too.

use std::time::Duration;

use crate::app::{App, ProcDone};
use crate::bar::{ac, Action, Hit};
use crate::cards::{plate, Ui};
use crate::color::Color;
use crate::services::{self, Services};
use crate::theme::{self, FONT_SIZE};

#[derive(Default)]
pub struct Pult {
    pub has_adapter: bool,
    pub bt_powered: bool,
    pub bt_connected: bool,
    pub bt_connected_device: String,
    pub bt_devices: Vec<(String, String)>,
    pub scan_done: bool,
    pub found: Vec<(String, String)>,
    pub pairing_mac: String,
    pub pair_failed_mac: String,
    pub has_profiles: bool,
    pub current_profile: String,
    pub night_on: bool,
    pub keep_awake: bool,
    /// Which opening of the card this is: its D-Bus watchers run under tags
    /// that carry it (watch()).
    opening: u32,
    /// Asked for again while still running (Process's targetRunning): the
    /// power chain with the last click's state, one more night-light toggle.
    bt_power_again: Option<bool>,
    night_again: bool,
}

const PROFILES: [&str; 3] = ["performance", "balanced", "power-saver"];
const PPD: [&str; 4] = ["net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "ActiveProfile"];

fn profile_label(p: &str) -> String {
    match p {
        "performance" => "Разгон",
        "balanced" => "Норма",
        "power-saver" => "Экономия",
        other => other,
    }
    .to_uppercase()
}

// ---- state ----

pub fn start(app: &mut App) {
    refresh(app);
    // KeepAwake: the switch survives a bar restart in the session's runtime dir.
    let on = std::fs::read_to_string(keep_awake_path()).map_or(false, |t| t.trim() == "on");
    app.svc.pult.keep_awake = on;
    if on {
        inhibit(app, true);
    }
}

pub fn refresh(app: &mut App) {
    app.svc.pult.has_adapter = has_bluetooth();
    if app.svc.pult.has_adapter {
        bt_status(app);
        bt_connected(app);
        bt_devices(app);
        watch(app);
    }
    let mut argv = vec!["busctl", "--system", "get-property"];
    argv.extend(PPD);
    app.spawn("profile-get", &argv, |app, d| {
        if let Some(p) = d.stdout.split('"').nth(1) {
            app.svc.pult.current_profile = p.to_string();
            app.svc.pult.has_profiles = true;
            watch(app);
            app.mark_all_dirty();
        }
    });
    read_night(app);
    app.mark_all_dirty();
}

/// btPresenceProc (PultWidget.qml:28-32, 129-145): `ls -d
/// /sys/class/bluetooth/hci*`, else `rfkill -n -o TYPE list bluetooth | grep -q
/// bluetooth` - a blocked radio empties the class but keeps its rfkill
/// switch. Read here rather than through sh, ls, rfkill and grep.
fn has_bluetooth() -> bool {
    let any = |dir: &str, f: &dyn Fn(&std::fs::DirEntry) -> bool| std::fs::read_dir(dir).map_or(false, |d| d.flatten().any(|e| f(&e)));
    any("/sys/class/bluetooth", &|e| e.file_name().to_string_lossy().starts_with("hci"))
        || any("/sys/class/rfkill", &|e| std::fs::read_to_string(e.path().join("type")).map_or(false, |t| t.trim() == "bluetooth"))
}

/// btStatusProc: `bluetoothctl show | grep -E 'Powered|Name'`, then "Powered:
/// yes" anywhere in it - the same as in the whole output, so no shell or grep.
fn bt_status(app: &mut App) {
    app.spawn("bt-status", &["bluetoothctl", "show"], |app, d| {
        app.svc.pult.bt_powered = d.stdout.contains("Powered: yes");
        app.mark_all_dirty();
    });
}

/// btConnectedProc: `bluetoothctl info 2>/dev/null | grep -E 'Name|Connected'
/// | head -2`, the filter done here.
fn bt_connected(app: &mut App) {
    app.spawn("bt-connected", &["bluetoothctl", "info"], |app, d| {
        let out: Vec<&str> = d.stdout.lines().filter(|l| l.contains("Name") || l.contains("Connected")).take(2).collect();
        let p = &mut app.svc.pult;
        if out.iter().any(|l| l.contains("Connected: yes")) {
            p.bt_connected = true;
            if let Some(n) = out.iter().find_map(|l| l.trim().strip_prefix("Name:")) {
                p.bt_connected_device = n.trim().to_string();
            }
        } else {
            p.bt_connected = false;
            p.bt_connected_device.clear();
        }
        app.mark_all_dirty();
    });
}

/// btDevices / foundDevices = a list. A different one is a new model for its
/// ListView, which makes the rows anew (setModel compares the values): their
/// texts start fresh (subpixel) - this list's only, so each list has its own
/// text parts (the framework's list_replaced forgets ConsoleRow's 0xC1-0xC4,
/// card-wide, which these rows do not use).
fn set_list(app: &mut App, found: bool, list: Vec<(String, String)>) {
    let p = &mut app.svc.pult;
    let (old, texts) = if found { (&mut p.found, FOUND_TEXTS) } else { (&mut p.bt_devices, PAIRED_TEXTS) };
    if *old == list {
        return;
    }
    *old = list;
    if let Some(c) = app.card.as_mut().filter(|c| c.kind == crate::cards::CardKind::Pult) {
        c.texts.forget_parts(&[texts + 1, texts + 3, texts + 4]);
    }
}

/// "Device <MAC> <name>" lines.
fn parse_devices(out: &str) -> Vec<(String, String)> {
    out.lines()
        .filter_map(|l| {
            let rest = l.trim().strip_prefix("Device")?.trim_start();
            let (mac, name) = rest.split_once(char::is_whitespace)?;
            let mac_ok = mac.len() == 17 && mac.chars().all(|c| c.is_ascii_hexdigit() || c == ':');
            (mac_ok && !name.trim().is_empty()).then(|| (mac.to_string(), name.trim().to_string()))
        })
        .collect()
}

fn bt_devices(app: &mut App) {
    app.spawn("bt-devices", &["bluetoothctl", "devices", "Paired"], |app, d| {
        set_list(app, false, parse_devices(&d.stdout));
        app.mark_all_dirty();
    });
}

fn bt_found(app: &mut App) {
    app.spawn("bt-found", &["bluetoothctl", "devices"], |app, d| {
        let p = &app.svc.pult;
        let paired: Vec<&String> = p.bt_devices.iter().map(|d| &d.0).collect();
        // Unnamed devices show their MAC (with dashes) as the name: skip those.
        let is_mac_name = |n: &str| n.len() == 17 && n.split('-').count() == 6 && n.chars().all(|c| c.is_ascii_hexdigit() || c == '-');
        let found = parse_devices(&d.stdout).into_iter().filter(|(m, n)| !paired.contains(&m) && !is_mac_name(n)).collect();
        set_list(app, true, found);
        app.mark_all_dirty();
    });
}

fn set_bluetooth(app: &mut App, on: bool) {
    app.svc.pult.bt_powered = on;
    bt_power(app, on);
    if on {
        app.exec_detached(&["blueman-applet"]);
    } else {
        stop_scan(app);
        app.exec_detached(&["sh", "-c", "killall blueman-applet blueman-tray 2>/dev/null || true"]);
    }
    app.mark_all_dirty();
}

/// btPowerProc.running = true with powerOn = `on` (PultWidget.qml:312-326).
/// Clicked again while the chain still runs, Process runs it once more when
/// it ends, with the last click's powerOn (targetRunning, quickshell
/// process.cpp:274-287): a quick on-off ends with the radio off, as in QML.
/// spawn() dropped the second run, so the radio stayed on while the switch
/// said off and the applet had been killed.
fn bt_power(app: &mut App, on: bool) {
    if app.is_running("bt-power") {
        app.svc.pult.bt_power_again = Some(on);
        return;
    }
    let cmd = if on {
        "sudo rfkill unblock bluetooth && sudo systemctl start bluetooth && sleep 0.5 && bluetoothctl power on"
    } else {
        "bluetoothctl power off && sudo systemctl stop bluetooth && sudo rfkill block bluetooth"
    };
    app.spawn("bt-power", &["sh", "-c", cmd], |app, _| {
        bt_status(app);
        bt_connected(app);
        bt_devices(app);
        if let Some(on) = app.svc.pult.bt_power_again.take() {
            bt_power(app, on);
        }
    });
}

pub fn scanning(app: &App) -> bool {
    app.is_running("bt-scan")
}

fn start_scan(app: &mut App) {
    set_list(app, true, Vec::new());
    let p = &mut app.svc.pult;
    p.scan_done = false;
    p.pair_failed_mac.clear();
    app.spawn("bt-scan", &["bluetoothctl", "--timeout", "30", "scan", "on"], |app, _| {
        app.svc.pult.scan_done = true;
        bt_found(app);
    });
    app.debounce(FOUND_POLL, Duration::from_millis(1500), found_tick);
    app.mark_all_dirty();
}

/// Timer { interval: 1500; running: pult.scanning; repeat: true }
/// (PultWidget.qml:262-267): one, by name, started again with each search -
/// a search stopped and started again within 1.5 s kept the old one ticking
/// beside the new one.
const FOUND_POLL: &str = "bt-found-poll";

fn found_tick(app: &mut App) {
    if scanning(app) {
        bt_found(app);
        app.debounce(FOUND_POLL, Duration::from_millis(1500), found_tick);
    }
}

pub fn stop_scan(app: &mut App) {
    app.kill("bt-scan");
}

fn pair(app: &mut App, mac: &str) {
    if !app.svc.pult.pairing_mac.is_empty() {
        return;
    }
    stop_scan(app);
    app.svc.pult.pair_failed_mac.clear();
    app.svc.pult.pairing_mac = mac.to_string();
    let script = "bluetoothctl --timeout 30 pair \"$1\" >/dev/null 2>&1; if bluetoothctl info \"$1\" 2>/dev/null | grep -q 'Paired: yes'; then bluetoothctl trust \"$1\" >/dev/null 2>&1; bluetoothctl --timeout 15 connect \"$1\" >/dev/null 2>&1; echo ok; else echo fail; fi";
    app.spawn("bt-pair", &["sh", "-c", script, "sh", mac], |app, d: ProcDone| {
        let p = &mut app.svc.pult;
        let mac = std::mem::take(&mut p.pairing_mac);
        if d.stdout.trim() == "fail" {
            p.pair_failed_mac = mac;
        } else {
            let rest = p.found.iter().filter(|f| f.0 != mac).cloned().collect();
            set_list(app, true, rest);
        }
        bt_devices(app);
        bt_connected(app);
    });
    app.mark_all_dirty();
}

fn set_profile(app: &mut App, profile: &str) {
    if profile == app.svc.pult.current_profile {
        return;
    }
    app.svc.pult.current_profile = profile.to_string();
    let mut argv = vec!["busctl", "--system", "set-property"];
    argv.extend(PPD);
    argv.extend(["s", profile]);
    app.spawn("profile-set", &argv, |app, _| {
        let mut argv = vec!["busctl", "--system", "get-property"];
        argv.extend(PPD);
        app.spawn("profile-get", &argv, |app, d| {
            if let Some(p) = d.stdout.split('"').nth(1) {
                app.svc.pult.current_profile = p.to_string();
                app.mark_all_dirty();
            }
        });
    });
    app.mark_all_dirty();
}

/// What NightLight.sh last wrote to its state file: "on" or not.
fn night_file_on() -> bool {
    std::fs::read_to_string(format!("{}/.cache/.nightlight_state", services::home())).map_or(false, |t| t.trim() == "on")
}

/// NightLight.qml: on = the state file says so and wlsunset is alive
/// (aliveProc's `pgrep -x wlsunset`, read here from /proc - refresh()
/// redraws).
fn read_night(app: &mut App) {
    app.svc.pult.night_on = night_file_on() && wlsunset_alive();
}

/// `pgrep -x wlsunset`: a process whose name (/proc/<pid>/comm) is wlsunset.
fn wlsunset_alive() -> bool {
    let Ok(dir) = std::fs::read_dir("/proc") else { return false };
    dir.flatten().any(|e| {
        let pid = e.file_name().to_str().map_or(false, |n| n.bytes().all(|b| b.is_ascii_digit()));
        pid && std::fs::read(e.path().join("comm")).map_or(false, |c| c == b"wlsunset\n")
    })
}

/// NightLight.toggle(): toggleProc.running = true (NightLight.qml:64-71). On
/// a toggle still running, Process runs it once more after it (targetRunning),
/// so a double click toggles twice, as in QML. Its end shows what the script
/// wrote, as the state file's watch does (applyState, NightLight.qml:28-35):
/// a fresh "on" is trusted - a pgrep right then can come before nohup has
/// started wlsunset and turn the switch off.
fn night_toggle(app: &mut App) {
    if app.is_running("night-toggle") {
        app.svc.pult.night_again = true;
        return;
    }
    app.spawn("night-toggle", &["bash", "-c", "$HOME/.config/hypr/scripts/NightLight.sh toggle"], |app, _| {
        app.svc.pult.night_on = night_file_on();
        app.mark_all_dirty();
        if std::mem::take(&mut app.svc.pult.night_again) {
            night_toggle(app);
        }
    });
}

fn keep_awake_path() -> String {
    format!("{}/quickshell-keep-awake", std::env::var("XDG_RUNTIME_DIR").unwrap_or("/tmp".into()))
}

/// KeepAwake: systemd-inhibit --what=idle held by a child that ends with the bar.
fn inhibit(app: &mut App, on: bool) {
    if on {
        let cmd = "exec systemd-inhibit --what=idle --who=\"Quickshell bar\" --why=\"НЕ ЗАСЫПАТЬ is on\" --mode=block sh -c 'while kill -0 \"$1\" 2>/dev/null && kill -0 \"$PPID\" 2>/dev/null; do sleep 5; done' sh \"$PPID\"";
        app.spawn_lines_tagged("keep-awake", &["sh", "-c", cmd], |_, _| {});
    } else {
        app.kill("keep-awake");
    }
}

fn set_keep_awake(app: &mut App, on: bool) {
    app.svc.pult.keep_awake = on;
    let _ = std::fs::write(keep_awake_path(), if on { "on\n" } else { "off\n" });
    inhibit(app, on);
    app.mark_all_dirty();
}

/// SystemStats.setShown: the strip's CPU/RAM readouts.
fn set_stats_shown(app: &mut App, on: bool) {
    app.svc.stats.shown = on;
    let path = format!("{}/.cache/quickshell/bar-stats", services::home());
    if let Some(dir) = std::path::Path::new(&path).parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(&path, if on { "on\n" } else { "off\n" });
    app.mark_all_dirty();
}

/// The card opened: fresh readings, the D-Bus watchers on while it stays open.
pub fn opened(app: &mut App) {
    app.svc.pult.opening = app.svc.pult.opening.wrapping_add(1);
    set_list(app, true, Vec::new());
    let p = &mut app.svc.pult;
    p.scan_done = false;
    p.pair_failed_mac.clear();
    refresh(app);
    watch(app);
}

/// btMonitor / profileMonitor (PultWidget.qml:338-397): `running:
/// pult.dropdownOpen && pult.hasAdapter` (hasProfiles) - started whenever
/// both hold, so also when the adapter or the daemon answers after the card
/// opened. The tags carry the opening: the last opening's watcher, killed by
/// closed() but holding its tag until its pipe closes, made another bar's ⚙
/// (a close and an open in one go) start none.
fn watch(app: &mut App) {
    if app.card.as_ref().map(|c| c.kind) != Some(crate::cards::CardKind::Pult) {
        return;
    }
    let n = app.svc.pult.opening;
    if app.svc.pult.has_adapter {
        // --profile: one line per signal (QML's `while read line` turns each
        // of the default format's 8-10 lines into a line), so a search's RSSI
        // stream restarts the 400 ms settle once per signal; the output is
        // only ever a trigger.
        app.spawn_lines_tagged(&format!("bt-monitor-{n}"), &["dbus-monitor", "--system", "--profile", "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='/org/bluez'"], |app, _| {
            app.debounce("bt-settle", Duration::from_millis(400), |app| {
                bt_status(app);
                bt_connected(app);
            });
        });
    }
    if app.svc.pult.has_profiles {
        app.spawn_lines_tagged(&format!("profile-monitor-{n}"), &["dbus-monitor", "--system", "--profile", "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/net/hadess/PowerProfiles'"], |app, _| {
            let mut argv = vec!["busctl", "--system", "get-property"];
            argv.extend(PPD);
            app.spawn("profile-get", &argv, |app, d| {
                if let Some(p) = d.stdout.split('"').nth(1) {
                    app.svc.pult.current_profile = p.to_string();
                    app.mark_all_dirty();
                }
            });
        });
    }
}

pub fn closed(app: &mut App) {
    stop_scan(app);
    let n = app.svc.pult.opening;
    app.kill(&format!("bt-monitor-{n}"));
    app.kill(&format!("profile-monitor-{n}"));
}

// ---- the card ----

pub const SW_BT: u32 = 1;
pub const SW_NIGHT: u32 = 2;
pub const SW_AWAKE: u32 = 3;
pub const SW_STATS: u32 = 4;
pub const SEARCH: u32 = 5;
pub const PAIRED_ROW: u32 = 0x100;
pub const FOUND_ROW: u32 = 0x200;
pub const PROFILE: u32 = 0x300;

fn qround(v: f32) -> f32 {
    (v + 0.5).floor()
}

struct M {
    cap_h: f32,
    sw_h: f32,
    btn_h: f32,
    row_h: f32,
    text_h: f32,
}

fn metrics(fonts: &mut crate::text::Fonts) -> M {
    let cap_h = fonts.layout("Н", theme::bar_font(true), FONT_SIZE - 5.0, 1.0).height();
    let lbl_h = fonts.layout("Н", theme::bar_font(true), FONT_SIZE - 7.0, 1.0).height();
    let btn_h = ((FONT_SIZE - 6.0) * 2.1).round();
    M { cap_h, sw_h: lbl_h.max(btn_h) + 4.0, btn_h, row_h: ((FONT_SIZE - 3.0) * 1.75).round(), text_h: fonts.layout("Н", theme::bar_font(false), FONT_SIZE - 4.0, 0.0).height() }
}

/// The card's Column, as (kind of child, height) - shared by measuring and drawing.
fn children(fonts: &mut crate::text::Fonts, svc: &Services, scanning: bool) -> Vec<(u8, f32)> {
    let p = &svc.pult;
    let m = metrics(fonts);
    let mut v = vec![(0u8, m.cap_h)];
    let switches = if p.has_adapter { 4.0 } else { 3.0 };
    v.push((1, switches * m.sw_h + (switches - 1.0) * 2.0 + 12.0));
    if p.has_adapter && p.bt_powered {
        v.push((2, m.btn_h));
        if !p.bt_devices.is_empty() {
            let n = p.bt_devices.len().min(6) as f32;
            v.push((3, n * (m.row_h + 2.0) - 2.0 + 8.0));
        } else {
            v.push((4, m.text_h));
        }
    }
    if p.bt_powered && (scanning || p.scan_done) {
        v.push((5, m.cap_h));
    }
    if p.bt_powered && !p.found.is_empty() {
        let n = p.found.len().min(6) as f32;
        v.push((6, n * (m.row_h + 2.0) - 2.0 + 8.0));
    }
    if p.bt_powered && p.found.is_empty() && (scanning || p.scan_done) {
        v.push((7, m.text_h));
    }
    if p.has_profiles {
        v.push((8, m.cap_h));
        v.push((9, m.btn_h));
    }
    v
}

pub fn card_height(fonts: &mut crate::text::Fonts, svc: &Services, scanning: bool) -> f32 {
    let c = children(fonts, svc, scanning);
    let h: f32 = c.iter().map(|x| x.1).sum::<f32>() + 8.0 * (c.len().saturating_sub(1)) as f32;
    h.ceil() + 28.0
}

// The card's Texts, keyed for TextMemo (text_of) by the item they are, not by
// the order a frame draws them in: a caption or note that appears (НАЙДЕНО at
// a search) or a switch that does (BLUETOOTH) took the place of the next one
// and grayed it, where Qt makes the new item's node fresh (subpixel) and
// leaves the others alone. Captions and notes: part NOTE, id = their kind in
// children(); a switch: parts SWITCH + 1..3 (glyph, label, detail), id = its
// code (its key's caption is ConsoleButton's 0xB2); a device row: its list's
// parts + 1 (icon), + 3 (detail), + 4 (label), id = its code.
const NOTE: u64 = 0xA0;
const SWITCH: u64 = 0xA4;
const PAIRED_TEXTS: u64 = 0xD0;
const FOUND_TEXTS: u64 = 0xE0;

/// ConsoleCaption: bold, fontSize - 5, letterSpacing 1, colDim.
fn caption(ui: &mut Ui, kind: u8, text: &str, x: f32, y: f32) {
    let l = crate::cards::caption(ui.fonts, text);
    let c = ui.theme.col_dim;
    ui.text_of(kind as u32, NOTE, &l, x, y, c);
}

/// PultSwitch: lamp, glyph, bold label, detail, and the ВКЛ/ВЫКЛ key.
#[allow(clippy::too_many_arguments)]
fn switch(ui: &mut Ui, code: u32, x: f32, y: f32, w: f32, h: f32, icon: &str, label: &str, detail: &str, on: bool) {
    let t = ui.theme;
    crate::cards::lamp(ui, code, x + 4.0, y + ac(h, 10.0), on);
    let fg = if on { t.col_white } else { t.col_grey };
    let gw = FONT_SIZE - 2.0;
    let gx = x + 4.0 + 10.0 + 10.0;
    let g = ui.fonts.layout(icon, theme::bar_font(false), FONT_SIZE - 4.0, 0.0);
    ui.text_of(code, SWITCH + 1, &g, gx + (gw - g.adv) / 2.0, y + ac(h, g.height()), fg);
    let lx = gx + gw + 8.0;
    let l = ui.fonts.layout(label, theme::bar_font(true), FONT_SIZE - 7.0, 1.0);
    ui.text_of(code, SWITCH + 2, &l, lx, y + ac(h, l.height()), fg);
    let font = FONT_SIZE - 6.0;
    let bw = ui.console_button_width(font, "", if on { "ВКЛ" } else { "ВЫКЛ" }, 72.0);
    let bh = (font * 2.1).round();
    let bx = x + w - bw;
    if !detail.is_empty() {
        let dx = lx + l.width + 10.0;
        let dw = bx - 8.0 - dx;
        let key = theme::bar_font(false);
        let full = ui.fonts.layout(detail, key, FONT_SIZE - 7.0, 0.0);
        let d = ui.fonts.elide_right(&full, detail, key, dw, 0.0);
        ui.text_of(code, SWITCH + 3, &d, dx, y + ac(h, d.height()), t.col_dim);
    }
    ui.console_button_sized(code, bx, y + ac(h, bh), bw, font, "", t.col_grey, if on { "ВКЛ" } else { "ВЫКЛ" }, on);
}

/// A device row: ConsoleRow (as cards::console_row draws it) with the icon
/// 󰂯, a detail, and on the found list the trailing Row with its Spinner
/// (`spinner_cell`: Some(pairing)). `texts` is the list's text parts.
#[allow(clippy::too_many_arguments)]
fn device_row(ui: &mut Ui, code: u32, texts: u64, x: f32, y: f32, w: f32, h: f32, label: &str, lit: bool, detail: &str, detail_color: Color, spinner_cell: Option<bool>) {
    let t = ui.theme;
    let font = FONT_SIZE - 3.0;
    let focused = ui.focusable(code);
    let hot = ui.hovered(x, y, w, h) || focused;
    let (bg, run) = ui.card.color(0x5_0000 + code, if hot { t.col_plate.lighter(1.6) } else { Color::TRANSPARENT }, 110, ui.now);
    ui.animating |= run;
    ui.scene.rect(x, y, w, h, bg, 4.0, if focused { 2.0 } else { 0.0 }, t.col_white, true);
    crate::cards::lamp(ui, code, x + 6.0, y + qround((h - 10.0) / 2.0), lit);
    let fg = if lit || hot { t.col_white } else { t.col_grey };
    let ix = x + 6.0 + 10.0 + 8.0;
    let il = ui.fonts.layout("\u{f00af}", theme::bar_font(false), font, 0.0);
    ui.text_of(code, texts + 1, &il, ix + (font + 2.0 - il.adv) / 2.0, y + qround((h - il.height()) / 2.0), fg);
    let tx = ix + font + 2.0 + 8.0;
    // ConsoleRow's RowLayout (ConsoleRow.qml:117-171): the detail and the
    // trailing Row are cells of qCeil(implicitWidth) on whole pixels from the
    // right edge, 8 apart, each Text at its cell's start; the label fills
    // what is left. The found rows' Row always holds the Spinner, so it is a
    // cell with its spacing even while the Spinner is hidden (zero wide).
    let mut right = x + w - 6.0;
    if let Some(spinning) = spinner_cell {
        if spinning {
            let s = FONT_SIZE - 8.0;
            right -= s;
            spinner(ui, right, y + qround((h - s) / 2.0), s, t.col_white);
        }
        right -= 8.0;
    }
    if !detail.is_empty() {
        let d = ui.fonts.layout(detail, theme::bar_font(false), font - 2.0, 0.0);
        right -= d.width.ceil();
        ui.text_of(code, texts + 3, &d, right, y + qround((h - d.height()) / 2.0), detail_color);
        right -= 8.0;
    }
    let key = theme::bar_font(lit);
    let full = ui.fonts.layout(label, key, font, 0.0);
    let line = ui.fonts.elide_right(&full, label, key, right - tx, 0.0);
    ui.text_of(code, texts + 4, &line, tx, y + qround((h - line.height()) / 2.0), fg);
    ui.hits.push(Hit { x, y, w, h, action: Action::Card(code) });
}

/// Spinner: eight dots on a ring, fading towards the tail, a turn per 900 ms.
pub fn spinner<S: crate::cards::UiState>(ui: &mut Ui<S>, x: f32, y: f32, size: f32, color: Color) {
    let dot = 2f32.max((size / 7.0).round());
    let r = size / 2.0 - dot / 2.0;
    let ms = ui.now.duration_since(*crate::cards::EPOCH.get_or_init(std::time::Instant::now)).as_millis() % 900;
    let angle = ms as f32 / 900.0 * std::f32::consts::TAU;
    let (c, s) = (angle.cos(), angle.sin());
    let (cx, cy) = (x + size / 2.0, y + size / 2.0);
    for i in 0..8 {
        let a = i as f32 * std::f32::consts::TAU / 8.0;
        let (dx, dy) = (a.cos() * r, a.sin() * r);
        let (rx, ry) = (dx * c - dy * s, dx * s + dy * c);
        let o = 0.12 + 0.88 * (i as f32 / 7.0);
        ui.scene.save();
        ui.scene.multiply_opacity(o);
        ui.scene.rect(cx + rx - dot / 2.0, cy + ry - dot / 2.0, dot, dot, color, dot / 2.0, 0.0, Color::TRANSPARENT, true);
        ui.scene.restore();
    }
    ui.animating = true;
}

pub fn draw(ui: &mut Ui, w: f32, svc: &Services, scanning: bool) {
    let t = ui.theme;
    let p = &svc.pult;
    let m = metrics(ui.fonts);
    let (x0, cw) = (8.0, w - 16.0);
    let mut y = 12.0 + 8.0;
    for (kind, h) in children(ui.fonts, svc, scanning) {
        match kind {
            0 => caption(ui, kind, "НАСТРОЙКИ", x0, y),
            1 => {
                plate(ui, x0, y, cw, h);
                let (ix, iw) = (x0 + 6.0, cw - 12.0);
                let mut sy = y + 6.0;
                let rows: Vec<(u32, &str, &str, String, bool)> = [
                    p.has_adapter.then(|| (SW_BT, if p.bt_connected { "\u{f00b1}" } else { "\u{f00af}" }, "BLUETOOTH", if p.bt_connected { p.bt_connected_device.clone() } else { String::new() }, p.bt_powered)),
                    Some((SW_NIGHT, "\u{f050e}", "НОЧНОЙ СВЕТ", String::new(), p.night_on)),
                    Some((SW_AWAKE, "\u{f0176}", "НЕ ЗАСЫПАТЬ", String::new(), p.keep_awake)),
                    Some((SW_STATS, "\u{f035b}", "ЦП · ОЗУ НА ПАНЕЛИ", String::new(), svc.stats.shown)),
                ]
                .into_iter()
                .flatten()
                .collect();
                for (code, icon, label, detail, on) in rows {
                    switch(ui, code, ix, sy, iw, m.sw_h, icon, label, &detail, on);
                    sy += m.sw_h + 2.0;
                }
            }
            2 => {
                let cl = crate::cards::caption(ui.fonts, "СОПРЯЖЁННЫЕ УСТРОЙСТВА");
                ui.text_of(kind as u32, NOTE, &cl, x0, y + ac(h, cl.height()), t.col_dim);
                let font = FONT_SIZE - 6.0;
                let label = if scanning { "СТОП" } else { "ПОИСК" };
                let bw = ui.console_button_width(font, "\u{f0349}", label, 58.0);
                // busy: pult.scanning (PultWidget.qml:465-474) - the spinner
                // takes the glyph's place in its box and the caption stays
                // beside it; the key stays enabled.
                ui.console_button_ex(SEARCH, x0 + cw - bw, y, bw, font, "\u{f0349}", t.col_grey, label, false, scanning, true);
            }
            3 | 6 => {
                plate(ui, x0, y, cw, h);
                let (list, base) = if kind == 3 { (&p.bt_devices, PAIRED_ROW) } else { (&p.found, FOUND_ROW) };
                // deviceList / foundList: 6 rows in view, the rest scrolled to.
                let lv = ui.list_begin(base, x0 + 4.0, y + 4.0, cw - 8.0, list.len().min(6), list.len(), m.row_h, 2.0, crate::cards::model_sig(list), |_| true);
                for (i, (mac, name)) in list.iter().enumerate() {
                    let ry = lv.row_y(i);
                    if kind == 3 {
                        let connected = *name == p.bt_connected_device;
                        device_row(ui, PAIRED_ROW + i as u32, PAIRED_TEXTS, x0 + 4.0, ry, cw - 8.0, m.row_h, name, connected, if connected { "ПОДКЛЮЧЕНО" } else { "" }, t.col_dim, None);
                    } else {
                        let pairing = *mac == p.pairing_mac;
                        let failed = *mac == p.pair_failed_mac;
                        device_row(ui, FOUND_ROW + i as u32, FOUND_TEXTS, x0 + 4.0, ry, cw - 8.0, m.row_h, name, false, if pairing { "СОПРЯЖЕНИЕ…" } else if failed { "ОШИБКА" } else { "" }, if failed { t.col_alert } else { t.col_dim }, Some(pairing));
                    }
                }
                ui.view_end(lv);
            }
            // Two Texts in QML: "Нет сопряжённых…" and the search's note.
            4 | 7 => {
                let text = if kind == 4 { "Нет сопряжённых устройств" } else if scanning { "Поиск устройств…" } else { "Ничего не найдено" };
                let l = ui.fonts.layout(text, theme::bar_font(false), FONT_SIZE - 4.0, 0.0);
                ui.text_of(kind as u32, NOTE, &l, x0 + (cw - l.adv) / 2.0, y, t.col_grey);
            }
            5 => caption(ui, kind, "НАЙДЕНО", x0, y),
            8 => caption(ui, kind, "РЕЖИМ ПИТАНИЯ", x0, y),
            9 => {
                let bw = (cw - 12.0) / 3.0;
                for (i, prof) in PROFILES.iter().enumerate() {
                    let cur = *prof == p.current_profile;
                    ui.console_button_sized(PROFILE + i as u32, x0 + i as f32 * (bw + 6.0), y, bw, FONT_SIZE - 6.0, "", t.col_grey, &profile_label(prof), cur);
                }
            }
            _ => {}
        }
        y += h + 8.0;
    }
}

pub fn activate(app: &mut App, code: u32) {
    let p = &app.svc.pult;
    match code {
        SW_BT => set_bluetooth(app, !p.bt_powered),
        SW_NIGHT => night_toggle(app),
        SW_AWAKE => set_keep_awake(app, !p.keep_awake),
        SW_STATS => set_stats_shown(app, !app.svc.stats.shown),
        SEARCH => {
            if scanning(app) {
                stop_scan(app)
            } else {
                start_scan(app)
            }
        }
        c if (PAIRED_ROW..PAIRED_ROW + 0x100).contains(&c) => {
            if let Some((mac, name)) = p.bt_devices.get((c - PAIRED_ROW) as usize).cloned() {
                if name == p.bt_connected_device {
                    app.exec_detached(&["bluetoothctl", "disconnect"]);
                } else {
                    app.exec_detached(&["bluetoothctl", "connect", &mac]);
                }
            }
        }
        c if (FOUND_ROW..FOUND_ROW + 0x100).contains(&c) => {
            if let Some((mac, _)) = p.found.get((c - FOUND_ROW) as usize).cloned() {
                pair(app, &mac);
            }
        }
        c if (PROFILE..PROFILE + 3).contains(&c) => set_profile(app, PROFILES[(c - PROFILE) as usize]),
        _ => {}
    }
}
