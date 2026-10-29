//! Claude Code usage: the collector's readings and the agent card.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::Value;

use crate::app::App;
use crate::bar::ac;
use crate::cards::{plate, CardKind, Ui};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::services::{self, Services};
use crate::theme::{self, FONT_SIZE};

#[derive(Clone, Default, PartialEq)]
pub struct Limit {
    pub label: String,
    pub window: String,
    pub percent: f64,
    pub severity: String,
    pub active: bool,
    pub resets_at: String,
}

#[derive(Clone, Default, PartialEq)]
pub struct ModelUse {
    pub model: String,
    pub tokens: f64,
    pub input: f64,
    pub output: f64,
    pub cache_read: f64,
}

#[derive(Default)]
pub struct Usage {
    pub plan: String,
    pub limits: Vec<Limit>,
    pub limits_error: String,
    pub by_day: Vec<(String, f64)>,
    pub by_model: Vec<ModelUse>,
    pub oldest_hour: f64,
    pub loaded: bool,
    pub stale_at: f64,
    last_probe_at: f64,
    /// The open card's ticks, and its clock-driven texts as last seen.
    ticks: u32,
    clock_texts: String,
}

/// The open card's 30 s timer (the clock-driven texts and the stats
/// reading); cards::close stops it by this name.
pub(crate) const TICK: &str = "agent-tick";

fn now_s() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0.0, |d| d.as_secs_f64())
}

/// Applies the collector's JSON.
fn apply(app: &mut App, text: &str) {
    let Ok(j) = serde_json::from_str::<Value>(text.trim()) else { return };
    // The strip shows the widget once it is installed; the readings are the
    // card's.
    if j.get("installed").and_then(Value::as_bool) == Some(true) && !app.svc.agent_installed {
        app.svc.agent_installed = true;
        app.mark_strips_dirty();
    }
    if j.get("checkOnly").and_then(Value::as_bool) == Some(true) {
        return;
    }
    let u = &mut app.svc.agent;
    // A Repeater handed an array that differs from its model makes all its
    // rows anew: new Texts (subpixel again), and new segment gauges whose
    // cells fade from their first layout pass (first_lit). An equal one
    // keeps them.
    let mut remade: Vec<u64> = Vec::new();
    let mut gauges: Vec<(u32, i32)> = Vec::new();
    if j.get("probed").and_then(Value::as_bool) == Some(true) {
        if let Some(p) = j.get("plan").and_then(Value::as_str).filter(|p| !p.is_empty()) {
            u.plan = p.into();
        }
        if let Some(l) = j.get("limits").and_then(Value::as_array).filter(|l| !l.is_empty()) {
            let limits: Vec<Limit> = l
                .iter()
                .map(|x| Limit {
                    label: x.get("label").and_then(Value::as_str).unwrap_or("").into(),
                    window: x.get("window").and_then(Value::as_str).unwrap_or("").into(),
                    percent: x.get("percent").and_then(Value::as_f64).unwrap_or(0.0),
                    severity: x.get("severity").and_then(Value::as_str).unwrap_or("").into(),
                    active: x.get("active").and_then(Value::as_bool).unwrap_or(false),
                    resets_at: x.get("resetsAt").and_then(Value::as_str).unwrap_or("").into(),
                })
                .collect();
            if limits != u.limits {
                remade.extend(LIMIT_TEXTS);
                gauges.extend(limits.iter().enumerate().map(|(i, l)| (i as u32, first_lit(l.percent / 100.0, true))));
            }
            u.limits = limits;
        }
        u.limits_error = j.get("limitsError").and_then(Value::as_str).unwrap_or("").into();
        u.stale_at = j.get("staleAt").and_then(Value::as_f64).unwrap_or(0.0);
        u.last_probe_at = now_s();
    }
    if let Some(h) = j.get("oldestHour").and_then(Value::as_f64).filter(|h| *h > 0.0) {
        u.oldest_hour = h;
    }
    if let Some(d) = j.get("byDay").and_then(Value::as_array).filter(|d| !d.is_empty()) {
        let by_day: Vec<(String, f64)> = d.iter().map(|x| (x.get("day").and_then(Value::as_str).unwrap_or("").to_string(), x.get("tokens").and_then(Value::as_f64).unwrap_or(0.0))).collect();
        if by_day != u.by_day {
            remade.extend(DAY_TEXTS);
            let old = u.by_day.iter().map(|d| d.1).fold(0.0, f64::max);
            gauges.extend(by_day.iter().enumerate().map(|(i, d)| (16 + i as u32, first_lit(if old > 0.0 { d.1 / old } else { 0.0 }, true))));
        }
        u.by_day = by_day;
    }
    if let Some(m) = j.get("byModel").and_then(Value::as_array).filter(|m| !m.is_empty()) {
        let n = |x: &Value, k: &str| x.get(k).and_then(Value::as_f64).unwrap_or(0.0);
        let by_model: Vec<ModelUse> = m.iter().map(|x| ModelUse { model: x.get("model").and_then(Value::as_str).unwrap_or("").into(), tokens: n(x, "tokens"), input: n(x, "input"), output: n(x, "output"), cache_read: n(x, "cacheRead") }).collect();
        if by_model != u.by_model {
            remade.extend(MODEL_TEXTS);
            let old = u.by_model.iter().map(|m| m.tokens).fold(0.0, f64::max);
            gauges.extend(by_model.iter().enumerate().map(|(i, m)| (64 + i as u32, first_lit(if old > 0.0 { m.tokens / old } else { 0.0 }, false))));
        }
        u.by_model = by_model;
    }
    u.loaded = true;
    u.clock_texts = clock_texts(u);
    if let Some(c) = app.card.as_mut().filter(|c| c.kind == CardKind::Agent) {
        c.texts.forget_parts(&remade);
        c.gauge_from.extend(gauges);
    }
    app.mark_card_dirty(&[CardKind::Agent]);
}

