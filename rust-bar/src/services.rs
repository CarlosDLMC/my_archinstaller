//! The data the strip shows - the singletons of the QML bar (Mango.qml,
//! SystemStats.qml, the clock and weather of CenterInfo.qml), with the same
//! sources and the same intervals.

use std::os::unix::net::UnixStream;
use std::time::Duration;

use serde_json::Value;

use crate::app::App;

#[derive(Clone, Debug, Default)]
pub struct Tag {
    pub index: i64,
    pub client_count: i64,
}

#[derive(Clone, Debug, Default)]
pub struct Monitor {
    pub name: String,
    pub active: bool,
    pub tags: Vec<Tag>,
    pub active_tags: Vec<i64>,
    pub client_id: Option<i64>,
    pub client_title: String,
}

#[derive(Default)]
pub struct Mango {
    pub monitors: Vec<Monitor>,
    pub keyboard_layout: String,
    pub game_mode: bool,
}

impl Mango {
    pub fn monitor(&self, name: &str) -> Option<&Monitor> {
        self.monitors.iter().find(|m| m.name == name)
    }

    pub fn focused(&self) -> Option<&Monitor> {
        self.monitors.iter().find(|m| m.active)
    }

    pub fn focused_title(&self) -> &str {
        self.focused().filter(|m| m.client_id.is_some()).map_or("", |m| m.client_title.as_str())
    }
}

#[derive(Default)]
pub struct Stats {
    pub cpu_usage: i64,
    pub cpu_temp: i64,
    pub mem_usage: String,
    pub shown: bool,
    last_idle: u64,
    last_total: u64,
    temp_path: Option<String>,
}

#[derive(Default)]
pub struct Battery {
    pub present: bool,
    paths: Vec<String>,
    mains: String,
    pub level: i64,
    pub charge_state: String,
    pub limit_end: i64,
    pub draw_watts: f64,
}

#[derive(Default)]
pub struct Weather {
    pub text: String,
    pub alt: String,
    pub alt_display: String,
    pub city: String,
    pub location: String,
    pub icon: String,
    pub feels_like: String,
    pub min_temp: String,
    pub max_temp: String,
    pub hourly_rain: Vec<i64>,
    retry_step: usize,
}

fn strip_html(s: &str) -> String {
    let mut out = String::new();
    let mut tag = false;
    for c in s.chars() {
        match c {
            '<' => tag = true,
            '>' if tag => tag = false,
            c if !tag => out.push(c),
            _ => {}
        }
    }
    out.trim().to_string()
}

/// The first `open([^<]+)close` in s.
fn between(s: &str, open: &str, close: &str) -> Option<String> {
    let mut rest = s;
    while let Some(i) = rest.find(open) {
        let after = &rest[i + open.len()..];
        let end = after.find('<').unwrap_or(after.len());
        if end > 0 && after[end..].starts_with(close) {
            return Some(after[..end].to_string());
        }
        rest = after;
    }
    None
}

/// CenterInfo.parseWeatherJson's reading of the tooltip.
fn parse_tooltip(w: &mut Weather, tip: &str) {
    if let Some(l) = between(tip, "<b>", "</b>") {
        w.location = strip_html(&l);
    }
    if let Some(i) = tip.find("Feels like ") {
        let rest = &tip[i + 11..];
        let end = rest.find(['<', '\n']).unwrap_or(rest.len());
        if end > 0 {
            w.feels_like = strip_html(&rest[..end]);
        }
    }
    if let Some(ic) = between(tip, "<big>", "</big>") {
        w.icon = strip_html(&ic);
    }
    for line in tip.split('\n') {
        // \s*([^\t]+)\t\t\s*([^\t\n]+), both halves with a degree sign
        let t = line.trim_start();
        if let Some(i) = t.find("\t\t") {
            let (a, b) = (&t[..i], t[i + 2..].trim_start());
            if !a.is_empty() && !a.contains('\t') && !b.is_empty() {
                let b = b.split('\t').next().unwrap_or("");
                if !b.is_empty() && a.contains('°') && b.contains('°') {
                    w.min_temp = strip_html(a);
                    w.max_temp = strip_html(b);
                }
            }
        }
    }
    let mut rain = Vec::new();
    let mut rest = tip;
    while let Some(i) = rest.find("Rain drop ") {
        rest = &rest[i + 10..];
        let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
        if !digits.is_empty() && rest[digits.len()..].starts_with('%') {
            if rain.len() < 5 {
                rain.push(digits.parse().unwrap_or(0));
            }
        }
    }
    if !rain.is_empty() {
        w.hourly_rain = rain;
    }
}

