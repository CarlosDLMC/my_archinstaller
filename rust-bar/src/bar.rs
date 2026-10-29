//! The strip: the row of widgets, laid out at the 2560 px reference width
//! and scaled to the screen (ui_scale).

use crate::app::App;
use crate::color::Color;
use crate::gpu::{Scene, TextStyle};
use crate::services::{self, Services};
use crate::text::{FontKey, Fonts, Line};
use crate::theme::{self, Theme, FONT_SIZE};

const REFERENCE_WIDTH: f32 = 2560.0;
const MIN_SCALE: f32 = 0.90;
const DESIGN_HEIGHT: f32 = 34.0;

pub fn ui_scale(screen_width: f32) -> f32 {
    MIN_SCALE.max((screen_width / REFERENCE_WIDTH).min(1.0))
}

pub fn strip_height(screen_width: f32) -> u32 {
    (DESIGN_HEIGHT * ui_scale(screen_width)).round() as u32
}

/// The strip reserves 12 px less than its height (mango's outer gap fills
/// the rest); game mode has no gaps.
pub fn exclusive_zone(height: u32, game_mode: bool) -> i32 {
    let gap = if game_mode { 0 } else { 12 };
    (height as i32 - gap).max(0)
}

/// qRound (JS Math.round).
fn qround(v: f32) -> f32 {
    (v + 0.5).floor()
}

/// Half an extent the way QQuickAnchors takes it with alignWhenCentered:
/// an odd integer part rounds the half up.
fn anchor_half(v: f32) -> f32 {
    if (v as i64) % 2 != 0 {
        (v + 1.0) / 2.0
    } else {
        v / 2.0
    }
}

/// Where anchors.centerIn / verticalCenter puts an item of `size` in `parent`:
/// qRound(half(parent) - half(size)), checked against Qt on ten cases.
pub fn ac(parent: f32, size: f32) -> f32 {
    qround(anchor_half(parent) - anchor_half(size))
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Action {
    Logo,
    Workspace(i64),
    LayoutCycle,
    Pult,
    Agent,
    Volume,
    Battery,
    Wifi,
    Vpn,
    Bell,
    Weather,
    Clock,
    /// A control inside the open card (its index in the focus chain).
    Card(u32),
    /// A hover area inside a card: no hand cursor, no click.
    Hover(u32),
}

/// Action::Hover(TEXT_FIELD) over a TextInput's own rect: a press there is
/// the field's, not what lies under it, and it has no click of its own. The
/// cursor stays the arrow (Qt 6.12's QQuickTextInput sets none).
pub const TEXT_FIELD: u32 = 0xFFFF_FFFE;

#[derive(Clone, Debug)]
pub struct Hit {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub action: Action,
}

impl Hit {
    pub fn contains(&self, x: f32, y: f32) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }
}

pub struct Ctx<'a> {
    pub width: f32,
    pub screen_width: f32,
    pub name: &'a str,
    pub pointer: Option<(f32, f32)>,
    /// The card open on this strip, if any.
    pub open: Option<crate::cards::CardKind>,
    /// The Wi-Fi connect running (or last run) is this bar's: every bar has
    /// its own Wi-Fi widget and connect, and only that widget's icon blinks.
    pub wifi_pulse: bool,
}

struct Painter<'a> {
    now: std::time::Instant,
    /// Something is mid-animation: draw again on the next frame.
    animating: bool,
    scene: &'a mut Scene,
    fonts: &'a mut Fonts,
    theme: &'a Theme,
    hits: Vec<Hit>,
    ui: f32,
    pointer: Option<(f32, f32)>,
    open: Option<crate::cards::CardKind>,
    memo: &'a mut crate::text::TextMemo,
}