pub fn run(app: &mut App, mode: &str) {
    let cmd = format!("{}/.config/rust-bar/scripts/agent-usage.py {mode}", services::home());
    app.spawn("agent-usage", &["sh", "-c", &cmd], |app, d| {
        apply(app, &d.stdout);
        busy_changed(app);
    });
    busy_changed(app);
}

/// Busy follows the collector process, whatever it prints, and the open
/// card's no-data text follows busy.
fn busy_changed(app: &mut App) {
    let u = &app.svc.agent;
    if !(u.by_day.is_empty() && u.limits.is_empty()) {
        return;
    }
    if let Some(c) = app.card.as_mut().filter(|c| c.kind == CardKind::Agent) {
        c.win.dirty = true;
    }
}

/// The card opened: a full probe if the last one is over two minutes old,
/// then the tick while the card stays open; opening again restarts it.
pub fn opened(app: &mut App) {
    let mode = if now_s() - app.svc.agent.last_probe_at > 120.0 { "full" } else { "stats" };
    run(app, mode);
    let u = &mut app.svc.agent;
    u.ticks = 0;
    u.clock_texts = clock_texts(u);
    app.debounce(TICK, Duration::from_secs(30), tick);
}

/// While the card is open: a tick every 30 s, which moves the reset
/// countdowns and the stale age, and the 60 s stats reading on every second
/// tick. Both stop with the card; a stray tick after it closed ends here.
fn tick(app: &mut App) {
    if app.card.as_ref().map(|c| c.kind) != Some(CardKind::Agent) {
        return;
    }
    let u = &mut app.svc.agent;
    u.ticks += 1;
    // Qt redraws a Text only when its string changed.
    let texts = clock_texts(u);
    if texts != u.clock_texts {
        u.clock_texts = texts;
        if let Some(c) = app.card.as_mut() {
            c.win.dirty = true;
        }
    }
    if app.svc.agent.ticks % 2 == 0 {
        run(app, "stats");
    }
    app.debounce(TICK, Duration::from_secs(30), tick);
}

