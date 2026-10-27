//! LayoutState.qml + LayoutOsd.qml: keyboard layouts in most-recently-used
//! order (layout next = alt-tab between the last two), the switcher OSD that
//! shows on every change, and clicking a layout in it.

use std::time::Duration;

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{lamp, plate, Ui, UiState};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::osd::{self, OpenParams, OsdKind};
use crate::services::{self, Services};
use crate::theme;

const OSD_VISIBLE_MS: u64 = 1300;
const OSD_FADE_MS: u64 = 200;

#[derive(Clone, Default)]
pub struct Layout {
    pub code: String,
    pub short: String,
    pub name: String,
}

#[derive(Default)]
pub struct LayoutState {
    pub layouts: Vec<Layout>,
    pub mru: Vec<usize>,
    pub current: usize,
    session_active: bool,
    session_pos: usize,
    held: bool,
    /// The OSD's hovered entry, -1 = none.
    hovered: Option<usize>,
}

impl LayoutState {
    fn ready(&self) -> bool {
        !self.layouts.is_empty()
    }
    fn switcher_items(&self) -> Vec<&Layout> {
        self.mru.iter().filter_map(|&i| self.layouts.get(i)).collect()
    }
    fn selected_pos(&self) -> usize {
        if self.session_active {
            return self.session_pos;
        }
        self.mru.iter().position(|&i| i == self.current).unwrap_or(0)
    }
}

fn move_to_front(list: &[usize], v: usize) -> Vec<usize> {
    std::iter::once(v).chain(list.iter().copied().filter(|&x| x != v)).collect()
}

/// loadProc: the configured layouts and the current one.
pub fn start(app: &mut App) {
    let cmd = format!("{}/.config/quickshell/bar/scripts/layouts.py", services::home());
    app.spawn_lines_tagged("layouts", &["sh", "-c", &cmd], |app, line| {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else { return };
        let Some(list) = v.get("layouts").and_then(|l| l.as_array()) else { return };
        let s = &mut app.svc.layout;
        s.layouts = list
            .iter()
            .map(|l| {
                let f = |k: &str| l.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
                Layout { code: f("code"), short: f("short"), name: f("name") }
            })
            .collect();
        s.current = v.get("current").and_then(|c| c.as_u64()).unwrap_or(0) as usize;
        let order: Vec<usize> = (0..s.layouts.len()).collect();
        s.mru = move_to_front(&order, s.current);
    });
}

fn activate(app: &App, index: usize) {
    services::mango_dispatch(app, &format!("switch_keyboard_layout,{}", index + 1));
}

/// The strip's layout label: the next layout in configured order.
pub fn cycle(app: &mut App) {
    let s = &app.svc.layout;
    if !s.ready() {
        return;
    }
    activate(app, (s.current + 1) % s.layouts.len());
}

/// `layout next`: alt-tab through the MRU list.
pub fn switch_next(app: &mut App) {
    let s = &mut app.svc.layout;
    if !s.ready() || s.mru.len() < 2 {
        return;
    }
    if !s.session_active {
        s.session_active = true;
        s.session_pos = 1;
    } else {
        s.session_pos = (s.session_pos + 1) % s.mru.len();
    }
    let target = s.mru[s.session_pos];
    activate(app, target);
    show_osd(app);
    commit_restart(app);
}

fn commit_restart(app: &mut App) {
    app.debounce("layout-commit", Duration::from_millis(OSD_VISIBLE_MS + OSD_FADE_MS + 250), |app| {
        let s = &mut app.svc.layout;
        s.mru = move_to_front(&s.mru, s.current);
        s.session_active = false;
        s.session_pos = 0;
        app.mark_all_dirty();
    });
}

/// Mango.onKeyboardLayoutChanged: a change from anywhere shows the OSD.
pub fn layout_changed(app: &mut App) {
    let name = app.svc.mango.keyboard_layout.clone();
    if name.is_empty() {
        return;
    }
    let s = &mut app.svc.layout;
    let Some(idx) = s.layouts.iter().position(|l| l.name == name) else { return };
    if idx == s.current && !s.session_active {
        return;
    }
    s.current = idx;
    if !s.session_active {
        show_osd(app);
        commit_restart(app);
    }
    app.mark_all_dirty();
}