#[derive(Default)]
pub struct Wifi {
    pub has: bool,
    pub connected: bool,
    pub ssid: String,
    pub signal: i64,
    pub connecting: bool,
    pub pulse: crate::anim::Pulse,
}

#[derive(Default)]
pub struct Services {
    pub mango: Mango,
    pub stats: Stats,
    pub clock: String,
    pub timezone: String,
    pub dnd_enabled: bool,
    pub dnd_available: bool,
    pub weather: Weather,
    pub battery: Battery,
    pub wifi: Wifi,
    pub vpn: String,
    vpn_checked: bool,
    /// Default sink: volume/mute and its node (name, description, nick).
    pub audio: (crate::pw::Audio, Option<crate::pw::NodeInfo>),
    pub pw: Option<crate::pw::Pw>,
    pub agent_installed: bool,
    /// The command PowerWidget.endSession() runs 250 ms after its card closes.
    pub pending_end: String,
    pub pult: crate::pult::Pult,
    pub vpn_card: crate::vpn::Vpn,
    pub agent: crate::agent::Usage,
    pub agent_busy: bool,
    /// (time sync busy, weather sync busy), mirrored for drawing.
    pub vpn_busy: (bool, bool),
    /// btScanProc.running, mirrored for drawing.
    pub pult_scanning: bool,
}

pub fn home() -> String {
    std::env::var("HOME").unwrap_or_default()
}

pub fn palette_path() -> String {
    format!("{}/.config/quickshell/bar/wallust-colors.json", home())
}

fn parse_monitors(v: &Value) -> Option<Vec<Monitor>> {
    let arr = v.get("monitors")?.as_array()?;
    Some(
        arr.iter()
            .map(|m| {
                let client = m.get("active_client");
                Monitor {
                    name: m.get("name").and_then(Value::as_str).unwrap_or("").into(),
                    active: m.get("active").and_then(Value::as_bool).unwrap_or(false),
                    tags: m
                        .get("tags")
                        .and_then(Value::as_array)
                        .map(|t| {
                            t.iter()
                                .map(|t| Tag {
                                    index: t.get("index").and_then(Value::as_i64).unwrap_or(0),
                                    client_count: t.get("client_count").and_then(Value::as_i64).unwrap_or(0),
                                })
                                .collect()
                        })
                        .unwrap_or_default(),
                    active_tags: m
                        .get("active_tags")
                        .and_then(Value::as_array)
                        .map(|a| a.iter().filter_map(Value::as_i64).collect())
                        .unwrap_or_default(),
                    client_id: client.and_then(|c| c.get("id")).and_then(Value::as_i64),
                    client_title: client.and_then(|c| c.get("title")).and_then(Value::as_str).unwrap_or("").into(),
                }
            })
            .collect(),
    )
}

fn on_monitors(app: &mut App, line: &str) {
    let Ok(v) = serde_json::from_str::<Value>(line) else { return };
    let Some(mons) = parse_monitors(&v) else { return };
    let before = app.svc.mango.focused().and_then(|m| m.client_id);
    app.svc.mango.monitors = mons;
    let after = app.svc.mango.focused().and_then(|m| m.client_id);
    if before != after {
        crate::bar::close_all_popups(app);
    }
    app.mark_all_dirty();
}

fn on_layout(app: &mut App, line: &str) {
    let Ok(v) = serde_json::from_str::<Value>(line) else { return };
    if let Some(l) = v.get("layout").and_then(Value::as_str) {
        if l != app.svc.mango.keyboard_layout {
            app.svc.mango.keyboard_layout = l.into();
            app.mark_all_dirty();
        }
    }
}

fn connect_watch(app: &mut App, what: &str, on_line: fn(&mut App, &str)) {
    let Ok(path) = std::env::var("MANGO_INSTANCE_SIGNATURE") else { return };
    if let Ok(mut s) = UnixStream::connect(&path) {
        use std::io::Write;
        let _ = s.write_all(format!("watch {what}\n").as_bytes());
        app.watch_lines(s, on_line);
    }
}

pub fn mango_dispatch(app: &App, command: &str) {
    app.exec_detached(&["mmsg", "dispatch", command]);
}

// ---- SystemStats ----