/// What the two clock-driven texts show: the limits error with its age, and
/// the reset countdowns.
fn clock_texts(u: &Usage) -> String {
    let error = if u.limits_error.is_empty() { String::new() } else { limits_error_text(u) };
    format!("{error}\n{}", session_text(u).unwrap_or_default())
}

/// compact(): 1.2B / 3.4M / 56k / 7, toFixed's ties going up (2,500 is 3k).
fn compact(n: f64) -> String {
    if n.is_nan() {
        "—".into()
    } else if n >= 1e9 {
        format!("{}B", services::to_fixed(n / 1e9, 1))
    } else if n >= 1e6 {
        format!("{}M", services::to_fixed(n / 1e6, 1))
    } else if n >= 1e3 {
        format!("{}k", services::to_fixed(n / 1e3, 0))
    } else {
        format!("{}", n.round())
    }
}

/// An ISO 8601 time as epoch seconds (the collector's resetsAt).
fn parse_iso(s: &str) -> Option<f64> {
    let (date, rest) = s.split_once('T')?;
    let mut d = date.split('-').map(|x| x.parse::<i64>().ok());
    let (y, m, dd) = (d.next()??, d.next()??, d.next()??);
    let tz_at = rest.find(['+', '-', 'Z']).unwrap_or(rest.len());
    let (time, tz) = rest.split_at(tz_at);
    let mut t = time.split(':');
    let (hh, mm) = (t.next()?.parse::<f64>().ok()?, t.next()?.parse::<f64>().ok()?);
    let ss: f64 = t.next().and_then(|v| v.parse().ok()).unwrap_or(0.0);
    let off = if tz.starts_with('+') || tz.starts_with('-') {
        let sign = if tz.starts_with('-') { -1.0 } else { 1.0 };
        let mut p = tz[1..].split(':');
        sign * (p.next()?.parse::<f64>().ok()? * 3600.0 + p.next().and_then(|v| v.parse::<f64>().ok()).unwrap_or(0.0) * 60.0)
    } else {
        0.0
    };
    let days = {
        let y = if m <= 2 { y - 1 } else { y };
        let era = y.div_euclid(400);
        let yoe = y - era * 400;
        let mp = (m + 9) % 12;
        let doy = (153 * mp + 2) / 5 + dd - 1;
        era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
    };
    Some(days as f64 * 86400.0 + hh * 3600.0 + mm * 60.0 + ss - off)
}

/// The time left until `iso`: "сейчас" under a minute, else days and hours,
/// hours and minutes, or minutes.
fn until(iso: &str) -> String {
    let Some(t) = parse_iso(iso) else { return String::new() };
    let s = (t - now_s()).round().max(0.0) as i64;
    if s < 60 {
        return "сейчас".into();
    }
    let (m, h) = (s / 60, s / 3600);
    let d = h / 24;
    if d >= 1 {
        format!("{d} дн {} ч", h % 24)
    } else if h >= 1 {
        format!("{h} ч {} мин", m % 60)
    } else {
        format!("{m} мин")
    }
}

/// How long ago `epoch` was: "только что" under 90 s, else minutes, hours
/// (under 48) or days.
fn ago(epoch: f64) -> String {
    let s = (now_s() - epoch).round().max(0.0) as i64;
    if s < 90 {
        return "только что".into();
    }
    let m = (s as f64 / 60.0).round() as i64;
    if m < 60 {
        return format!("{m} мин назад");
    }
    let h = (m as f64 / 60.0).round() as i64;
    if h < 48 {
        format!("{h} ч назад")
    } else {
        format!("{} дн назад", (h as f64 / 24.0).round() as i64)
    }
}

