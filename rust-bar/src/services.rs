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
pub struct Services {
    pub mango: Mango,
    pub stats: Stats,
    pub clock: String,
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

pub fn now_hm() -> String {
    let t = unsafe { libc::time(std::ptr::null_mut()) };
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&t, &mut tm) };
    format!("{:02}:{:02}", tm.tm_hour, tm.tm_min)
}

fn tick_clock(app: &mut App) -> bool {
    let t = now_hm();
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

    app.svc.clock = now_hm();
    app.every(Duration::from_millis(1000), tick_clock);
}