fn read_cpu(s: &mut Stats) {
    let Ok(t) = std::fs::read_to_string("/proc/stat") else { return };
    let Some(line) = t.lines().next() else { return };
    if !line.starts_with("cpu") {
        return;
    }
    let p: Vec<u64> = line.split_whitespace().skip(1).take(7).map(|v| v.parse().unwrap_or(0)).collect();
    if p.len() < 7 {
        return;
    }
    let total: u64 = p.iter().sum();
    let idle = p[3] + p[4];
    if s.last_total > 0 {
        let td = total.saturating_sub(s.last_total);
        let idd = idle.saturating_sub(s.last_idle);
        if td > 0 {
            s.cpu_usage = (100.0 * (td - idd.min(td)) as f64 / td as f64).round() as i64;
        }
    }
    s.last_total = total;
    s.last_idle = idle;
}

fn read_mem(s: &mut Stats) {
    let Ok(t) = std::fs::read_to_string("/proc/meminfo") else { return };
    let (mut total, mut avail) = (0u64, 0u64);
    for l in t.lines() {
        let num = || l.chars().filter(|c| c.is_ascii_digit()).collect::<String>().parse::<u64>().unwrap_or(0);
        if l.starts_with("MemTotal:") {
            total = num();
        } else if l.starts_with("MemAvailable:") {
            avail = num();
        }
        if total > 0 && avail > 0 {
            break;
        }
    }
    if total > 0 {
        // JS toFixed(2)
        s.mem_usage = format!("{:.2}G", (total - avail) as f64 / 1024.0 / 1024.0);
    }
}

fn read_temp(s: &mut Stats) {
    let Some(p) = &s.temp_path else { return };
    if let Ok(t) = std::fs::read_to_string(p) {
        if let Ok(m) = t.trim().parse::<f64>() {
            s.cpu_temp = (m / 1000.0).round() as i64;
        }
    }
}

fn find_temp_path() -> Option<String> {
    for d in glob_dir("/sys/class/hwmon", "hwmon") {
        let name = std::fs::read_to_string(format!("{d}/name")).unwrap_or_default();
        if matches!(name.trim(), "k10temp" | "zenpower" | "coretemp") && std::path::Path::new(&format!("{d}/temp1_input")).exists() {
            return Some(format!("{d}/temp1_input"));
        }
    }
    for want in ["x86_pkg_temp", "acpitz"] {
        for z in glob_dir("/sys/class/thermal", "thermal_zone") {
            if std::fs::read_to_string(format!("{z}/type")).unwrap_or_default().trim() == want && std::path::Path::new(&format!("{z}/temp")).exists() {
                return Some(format!("{z}/temp"));
            }
        }
    }
    glob_dir("/sys/class/thermal", "thermal_zone").into_iter().map(|z| format!("{z}/temp")).find(|p| std::path::Path::new(p).exists())
}

fn glob_dir(dir: &str, prefix: &str) -> Vec<String> {
    let mut v: Vec<String> = std::fs::read_dir(dir)
        .map(|r| r.filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().into_owned()).filter(|n| n.starts_with(prefix)).map(|n| format!("{dir}/{n}")).collect())
        .unwrap_or_default();
    v.sort();
    v
}

fn stats_pref() -> bool {
    std::fs::read_to_string(format!("{}/.cache/quickshell/bar-stats", home())).map_or(true, |t| t.trim() != "off")
}

fn refresh_stats(app: &mut App) -> bool {
    if app.svc.stats.shown {
        let s = &mut app.svc.stats;
        let before = (s.cpu_usage, s.cpu_temp, s.mem_usage.clone());
        read_cpu(s);
        read_mem(s);
        read_temp(s);
        if before != (s.cpu_usage, s.cpu_temp, s.mem_usage.clone()) {
            app.mark_all_dirty();
        }
    }
    true
}

// ---- clock ----

/// HH:mm in the custom timezone (~/.cache/quickshell/timezone, set by the
/// VPN card's time sync) or local time.
pub fn now_hm(tz: &str) -> String {
    if !tz.is_empty() {
        std::env::set_var("TZ", tz);
    } else {
        std::env::remove_var("TZ");
    }
    unsafe { tzset() };
    let t = unsafe { libc::time(std::ptr::null_mut()) };
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&t, &mut tm) };
    format!("{:02}:{:02}", tm.tm_hour, tm.tm_min)
}

extern "C" {
    fn tzset();
}

fn cache_dir() -> String {
    format!("{}/.cache/quickshell", home())
}