/// Qt.locale().toString(d, "d MMM") for LC_TIME (CLDR's abbreviated months).
fn since_label(oldest_hour: f64) -> String {
    if oldest_hour <= 0.0 {
        return "НЕТ ДАННЫХ".into();
    }
    let secs = (oldest_hour * 3600.0) as i64;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&secs, &mut tm) };
    let (y, m, d) = (tm.tm_year + 1900, tm.tm_mon as usize, tm.tm_mday);
    let month = crate::cal::month_abbr(m as u32 + 1);
    let this_year = crate::cal::today().0;
    let s = if y == this_year { format!("{d} {month}") } else { format!("{d} {month} {y}") };
    format!("С {}", s.to_uppercase())
}

const LABEL: f32 = FONT_SIZE - 3.0;
const HEADER: f32 = FONT_SIZE - 5.0;

/// TextMemo parts of the Repeaters' rows, named by row so a row's texts keep
/// their key whatever is drawn before them: (label, value) of the limit and
/// day MeterRows, (name, total) of the model rows.
const LIMIT_TEXTS: [u64; 2] = [0xA1, 0xA2];
const DAY_TEXTS: [u64; 2] = [0xA3, 0xA4];
const MODEL_TEXTS: [u64; 2] = [0xA5, 0xA6];
/// TextMemo parts of the wrapped Texts: one Text each, one verdict for all
/// its lines.
const ERROR_TEXT: u64 = 0xA7;
const RESET_TEXT: u64 = 0xA8;

fn meter_color(sev: &str, pct: f64, t: &theme::Theme) -> Color {
    let s = sev.to_lowercase();
    if !s.is_empty() && s != "normal" || pct >= 80.0 {
        t.col_alert
    } else {
        t.col_white
    }
}

/// The body's children: (kind, height) - measured and drawn the same way.
fn body(fonts: &mut crate::text::Fonts, u: &Usage, w: f32, busy: bool) -> Vec<(u8, f32)> {
    let cw = w - 16.0;
    let iw = cw - 20.0;
    let cap = fonts.layout("Л", theme::bar_font(true), FONT_SIZE - 5.0, 1.0).height();
    let meter = (LABEL * 1.35).round();
    let small = |fonts: &mut crate::text::Fonts, s: &str| fonts.wrap(s, theme::bar_font(false), HEADER, 0.0, iw).iter().map(|l| l.height()).sum::<f32>();
    let mut v = vec![(0u8, (LABEL * 1.8).round())];
    // ЛИМИТЫ
    let mut h = cap;
    if !u.limits_error.is_empty() {
        h += 6.0 + small(fonts, &limits_error_text(u));
    }
    h += u.limits.len() as f32 * (6.0 + meter);
    if session_text(u).is_some() {
        h += 6.0 + small(fonts, &session_text(u).unwrap_or_default());
    }
    v.push((1, h + 20.0));
    if !u.by_day.is_empty() {
        v.push((2, cap + u.by_day.len() as f32 * (6.0 + meter) + 20.0));
    }
    if !u.by_model.is_empty() {
        let name_h = fonts.layout("a", theme::bar_font(false), LABEL - 1.0, 0.0).height();
        let note_h = fonts.layout("з", theme::bar_font(false), HEADER, 0.0).height();
        v.push((3, cap + 8.0 + note_h + u.by_model.len() as f32 * (8.0 + name_h + 12.0) + 20.0));
    }
    if u.by_day.is_empty() && u.limits.is_empty() {
        let _ = busy;
        v.push((4, fonts.layout("Д", theme::bar_font(false), LABEL, 0.0).height()));
    }
    v
}

fn limits_error_text(u: &Usage) -> String {
    if u.limits.is_empty() {
        return u.limits_error.clone();
    }
    let age = if u.stale_at > 0.0 { format!(" от {}", ago(u.stale_at)) } else { String::new() };
    format!("{}  Показано последнее значение{}.", u.limits_error, age)
}

