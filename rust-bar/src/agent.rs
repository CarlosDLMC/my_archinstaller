//! Claude Code usage (AgentUsage.qml + AgentPanel.qml): the collector's
//! readings and the agent card.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::Value;

use crate::app::App;
use crate::bar::ac;
use crate::cards::{plate, Ui};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::services::{self, Services};
use crate::theme::{self, FONT_SIZE};

#[derive(Clone, Default)]
pub struct Limit {
    pub label: String,
    pub window: String,
    pub percent: f64,
    pub severity: String,
    pub active: bool,
    pub resets_at: String,
}

#[derive(Clone, Default)]
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
}

fn now_s() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0.0, |d| d.as_secs_f64())
}

/// AgentUsage.apply(): the collector's JSON.
fn apply(app: &mut App, text: &str) {
    let Ok(j) = serde_json::from_str::<Value>(text.trim()) else { return };
    if j.get("installed").and_then(Value::as_bool) == Some(true) {
        app.svc.agent_installed = true;
    }
    if j.get("checkOnly").and_then(Value::as_bool) == Some(true) {
        app.mark_all_dirty();
        return;
    }
    let u = &mut app.svc.agent;
    if j.get("probed").and_then(Value::as_bool) == Some(true) {
        if let Some(p) = j.get("plan").and_then(Value::as_str).filter(|p| !p.is_empty()) {
            u.plan = p.into();
        }
        if let Some(l) = j.get("limits").and_then(Value::as_array).filter(|l| !l.is_empty()) {
            u.limits = l
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
        }
        u.limits_error = j.get("limitsError").and_then(Value::as_str).unwrap_or("").into();
        u.stale_at = j.get("staleAt").and_then(Value::as_f64).unwrap_or(0.0);
        u.last_probe_at = now_s();
    }
    if let Some(h) = j.get("oldestHour").and_then(Value::as_f64).filter(|h| *h > 0.0) {
        u.oldest_hour = h;
    }
    if let Some(d) = j.get("byDay").and_then(Value::as_array).filter(|d| !d.is_empty()) {
        u.by_day = d.iter().map(|x| (x.get("day").and_then(Value::as_str).unwrap_or("").to_string(), x.get("tokens").and_then(Value::as_f64).unwrap_or(0.0))).collect();
    }
    if let Some(m) = j.get("byModel").and_then(Value::as_array).filter(|m| !m.is_empty()) {
        let n = |x: &Value, k: &str| x.get(k).and_then(Value::as_f64).unwrap_or(0.0);
        u.by_model = m.iter().map(|x| ModelUse { model: x.get("model").and_then(Value::as_str).unwrap_or("").into(), tokens: n(x, "tokens"), input: n(x, "input"), output: n(x, "output"), cache_read: n(x, "cacheRead") }).collect();
    }
    u.loaded = true;
    app.mark_all_dirty();
}

pub fn run(app: &mut App, mode: &str) {
    let cmd = format!("{}/.config/quickshell/bar/scripts/agent-usage.py {mode}", services::home());
    app.spawn("agent-usage", &["sh", "-c", &cmd], |app, d| apply(app, &d.stdout));
}

/// cardOpen: a full probe if the last one is over two minutes old, then
/// stats every minute while the card stays open.
pub fn opened(app: &mut App) {
    let mode = if now_s() - app.svc.agent.last_probe_at > 120.0 { "full" } else { "stats" };
    run(app, mode);
    app.every(Duration::from_secs(60), |app| {
        if app.card.as_ref().map(|c| c.kind) != Some(crate::cards::CardKind::Agent) {
            return false;
        }
        run(app, "stats");
        true
    });
}