/// selectPos(): a click on a layout in the OSD.
fn select_pos(app: &mut App, pos: usize) {
    let s = &mut app.svc.layout;
    if !s.ready() || pos >= s.mru.len() {
        return;
    }
    s.session_active = true;
    s.session_pos = pos;
    let target = s.mru[pos];
    activate(app, target);
    hide_osd(app);
    release(app);
}

fn release(app: &mut App) {
    app.svc.layout.held = false;
    commit_restart(app);
}

// ---- the OSD ----

const UI: f32 = 1.4;
fn px(v: f32) -> f32 {
    (v * UI).round()
}

struct M {
    tile: f32,
    code: f32,
    name: f32,
    name_w: f32,
    item_sp: f32,
    row_sp: f32,
    plate_pad: f32,
    panel_pad: f32,
}

const MET: fn() -> M = || M {
    tile: px(76.0),
    code: px(28.0),
    name: px(13.0),
    name_w: px(96.0),
    item_sp: px(8.0),
    row_sp: px(10.0),
    plate_pad: px(12.0),
    panel_pad: px(28.0),
};

fn code_of(l: &Layout) -> String {
    match l.code.as_str() {
        "us" => "АНГ".into(),
        "ru" => "РУС".into(),
        "es" => "ИСП".into(),
        _ => l.short.to_uppercase(),
    }
}

fn name_of(l: &Layout) -> String {
    match l.name.as_str() {
        "English (US)" => "АНГЛИЙСКАЯ".into(),
        "Russian" => "РУССКАЯ".into(),
        "Spanish" => "ИСПАНСКАЯ".into(),
        _ => l.name.to_uppercase(),
    }
}

/// The panel's size: the body Column plus panelPad.
fn panel_size(app: &mut App) -> (f32, f32) {
    let m = MET();
    let n = app.svc.layout.switcher_items().len() as f32;
    let cap = app.fonts.layout("РАСКЛАДКА", theme::bar_font(true), m.name, 1.0);
    let row_w = n * m.name_w + (n - 1.0).max(0.0) * m.row_sp;
    let plate_w = row_w + 2.0 * m.plate_pad;
    let name_h = app.fonts.layout("Н", theme::bar_font(true), m.name, 1.0).height().max(10.0);
    let entry_h = m.tile + m.item_sp + name_h;
    let plate_h = entry_h + 2.0 * m.plate_pad;
    let body_w = cap.width.max(plate_w);
    let body_h = cap.height() + m.item_sp + plate_h;
    (body_w + m.panel_pad, body_h + m.panel_pad)
}

fn show_osd(app: &mut App) {
    if app.svc.layout.switcher_items().is_empty() {
        return;
    }
    let (pw, ph) = panel_size(app);
    // implicitWidth: panel + 40; the panel centred in it.
    let (w, h) = ((pw + 40.0).ceil(), (ph + 40.0).ceil());
    osd::show(app, OpenParams { kind: OsdKind::Layout, size: (w as u32, h as u32), panel: (ac(w, pw), ac(h, ph), pw, ph), dim: None, keyboard: false, namespace: "quickshell", fade_ms: OSD_FADE_MS, min_scale: 0.94, pos: None });
    app.svc.layout.hovered = None;
    // hideTimer: fade after 1.3 s unless the pointer holds it.
    app.debounce("layout-osd-hide", Duration::from_millis(OSD_VISIBLE_MS), |app| {
        if !app.svc.layout.held {
            osd::hide(app, OsdKind::Layout);
        }
    });
}

fn hide_osd(app: &mut App) {
    app.svc.layout.hovered = None;
    osd::hide(app, OsdKind::Layout);
}

/// MouseArea.onEntered / onExited over the panel.
pub fn osd_hover(app: &mut App, inside: bool) {
    if inside {
        app.svc.layout.held = true;
        show_osd(app);
        app.cancel_timer("layout-commit");
    } else {
        app.svc.layout.hovered = None;
        release(app);
        app.debounce("layout-osd-hide", Duration::from_millis(OSD_VISIBLE_MS), |app| {
            if !app.svc.layout.held {
                osd::hide(app, OsdKind::Layout);
            }
        });
    }
}

pub fn osd_click(app: &mut App, action: Action, _button: u32) {
    if let Action::Card(pos) = action {
        select_pos(app, pos as usize);
    }
}

