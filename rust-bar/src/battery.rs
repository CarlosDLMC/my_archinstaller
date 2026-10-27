//! BatteryState.qml + BatteryPanel.qml: the system batteries read straight
//! from sysfs (energy-weighted level, state, prediction, charge limit), kept
//! fresh by the kernel's power_supply uevents, and the battery card.

use crate::app::App;
use crate::bar::ac;
use crate::cards::{lamp, lamp_tinted, plate, Ui};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::services::{glob_dir, js_num, to_fixed, Services};
use crate::text::{Fonts, Line};
use crate::theme::{self, FONT_SIZE};

const HELPER: &str = "/usr/local/bin/battery-charge-limit";

#[derive(Default, Clone)]
pub struct Pack {
    pub name: String,
    pub status: String,
    pub model: String,
    pub capacity: i64,
    pub energy_now: f64,
    pub energy_full: f64,
    pub energy_design: f64,
    pub power_now: f64,
    pub cycles: f64,
    pub health: i64,
    pub limit_end: i64,
    pub limit_start: i64,
}

#[derive(Default)]
pub struct Battery {
    pub present: bool,
    paths: Vec<String>,
    mains: String,
    helper: bool,
    pub packs: Vec<Pack>,
    pub level: i64,
    pub on_ac: bool,
    pub draw_watts: f64,
    pub energy_now: f64,
    pub energy_full: f64,
    pub energy_design: f64,
    pub cycles: f64,
    pub seconds_left: f64,
    pub charge_state: String,
    pub limit_end: i64,
    pub limit_start: i64,
    pub limit_supported: bool,
    pub pending_limit: i64,
    uevents: Option<std::os::fd::OwnedFd>,
}

impl Battery {
    pub fn limit_writable(&self) -> bool {
        self.limit_supported && self.helper
    }
    pub fn effective_limit(&self) -> i64 {
        if self.pending_limit > 0 { self.pending_limit } else { self.limit_end }
    }
    pub fn health(&self) -> i64 {
        if self.energy_design > 0.0 { js_round(100.0 * self.energy_full / self.energy_design) as i64 } else { 0 }
    }
    pub fn charging(&self) -> bool {
        self.charge_state == "charging"
    }
    pub fn low(&self) -> bool {
        self.charge_state == "discharging" && self.level <= 15
    }
}

/// Math.round: halves go up.
fn js_round(v: f64) -> f64 {
    (v + 0.5).floor()
}

fn read_kv(path: &str) -> Vec<(String, String)> {
    std::fs::read_to_string(path)
        .unwrap_or_default()
        .lines()
        .filter_map(|l| l.split_once('=').map(|(k, v)| (k.to_string(), v.trim().to_string())))
        .collect()
}

fn read_int(path: &str) -> i64 {
    std::fs::read_to_string(path).ok().and_then(|t| t.trim().parse().ok()).unwrap_or(0)
}

/// Probe + the minute timer + the uevent socket (`udevadm monitor` in QML).
pub fn start(app: &mut App) {
    probe(app);
    if app.svc.battery.present {
        listen(app);
    }
    app.every(std::time::Duration::from_secs(60), |app| {
        refresh(app, true);
        true
    });
}