fn read_cache_files(app: &mut App) {
    app.svc.timezone = std::fs::read_to_string(format!("{}/timezone", cache_dir())).map(|t| t.trim().to_string()).unwrap_or_default();
    app.svc.weather.city = std::fs::read_to_string(format!("{}/weather_city", cache_dir())).map(|t| t.trim().to_string()).unwrap_or_default();
}

/// ~/.cache/quickshell changed: the timezone and weather city follow the VPN
/// card's sync (CenterInfo's FileViews); a new city fetches the weather.
fn cache_changed(app: &mut App, name: &str) {
    match name {
        "timezone" => {
            read_cache_files(app);
            tick_clock(app);
            app.mark_all_dirty();
        }
        "weather_city" => {
            let before = app.svc.weather.city.clone();
            read_cache_files(app);
            if app.svc.weather.city != before {
                request_weather(app);
            }
            app.mark_all_dirty();
        }
        _ => {}
    }
}

/// Theme.qml's FileView on wallust-colors.json, debounced 80 ms (wallust
/// rewrites it in place).
fn palette_changed(app: &mut App, name: &str) {
    if name == "wallust-colors.json" {
        app.debounce("palette", Duration::from_millis(80), |app| {
            if let Ok(t) = std::fs::read_to_string(palette_path()) {
                if app.theme.apply_json(&t) {
                    if let Some(c) = app.card.as_mut() {
                        c.invalidate_notch();
                    }
                    app.mark_all_dirty();
                }
            }
        });
    }
}

fn tick_clock(app: &mut App) -> bool {
    let t = now_hm(&app.svc.timezone);
    if t != app.svc.clock {
        app.svc.clock = t;
        app.mark_all_dirty();
    }
    true
}

pub fn start(app: &mut App) {
    connect_watch(app, "all-monitors", on_monitors);
    connect_watch(app, "keyboardlayout", on_layout);
    let gm = format!("{}/mango-gamemode.conf", std::env::var("XDG_RUNTIME_DIR").unwrap_or("/tmp".into()));
    app.svc.mango.game_mode = std::path::Path::new(&gm).exists();

    app.svc.stats.shown = stats_pref();
    app.svc.stats.temp_path = find_temp_path();
    app.svc.stats.mem_usage = "0G".into();
    refresh_stats(app);
    app.every(Duration::from_millis(5000), refresh_stats);

    read_cache_files(app);
    let _ = std::fs::create_dir_all(cache_dir());
    app.watch_dir(&cache_dir(), cache_changed);
    app.watch_dir(&format!("{}/.config/quickshell/bar", home()), palette_changed);
    tick_clock(app);
    app.every(Duration::from_millis(1000), tick_clock);

    app.svc.dnd_available = true;
    dnd_poll(app);
    app.every(Duration::from_millis(5000), |app| {
        dnd_poll(app);
        true
    });

    if let Ok(t) = std::fs::read_to_string(format!("{}/weather.json", cache_dir())) {
        apply_weather(app, &t);
    }
    request_weather(app);
    app.every(Duration::from_secs(3600), |app| {
        request_weather(app);
        true
    });

    if let Some(pw) = crate::pw::Pw::new() {
        let fd = pw.fd();
        app.svc.pw = Some(pw);
        app.watch_fd(fd, |app| {
            let changed = app.svc.pw.as_ref().map_or(false, |p| p.dispatch());
            if changed {
                app.svc.audio = app.svc.pw.as_ref().unwrap().sink();
                app.mark_all_dirty();
            }
        });
    }

    crate::pult::start(app);

    battery_probe(app);
    app.every(Duration::from_secs(60), |app| {
        battery_refresh(app, true);
        true
    });

    app.svc.wifi.has = glob_dir("/sys/class/net", "").iter().any(|d| std::path::Path::new(&format!("{d}/wireless")).exists());
    if app.svc.wifi.has {
        wifi_status(app);
        app.spawn_lines(&["nmcli", "monitor"], |app, _| app.debounce("wifi", Duration::from_millis(400), wifi_status));
    }

    vpn_poll(app);
    app.every(Duration::from_millis(5000), |app| {
        vpn_poll(app);
        true
    });

    crate::agent::run(app, "check");
}

// ---- DND (dunstctl), as CenterInfo polls it ----