impl Painter<'_> {
    fn line(&mut self, s: &str, bold: bool, size: f32) -> Line {
        self.fonts.layout(s, theme::bar_font(bold), size, 0.0)
    }

    /// A bar Text: bold, outlined, FONT_SIZE, top-left at (x, y).
    fn label(&mut self, line: &Line, x: f32, y: f32, color: Color) {
        let shadow = self.theme.col_text_shadow;
        self.scene.text(self.fonts, line, x, y + line.ascent, color, TextStyle::Outline(shadow));
    }

    fn hit(&mut self, x: f32, y: f32, w: f32, h: f32, action: Action) {
        let s = self.ui;
        self.hits.push(Hit { x: x * s, y: y * s, w: w * s, h: h * s, action });
    }

    fn hovered(&self, x: f32, y: f32, w: f32, h: f32) -> bool {
        let s = self.ui;
        self.pointer.map_or(false, |(px, py)| px >= x * s && px < (x + w) * s && py >= y * s && py < (y + h) * s)
    }

    fn separator(&mut self, x: f32) -> f32 {
        let h = (FONT_SIZE * 0.75).round();
        self.scene.save();
        self.scene.multiply_opacity(0.45);
        self.scene.fill(x + 6.0, ((DESIGN_HEIGHT - h) / 2.0).round(), 1.0, h, self.theme.col_separator);
        self.scene.restore();
        x + 13.0
    }
}

/// One slot of the strip's row.
enum Slot {
    Pad(f32),
    Logo,
    Workspaces,
    Sep,
    Title,
    Center,
    Cpu,
    Mem,
    Layout,
    Pult,
    Agent,
    Volume,
    Battery,
    Wifi,
    Vpn,
}

fn workspace_items(svc: &Services, screen: &str) -> (Vec<(i64, bool, bool)>, i64) {
    let mon = svc.mango.monitor(screen);
    let tags = mon.map(|m| m.tags.clone()).unwrap_or_default();
    let max_with = tags.iter().filter(|t| t.client_count > 0).map(|t| t.index).max().unwrap_or(0);
    let active = mon.and_then(|m| m.active_tags.first().copied()).unwrap_or(1);
    let n = 5.max(max_with).max(active);
    let items = (1..=n)
        .map(|id| {
            let has = tags.iter().find(|t| t.index == id).map_or(false, |t| t.client_count > 0);
            (id, id == active, has)
        })
        .collect();
    (items, active)
}

fn layout_label(raw: &str) -> String {
    let l = raw.trim().to_lowercase();
    let code = if l.is_empty() || l.contains("english") {
        "us".to_string()
    } else if l.contains("spanish") {
        "es".into()
    } else if l.contains("russian") {
        "ru".into()
    } else {
        l.chars().take(2).collect()
    };
    match code.as_str() {
        "us" => "АНГ".into(),
        "ru" => "РУС".into(),
        "es" => "ИСП".into(),
        c => c.to_uppercase(),
    }
}