/// probeProc: the system batteries, the mains supply, the limit helper.
fn probe(app: &mut App) {
    let b = &mut app.svc.battery;
    b.paths.clear();
    b.mains.clear();
    for d in glob_dir("/sys/class/power_supply", "") {
        let Ok(ty) = std::fs::read_to_string(format!("{d}/type")) else { continue };
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
    b.helper = crate::services::is_executable(HELPER);
    b.present = !b.paths.is_empty();
    refresh(app, true);
    app.mark_all_dirty();
}

/// The kernel's power_supply uevents: add/remove probes again, anything
/// else (a change) re-reads the packs.
fn listen(app: &mut App) {
    use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
    let fd = unsafe { libc::socket(libc::AF_NETLINK, libc::SOCK_DGRAM | libc::SOCK_CLOEXEC | libc::SOCK_NONBLOCK, libc::NETLINK_KOBJECT_UEVENT) };
    if fd < 0 {
        return;
    }
    let fd = unsafe { OwnedFd::from_raw_fd(fd) };
    let mut addr: libc::sockaddr_nl = unsafe { std::mem::zeroed() };
    addr.nl_family = libc::AF_NETLINK as u16;
    addr.nl_groups = 1;
    let ok = unsafe { libc::bind(fd.as_raw_fd(), &addr as *const _ as *const libc::sockaddr, std::mem::size_of::<libc::sockaddr_nl>() as u32) };
    if ok < 0 {
        return;
    }
    let raw = fd.as_raw_fd();
    app.svc.battery.uevents = Some(fd);
    app.watch_fd(raw, |app| {
        let Some(fd) = app.svc.battery.uevents.as_ref().map(|f| std::os::fd::AsRawFd::as_raw_fd(f)) else { return };
        let mut buf = [0u8; 4096];
        let (mut change, mut replug) = (false, false);
        loop {
            let n = unsafe { libc::recv(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) };
            if n <= 0 {
                break;
            }
            let msg = &buf[..n as usize];
            if !msg.split(|b| *b == 0).any(|f| f == b"SUBSYSTEM=power_supply") {
                continue;
            }
            if msg.split(|b| *b == 0).any(|f| f == b"ACTION=add" || f == b"ACTION=remove") {
                replug = true;
            } else {
                change = true;
            }
        }
        if replug {
            probe(app);
        } else if change {
            refresh(app, false);
        }
    });
}

/// Probe.read(): one pack's uevent, charge-based packs converted to energy.
fn read_pack(dir: &str, with_limits: bool) -> Option<Pack> {
    let kv = read_kv(&format!("{dir}/uevent"));
    if kv.is_empty() {
        return None;
    }
    let get = |k: &str| kv.iter().find(|(kk, _)| kk.strip_prefix("POWER_SUPPLY_") == Some(k)).map(|(_, v)| v.as_str());
    let num = |k: &str| get(k).and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0);
    let volts = num("VOLTAGE_NOW");
    let (mut e_now, mut e_full, mut e_design, mut p_now) = (num("ENERGY_NOW"), num("ENERGY_FULL"), num("ENERGY_FULL_DESIGN"), num("POWER_NOW"));
    if e_full == 0.0 && volts > 0.0 {
        e_now = num("CHARGE_NOW") * volts / 1e6;
        e_full = num("CHARGE_FULL") * volts / 1e6;
        e_design = num("CHARGE_FULL_DESIGN") * volts / 1e6;
        p_now = num("CURRENT_NOW") * volts / 1e6;
    }
    let mut capacity = num("CAPACITY");
    if capacity == 0.0 && e_full > 0.0 {
        capacity = js_round(100.0 * e_now / e_full);
    }
    let mut pack = Pack {
        name: get("NAME").filter(|s| !s.is_empty()).unwrap_or("BAT").into(),
        status: get("STATUS").filter(|s| !s.is_empty()).unwrap_or("Unknown").into(),
        model: get("MODEL_NAME").unwrap_or("").into(),
        capacity: capacity as i64,
        energy_now: e_now,
        energy_full: e_full,
        energy_design: e_design,
        power_now: p_now.abs(),
        cycles: num("CYCLE_COUNT"),
        health: if e_design > 0.0 { js_round(100.0 * e_full / e_design) as i64 } else { 0 },
        ..Default::default()
    };
    if with_limits {
        pack.limit_end = read_int(&format!("{dir}/charge_control_end_threshold"));
        pack.limit_start = read_int(&format!("{dir}/charge_control_start_threshold"));
    }
    Some(pack)
}