fn dnd_poll(app: &mut App) {
    app.spawn("dnd", &["dunstctl", "is-paused"], |app, d| {
        let v = d.stdout.trim().lines().last().unwrap_or("").to_string();
        let ok = d.ok && (v == "true" || v == "false");
        let (en, av) = (if ok { v == "true" } else { app.svc.dnd_enabled }, ok);
        if (en, av) != (app.svc.dnd_enabled, app.svc.dnd_available) {
            app.svc.dnd_enabled = en;
            app.svc.dnd_available = av;
            app.mark_all_dirty();
        }
    });
}

pub fn dnd_toggle(app: &mut App) {
    app.spawn("dnd-toggle", &["dunstctl", "set-paused", "toggle"], |app, d| {
        if !d.ok {
            app.svc.dnd_available = false;
        }
        dnd_poll(app);
    });
}

// ---- weather (weather-fetch.sh), with CenterInfo's retry ladder ----

fn apply_weather(app: &mut App, out: &str) -> bool {
    let Ok(v) = serde_json::from_str::<Value>(out.trim()) else { return false };
    let w = &mut app.svc.weather;
    w.text = v.get("text").and_then(Value::as_str).unwrap_or("").into();
    w.alt = v.get("alt").and_then(Value::as_str).unwrap_or("").into();
    w.alt_display = v.get("alt_display").and_then(Value::as_str).filter(|s| !s.is_empty()).unwrap_or(&w.alt).to_string();
    if let Some(tip) = v.get("tooltip").and_then(Value::as_str) {
        parse_tooltip(w, tip);
    }
    app.mark_all_dirty();
    v.get("stale").and_then(Value::as_bool) != Some(true)
}

pub fn request_weather(app: &mut App) {
    let cmd = format!("{}/.config/quickshell/bar/scripts/weather-fetch.sh 2>/dev/null", home());
    app.spawn("weather", &["sh", "-c", &cmd], |app, d| {
        let good = !d.stdout.trim().is_empty() && apply_weather(app, &d.stdout);
        if good {
            app.svc.weather.retry_step = 0;
            return;
        }
        let minutes = [1u64, 2, 5, 10][app.svc.weather.retry_step.min(3)];
        app.svc.weather.retry_step += 1;
        app.debounce("weather-retry", Duration::from_secs(minutes * 60), request_weather);
    });
}

// ---- battery (BatteryState.qml, read straight from sysfs) ----

fn read_kv(path: &str) -> Vec<(String, String)> {
    std::fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.split_once('=').map(|(k, v)| (k.to_string(), v.trim().to_string())))
        .collect()
}

fn battery_probe(app: &mut App) {
    let b = &mut app.svc.battery;
    b.paths.clear();
    b.mains.clear();
    for d in glob_dir("/sys/class/power_supply", "") {
        let ty = std::fs::read_to_string(format!("{d}/type")).unwrap_or_default();
        match ty.trim() {
            "Battery" => {
                let scope = std::fs::read_to_string(format!("{d}/scope")).unwrap_or("System".into());
                let present = std::fs::read_to_string(format!("{d}/present")).unwrap_or("1".into());
                if scope.trim() == "System" && present.trim() == "1" {
                    b.paths.push(d);
                }
            }
            "Mains" if b.mains.is_empty() => b.mains = d,
            _ => {}
        }
    }
    b.present = !b.paths.is_empty();
    battery_refresh(app, true);
}