/// Draws the strip; returns its click areas and whether it is animating.
pub fn draw(scene: &mut Scene, fonts: &mut Fonts, theme: &Theme, svc: &Services, ctx: &Ctx, memo: &mut crate::text::TextMemo) -> (Vec<Hit>, bool) {
    memo.begin_frame();
    let ui = ui_scale(ctx.screen_width);
    let dw = ctx.width / ui;
    // The strip's background: the wash under the compositor blur.
    scene.fill(0.0, 0.0, ctx.width, (DESIGN_HEIGHT * ui).round(), theme.col_bg_wash);
    scene.save();
    scene.scale(ui, ui);
    let mut p = Painter { now: std::time::Instant::now(), animating: false, scene, fonts, theme, hits: Vec::new(), ui, pointer: ctx.pointer, open: ctx.open, memo };

    // The strip's order; a hidden widget takes its separator with it.
    let mut slots = vec![Slot::Pad(12.0), Slot::Logo, Slot::Workspaces, Slot::Sep, Slot::Title, Slot::Center];
    if svc.agent_installed {
        slots.extend([Slot::Agent, Slot::Sep]);
    }
    if svc.stats.shown {
        slots.extend([Slot::Cpu, Slot::Sep, Slot::Mem, Slot::Sep]);
    }
    slots.push(Slot::Volume);
    if svc.battery.present {
        slots.extend([Slot::Sep, Slot::Battery]);
    }
    if svc.wifi.has {
        slots.extend([Slot::Sep, Slot::Wifi]);
    }
    slots.extend([Slot::Sep, Slot::Vpn, Slot::Sep, Slot::Layout, Slot::Sep, Slot::Pult, Slot::Pad(8.0)]);

    // Widths first; the centre takes what is left (Layout.fillWidth).
    let ws = workspace_items(svc, ctx.name).0;
    let logo_line = p.fonts.layout("\u{f303}", theme::bar_font(false), (DESIGN_HEIGHT * 1.09).round(), 0.0);
    let width_of = |p: &mut Painter, s: &Slot| -> f32 {
        match s {
            Slot::Pad(w) => *w,
            Slot::Logo => logo_line.width + 16.0 - 6.0,
            Slot::Workspaces => ws.iter().map(|(id, act, _)| p.line(&ws_text(*id, *act), *act, FONT_SIZE).width).sum(),
            Slot::Sep => 13.0,
            Slot::Title => 5.0 + 375.0,
            Slot::Center => 0.0,
            Slot::Cpu => cpu_width(p, svc),
            Slot::Mem => mem_width(p, svc),
            Slot::Layout => p.line(&layout_label(&svc.mango.keyboard_layout), true, FONT_SIZE).width,
            Slot::Pult => p.fonts.layout("\u{f0493}", theme::bar_font(false), FONT_SIZE + 2.0, 0.0).width,
            Slot::Agent => p.line(AGENT_ICON, true, FONT_SIZE).width,
            Slot::Volume => p.line(&volume_text(svc), true, FONT_SIZE).width,
            Slot::Battery => p.line(&battery_text(svc), true, FONT_SIZE).width,
            Slot::Wifi => p.line(wifi_icon(svc), true, FONT_SIZE + 4.0).width,
            Slot::Vpn => vpn_slot_width(p),
        }
    };
    let widths: Vec<f32> = slots.iter().map(|s| width_of(&mut p, s)).collect();
    // RowLayout on the pixel grid: an item that cannot shrink has its
    // preferred size (margins included) as its minimum, and the minimum is
    // rounded up - so every fixed cell is whole pixels and the items start
    // on whole pixels; the centre takes what is left.
    let cells: Vec<f32> = widths.iter().map(|w| w.ceil()).collect();
    let fixed: f32 = cells.iter().sum();
    let center_w = (dw - fixed).max(0.0);

    let mut x = 0.0f32;
    for (s, cell) in slots.iter().zip(cells.iter()) {
        match s {
            Slot::Pad(_) => {}
            Slot::Logo => {
                let item_w = logo_line.width + 16.0;
                let tx = ac(item_w, logo_line.width);
                let ty = ac(DESIGN_HEIGHT, logo_line.height());
                let st = p.memo.style(1, &logo_line, theme.col_logo, TextStyle::Normal);
                p.scene.text(p.fonts, &logo_line, x + tx, ty + logo_line.ascent, theme.col_logo, st);
                p.hit(x, 0.0, item_w, DESIGN_HEIGHT, Action::Logo);
            }
            Slot::Workspaces => {
                let mut wx = x;
                for (id, act, has) in &ws {
                    let line = p.line(&ws_text(*id, *act), *act, FONT_SIZE);
                    let (rw, rh) = (line.width, 28.0);
                    let ry = (DESIGN_HEIGHT - rh) / 2.0;
                    if !act && p.hovered(wx, ry, rw, rh) {
                        p.scene.rect(wx, ry, rw, rh, Color::qt_rgba(1.0, 1.0, 1.0, 0.05), 4.0, 0.0, Color::TRANSPARENT, true);
                    }
                    let color = if *act || *has { theme.col_white } else { theme.col_grey };
                    p.label(&line, wx, ry + ac(rh, line.height()), color);
                    p.hit(wx, ry, rw, rh, Action::Workspace(*id));
                    wx += rw;
                }
            }
            Slot::Sep => {
                p.separator(x);
            }
            Slot::Title => {
                let title = svc.mango.focused_title();
                if !title.is_empty() {
                    let key = theme::bar_font(true);
                    let line = match title.split_once('\n') {
                        // maximumLineCount: 1 on a title with a newline: Qt
                        // sizes the Text to its first line (RowLayout rounds
                        // that up) and elides the line with "…" in it -
                        // "first lin…", measured on Qt 6.12.
                        Some((first, _)) => {
                            let width = p.fonts.layout(first, key, FONT_SIZE, 0.0).width.ceil().min(375.0);
                            let text = format!("{first}…");
                            let full = p.fonts.layout(&text, key, FONT_SIZE, 0.0);
                            p.fonts.elide_right(&full, &text, key, width, 0.0)
                        }
                        None => {
                            let full = p.fonts.layout(title, key, FONT_SIZE, 0.0);
                            p.fonts.elide_right(&full, title, key, 375.0, 0.0)
                        }
                    };
                    p.label(&line, x + 5.0, ((DESIGN_HEIGHT - line.height()) / 2.0).round(), theme.col_window);
                }
            }
            Slot::Center => draw_center(&mut p, svc, x, center_w, dw),
            Slot::Cpu => draw_cpu(&mut p, svc, x),
            Slot::Mem => draw_mem(&mut p, svc, x),
            Slot::Layout => {
                let line = p.line(&layout_label(&svc.mango.keyboard_layout), true, FONT_SIZE);
                if p.hovered(x, 0.0, line.width, DESIGN_HEIGHT) {
                    p.scene.rect(x, 0.0, line.width, DESIGN_HEIGHT, Color::qt_rgba(1.0, 1.0, 1.0, 0.1), 6.0, 0.0, Color::TRANSPARENT, true);
                }
                p.label(&line, x, ac(DESIGN_HEIGHT, line.height()), theme.col_white);
                p.hit(x, 0.0, line.width, DESIGN_HEIGHT, Action::LayoutCycle);
            }
            Slot::Pult => {
                let line = p.fonts.layout("\u{f0493}", theme::bar_font(false), FONT_SIZE + 2.0, 0.0);
                let open = p.open == Some(crate::cards::CardKind::Pult);
                icon_slot(&mut p, &line, x, if open { theme.col_white } else { theme.col_grey }, Action::Pult);
            }
            Slot::Agent => {
                let line = p.line(AGENT_ICON, true, FONT_SIZE);
                icon_slot(&mut p, &line, x, theme.col_white, Action::Agent);
            }
            Slot::Volume => {
                let line = p.line(&volume_text(svc), true, FONT_SIZE);
                let muted = svc.audio.0.muted;
                icon_slot(&mut p, &line, x, if muted { theme.col_grey } else { theme.col_white }, Action::Volume);
            }
            Slot::Battery => {
                let line = p.line(&battery_text(svc), true, FONT_SIZE);
                let b = &svc.battery;
                let alert = b.charge_state == "discharging" && b.level <= 15;
                icon_slot(&mut p, &line, x, if alert { theme.col_alert } else { theme.col_white }, Action::Battery);
            }
            Slot::Wifi => {
                let line = p.line(wifi_icon(svc), true, FONT_SIZE + 4.0);
                let c = if svc.wifi.connected { theme.col_white } else { theme.col_grey };
                // Blinks 1 -> .35 -> 1 (450 ms each, InOutQuad) while this
                // bar's connect runs.
                let (o, running) = if ctx.wifi_pulse { svc.wifi.pulse.value(p.now, 0.35, 450, crate::anim::Easing::InOutQuad) } else { (1.0, false) };
                p.animating |= running;
                p.scene.save();
                p.scene.multiply_opacity(o);
                icon_slot(&mut p, &line, x, c, Action::Wifi);
                p.scene.restore();
            }
            Slot::Vpn => {
                let w = vpn_slot_width(&mut p);
                let on = !svc.vpn.is_empty();
                let line = p.line(if on { VPN_UP } else { VPN_DOWN }, true, FONT_SIZE + 4.0);
                let tx = ac(w, line.width);
                p.label(&line, x + tx, ac(DESIGN_HEIGHT, line.height()), if on { theme.col_alert } else { theme.col_grey });
                p.hit(x, 0.0, w, DESIGN_HEIGHT, Action::Vpn);
            }
        }
        x += if matches!(s, Slot::Center) { center_w } else { *cell };
    }
    let hits = std::mem::take(&mut p.hits);
    let animating = p.animating;
    scene.restore();
    (hits, animating)
}