/// refresh() + aggregate() + classify() + predict().
pub fn refresh(app: &mut App, with_limits: bool) {
    let b = &mut app.svc.battery;
    if !b.present {
        return;
    }
    let packs: Vec<Pack> = b.paths.iter().filter_map(|p| read_pack(p, with_limits)).collect();
    if packs.is_empty() {
        return;
    }
    b.packs = packs;
    b.on_ac = b.mains.is_empty() || std::fs::read_to_string(format!("{}/uevent", b.mains)).unwrap_or_default().contains("POWER_SUPPLY_ONLINE=1");

    let (mut e_now, mut e_full, mut e_design, mut watts, mut cyc) = (0f64, 0f64, 0f64, 0f64, 0f64);
    let (mut any_chg, mut any_dis, mut all_full) = (false, false, true);
    let (mut end_limit, mut start_limit, mut have_limit) = (0, 0, false);
    for p in &b.packs {
        e_now += p.energy_now;
        e_full += p.energy_full;
        e_design += p.energy_design;
        watts += p.power_now;
        cyc = cyc.max(p.cycles);
        any_chg |= p.status == "Charging";
        any_dis |= p.status == "Discharging";
        all_full &= p.status == "Full";
        if with_limits && p.limit_end > 0 {
            have_limit = true;
            if end_limit == 0 {
                end_limit = p.limit_end;
                start_limit = p.limit_start;
            }
        }
    }
    let before = (b.level, b.charge_state.clone());
    b.energy_now = e_now;
    b.energy_full = e_full;
    b.energy_design = e_design;
    b.draw_watts = watts / 1e6;
    b.cycles = cyc;
    if with_limits {
        b.limit_supported = have_limit;
        b.limit_end = end_limit;
        b.limit_start = start_limit;
    }
    b.level = if e_full > 0.0 { (js_round(100.0 * e_now / e_full) as i64).clamp(0, 100) } else { 0 };
    b.charge_state = if any_dis || !b.on_ac {
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
    b.seconds_left = if b.draw_watts <= 0.2 {
        -1.0
    } else if any_dis {
        (b.energy_now / 1e6) / b.draw_watts * 3600.0
    } else if b.charge_state == "charging" {
        let target = if b.limit_end > 0 && b.limit_end < 100 { b.energy_full * b.limit_end as f64 / 100.0 } else { b.energy_full };
        let missing = (target - b.energy_now) / 1e6;
        if missing <= 0.0 { -1.0 } else { missing / b.draw_watts * 3600.0 }
    } else {
        -1.0
    };
    // The strip shows the level and state; the open card shows the rest.
    let card_open = app.card.as_ref().map(|c| c.kind) == Some(crate::cards::CardKind::Battery);
    if card_open || before != (app.svc.battery.level, app.svc.battery.charge_state.clone()) {
        app.mark_all_dirty();
    }
}

/// setLimit(): through the root helper, then re-read the thresholds.
fn set_limit(app: &mut App, percent: i64) {
    if !app.svc.battery.limit_writable() || app.is_running("battery-limit") {
        return;
    }
    app.svc.battery.pending_limit = percent;
    let p = percent.to_string();
    app.spawn("battery-limit", &["sudo", "-n", HELPER, "set", &p], |app, _| {
        refresh(app, true);
        app.svc.battery.pending_limit = 0;
        app.mark_all_dirty();
    });
    app.mark_all_dirty();
}

// ---- the card ----

const LABEL: f32 = FONT_SIZE - 3.0;
const PRESETS: [(i64, &str, &str); 3] = [(60, "60%", "Всегда от сети"), (80, "80%", "Смешанный режим"), (100, "100%", "Без ограничения")];
pub const LIMIT: u32 = 0x10;

fn fmt_duration(seconds: f64) -> String {
    if seconds < 0.0 || !seconds.is_finite() {
        return "—".into();
    }
    let mut h = (seconds / 3600.0).floor() as i64;
    let mut m = js_round((seconds % 3600.0) / 60.0) as i64;
    if m == 60 {
        h += 1;
        m = 0;
    }
    if h > 0 {
        if m > 0 { format!("{h} ч {m} мин") } else { format!("{h} ч") }
    } else {
        format!("{m} мин")
    }
}

fn fmt_wh(micro_wh: f64) -> String {
    if !(micro_wh > 0.0) {
        return "—".into();
    }
    format!("{} Вт·ч", to_fixed(micro_wh / 1e6, 1))
}

fn state_label(b: &Battery) -> String {
    match b.charge_state.as_str() {
        "charging" => "Зарядка".into(),
        "discharging" => "От батареи".into(),
        "full" => "Заряжена".into(),
        "idle" => "От сети".into(),
        "holding" if b.level > b.limit_end + 2 => format!("Выше предела · {}%", b.limit_end),
        "holding" => format!("Удержание {}%", b.limit_end),
        _ => "—".into(),
    }
}

fn health_color(health: i64, t: &theme::Theme) -> Color {
    if health <= 0 {
        t.col_dim
    } else if health < 60 {
        t.col_alert
    } else if health < 80 {
        t.col_grey
    } else {
        t.col_white
    }
}

fn limit_note(b: &Battery) -> String {
    let lim = b.effective_limit();
    let mut note = PRESETS.iter().filter(|p| p.0 == lim).map(|p| p.2.to_string()).last().unwrap_or_default();
    if note.is_empty() && lim > 0 {
        note = format!("Зарядка до {lim}%");
    }
    if lim > 0 && lim < 100 && b.level > lim + 2 {
        note += "  ·  отключите питание, чтобы разрядить до него";
    }
    note
}

fn warn_text(b: &Battery) -> String {
    format!("Предел {}%. Чтобы менять его здесь, запустите install-scripts/battery_charge_limit.sh.", b.limit_end)
}

fn time_visible(b: &Battery) -> bool {
    b.seconds_left >= 0.0 || b.draw_watts > 0.2
}

/// The blocks of the body Column (spacing 8) and their heights.
enum Block {
    Level,
    Info,
    Packs,
    Limit,
    Note(Vec<Line>),
    Warn(Vec<Line>),
}

fn level_plate_h(fonts: &mut Fonts, b: &Battery) -> f32 {
    let readout = fonts.layout("0%", theme::bar_font(true), FONT_SIZE + 6.0, 0.0).height();
    let mut h = readout + 6.0 + 12.0;
    if time_visible(b) {
        h += 6.0 + fonts.layout("0", theme::bar_font(false), LABEL - 2.0, 0.0).height();
    }
    h + 20.0
}

const PACK_ROW: f32 = 32.0; // Math.round(labelSize * 1.5)

fn blocks(fonts: &mut Fonts, b: &Battery, w: f32) -> Vec<(Block, f32)> {
    let mut out = vec![(Block::Level, level_plate_h(fonts, b))];
    out.push((Block::Info, crate::cards::info_grid_height(fonts, 2) + 20.0));
    if b.packs.len() > 1 {
        let n = b.packs.len() as f32;
        out.push((Block::Packs, n * PACK_ROW + (n - 1.0) * 6.0 + 20.0));
    }
    if b.limit_writable() {
        out.push((Block::Limit, ((FONT_SIZE - 4.0) * 2.1).round()));
        let lines = fonts.wrap(&limit_note(b), theme::bar_font(false), LABEL - 2.0, 0.0, w);
        let h = lines.iter().map(|l| l.height()).sum();
        out.push((Block::Note(lines), h));
    }
    if b.limit_supported && !b.limit_writable() {
        let lines = fonts.wrap(&warn_text(b), theme::bar_font(false), LABEL - 2.0, 0.0, w);
        let h = lines.iter().map(|l| l.height()).sum();
        out.push((Block::Warn(lines), h));
    }
    out
}

/// body.implicitHeight, for the card's height binding.
pub fn content_height(fonts: &mut Fonts, svc: &Services, w: f32) -> f32 {
    let bl = blocks(fonts, &svc.battery, w - 16.0);
    bl.iter().map(|b| b.1).sum::<f32>() + 8.0 * (bl.len() as f32 - 1.0)
}

/// popupHeight: max(200, min(ceil(content) + 30, 620)).
pub fn card_height(fonts: &mut Fonts, svc: &Services, w: f32) -> f32 {
    200f32.max((content_height(fonts, svc, w).ceil() + 30.0).min(620.0))
}

pub fn opened(app: &mut App) {
    refresh(app, true);
}

pub fn activate(app: &mut App, code: u32) {
    if let Some(p) = code.checked_sub(LIMIT).and_then(|i| PRESETS.get(i as usize)) {
        set_limit(app, p.0);
    }
}

pub fn draw(ui: &mut Ui, w: f32, svc: &Services, top: f32) {
    let b = &svc.battery;
    let t = ui.theme;
    let (x0, cw) = (8.0, w - 16.0);
    let (ix, iw) = (x0 + 10.0, cw - 20.0);
    let mut y = top;
    for (block, h) in blocks(ui.fonts, b, cw) {
        match block {
            Block::Level => {
                plate(ui, x0, y, cw, h);
                let mut cy = y + 10.0;
                // ЗАРЯД, the level, and the mains lamp with the state on the right.
                let readout = ui.fonts.layout(&format!("{}%", b.level), theme::bar_font(true), FONT_SIZE + 6.0, 0.0);
                let rh = readout.height();
                let cap = crate::cards::caption(ui.fonts, "ЗАРЯД");
                ui.text(&cap, ix, cy + ac(rh, cap.height()), t.col_dim, TextStyle::Normal);
                let level_col = if b.low() { t.col_alert } else { t.col_white };
                ui.text(&readout, ix + cap.width + 10.0, cy + ac(rh, readout.height()), level_col, TextStyle::Normal);
                let state = ui.fonts.layout(&state_label(b).to_uppercase(), theme::bar_font(true), LABEL - 1.0, 0.0);
                let row_h = state.height().max(10.0);
                let row_x = ix + iw - (10.0 + 8.0 + state.width);
                let row_y = cy + ac(rh, row_h);
                lamp(ui, 0x7000, row_x, row_y + ac(row_h, 10.0), b.on_ac);
                ui.text(&state, row_x + 18.0, row_y + ac(row_h, state.height()), t.col_grey, TextStyle::Normal);
                cy += rh + 6.0;
                crate::cards::gauge(ui, ix, cy, iw, b.level as f32, b.effective_limit() as f32, if b.low() { t.col_alert } else { t.col_accent });
                cy += 12.0;
                if time_visible(b) {
                    cy += 6.0;
                    let key = theme::bar_font(false);
                    let left = format!("{}{}", if b.charging() { "ДО ПОЛНОЙ  " } else { "ОСТАЛОСЬ  " }, fmt_duration(b.seconds_left));
                    let watts = if b.draw_watts > 0.2 { format!("{} Вт", to_fixed(b.draw_watts, 1)) } else { "—".into() };
                    let right = format!("{}{}", if b.charging() { "ЗАРЯДКА  " } else { "РАСХОД  " }, watts);
                    let l = ui.fonts.layout(&left, key, LABEL - 2.0, 0.0);
                    let r = ui.fonts.layout(&right, key, LABEL - 2.0, 0.0);
                    ui.text(&l, ix, cy, t.col_dim, TextStyle::Normal);
                    ui.text(&r, ix + iw - r.width, cy, t.col_dim, TextStyle::Normal);
                }
            }
            Block::Info => {
                plate(ui, x0, y, cw, h);
                info_grid(ui, ix, y + 10.0, iw, b);
            }
            Block::Packs => {
                plate(ui, x0, y, cw, h);
                let mut ry = y + 10.0;
                for (i, p) in b.packs.iter().enumerate() {
                    pack_row(ui, i as u32, ix, ry, iw, p);
                    ry += PACK_ROW + 6.0;
                }
            }
            Block::Limit => {
                let cap = crate::cards::caption(ui.fonts, "ПРЕДЕЛ ЗАРЯДА");
                ui.text(&cap, x0, y + ac(h, cap.height()), t.col_dim, TextStyle::Normal);
                let font = FONT_SIZE - 4.0;
                let widths: Vec<f32> = PRESETS.iter().map(|p| ui.console_button_width(font, "", p.1, 58.0)).collect();
                let mut bx = x0 + cw - (widths.iter().sum::<f32>() + 6.0 * (widths.len() - 1) as f32);
                let lim = b.effective_limit();
                for (i, p) in PRESETS.iter().enumerate() {
                    let current = lim == p.0 || (p.0 == 100 && lim >= 99);
                    ui.console_button_sized(LIMIT + i as u32, bx, y, widths[i], font, "", t.col_grey, p.1, current);
                    bx += widths[i] + 6.0;
                }
            }
            Block::Note(lines) => {
                let mut ly = y;
                for l in &lines {
                    ui.text(l, x0 + cw - l.adv, ly, t.col_muted, TextStyle::Normal);
                    ly += l.height();
                }
            }
            Block::Warn(lines) => {
                let mut ly = y;
                for l in &lines {
                    ui.text(l, x0, ly, t.col_warn, TextStyle::Normal);
                    ly += l.height();
                }
            }
        }
        y += h + 8.0;
    }
}

/// The info plate's grid: capacity, cycles, health, energy.
fn info_grid(ui: &mut Ui, x: f32, y: f32, w: f32, b: &Battery) {
    let t = ui.theme;
    let health = b.health();
    let rows = [
        vec![("ЁМКОСТЬ", fmt_wh(b.energy_full), t.col_white), ("ЦИКЛЫ", if b.cycles > 0.0 { js_num(b.cycles) } else { "—".into() }, t.col_white)],
        vec![("РЕСУРС", if health > 0 { format!("{health}%") } else { "—".into() }, health_color(health, t)), ("ЗАПАС", fmt_wh(b.energy_now), t.col_white)],
    ];
    crate::cards::info_grid(ui, x, y, w, &rows);
}

/// One pack: lamp, name, model (elided), capacity · health · cycles.
fn pack_row(ui: &mut Ui, i: u32, x: f32, y: f32, w: f32, p: &Pack) {
    let t = ui.theme;
    let tint = if p.health > 0 && p.health < 60 { t.col_alert } else { t.col_accent };
    lamp_tinted(ui, 0x7100 + i, x, y + ac(PACK_ROW, 10.0), true, tint);
    let name = ui.fonts.layout(&p.name, theme::bar_font(true), LABEL, 0.0);
    ui.text(&name, x + 18.0, y + ac(PACK_ROW, name.height()), t.col_white, TextStyle::Normal);
    let health = if p.health > 0 { format!("ресурс {}%", p.health) } else { "—".into() };
    let stats_text = format!("{}% · {} · {} цикл.", p.capacity, health, js_num(p.cycles));
    let stats = ui.fonts.layout(&stats_text, theme::bar_font(false), LABEL - 1.0, 0.0);
    let sx = x + w - stats.width;
    ui.text(&stats, sx, y + ac(PACK_ROW, stats.height()), health_color(p.health, t), TextStyle::Normal);
    let mx = x + 18.0 + name.width + 10.0;
    let key = theme::bar_font(false);
    let full = ui.fonts.layout(&p.model, key, LABEL - 2.0, 0.0);
    let model = ui.fonts.elide_right(&full, &p.model, key, sx - 10.0 - mx, 0.0);
    ui.text(&model, mx, y + ac(PACK_ROW, model.height()), t.col_muted, TextStyle::Normal);
}