pub fn battery_refresh(app: &mut App, with_limits: bool) {
    let b = &mut app.svc.battery;
    if !b.present {
        return;
    }
    let (mut e_now, mut e_full, mut watts) = (0f64, 0f64, 0f64);
    let (mut any_chg, mut any_dis, mut all_full) = (false, false, true);
    let mut end_limit = 0i64;
    for p in &b.paths {
        let kv = read_kv(&format!("{p}/uevent"));
        let num = |k: &str| kv.iter().find(|(kk, _)| kk == &format!("POWER_SUPPLY_{k}")).and_then(|(_, v)| v.parse::<f64>().ok()).unwrap_or(0.0);
        let volts = num("VOLTAGE_NOW");
        let (mut en, mut ef, mut pn) = (num("ENERGY_NOW"), num("ENERGY_FULL"), num("POWER_NOW"));
        if ef == 0.0 && volts > 0.0 {
            en = num("CHARGE_NOW") * volts / 1e6;
            ef = num("CHARGE_FULL") * volts / 1e6;
            pn = num("CURRENT_NOW") * volts / 1e6;
        }
        e_now += en;
        e_full += ef;
        watts += pn.abs();
        let status = kv.iter().find(|(k, _)| k == "POWER_SUPPLY_STATUS").map(|(_, v)| v.as_str()).unwrap_or("Unknown");
        any_chg |= status == "Charging";
        any_dis |= status == "Discharging";
        all_full &= status == "Full";
        if with_limits && end_limit == 0 {
            end_limit = std::fs::read_to_string(format!("{p}/charge_control_end_threshold")).ok().and_then(|t| t.trim().parse().ok()).unwrap_or(0);
        }
    }
    if with_limits {
        b.limit_end = end_limit;
    }
    let on_ac = b.mains.is_empty() || std::fs::read_to_string(format!("{}/uevent", b.mains)).unwrap_or_default().contains("POWER_SUPPLY_ONLINE=1");
    b.draw_watts = watts / 1e6;
    let before = (b.level, b.charge_state.clone());
    b.level = if e_full > 0.0 { ((100.0 * e_now / e_full).round() as i64).clamp(0, 100) } else { 0 };
    b.charge_state = if any_dis || !on_ac {
        "discharging"
    } else if any_chg && b.draw_watts > 0.2 {
        "charging"
    } else if b.limit_end > 0 && b.limit_end < 99 && b.level >= b.limit_end - 2 {
        "holding"
    } else if all_full || b.level >= 97 {
        "full"
    } else {
        "idle"
    }
    .into();
    if before != (b.level, b.charge_state.clone()) {
        app.mark_all_dirty();
    }
}

// ---- Wi-Fi (nmcli, as WifiWidget asks it) ----

/// nmcli -t splits on ':' with '\\' escapes.
pub fn split_terse(line: &str) -> Vec<String> {
    let mut out = vec![String::new()];
    let mut it = line.chars();
    while let Some(c) = it.next() {
        match c {
            '\\' => {
                if let Some(n) = it.next() {
                    out.last_mut().unwrap().push(n);
                }
            }
            ':' => out.push(String::new()),
            c => out.last_mut().unwrap().push(c),
        }
    }
    out
}

fn wifi_status(app: &mut App) {
    app.spawn("wifi-current", &["sh", "-c", "nmcli -t -f IN-USE,SSID,SIGNAL device wifi list --rescan no | grep '^\\*' | head -1"], |app, d| {
        let w = &mut app.svc.wifi;
        let before = (w.connected, w.ssid.clone());
        let out = d.stdout.trim();
        if out.is_empty() {
            w.connected = false;
            w.ssid.clear();
            w.signal = 0;
        } else {
            let parts = split_terse(out);
            if parts.len() >= 3 {
                w.connected = true;
                w.ssid = parts[1].clone();
                w.signal = parts[2].parse().unwrap_or(0);
            }
        }
        if before != (w.connected, w.ssid.clone()) {
            app.mark_all_dirty();
        }
    });
}

// ---- VPN: the first WireGuard interface (what `wg show interfaces` lists) ----

/// VpnWidget's side effects: a VPN that went down, or none at start with a
/// city still cached from one, resets the time/weather sync (vpn-reset.sh).
fn vpn_reset(app: &mut App) {
    let cmd = format!("{}/.config/quickshell/bar/scripts/vpn-reset.sh all --forget", home());
    app.spawn("vpn-reset", &["sh", "-c", &cmd], |app, _| {
        tick_clock(app);
        request_weather(app);
    });
}

pub fn vpn_check(app: &mut App) {
    vpn_poll(app);
}

fn vpn_poll(app: &mut App) -> bool {
    let first = !app.svc.vpn_checked;
    app.svc.vpn_checked = true;
    // Interfaces of this network namespace (/proc/net/dev), the ones whose
    // sysfs entry says WireGuard - what `wg show interfaces` lists, unprivileged.
    let mut active = String::new();
    let devs = std::fs::read_to_string("/proc/net/dev").unwrap_or_default();
    for name in devs.lines().skip(2).filter_map(|l| l.split(':').next()).map(str::trim) {
        if std::fs::read_to_string(format!("/sys/class/net/{name}/uevent")).unwrap_or_default().contains("DEVTYPE=wireguard") {
            active = name.to_string();
            break;
        }
    }
    let was_active = !app.svc.vpn.is_empty();
    if active.is_empty() {
        if was_active {
            vpn_reset(app);
        } else if first && std::fs::read_to_string(format!("{}/weather_city", cache_dir())).map_or(false, |c| !c.trim().is_empty()) {
            vpn_reset(app);
        }
    }
    if active != app.svc.vpn {
        app.svc.vpn = active;
        app.mark_all_dirty();
    }
    true
}