const AGENT_ICON: &str = "\u{f16a3}";
const VPN_UP: &str = "\u{f0582}";
const VPN_DOWN: &str = "\u{f099c}";

/// A card widget's icon: a Text centred vertically in the 34 px slot.
fn icon_slot(p: &mut Painter, line: &Line, x: f32, color: Color, action: Action) {
    p.label(line, x, ac(DESIGN_HEIGHT, line.height()), color);
    p.hit(x, 0.0, line.width, DESIGN_HEIGHT, action);
}

fn volume_text(svc: &Services) -> String {
    let (audio, info) = &svc.audio;
    let level = if audio.ready { (audio.volume * 100.0).round() as i64 } else { 0 };
    let icon = if audio.muted {
        "\u{f0581}"
    } else {
        let s = info.as_ref().map(|i| format!("{} {} {}", i.name, i.description, i.nick).to_lowercase()).unwrap_or_default();
        // The sink's kind, in this order: hdmi before bluetooth, for a
        // sink whose name has both.
        if s.contains("headphone") || s.contains("headset") {
            "\u{f02cb}"
        } else if s.contains("hdmi") || s.contains("displayport") {
            "\u{f0841}"
        } else if s.contains("bluez") || s.contains("bluetooth") {
            "\u{f00b0}"
        } else {
            "\u{f057e}"
        }
    };
    format!("{icon} {level}%")
}