fn session_text(u: &Usage) -> Option<String> {
    let s = u.limits.iter().find(|l| l.label == "Session");
    let w = u.limits.iter().find(|l| l.label == "Weekly");
    if s.is_none() && w.is_none() {
        return None;
    }
    let mut parts = vec![];
    if let Some(s) = s {
        parts.push(format!("сессия {}", until(&s.resets_at)));
    }
    if let Some(w) = w {
        parts.push(format!("неделя {}", until(&w.resets_at)));
    }
    Some(format!("сброс через  {}", parts.join("  ·  ")))
}

pub fn content_height(fonts: &mut crate::text::Fonts, svc: &Services, w: f32, busy: bool) -> f32 {
    let b = body(fonts, &svc.agent, w, busy);
    b.iter().map(|x| x.1).sum::<f32>() + 8.0 * (b.len().saturating_sub(1)) as f32
}

/// A meter row: label, segment gauge, value; `parts` names its two Texts.
#[allow(clippy::too_many_arguments)]
fn meter_row(ui: &mut Ui, id: u32, parts: [u64; 2], x: f32, y: f32, w: f32, label: &str, value: &str, fraction: f64, fill: Color, emphasise: bool) {
    let t = ui.theme;
    let h = (LABEL * 1.35).round();
    let lw = (LABEL * 4.6).round();
    let key = theme::bar_font(emphasise);
    let full = ui.fonts.layout(label, key, LABEL - 1.0, 0.0);
    let l = ui.fonts.elide_right(&full, label, key, lw, 0.0);
    ui.text_of(id, parts[0], &l, x, y + ac(h, l.height()), if emphasise { t.col_white } else { t.col_grey });
    let vw = (LABEL * 3.0).round();
    let vl = ui.fonts.layout(value, theme::bar_font(true), LABEL, 0.0);
    ui.text_of(id, parts[1], &vl, x + w - vl.adv, y + ac(h, vl.height()), fill);
    let gx = x + lw + 8.0;
    let gw = (x + w - vw - 10.0) - gx;
    let n = 10.max((gw / 10.0).round() as i32);
    let f = fraction.clamp(0.0, 1.0);
    let value = if f > 0.0 { (f * 100.0).max(100.0 / n as f64) } else { 0.0 };
    let tint = if fill == t.col_alert { t.col_alert } else { t.col_accent };
    gauge(ui, id, gx, y + ac(h, 10.0), gw, 10.0, n, value as f32, tint);
}

/// The lit count of a segment gauge in a row a Repeater makes anew, at its
/// first layout pass: the row has no parent yet, so it is 0 wide and the
/// gauge has its minimum of 10 segments, and the card's maximum is still
/// the old one - the day and model maxima hear of the new array after the
/// Repeater. `at_least_one`: a limit or day row lights one segment for any
/// reading; a model row does not.
fn first_lit(fraction: f64, at_least_one: bool) -> i32 {
    let f = fraction.clamp(0.0, 1.0);
    let value = if at_least_one && f > 0.0 { (f * 100.0).max(10.0) } else { f * 100.0 };
    (value / 100.0 * 10.0).round() as i32
}

