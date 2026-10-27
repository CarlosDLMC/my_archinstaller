//! The strip: shell.qml's RowLayout and the widgets in it, laid out at the
//! 2560 px reference width and scaled like the QML bar (uiScale).

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

/// qRound: what anchors.alignWhenCentered does to a centred item.
fn qround(v: f32) -> f32 {
    (v + 0.5).floor()
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Action {
    Logo,
    Workspace(i64),
    LayoutCycle,
    Pult,
    Bell,
    Weather,
    Clock,
}

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
}

struct Painter<'a> {
    scene: &'a mut Scene,
    fonts: &'a mut Fonts,
    theme: &'a Theme,
    hits: Vec<Hit>,
    ui: f32,
    pointer: Option<(f32, f32)>,
}

impl Painter<'_> {
    fn line(&mut self, s: &str, bold: bool, size: f32) -> Line {
        self.fonts.layout(s, theme::bar_font(bold), size, 0.0)
    }

    /// A bar Text: bold, outlined, Theme.fontSize, top-left at (x, y).
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

/// One slot of shell.qml's RowLayout.
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

pub fn draw(scene: &mut Scene, fonts: &mut Fonts, theme: &Theme, svc: &Services, ctx: &Ctx) -> Vec<Hit> {
    let ui = ui_scale(ctx.screen_width);
    let dw = ctx.width / ui;
    // PanelWindow.color: the wash under the compositor blur.
    scene.fill(0.0, 0.0, ctx.width, (DESIGN_HEIGHT * ui).round(), theme.col_bg_wash);
    scene.save();
    scene.scale(ui, ui);
    let mut p = Painter { scene, fonts, theme, hits: Vec::new(), ui, pointer: ctx.pointer };

    let stats = svc.stats.shown;
    let mut slots = vec![Slot::Pad(12.0), Slot::Logo, Slot::Workspaces, Slot::Sep, Slot::Title, Slot::Center];
    if stats {
        slots.extend([Slot::Cpu, Slot::Sep, Slot::Mem, Slot::Sep]);
    }
    slots.extend([Slot::Layout, Slot::Sep, Slot::Pult, Slot::Pad(8.0)]);

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
        }
    };
    let widths: Vec<f32> = slots.iter().map(|s| width_of(&mut p, s)).collect();
    let fixed: f32 = widths.iter().sum();
    let center_w = (dw - fixed).max(0.0);

    let mut x = 0.0f32;
    for (s, w) in slots.iter().zip(widths.iter()) {
        match s {
            Slot::Pad(_) => {}
            Slot::Logo => {
                let item_w = logo_line.width + 16.0;
                let tx = qround((item_w - logo_line.width) / 2.0);
                let ty = qround((DESIGN_HEIGHT - logo_line.height()) / 2.0);
                p.scene.text(p.fonts, &logo_line, x + tx, ty + logo_line.ascent, theme.col_logo, TextStyle::Normal);
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
                    p.label(&line, wx, ry + qround((rh - line.height()) / 2.0), color);
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
                    let full = p.fonts.layout(title, key, FONT_SIZE, 0.0);
                    let line = p.fonts.elide_right(&full, title, key, 375.0, 0.0);
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
                p.label(&line, x, qround((DESIGN_HEIGHT - line.height()) / 2.0), theme.col_white);
                p.hit(x, 0.0, line.width, DESIGN_HEIGHT, Action::LayoutCycle);
            }
            Slot::Pult => {
                let line = p.fonts.layout("\u{f0493}", theme::bar_font(false), FONT_SIZE + 2.0, 0.0);
                let ty = qround((DESIGN_HEIGHT - line.height()) / 2.0);
                p.label(&line, x, ty, theme.col_grey);
                p.hit(x, 0.0, line.width, DESIGN_HEIGHT, Action::Pult);
            }
        }
        x += if matches!(s, Slot::Center) { center_w } else { *w };
    }
    let hits = std::mem::take(&mut p.hits);
    scene.restore();
    hits
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

/// CenterInfo: bell (+ weather pill) right of centre, "|" on the screen's
/// centre line, the clock pill after it.
fn draw_center(p: &mut Painter, svc: &Services, x0: f32, width: f32, design_width: f32) {
    let theme = p.theme;
    let time = p.line(&svc.clock, true, FONT_SIZE);
    let sep = p.fonts.layout("|", theme::bar_font(false), FONT_SIZE, 0.0);
    let center_x = design_width / 2.0 - x0 - sep.width / 2.0;
    let time_block = 8.0 + (time.width + 16.0) + 12.0;
    let max_x = width - sep.width - time_block;
    let sep_x = center_x.min(max_x.max(0.0));
    let sep_y = qround((DESIGN_HEIGHT - sep.height()) / 2.0);
    // No weather yet: the "|" and the weather pill are hidden; the bell stays.
    let bell = p.line("\u{f009a}  ", true, FONT_SIZE);
    let bell_x = x0 + sep_x - 8.0 - bell.width;
    p.label(&bell, bell_x, ((DESIGN_HEIGHT - bell.height()) / 2.0).round(), theme.col_grey);
    p.hit(bell_x, 0.0, bell.width, DESIGN_HEIGHT, Action::Bell);
    let _ = sep_y;
    let pill_x = x0 + sep_x + sep.width + 8.0;
    let pill_y = (DESIGN_HEIGHT - 26.0) / 2.0;
    let pill_w = time.width + 16.0;
    p.label(&time, pill_x + qround((pill_w - time.width) / 2.0), pill_y + qround((26.0 - time.height()) / 2.0), theme.col_white);
    p.hit(pill_x, pill_y, pill_w, 26.0, Action::Clock);
}

pub fn close_all_popups(_app: &mut App) {}

pub fn activate(app: &mut App, strip: usize, action: Action, _button: u32) {
    match action {
        Action::Workspace(id) => {
            let name = app.strips[strip].name.clone();
            services::mango_dispatch(app, &format!("viewcrossmon,{id},^{name}$"));
        }
        Action::LayoutCycle => crate::ipc::layout_next(app),
        _ => {}
    }
    let _ = FontKey { family: "", bold: false };
}