fn battery_text(svc: &Services) -> String {
    let b = &svc.battery;
    let icon = if b.charge_state == "holding" {
        "\u{f06a5}"
    } else if b.charge_state == "charging" {
        "\u{f0084}"
    } else {
        const STEPS: [&str; 10] = ["\u{f008e}", "\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}", "\u{f007e}", "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0082}"];
        match b.level {
            l if l <= 10 => STEPS[0],
            l if l <= 20 => STEPS[1],
            l if l <= 30 => STEPS[2],
            l if l <= 40 => STEPS[3],
            l if l <= 50 => STEPS[4],
            l if l <= 60 => STEPS[5],
            l if l <= 70 => STEPS[6],
            l if l <= 80 => STEPS[7],
            l if l <= 90 => STEPS[8],
            l if l < 100 => STEPS[9],
            _ => "\u{f0079}",
        }
    };
    format!("{icon} {}%", b.level)
}

fn wifi_icon(svc: &Services) -> &'static str {
    if svc.wifi.connected { "\u{f05a9}" } else { "\u{f05aa}" }
}

/// The wider of the two VPN glyphs' bounding-box (ink) widths, rounded up.
/// The font and the size never change, so it is measured once - not with
/// two hinted glyph loads twice per strip frame.
fn vpn_slot_width(p: &mut Painter) -> f32 {
    static SLOT: std::sync::OnceLock<f32> = std::sync::OnceLock::new();
    *SLOT.get_or_init(|| {
        let a = p.fonts.ink_width(VPN_UP, theme::bar_font(true), FONT_SIZE + 4.0);
        let b = p.fonts.ink_width(VPN_DOWN, theme::bar_font(true), FONT_SIZE + 4.0);
        a.max(b).ceil()
    })
}