pub fn draw_osd<S: UiState>(ui: &mut Ui<S>, panel: (f32, f32, f32, f32), svc: &Services) {
    let m = MET();
    let t = ui.theme;
    let s = &svc.layout;
    let (px0, py0, pw, ph) = panel;
    ui.scene.rect(px0, py0, pw, ph, Color { a: 0.96, ..t.col_bg }, px(12.0), 0.0, Color::TRANSPARENT, true);
    let items = s.switcher_items();
    let n = items.len() as f32;
    let cap = ui.fonts.layout("РАСКЛАДКА", theme::bar_font(true), m.name, 1.0);
    let row_w = n * m.name_w + (n - 1.0).max(0.0) * m.row_sp;
    let plate_w = row_w + 2.0 * m.plate_pad;
    let name_h = ui.fonts.layout("Н", theme::bar_font(true), m.name, 1.0).height().max(10.0);
    let entry_h = m.tile + m.item_sp + name_h;
    let plate_h = entry_h + 2.0 * m.plate_pad;
    let (body_w, body_h) = (cap.width.max(plate_w), cap.height() + m.item_sp + plate_h);
    let bx = px0 + ac(pw, body_w);
    let by = py0 + ac(ph, body_h);
    ui.text(&cap, bx, by, t.col_dim, TextStyle::Normal);
    let plate_y = by + cap.height() + m.item_sp;
    plate(ui, bx, plate_y, plate_w, plate_h);
    let (rx, ry) = (bx + m.plate_pad, plate_y + m.plate_pad);

    // posAt(): the hovered entry, anywhere over the panel.
    let hovered = ui.card.pointer().filter(|&(x, y)| x >= px0 && x < px0 + pw && y >= py0 && y < py0 + ph).map(|(x, _)| {
        let i = ((x - rx) / (m.name_w + m.row_sp)).floor();
        i.clamp(0.0, (n - 1.0).max(0.0)) as usize
    });
    let selected = hovered.unwrap_or(s.selected_pos());
    for (i, l) in items.iter().enumerate() {
        let ex = rx + i as f32 * (m.name_w + m.row_sp);
        let sel = i == selected;
        let tx = ex + ac(m.name_w, m.tile);
        let (bg, run) = ui.card.color(0x100 + i as u32, if sel { t.col_accent } else { t.col_plate.lighter(1.25) }, 120, ui.now);
        ui.animating |= run;
        ui.scene.rect(tx, ry, m.tile, m.tile, bg, px(5.0), 0.0, Color::TRANSPARENT, true);
        if !sel {
            let lip = px(3.0);
            ui.scene.rect(tx, ry + m.tile - lip, m.tile, lip, Color::qt_rgba(0.0, 0.0, 0.0, 0.45), px(5.0), 0.0, Color::TRANSPARENT, true);
        }
        let code = ui.fonts.layout(&code_of(l), theme::bar_font(true), m.code, 0.0);
        let cy = ry + ac(m.tile, code.height()) + if sel { 0.0 } else { -2.0 };
        ui.text_of(i as u32, 0xE1, &code, tx + ac(m.tile, code.width), cy, if sel { t.col_bg } else { t.col_grey });
        // Lamp + name, centred under the tile.
        let key = theme::bar_font(true);
        let name = name_of(l);
        let full = ui.fonts.layout(&name, key, m.name, 1.0);
        let nl = ui.fonts.elide_right(&full, &name, key, m.name_w - 20.0, 1.0);
        let nw = full.width.min(m.name_w - 20.0);
        let row_w = 10.0 + px(5.0) + nw;
        let row_h = nl.height().max(10.0);
        let lx = ex + ac(m.name_w, row_w);
        let ly = ry + m.tile + m.item_sp;
        lamp(ui, 0x200 + i as u32, lx, ly + ac(row_h, 10.0), sel);
        ui.text_of(i as u32, 0xE2, &nl, lx + 10.0 + px(5.0), ly + ac(row_h, nl.height()), if sel { t.col_white } else { t.col_grey });
    }
    // One MouseArea over the panel; posAt() splits it into a column per
    // entry, the first and last reaching the panel's edges.
    let step = m.name_w + m.row_sp;
    for i in 0..items.len() {
        let x0 = if i == 0 { px0 } else { rx + i as f32 * step };
        let x1 = if i + 1 == items.len() { px0 + pw } else { rx + (i + 1) as f32 * step };
        ui.hits.push(Hit { x: x0, y: py0, w: x1 - x0, h: ph, action: Action::Card(i as u32) });
    }
}