/// A segment gauge in a Repeater's row: each cell has a Behavior on its
/// colour (200 ms). A row made anew while the card is open (gauge_from, set
/// by apply()) gets its cells at the first layout pass - ten, at that pass's
/// lit count - and the second pass adds the rest dark (the cells' Repeater
/// hears of `segments` before `lit` does): the cells whose colour the second
/// pass changes fade from there. A row made with the card does not animate
/// (its Behaviors are not finalized yet).
#[allow(clippy::too_many_arguments)]
fn gauge(ui: &mut Ui, id: u32, x: f32, y: f32, w: f32, h: f32, n: i32, value: f32, tint: Color) {
    let cell = (w - 2.0 * (n - 1) as f32) / n as f32;
    let lit = (value.clamp(0.0, 100.0) / 100.0 * n as f32).round() as i32;
    let dark = Color::qt_rgba(1.0, 1.0, 1.0, 0.07);
    let key = |i: i32| 0x9_0000 + id * 128 + i as u32;
    if let Some(first) = ui.card.gauge_from.remove(&id) {
        for i in 0..n {
            ui.card.color_from(key(i), if i < first { tint } else { dark }, 200);
        }
    }
    for i in 0..n {
        let (c, run) = ui.card.color(key(i), if i < lit { tint } else { dark }, 200, ui.now);
        ui.animating |= run;
        ui.scene.rect(x + i as f32 * (cell + 2.0), y, cell, h, c, 1.0, 0.0, Color::TRANSPARENT, true);
    }
}