/// The weather's tint from the first number in the text, in steps at 0, 10,
/// 18, 25 and 32 degrees; the palette's foreground when there is none.
pub fn temp_color(text: &str, theme: &Theme) -> Color {
    let num: String = {
        let mut s = String::new();
        let mut it = text.chars().peekable();
        while let Some(c) = it.next() {
            if c.is_ascii_digit() || (c == '-' && it.peek().map_or(false, |n| n.is_ascii_digit())) {
                s.push(c);
                while let Some(&d) = it.peek() {
                    if d.is_ascii_digit() {
                        s.push(d);
                        it.next();
                    } else {
                        break;
                    }
                }
                break;
            }
        }
        s
    };
    let Ok(t) = num.parse::<i64>() else { return theme.pal_fg };
    let hex = match t {
        t if t <= 0 => "#8be9fd",
        t if t <= 10 => "#6db3f2",
        t if t <= 18 => "#50fa7b",
        t if t <= 25 => "#f1fa8c",
        t if t <= 32 => "#ffb86c",
        _ => "#ff5555",
    };
    Color::parse(hex).unwrap()
}

/// The weather pill's icon, temperature and location, from the weather text.
fn weather_parts(text: &str) -> (String, String, String) {
    if text.is_empty() {
        return Default::default();
    }
    let icon = text.split_once(char::is_whitespace).map(|(a, _)| a.to_string()).unwrap_or_default();
    let mut temp = String::new();
    let mut loc = String::new();
    let chars: Vec<char> = text.chars().collect();
    for i in 0..chars.len() {
        let start_ok = chars[i].is_ascii_digit() || (chars[i] == '-' && chars.get(i + 1).map_or(false, |c| c.is_ascii_digit()));
        if !start_ok {
            continue;
        }
        let mut j = i + 1;
        while j < chars.len() && chars[j].is_ascii_digit() {
            j += 1;
        }
        if chars.get(j) == Some(&'°') {
            temp = chars[i..=j].iter().collect();
            loc = chars[j + 1..].iter().collect::<String>().trim_start().to_string();
            break;
        }
    }
    (icon, temp, loc)
}

fn ws_text(id: i64, active: bool) -> String {
    if active {
        format!("[{id}]")
    } else {
        format!(" {id} ")
    }
}

fn cpu_parts(svc: &Services) -> [String; 3] {
    ["ЦП ".into(), format!("{}% ", svc.stats.cpu_usage), format!("{}°", svc.stats.cpu_temp)]
}

fn cpu_width(p: &mut Painter, svc: &Services) -> f32 {
    let parts = cpu_parts(svc);
    parts.iter().map(|s| p.line(s, true, FONT_SIZE).width).sum::<f32>() + 4.0 * 2.0
}

fn draw_cpu(p: &mut Painter, svc: &Services, mut x: f32) {
    let parts = cpu_parts(svc);
    for (i, s) in parts.iter().enumerate() {
        let line = p.line(s, true, FONT_SIZE);
        let color = if i == 0 { p.theme.col_grey } else { p.theme.col_value };
        p.label(&line, x, ((DESIGN_HEIGHT - line.height()) / 2.0).round(), color);
        x += line.width + 4.0;
    }
}

fn mem_text(svc: &Services) -> String {
    let m = &svc.stats.mem_usage;
    m.strip_suffix('G').map(|v| format!("{v}Г")).unwrap_or_else(|| m.clone())
}

fn mem_width(p: &mut Painter, svc: &Services) -> f32 {
    p.line("ОЗУ ", true, FONT_SIZE).width + 4.0 + p.line(&mem_text(svc), true, FONT_SIZE).width
}