/// compact(): 1.2B / 3.4M / 56k / 7.
fn compact(n: f64) -> String {
    if n.is_nan() {
        "—".into()
    } else if n >= 1e9 {
        format!("{:.1}B", n / 1e9)
    } else if n >= 1e6 {
        format!("{:.1}M", n / 1e6)
    } else if n >= 1e3 {
        format!("{:.0}k", n / 1e3)
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

/// untilText()
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

/// agoText()
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

/// MeterRow: label, SegmentGauge, value.
#[allow(clippy::too_many_arguments)]
fn meter_row(ui: &mut Ui, id: u32, x: f32, y: f32, w: f32, label: &str, value: &str, fraction: f64, fill: Color, emphasise: bool) {
    let t = ui.theme;
    let h = (LABEL * 1.35).round();
    let lw = (LABEL * 4.6).round();
    let key = theme::bar_font(emphasise);
    let full = ui.fonts.layout(label, key, LABEL - 1.0, 0.0);
    let l = ui.fonts.elide_right(&full, label, key, lw, 0.0);
    ui.text(&l, x, y + ac(h, l.height()), if emphasise { t.col_white } else { t.col_grey }, TextStyle::Normal);
    let vw = (LABEL * 3.0).round();
    let vl = ui.fonts.layout(value, theme::bar_font(true), LABEL, 0.0);
    ui.text(&vl, x + w - vl.adv, y + ac(h, vl.height()), fill, TextStyle::Normal);
    let gx = x + lw + 8.0;
    let gw = (x + w - vw - 10.0) - gx;
    let n = 10.max((gw / 10.0).round() as i32);
    let f = fraction.clamp(0.0, 1.0);
    let value = if f > 0.0 { (f * 100.0).max(100.0 / n as f64) } else { 0.0 };
    let tint = if fill == t.col_alert { t.col_alert } else { t.col_accent };
    gauge(ui, id, gx, y + ac(h, 10.0), gw, 10.0, n, value as f32, tint);
}

/// SegmentGauge (200 ms colour per segment).
#[allow(clippy::too_many_arguments)]
fn gauge(ui: &mut Ui, id: u32, x: f32, y: f32, w: f32, h: f32, n: i32, value: f32, tint: Color) {
    let cell = (w - 2.0 * (n - 1) as f32) / n as f32;
    let lit = (value.clamp(0.0, 100.0) / 100.0 * n as f32).round() as i32;
    for i in 0..n {
        let target = if i < lit { tint } else { Color::qt_rgba(1.0, 1.0, 1.0, 0.07) };
        let (c, run) = ui.card.color(0x9_0000 + id * 128 + i as u32, target, 200, ui.now);
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
                    for l in ui.fonts.wrap(&limits_error_text(u), theme::bar_font(false), HEADER, 0.0, iw) {
                        ui.text(&l, ix, cy, t.col_alert, TextStyle::Normal);
                        cy += l.height();
                    }
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
                    meter_row(ui, i as u32, ix, cy, iw, &label, &format!("{}%", l.percent.round()), l.percent / 100.0, meter_color(&l.severity, l.percent, t), l.active);
                    cy += (LABEL * 1.35).round();
                }
                if let Some(s) = session_text(u) {
                    cy += 6.0;
                    for l in ui.fonts.wrap(&s, theme::bar_font(false), HEADER, 0.0, iw) {
                        ui.text(&l, ix, cy, t.col_grey, TextStyle::Normal);
                        cy += l.height();
                    }
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
                    meter_row(ui, 16 + i as u32, ix, cy, iw, &label, &compact(*tokens), if max > 0.0 { tokens / max } else { 0.0 }, t.col_white, today);
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
                    // .replace(/^claude-/, "").replace(/-\d{8}$/, "") (AgentPanel.qml:396-397),
                    // on char boundaries: the id comes from the transcripts on disk.
                    let base = m.model.strip_prefix("claude-").unwrap_or(&m.model);
                    let name = match base.rsplit_once('-') {
                        Some((head, tail)) if tail.len() == 8 && tail.bytes().all(|b| b.is_ascii_digit()) => head,
                        _ => base,
                    };
                    let detail = format!("ввод {} · вывод {} · кэш {}", compact(m.input), compact(m.output), compact(m.cache_read));
                    let total = ui.fonts.layout(&compact(m.tokens), theme::bar_font(true), LABEL - 1.0, 0.0);
                    ui.text(&total, ix + iw - total.width, cy, t.col_white, TextStyle::Normal);
                    let shown: &str = if hover { &detail } else { name };
                    let key = theme::bar_font(false);
                    let full = ui.fonts.layout(shown, key, LABEL - 1.0, 0.0);
                    let line = ui.fonts.elide_right(&full, shown, key, iw - total.width - 8.0, 0.0);
                    ui.text(&line, ix, cy, if hover { t.col_grey } else { t.col_white }, TextStyle::Normal);
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
