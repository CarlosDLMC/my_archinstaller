//! The data the strip shows - the singletons of the QML bar (Mango.qml,
//! SystemStats.qml, the clock and weather of CenterInfo.qml), with the same
//! sources and the same intervals.

use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

use dbus::arg::{PropMap, Variant};
use dbus::channel::{BusType, Channel};
use dbus::message::{Message, MessageType};
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
    /// Layout position and size, and the output scale.
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub scale: f32,
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

/// dunst's pause state over the session bus (dnd_connect).
#[derive(Default)]
struct DndBus {
    chan: Option<Channel>,
    watch: Option<smithay_client_toolkit::reexports::calloop::RegistrationToken>,
    /// The Properties.Get in flight: its serial and when it went out.
    get: Option<(u32, Instant)>,
    /// Asked again while one was out: one more read when it answers.
    again: bool,
}

#[derive(Default)]
pub struct Services {
    pub mango: Mango,
    pub stats: Stats,
    pub clock: String,
    /// The minute the clock last showed (lastClockMinute), and the wall
    /// clock at the last tick in ms (lastTickMs).
    clock_minute: Option<i32>,
    last_tick_ms: u64,
    pub timezone: String,
    pub dnd_enabled: bool,
    pub dnd_available: bool,
    dnd_bus: DndBus,
    pub weather: Weather,
    pub battery: crate::battery::Battery,
    pub net: crate::network_card::NetPanel,
    pub layout: crate::layout::LayoutState,
    pub power: crate::power::PowerState,
    pub capture: crate::capture::Capture,
    pub polkit: crate::polkit::Polkit,
    pub clip: crate::clip::Clip,
    pub wall: crate::wallpaper::Wall,
    pub overview: crate::overview::Overview,
    /// The output names, by the overview windows' screen index.
    pub overview_screens: Vec<String>,
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
    pub wifi_card: crate::wifi_card::WifiCard,
    pub wifi_connecting: bool,
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
                    x: m.get("x").and_then(Value::as_f64).unwrap_or(0.0) as f32,
                    y: m.get("y").and_then(Value::as_f64).unwrap_or(0.0) as f32,
                    width: m.get("width").and_then(Value::as_f64).unwrap_or(1920.0) as f32,
                    height: m.get("height").and_then(Value::as_f64).unwrap_or(1080.0) as f32,
                    scale: m.get("scale").and_then(Value::as_f64).unwrap_or(1.0) as f32,
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
            crate::layout::layout_changed(app);
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

/// Mango.dispatch(command, clientId): the client as its own argument.
pub fn mango_dispatch_client(app: &App, command: &str, client: i64) {
    let c = format!("client,{client}");
    app.exec_detached(&["mmsg", "dispatch", command, &c]);
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

pub(crate) fn glob_dir(dir: &str, prefix: &str) -> Vec<String> {
    let mut v: Vec<String> = std::fs::read_dir(dir)
        .map(|r| r.filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().into_owned()).filter(|n| n.starts_with(prefix)).map(|n| format!("{dir}/{n}")).collect())
        .unwrap_or_default();
    v.sort();
    v
}

/// Number.prototype.toFixed(digits): the nearest multiple of 10^-digits to
/// the exact value, an exact tie going up (Rust's formatter picks the even one).
pub fn to_fixed(v: f64, digits: i32) -> String {
    let scale = 10f64.powi(digits);
    let s = v * scale;
    let d = digits.max(0) as usize;
    if v.mul_add(scale, -s) == 0.0 && (s - s.floor()) == 0.5 {
        return format!("{:.*}", d, (s + 0.5).floor() / scale);
    }
    format!("{v:.d$}")
}

/// A JS number as String() prints it (shortest round trip; whole numbers bare).
pub fn js_num(v: f64) -> String {
    if v.fract() == 0.0 && v.abs() < 1e21 { format!("{}", v as i64) } else { format!("{v}") }
}

/// `[ -x path ]`.
pub(crate) fn is_executable(path: &str) -> bool {
    std::ffi::CString::new(path).map_or(false, |c| unsafe { libc::access(c.as_ptr(), libc::X_OK) } == 0)
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

/// The local wall clock now: the minute of the hour and HH:mm. tzset() each
/// time, as Qt does for local time, so a new /etc/localtime shows.
fn local_now() -> (i32, String) {
    unsafe { tzset() };
    let t = unsafe { libc::time(std::ptr::null_mut()) };
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&t, &mut tm) };
    (tm.tm_min, format!("{:02}:{:02}", tm.tm_hour, tm.tm_min))
}