fn draw_mem(p: &mut Painter, svc: &Services, x: f32) {
    let a = p.line("ОЗУ ", true, FONT_SIZE);
    let b = p.line(&mem_text(svc), true, FONT_SIZE);
    let y = ((DESIGN_HEIGHT - a.height()) / 2.0).round();
    p.label(&a, x, y, p.theme.col_grey);
    p.label(&b, x + a.width + 4.0, y, p.theme.col_value);
}

/// The centre: bell + weather pill ending 8 left of the "|" on the screen's
/// centre line, the clock pill after it.
fn draw_center(p: &mut Painter, svc: &Services, x0: f32, width: f32, design_width: f32) {
    let theme = p.theme;
    let time = p.line(&svc.clock, true, FONT_SIZE);
    let sep = p.fonts.layout("|", theme::bar_font(false), FONT_SIZE, 0.0);
    let center_x = design_width / 2.0 - x0 - sep.width / 2.0;
    let time_block = 8.0 + (time.width + 16.0) + 12.0;
    let max_x = width - sep.width - time_block;
    let sep_x = center_x.min(max_x.max(0.0));
    let has_weather = !svc.weather.text.is_empty();
    if has_weather {
        let st = p.memo.style(2, &sep, theme.col_separator, TextStyle::Normal);
        p.scene.text(p.fonts, &sep, x0 + sep_x, ac(DESIGN_HEIGHT, sep.height()) + sep.ascent, theme.col_separator, st);
    }

    // The bell and the weather pill in a row, its right edge 8 left of the "|".
    let bell_icon = if !svc.dnd_available { "\u{f009c}  " } else if svc.dnd_enabled { "\u{f009b}  " } else { "\u{f009a}  " };
    let bell_color = if !svc.dnd_available { theme.col_warn } else if svc.dnd_enabled { theme.col_alert } else { theme.col_grey };
    let bell = p.line(bell_icon, true, FONT_SIZE);
    let (icon, temp, loc) = weather_parts(&svc.weather.text);
    let parts: Vec<(Line, Color)> = [(icon, true), (temp, true), (loc, false)]
        .into_iter()
        .filter(|(s, _)| !s.is_empty())
        .map(|(s, tinted)| {
            let l = p.line(&s, true, FONT_SIZE);
            (l, if tinted { temp_color(&svc.weather.text, theme) } else { theme.col_white })
        })
        .collect();
    let row_w: f32 = parts.iter().map(|(l, _)| l.width).sum::<f32>() + 5.0 * (parts.len().saturating_sub(1)) as f32;
    let pill_w = if has_weather { row_w + 16.0 } else { 0.0 };
    let row_h: f32 = if has_weather { 26.0f32.max(bell.height()) } else { bell.height() };
    let row_y = ac(DESIGN_HEIGHT, row_h);
    let left_x = x0 + sep_x - 8.0 - (bell.width + pill_w);
    let bell_y = row_y + ac(row_h, bell.height());
    p.label(&bell, left_x, bell_y, bell_color);
    // Its MouseArea fills the bell's Text, not the strip's height.
    p.hit(left_x, bell_y, bell.width, bell.height(), Action::Bell);
    if has_weather {
        let px = left_x + bell.width;
        let py = row_y + ac(row_h, 26.0);
        if p.open == Some(crate::cards::CardKind::Weather) {
            p.scene.rect(px, py, pill_w, 26.0, theme.col_bg, 8.0, 0.0, Color::TRANSPARENT, true);
        }
        let mut tx = px + ac(pill_w, row_w);
        let row_text_h = parts.iter().map(|(l, _)| l.height()).fold(0.0, f32::max);
        let ty = py + ac(26.0, row_text_h);
        for (l, c) in &parts {
            p.label(l, tx, ty + ac(row_text_h, l.height()), *c);
            tx += l.width + 5.0;
        }
        p.hit(px, py, pill_w, 26.0, Action::Weather);
    }

    let pill_x = x0 + sep_x + sep.width + 8.0;
    let pill_y = ac(DESIGN_HEIGHT, 26.0);
    let pill_w = time.width + 16.0;
    if p.open == Some(crate::cards::CardKind::Calendar) {
        p.scene.rect(pill_x, pill_y, pill_w, 26.0, theme.col_bg, 8.0, 0.0, Color::TRANSPARENT, true);
    }
    p.label(&time, pill_x + ac(pill_w, time.width), pill_y + ac(26.0, time.height()), theme.col_white);
    p.hit(pill_x, pill_y, pill_w, 26.0, Action::Clock);
}