pub fn draw(ui: &mut Ui, w: f32, svc: &Services, busy: bool, top: f32) {
    let t = ui.theme;
    let u = &svc.agent;
    let (x0, cw) = (8.0, w - 16.0);
    let (ix, iw) = (x0 + 10.0, cw - 20.0);
    let mut y = top;
    for (kind, h) in body(ui.fonts, u, w, busy) {
        match kind {
            0 => {
                let icon = ui.fonts.layout("\u{f16a3}", theme::bar_font(false), LABEL + 2.0, 0.0);
                let name = ui.fonts.layout("CLAUDE CODE", theme::bar_font(true), LABEL, 1.0);
                let row_h = icon.height().max(name.height());
                let ry = y + ac(h, row_h);
                ui.text(&icon, x0 + 4.0, ry + ac(row_h, icon.height()), t.col_white, TextStyle::Normal);
                ui.text(&name, x0 + 4.0 + icon.width + 10.0, ry + ac(row_h, name.height()), t.col_white, TextStyle::Normal);
                if !u.plan.is_empty() {
                    let p = ui.fonts.layout(&u.plan.to_uppercase(), theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
                    ui.text(&p, x0 + cw - p.width, y + ac(h, p.height()), t.col_dim, TextStyle::Normal);
                }
            }
            1 => {
                plate(ui, x0, y, cw, h);
                let mut cy = y + 10.0;
                let cap = ui.fonts.layout("ЛИМИТЫ", theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
                ui.text(&cap, ix, cy, t.col_dim, TextStyle::Normal);
                cy += cap.height();
                if !u.limits_error.is_empty() {
                    cy += 6.0;
                    let lines = ui.fonts.wrap(&limits_error_text(u), theme::bar_font(false), HEADER, 0.0, iw);
                    cy += ui.text_block(0, ERROR_TEXT, &lines, ix, cy, t.col_alert);
                }
                for (i, l) in u.limits.iter().enumerate() {
                    cy += 6.0;
                    let label = if l.window == "7 days" && l.label != "Weekly" {
                        format!("{} нед", l.label)
                    } else {
                        match l.label.as_str() {
                            "Session" => "Сессия".into(),
                            "Weekly" => "Неделя".into(),
                            other => other.into(),
                        }
                    };
                    meter_row(ui, i as u32, LIMIT_TEXTS, ix, cy, iw, &label, &format!("{}%", l.percent.round()), l.percent / 100.0, meter_color(&l.severity, l.percent, t), l.active);
                    cy += (LABEL * 1.35).round();
                }
                if let Some(s) = session_text(u) {
                    cy += 6.0;
                    let lines = ui.fonts.wrap(&s, theme::bar_font(false), HEADER, 0.0, iw);
                    ui.text_block(0, RESET_TEXT, &lines, ix, cy, t.col_grey);
                }
            }
            2 => {
                plate(ui, x0, y, cw, h);
                let mut cy = y + 10.0;
                let cap = ui.fonts.layout("ТОКЕНЫ ПО ДНЯМ · 7 ДНЕЙ", theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
                ui.text(&cap, ix, cy, t.col_dim, TextStyle::Normal);
                cy += cap.height();
                let max = u.by_day.iter().map(|d| d.1).fold(0.0, f64::max);
                let n = u.by_day.len();
                for (i, (day, tokens)) in u.by_day.iter().enumerate() {
                    cy += 6.0;
                    let today = i == n - 1;
                    let label = if today { "Сегодня".to_string() } else { crate::cal::day_name_of_iso(day) };
                    meter_row(ui, 16 + i as u32, DAY_TEXTS, ix, cy, iw, &label, &compact(*tokens), if max > 0.0 { tokens / max } else { 0.0 }, t.col_white, today);
                    cy += (LABEL * 1.35).round();
                }
            }
            3 => {
                plate(ui, x0, y, cw, h);
                let mut cy = y + 10.0;
                let cap = ui.fonts.layout(&format!("ТОКЕНЫ ПО МОДЕЛЯМ · {}", since_label(u.oldest_hour)), theme::bar_font(true), FONT_SIZE - 5.0, 1.0);
                ui.text(&cap, ix, cy, t.col_dim, TextStyle::Normal);
                cy += cap.height() + 8.0;
                let note = ui.fonts.layout("запрос + ответ, без кэша", theme::bar_font(false), HEADER, 0.0);
                ui.text(&note, ix, cy, t.col_grey, TextStyle::Normal);
                cy += note.height();
                let max = u.by_model.iter().map(|m| m.tokens).fold(0.0, f64::max);
                for (i, m) in u.by_model.iter().enumerate() {
                    cy += 8.0;
                    let name_h = ui.fonts.layout("a", theme::bar_font(false), LABEL - 1.0, 0.0).height();
                    let rh = name_h + 12.0;
                    let hover = ui.hovered(ix, cy, iw, rh);
                    // The id less a `claude-` prefix and a `-\d{8}` date suffix,
                    // on char boundaries: the id comes from the transcripts on disk.
                    let base = m.model.strip_prefix("claude-").unwrap_or(&m.model);
                    let name = match base.rsplit_once('-') {
                        Some((head, tail)) if tail.len() == 8 && tail.bytes().all(|b| b.is_ascii_digit()) => head,
                        _ => base,
                    };
                    let detail = format!("ввод {} · вывод {} · кэш {}", compact(m.input), compact(m.output), compact(m.cache_read));
                    let total = ui.fonts.layout(&compact(m.tokens), theme::bar_font(true), LABEL - 1.0, 0.0);
                    ui.text_of(i as u32, MODEL_TEXTS[1], &total, ix + iw - total.width, cy, t.col_white);
                    let shown: &str = if hover { &detail } else { name };
                    let key = theme::bar_font(false);
                    let full = ui.fonts.layout(shown, key, LABEL - 1.0, 0.0);
                    let line = ui.fonts.elide_right(&full, shown, key, iw - total.width - 8.0, 0.0);
                    ui.text_of(i as u32, MODEL_TEXTS[0], &line, ix, cy, if hover { t.col_grey } else { t.col_white });
                    let n = 10.max((iw / 10.0).round() as i32);
                    gauge(ui, 64 + i as u32, ix, cy + rh - 8.0, iw, 8.0, n, ((if max > 0.0 { m.tokens / max } else { 0.0 }).clamp(0.0, 1.0) * 100.0) as f32, t.col_accent);
                    ui.hits.push(crate::bar::Hit { x: ix, y: cy, w: iw, h: rh, action: crate::bar::Action::Hover(0xA00 + i as u32) });
                    cy += rh;
                }
            }
            _ => {
                let s = if busy { "Чтение данных…" } else { "Данных Claude Code нет" };
                let l = ui.fonts.layout(s, theme::bar_font(false), LABEL, 0.0);
                ui.text(&l, x0, y, t.col_grey, TextStyle::Normal);
            }
        }
        y += h + 8.0;
    }
}