/// updateClock(force): only a new minute does anything. With a timezone from
/// the VPN card's sync (~/.cache/quickshell/timezone), `date` gives the time
/// there, as QML's timeProc does - TZ goes into that process's environment,
/// never the bar's, which everything the bar runs would inherit.
fn update_clock(app: &mut App, force: bool) {
    let (minute, hm) = local_now();
    if !force && Some(minute) == app.svc.clock_minute {
        return;
    }
    app.svc.clock_minute = Some(minute);
    if app.svc.timezone.is_empty() {
        set_clock(app, hm);
        return;
    }
    let tz = format!("TZ={}", app.svc.timezone);
    app.spawn("clock-tz", &["env", &tz, "date", "+%H:%M"], |app, d| {
        let t = d.stdout.trim().to_string();
        if !t.is_empty() {
            set_clock(app, t);
        }
    });
}

fn set_clock(app: &mut App, t: String) {
    if t != app.svc.clock {
        app.svc.clock = t;
        app.mark_all_dirty();
    }
}

/// refreshTimezone(): the timezone file again; a new zone redraws the clock.
fn refresh_timezone(app: &mut App) {
    let before = app.svc.timezone.clone();
    read_cache_files(app);
    if app.svc.timezone != before {
        update_clock(app, true);
    }
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
        "timezone" => refresh_timezone(app),
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
        crate::wallpaper::palette_changed(app);
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

/// CenterInfo's one-second tick. It also notices a resume: the timers run on
/// the monotonic clock, which stops in suspend, so a wall-clock jump of over
/// two minutes between ticks fetches the weather once the network has had ten
/// seconds to come back (the hourly fetch could still be an hour away).
fn tick_clock(app: &mut App) -> bool {
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64);
    if app.svc.last_tick_ms > 0 && now.saturating_sub(app.svc.last_tick_ms) > 120_000 {
        app.debounce("weather-after-resume", Duration::from_secs(10), request_weather);
    }
    app.svc.last_tick_ms = now;
    update_clock(app, false);
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
    update_clock(app, true);
    app.every(Duration::from_millis(1000), tick_clock);

    app.svc.dnd_available = true;
    dnd_connect(app);
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

    crate::battery::start(app);
    crate::layout::start(app);
    crate::power::start(app);
    crate::capture::start(app);
    crate::polkit::start(app);
    crate::clip::start(app);
    crate::wallpaper::start(app);

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

// ---- DND (dunst's pause state), as CenterInfo polls it ----

const DUNST: &str = "org.freedesktop.Notifications";
const DUNST_PATH: &str = "/org/freedesktop/Notifications";
const DUNST_IFACE: &str = "org.dunstproject.cmd0";

/// `dunstctl is-paused` is a shell script around one D-Bus call, the
/// Properties.Get of dunst's `paused`: two processes every five seconds. The
/// bar makes that call itself, on its own session-bus connection and the same
/// timer, and reads it again at once when dunst announces a change
/// (PropertiesChanged) or comes back (NameOwnerChanged). Without a session
/// bus it runs dunstctl, as before.
fn dnd_connect(app: &mut App) {
    let Ok(mut ch) = Channel::get_private(BusType::Session) else { return };
    let rules = [
        format!("type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='{DUNST_PATH}',arg0='{DUNST_IFACE}'"),
        format!("type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='{DUNST}'"),
    ];
    for rule in rules {
        let Ok(m) = Message::new_method_call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch") else { return };
        if ch.send(m.append1(rule)).is_err() {
            return;
        }
    }
    ch.flush();
    ch.set_watch_enabled(true);
    let fd = ch.watch().fd;
    app.svc.dnd_bus.chan = Some(ch);
    app.svc.dnd_bus.watch = app.watch_fd(fd, dnd_bus_ready);
}

fn dnd_poll(app: &mut App) {
    let bus = &mut app.svc.dnd_bus;
    if let Some(ch) = bus.chan.as_ref() {
        // One read at a time, as a running Process ignores `running = true`;
        // dbus-send gives up on dunst after 25 s.
        if let Some((_, at)) = bus.get {
            if at.elapsed() < Duration::from_secs(25) {
                bus.again = true;
                return;
            }
            bus.get = None;
            dnd_apply(app, None);
            return dnd_poll(app);
        }
        let Ok(m) = Message::new_method_call(DUNST, DUNST_PATH, "org.freedesktop.DBus.Properties", "Get") else { return };
        if let Ok(serial) = ch.send(m.append2(DUNST_IFACE, "paused")) {
            ch.flush();
            bus.get = Some((serial, Instant::now()));
        }
        return;
    }
    app.spawn("dnd", &["dunstctl", "is-paused"], |app, d| {
        let v = d.stdout.trim().lines().last().unwrap_or("").to_string();
        let ok = d.ok && (v == "true" || v == "false");
        dnd_apply(app, ok.then_some(v == "true"));
    });
}

/// A read of dunst's pause state: Some(paused), or None when dunst did not answer.
fn dnd_apply(app: &mut App, paused: Option<bool>) {
    let (en, av) = (paused.unwrap_or(app.svc.dnd_enabled), paused.is_some());
    if (en, av) != (app.svc.dnd_enabled, app.svc.dnd_available) {
        app.svc.dnd_enabled = en;
        app.svc.dnd_available = av;
        app.mark_all_dirty();
    }
}

/// The session bus has data: the answer to a read, or one of dunst's signals.
fn dnd_bus_ready(app: &mut App) {
    let mut msgs = Vec::new();
    let mut lost = false;
    if let Some(ch) = app.svc.dnd_bus.chan.as_mut() {
        lost = ch.read_write(Some(Duration::ZERO)).is_err();
        while let Some(m) = ch.pop_message() {
            msgs.push(m);
        }
    }
    for m in msgs {
        match m.msg_type() {
            MessageType::MethodReturn | MessageType::Error => {
                let Some((serial, _)) = app.svc.dnd_bus.get else { continue };
                if m.get_reply_serial() != Some(serial) {
                    continue;
                }
                app.svc.dnd_bus.get = None;
                let paused = if m.msg_type() == MessageType::MethodReturn { m.read1::<Variant<bool>>().ok().map(|v| v.0) } else { None };
                dnd_apply(app, paused);
                if std::mem::take(&mut app.svc.dnd_bus.again) {
                    dnd_poll(app);
                }
            }
            MessageType::Signal => match m.member().as_deref() {
                Some("PropertiesChanged") => {
                    let Ok((iface, changed, invalidated)) = m.read3::<String, PropMap, Vec<String>>() else { continue };
                    if iface != DUNST_IFACE {
                        continue;
                    }
                    if let Some(v) = changed.get("paused").and_then(|v| v.0.as_u64()) {
                        dnd_apply(app, Some(v != 0));
                    } else if changed.contains_key("pauseLevel") || invalidated.iter().any(|p| p == "paused" || p == "pauseLevel") {
                        dnd_poll(app);
                    }
                }
                // dunst (re)started: its state is fresh. When it goes away
                // the next poll finds out, as dunstctl's would.
                Some("NameOwnerChanged") => {
                    let Ok((name, _, owner)) = m.read3::<String, String, String>() else { continue };
                    if name == DUNST && !owner.is_empty() {
                        dnd_poll(app);
                    }
                }
                _ => {}
            },
            _ => {}
        }
    }
    if lost {
        // The session bus went away: dunstctl from now on.
        if let Some(t) = app.svc.dnd_bus.watch.take() {
            app.unwatch(t);
        }
        app.svc.dnd_bus = DndBus::default();
    }
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

pub fn wifi_refresh(app: &mut App) {
    wifi_status(app);
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
        refresh_timezone(app);
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