/// The focused window changed: the widgets' cards close, the calendar and
/// weather cards of the centre stay open.
pub fn close_all_popups(app: &mut App) {
    use crate::cards::CardKind;
    if matches!(app.card.as_ref().map(|c| c.kind), Some(CardKind::Calendar | CardKind::Weather)) {
        return;
    }
    crate::cards::close(app);
}

const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;

/// The wheel over a widget: the volume widget steps 5%.
pub fn wheel(app: &mut App, _strip: usize, action: Action, delta: f32) {
    if action == Action::Volume {
        let (a, n) = app.svc.audio.clone();
        if let (Some(n), Some(pw)) = (n, app.svc.pw.as_ref()) {
            if a.ready {
                pw.set_volume(n.id, (a.volume + if delta > 0.0 { 0.05 } else { -0.05 }).clamp(0.0, 1.0));
            }
        }
    }
}

pub fn activate(app: &mut App, strip: usize, action: Action, button: u32) {
    let hit = app.strips[strip].hits.iter().find(|h| h.action == action).cloned();
    match action {
        Action::Logo if button == BTN_LEFT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Power, &h, false);
            }
        }
        // The workspaces, the layout label and the bell: MouseAreas with the
        // default acceptedButtons, the left button only.
        Action::Workspace(id) if button == BTN_LEFT => {
            let name = app.strips[strip].name.clone();
            services::mango_dispatch(app, &format!("viewcrossmon,{id},^{name}$"));
        }
        Action::Clock if button == BTN_LEFT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Calendar, &h, false);
            }
        }
        Action::Weather if button == BTN_LEFT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Weather, &h, false);
            }
        }
        // Volume: right click opens the card, left click mutes.
        Action::Volume if button == BTN_RIGHT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Audio, &h, false);
            }
        }
        Action::Volume if button == BTN_LEFT => {
            let (a, n) = app.svc.audio.clone();
            if let (Some(n), Some(pw)) = (n, app.svc.pw.as_ref()) {
                pw.set_mute(n.id, !a.muted);
            }
        }
        Action::Pult if button == BTN_LEFT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Pult, &h, false);
            }
        }
        Action::Vpn if button == BTN_LEFT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Vpn, &h, false);
            }
        }
        Action::Agent if button == BTN_LEFT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Agent, &h, false);
            }
        }
        // Agent: the middle button forces a full probe.
        Action::Agent if button == 0x112 => crate::agent::run(app, "full"),
        // Wi-Fi: left click lists the networks (or closes either view),
        // right click the details card.
        Action::Wifi if button == BTN_LEFT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Wifi, &h, false);
            }
        }
        Action::Wifi if button == BTN_RIGHT => {
            if let Some(h) = hit {
                crate::cards::wifi_details(app, strip, &h);
            }
        }
        Action::Battery if button == BTN_LEFT => {
            if let Some(h) = hit {
                crate::cards::toggle(app, strip, crate::cards::CardKind::Battery, &h, false);
            }
        }
        Action::LayoutCycle if button == BTN_LEFT => crate::layout::cycle(app),
        Action::Bell if button == BTN_LEFT => services::dnd_toggle(app),
        _ => {}
    }
    let _ = FontKey { family: "", bold: false, plain: false };
}
