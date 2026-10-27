//! PowerState.qml + PowerOsd.qml: the power console (CTRL ALT P, and CTRL ALT
//! Del opens it on ВЫХОД). A character-cell TUI: five keys, the radio line,
//! and for logout/reboot/poweroff a five-second launch countdown that syncs
//! the disks on its third step and fires at zero; lock and suspend go at once.

use std::time::{Duration, Instant};

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{Ui, UiState};
use crate::color::Color;
use crate::osd::{self, OpenParams, OsdKind};
use crate::services::{self, Services};
use crate::text::FontKey;

struct Mode {
    k: &'static str,
    ru: &'static str,
    name: &'static str,
    slogan: &'static str,
    arm: bool,
    glyph: char,
    ask: &'static str,
    readback: &'static str,
    show: &'static str,
}

const MODES: [Mode; 5] = [
    Mode { k: "L", ru: "Д", name: "БЛОКИРОВКА", slogan: "ПОСТ СДАН.", arm: false, glyph: '\u{F033E}', ask: "Пост сдать, терминал под охрану.", readback: "", show: "loginctl lock-session" },
    Mode { k: "E", ru: "У", name: "ВЫХОД", slogan: "СМЕНА ОКОНЧЕНА.", arm: true, glyph: '\u{F0343}', ask: "Смену закончить, сеанс сдать.", readback: "Вас понял: смену сдаю.", show: "mmsg dispatch quit" },
    Mode { k: "U", ru: "Г", name: "СПЯЩИЙ РЕЖИМ", slogan: "ПЕРЕКУР.", arm: false, glyph: '\u{F04B2}', ask: "Разрешаю перекур.", readback: "", show: "systemctl suspend" },
    Mode { k: "R", ru: "К", name: "ПЕРЕЗАГРУЗКА", slogan: "ПОЕХАЛИ!", arm: true, glyph: '\u{F0709}', ask: "Повторный старт. Поехали!", readback: "Вас понял: к повторному старту готов.", show: "systemctl reboot" },
    Mode { k: "S", ru: "Ы", name: "ВЫКЛЮЧЕНИЕ", slogan: "ОТБОЙ, ТОВАРИЩ.", arm: true, glyph: '\u{F0425}', ask: "Приказ на отбой. Как поняли?", readback: "Вас понял: отбой.", show: "systemctl poweroff" },
];

/// The keys that live only on the keyboard: B (UEFI) and W (Windows).
struct Extra {
    ru: &'static str,
    name: &'static str,
    readback: &'static str,
    show: &'static str,
}

const EXTRA_B: Extra = Extra { ru: "И", name: "ПЕРЕЗАГРУЗКА В UEFI", readback: "Вас понял: иду в машинное отделение.", show: "systemctl reboot --firmware-setup" };
const EXTRA_W: Extra = Extra { ru: "Ц", name: "ПЕРЕЗАГРУЗКА В WINDOWS", readback: "Вас понял: ухожу на чужую ОС.", show: "boot-windows-next && systemctl reboot" };

const LITANY: [&str; 5] = ["КЛЮЧ НА СТАРТ", "ПРОТЯЖКА-1", "ПРОДУВКА", "КЛЮЧ НА ДРЕНАЖ", "ПУСК"];
const COUNTDOWN: f32 = 5.0;
const FADE_MS: u64 = 160;

const INK: Color = rgb(0xD8, 0xD8, 0xD0);
const DIM: Color = rgb(0x6E, 0x70, 0x66);
const RED: Color = rgb(0xC4, 0x2B, 0x1C);
const WHITE: Color = rgb(0xF2, 0xF2, 0xEC);
const BLACK: Color = rgb(0, 0, 0);
const GREY1: Color = rgb(0x1A, 0x1B, 0x18);
const GREY2: Color = rgb(0x2A, 0x2B, 0x27);
const GREY3: Color = rgb(0x45, 0x46, 0x3F);
const SHADE: Color = rgb(0x05, 0x05, 0x05);

const fn rgb(r: u8, g: u8, b: u8) -> Color {
    Color { r: r as f32 / 255.0, g: g as f32 / 255.0, b: b as f32 / 255.0, a: 1.0 }
}

const MONO: FontKey = FontKey { family: "JetBrainsMono Nerd Font Mono", bold: false, plain: true };
const MONO_BOLD: FontKey = FontKey { family: "JetBrainsMono Nerd Font Mono", bold: true, plain: true };

#[derive(Default)]
pub struct PowerState {
    pub open: bool,
    selected: usize,
    armed_key: String,
    armed_at: Option<Instant>,
    elapsed: f32,
    sync_done: bool,
    can_firmware: bool,
    windows_entry: String,
    uptime: f64,
    pending: String,
}

impl PowerState {
    fn armed(&self) -> bool {
        !self.armed_key.is_empty()
    }
    fn step(&self) -> usize {
        (LITANY.len() - 1).min(self.elapsed.floor().max(0.0) as usize)
    }
    fn seconds_left(&self) -> i32 {
        (COUNTDOWN - self.elapsed).ceil().max(0.0) as i32
    }
    fn armed_mode(&self) -> Option<&'static Mode> {
        MODES.iter().find(|m| m.k == self.armed_key)
    }
    fn armed_extra(&self) -> Option<&'static Extra> {
        match self.armed_key.as_str() {
            "B" => Some(&EXTRA_B),
            "W" => Some(&EXTRA_W),
            _ => None,
        }
    }
    fn armed_name(&self) -> &'static str {
        self.armed_mode().map(|m| m.name).or(self.armed_extra().map(|e| e.name)).unwrap_or("")
    }
    fn armed_ru(&self) -> &'static str {
        self.armed_mode().map(|m| m.ru).or(self.armed_extra().map(|e| e.ru)).unwrap_or("")
    }
    fn armed_show(&self) -> &'static str {
        self.armed_mode().map(|m| m.show).or(self.armed_extra().map(|e| e.show)).unwrap_or("")
    }
    fn step_action(&self, i: usize) -> String {
        match i {
            0 => "приказ принят".into(),
            1 => "журнал на ленту".into(),
            2 => "sync".into(),
            3 => "проверка блокировок".into(),
            _ => self.armed_show().into(),
        }
    }
    fn radio_who(&self) -> &'static str {
        if self.armed() { "КЕДР" } else { "ЗАРЯ" }
    }
    fn radio_text(&self) -> String {
        if self.armed() {
            let rb = self.armed_mode().map(|m| m.readback).or(self.armed_extra().map(|e| e.readback)).unwrap_or("");
            return format!("Заря, я Кедр. {rb}");
        }
        format!("Кедр, я Заря. {}", MODES[self.selected].ask)
    }
    fn available(&self, k: &str) -> bool {
        match k {
            "B" => self.can_firmware,
            "W" => !self.windows_entry.is_empty(),
            _ => MODES.iter().any(|m| m.k == k),
        }
    }
}

fn clock(secs: f64) -> String {
    let s = secs.max(0.0).floor() as i64;
    format!("{:02}:{:02}:{:02}", s / 3600, (s / 60) % 60, s % 60)
}

fn crt() -> String {
    format!("{}/.config/hypr/scripts/CrtOff.sh ", services::home())
}

/// The command a key runs (cmd), as PowerState builds it.
fn command(app: &App, k: &str) -> String {
    let home = services::home();
    match k {
        "L" => format!("{home}/.config/hypr/scripts/LockScreen.sh"),
        "E" => format!("{}mmsg dispatch quit", crt()),
        "U" => "systemctl suspend".into(),
        "R" => format!("{}systemctl reboot", crt()),
        "S" => format!("{}systemctl poweroff", crt()),
        "B" => format!("{}systemctl reboot --firmware-setup", crt()),
        "W" => format!(
            "if [ -x /usr/local/bin/boot-windows-next ]; then sudo -n /usr/local/bin/boot-windows-next; else pkexec efibootmgr --bootnext {} >/dev/null; fi && {}systemctl reboot",
            app.svc.power.windows_entry,
            crt()
        ),
        _ => String::new(),
    }
}

/// The probes PowerState runs once: firmware setup, a Windows boot entry.
pub fn start(app: &mut App) {
    app.spawn("power-firmware", &["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "CanRebootToFirmwareSetup"], |app, d| {
        app.svc.power.can_firmware = d.stdout.contains("\"yes\"");
    });
    app.spawn("power-efi", &["sh", "-c", "command -v efibootmgr >/dev/null && efibootmgr 2>/dev/null"], |app, d| {
        app.svc.power.windows_entry = windows_entry(&d.stdout);
    });
}

/// HackBGRT's loader first, else Windows Boot Manager: the BootXXXX number.
fn windows_entry(out: &str) -> String {
    let entry = |l: &str| l.get(4..8).filter(|h| h.chars().all(|c| c.is_ascii_hexdigit())).map(String::from);
    for l in out.lines() {
        if l.starts_with("Boot") && l.get(8..9) == Some("*") && l.to_lowercase().contains("\\efi\\hackbgrt\\loader.efi") {
            if let Some(e) = entry(l) {
                return e;
            }
        }
    }
    for l in out.lines() {
        if l.starts_with("Boot") {
            let rest = l.get(8..).unwrap_or("");
            let rest = rest.strip_prefix('*').unwrap_or(rest);
            if rest.trim_start().starts_with("Windows Boot Manager") && rest.starts_with(char::is_whitespace) {
                if let Some(e) = entry(l) {
                    return e;
                }
            }
        }
    }
    String::new()
}

fn read_uptime() -> Option<f64> {
    std::fs::read_to_string("/proc/uptime").ok()?.split_whitespace().next()?.parse().ok()
}

fn open(app: &mut App) {
    let p = &mut app.svc.power;
    p.uptime = read_uptime().unwrap_or(0.0);
    p.selected = 0;
    disarm(app);
    app.svc.power.open = true;
    show_osd(app);
    uptime_tick(app);
}

pub fn close(app: &mut App) {
    disarm(app);
    app.svc.power.open = false;
    osd::hide(app, OsdKind::Power);
}

pub fn toggle(app: &mut App) {
    if app.svc.power.open {
        close(app);
    } else {
        open(app);
    }
}

/// openOn(): opens with `k` selected (CTRL ALT Del: ВЫХОД); closes if open.
pub fn open_on(app: &mut App, k: &str) {
    if app.svc.power.open {
        close(app);
        return;
    }
    open(app);
    if let Some(i) = MODES.iter().position(|m| m.k == k) {
        app.svc.power.selected = i;
    }
    redraw(app);
}

/// PowerWidget.armEnd(): the logo card's keyboard path.
pub fn arm_end(app: &mut App, k: &str) {
    if !app.svc.power.open {
        open_on(app, k);
    }
    press(app, k);
}

fn press(app: &mut App, k: &str) {
    if !app.svc.power.available(k) {
        return;
    }
    if app.svc.power.armed() {
        if k == app.svc.power.armed_key {
            fire(app);
        }
        return;
    }
    if let Some(i) = MODES.iter().position(|m| m.k == k) {
        if !MODES[i].arm {
            let cmd = command(app, k);
            run(app, cmd);
            return;
        }
        app.svc.power.selected = i;
    }
    let p = &mut app.svc.power;
    p.armed_key = k.into();
    p.armed_at = Some(Instant::now());
    p.elapsed = 0.0;
    p.sync_done = false;
    armed_tick(app);
    redraw(app);
}

fn disarm(app: &mut App) {
    app.svc.power.armed_key.clear();
    app.svc.power.elapsed = 0.0;
    app.cancel_timer("power-armed");
    redraw(app);
}

fn fire(app: &mut App) {
    let k = app.svc.power.armed_key.clone();
    let cmd = command(app, &k);
    if !cmd.is_empty() {
        run(app, cmd);
    }
}

/// run(): close first, then 250 ms later hand the command to a detached shell.
fn run(app: &mut App, cmd: String) {
    app.svc.power.pending = cmd;
    close(app);
    app.debounce("power-settle", Duration::from_millis(250), |app| {
        let cmd = format!("( {} ) >/dev/null 2>&1 &", app.svc.power.pending);
        app.exec_detached(&["sh", "-c", &cmd]);
    });
}

/// The 100 ms countdown timer while armed.
fn armed_tick(app: &mut App) {
    let p = &mut app.svc.power;
    let Some(at) = p.armed_at.filter(|_| p.armed()) else { return };
    p.elapsed = at.elapsed().as_secs_f32();
    if p.step() >= 2 && !p.sync_done {
        p.sync_done = true;
        app.exec_detached(&["sync"]);
    }
    if app.svc.power.elapsed >= COUNTDOWN {
        fire(app);
        return;
    }
    redraw(app);
    app.debounce("power-armed", Duration::from_millis(100), armed_tick);
}

fn uptime_tick(app: &mut App) {
    if !app.svc.power.open {
        return;
    }
    let p = &mut app.svc.power;
    p.uptime = read_uptime().unwrap_or(p.uptime + 1.0);
    redraw(app);
    app.debounce("power-uptime", Duration::from_secs(1), uptime_tick);
}

fn redraw(app: &mut App) {
    if let Some(o) = app.osd_mut(OsdKind::Power) {
        o.win.dirty = true;
    }
}

// ---- the window ----

/// The cell grid: k scales it with the screen (13 x 29 px cells at 1440p).
struct Grid {
    cw: f32,
    ch: f32,
    px: f32,
    k: f32,
}

const WW: f32 = 113.0;
const WH: f32 = 21.0;

fn grid(sw: f32, sh: f32) -> Grid {
    let k = 0.6f32.max((sw / 2560.0).min(sh / 1440.0));
    Grid { cw: 13.0 * k, ch: 29.0 * k, px: (22.0 * k).round(), k }
}

fn show_osd(app: &mut App) {
    let Some((_, sw, sh)) = osd::focused_output(app) else { return };
    let g = grid(sw, sh);
    let (w, h) = (WW * g.cw, WH * g.ch);
    let (x, y) = (ac(sw, w), ac(sh, h));
    // The surface also carries the window's shadow (2 cells right, 1 down).
    let size = ((w + 2.0 * g.cw).ceil() as u32, (h + g.ch).ceil() as u32);
    osd::show(app, OpenParams { kind: OsdKind::Power, size, panel: (0.0, 0.0, w, h), dim: Some(Color::qt_rgba(0.0, 0.0, 0.0, 0.62)), keyboard: true, namespace: "quickshell:power", fade_ms: FADE_MS, min_scale: 0.97, fade_easing: crate::anim::Easing::OutCubic, pos: Some((x as i32, y as i32)) });
}

/// Cell: `text` on `bg` (one cell per character), the label centred
/// vertically, its letter spacing making every character exactly one cell.
#[allow(clippy::too_many_arguments)]
fn cell<S: UiState>(ui: &mut Ui<S>, g: &Grid, id: u32, x: f32, y: f32, text: &str, fg: Color, bg: Option<Color>, bold: bool) -> f32 {
    let n = text.encode_utf16().count() as f32;
    let w = n * g.cw;
    if let Some(bg) = bg {
        ui.scene.fill(x, y, w, g.ch, bg);
    }
    let key = if bold { MONO_BOLD } else { MONO };
    let m_adv = ui.fonts.layout("M", MONO, g.px, 0.0).adv;
    let line = ui.fonts.layout(text, key, g.px, g.cw - m_adv);
    ui.text_of(id, 0xF0, &line, x, y + ac(g.ch, line.height()), fg);
    w
}

pub fn draw_osd<S: UiState>(ui: &mut Ui<S>, panel: (f32, f32, f32, f32), svc: &Services) {
    let (x0, y0, w, h) = panel;
    let g = grid_from_width(w);
    let p = &svc.power;
    let armed = p.armed();
    let (cw, ch) = (g.cw, g.ch);

    ui.scene.fill(x0 + 2.0 * cw, y0 + ch, w, h, SHADE);
    ui.scene.fill(x0, y0, w, h, BLACK);
    // The title bar.
    ui.scene.fill(x0, y0, w, ch, if armed { RED } else { GREY2 });
    let mut cx = x0;
    cx += cell(ui, &g, 1, cx, y0, " \u{f135} ПУСК ", if armed { RED } else { WHITE }, Some(if armed { WHITE } else { RED }), true);
    cx += 2.0 * cw;
    let title = if armed { format!("ПЯТИСЕКУНДНАЯ ГОТОВНОСТЬ  ·  {}", p.armed_name()) } else { "ПУЛЬТ УПРАВЛЕНИЯ ПИТАНИЕМ".into() };
    cell(ui, &g, 2, cx, y0, &title, if armed { WHITE } else { INK }, None, armed);
    let (l, r) = if armed {
        ("ДО ПУСКА  ".to_string(), format!("Т−00:00:0{}", p.seconds_left()))
    } else {
        ("ВРЕМЯ РАБОТЫ ".to_string(), format!("Т+{}", clock(p.uptime)))
    };
    let rw = (l.encode_utf16().count() + r.encode_utf16().count()) as f32 * cw;
    let rx = x0 + w - rw;
    let lw = cell(ui, &g, 3, rx, y0, &l, if armed { WHITE } else { DIM }, None, armed);
    cell(ui, &g, 4, rx + lw, y0, &r, WHITE, None, true);

    // The frame: two 1 px rules and the line over the radio.
    let frame = if armed { GREY3 } else { DIM };
    ui.scene.rect(x0 + cw / 2.0 - 2.0, y0 + 1.5 * ch - 2.0, w - cw + 4.0, (WH - 1.0) * ch - ch + 4.0, Color::TRANSPARENT, 0.0, 1.0, frame, false);
    ui.scene.rect(x0 + cw / 2.0 + 2.0, y0 + 1.5 * ch + 2.0, w - cw - 4.0, (WH - 1.0) * ch - ch - 4.0, Color::TRANSPARENT, 0.0, 1.0, frame, false);
    ui.scene.fill(x0 + cw / 2.0 + 2.0, y0 + 17.5 * ch, w - cw - 4.0, 1.0, frame);

    // The five keys.
    for (i, m) in MODES.iter().enumerate() {
        let sel = if armed { p.armed_key == m.k } else { p.selected == i };
        let hot = armed && sel;
        let off = armed && !sel;
        let bg = if hot { RED } else if sel { INK } else { BLACK };
        let fg = if hot { WHITE } else if sel { BLACK } else if off { GREY3 } else { INK };
        let fg2 = if hot { WHITE } else if sel { BLACK } else if off { GREY3 } else { DIM };
        let (bx, by, bw, bh) = (x0 + (4.0 + 21.0 * i as f32) * cw, y0 + 3.0 * ch, 19.0 * cw, 12.0 * ch);
        let id = 0x100 * (i as u32 + 1);
        ui.scene.fill(bx + 2.0 * cw, by + ch, bw, bh, GREY1);
        ui.scene.fill(bx, by, bw, bh, bg);
        let border = if hot { RED } else if sel { INK } else if off { GREY2 } else { DIM };
        ui.scene.rect(bx + cw / 2.0, by + ch / 2.0, bw - cw, bh - ch, Color::TRANSPARENT, 0.0, 1.0, border, false);
        if !hot {
            let gl = ui.fonts.layout(&m.glyph.to_string(), crate::theme::bar_font(false), (104.0 * g.k).round(), 0.0);
            let (tw, th) = (bw - 2.0 * cw, 5.0 * ch);
            ui.scene.save();
            if !(sel || off) {
                ui.scene.multiply_opacity(0.8);
            }
            ui.text_of(id, 0xF1, &gl, bx + cw + (tw - gl.adv) / 2.0, by + ch + (th - gl.height()) / 2.0, if sel || off { fg } else { INK });
            ui.scene.restore();
        } else {
            big_digit(ui, &g, bx + 6.0 * cw, by + ch, p.seconds_left());
            cell(ui, &g, id + 1, bx + 11.0 * cw, by + 5.0 * ch, "с", WHITE, None, true);
        }
        let n = m.name.encode_utf16().count() as f32;
        cell(ui, &g, id + 2, bx + ((19.0 - n) / 2.0).floor() * cw, by + 7.0 * ch, m.name, fg, None, true);
        let n = m.slogan.encode_utf16().count() as f32;
        cell(ui, &g, id + 3, bx + ((19.0 - n) / 2.0).floor() * cw, by + 8.0 * ch, m.slogan, if sel { fg } else { fg2 }, None, false);
        let timing = if hot { format!("через {} с", p.seconds_left()) } else if m.arm { "отсчёт 5 с".into() } else { "сразу".into() };
        let n = timing.encode_utf16().count() as f32;
        let mut tx = bx + ((19.0 - (7.0 + n)) / 2.0).floor() * cw;
        let key_bg = if hot { WHITE } else if sel { BLACK } else { GREY2 };
        let key_fg = if hot { RED } else if sel { WHITE } else if off { GREY3 } else { INK };
        tx += cell(ui, &g, id + 4, tx, by + 10.0 * ch, &format!(" {}/{} ", m.k, m.ru), key_fg, Some(key_bg), true);
        tx += 2.0 * cw;
        cell(ui, &g, id + 5, tx, by + 10.0 * ch, &timing, if sel { fg } else { fg2 }, None, hot);
        ui.hits.push(Hit { x: bx, y: by, w: bw, h: bh, action: Action::Card(i as u32) });
    }

    // The radio line and what Enter runs, or the launch litany.
    let (ix, iy, iw) = (x0 + 2.0 * cw, y0 + 18.0 * ch, w - 4.0 * cw);
    if !armed {
        let mut rx = ix + cw;
        rx += cell(ui, &g, 0x10, rx, iy, p.radio_who(), WHITE, None, true);
        rx += 2.0 * cw;
        cell(ui, &g, 0x11, rx, iy, &p.radio_text(), INK, None, false);
        let show = MODES[p.selected].show;
        let tw = ("ENTER › ".encode_utf16().count() + show.encode_utf16().count()) as f32 * cw;
        let ex = ix + iw - tw;
        let lw = cell(ui, &g, 0x12, ex, iy, "ENTER › ", DIM, None, false);
        cell(ui, &g, 0x13, ex + lw, iy, show, INK, None, false);
    } else {
        let mut lx = ix;
        for (i, step) in LITANY.iter().enumerate() {
            let done = i < p.step();
            let now = i == p.step();
            let mark = if done { " ✓ " } else if now { " ▶ " } else { " ○ " };
            let fg = if now { WHITE } else if done { INK } else { DIM };
            lx += cell(ui, &g, 0x20 + i as u32, lx, iy, &format!("{mark}{step} "), fg, if now { Some(RED) } else { None }, now);
            if i < LITANY.len() - 1 {
                lx += cell(ui, &g, 0x30 + i as u32, lx, iy, " › ", GREY3, None, false);
            }
        }
        let action = p.step_action(p.step());
        let tw = ("ЭВМ › ".encode_utf16().count() + action.encode_utf16().count()) as f32 * cw;
        let ex = ix + iw - tw;
        let lw = cell(ui, &g, 0x14, ex, iy, "ЭВМ › ", DIM, None, false);
        cell(ui, &g, 0x15, ex + lw, iy, &action, INK, None, false);
        let mut rx = x0 + 3.0 * cw;
        rx += cell(ui, &g, 0x16, rx, y0 + 19.0 * ch, p.radio_who(), WHITE, None, true);
        rx += 2.0 * cw;
        cell(ui, &g, 0x17, rx, y0 + 19.0 * ch, &p.radio_text(), INK, None, false);
    }

    // The key hints on the bottom rule, and the motto.
    let hints: Vec<(String, &str)> = if armed {
        vec![(format!("{}/{} · ENTER", p.armed_key, p.armed_ru()), "немедленно"), ("ESC".into(), "отставить")]
    } else {
        let mut v = vec![("← →".to_string(), "выбор"), ("ENTER".into(), "исполнить"), ("ESC".into(), "вольно")];
        if p.can_firmware {
            v.push(("B/И".into(), "в UEFI"));
        }
        if !p.windows_entry.is_empty() {
            v.push(("W/Ц".into(), "в Windows — перебежчик?"));
        }
        v
    };
    let hy = y0 + 20.0 * ch;
    let mut hx = x0 + 3.0 * cw;
    hx += cell(ui, &g, 0x40, hx, hy, " ", INK, Some(BLACK), false);
    for (i, (k, d)) in hints.iter().enumerate() {
        let id = 0x50 + 3 * i as u32;
        if i > 0 {
            hx += cell(ui, &g, id, hx, hy, "   ", INK, Some(BLACK), false);
        }
        hx += cell(ui, &g, id + 1, hx, hy, k, if armed { WHITE } else { INK }, Some(BLACK), true);
        hx += cell(ui, &g, id + 2, hx, hy, &format!(" {d}"), if armed { INK } else { DIM }, Some(BLACK), false);
    }
    cell(ui, &g, 0x41, hx, hy, " ", INK, Some(BLACK), false);
    let motto = " «КОСМОС НАШ» ";
    let n = motto.encode_utf16().count() as f32;
    cell(ui, &g, 0x42, x0 + w - (3.0 + n) * cw, hy, motto, DIM, Some(BLACK), false);
    let _ = h;
}

/// The grid from the window's width (the window is 113 cells wide).
fn grid_from_width(w: f32) -> Grid {
    let k = w / WW / 13.0;
    Grid { cw: 13.0 * k, ch: 29.0 * k, px: (22.0 * k).round(), k }
}

/// BigDigit: the countdown in 4 x 5 white cells.
fn big_digit<S: UiState>(ui: &mut Ui<S>, g: &Grid, x: f32, y: f32, digit: i32) {
    const TABLE: [[&str; 5]; 6] = [
        ["####", "#  #", "#  #", "#  #", "####"],
        ["  ##", "   #", "   #", "   #", "   #"],
        ["####", "   #", "####", "#   ", "####"],
        ["####", "   #", "####", "   #", "####"],
        ["#  #", "#  #", "####", "   #", "   #"],
        ["####", "#   ", "####", "   #", "####"],
    ];
    let Some(rows) = TABLE.get(digit.clamp(0, 5) as usize) else { return };
    for (r, row) in rows.iter().enumerate() {
        for (c, b) in row.bytes().enumerate() {
            if b == b'#' {
                ui.scene.fill(x + c as f32 * g.cw, y + r as f32 * g.ch, g.cw, g.ch, WHITE);
            }
        }
    }
}

pub fn osd_click(app: &mut App, action: Action, _button: u32) {
    if let Action::Card(i) = action {
        if let Some(m) = MODES.get(i as usize) {
            press(app, m.k);
        }
    }
}

/// MouseArea.onEntered over a key: it becomes the selection.
pub fn hovered(app: &mut App, action: Option<Action>) {
    if let Some(Action::Card(i)) = action {
        if !app.svc.power.armed() && (i as usize) < MODES.len() {
            app.svc.power.selected = i as usize;
            redraw(app);
        }
    }
}

/// Keys.onPressed: Esc, Enter, the arrows/Tab, and the letters by scan code
/// (the same physical keys on every layout).
pub fn key(app: &mut App, sym: smithay_client_toolkit::seat::keyboard::Keysym, scan: u32, shift: bool) {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    let by_key = |sc: u32| match sc {
        46 => Some("L"),
        26 => Some("E"),
        30 => Some("U"),
        27 => Some("R"),
        39 => Some("S"),
        56 => Some("B"),
        25 => Some("W"),
        _ => None,
    };
    let armed = app.svc.power.armed();
    match sym {
        Keysym::Escape => {
            if armed {
                disarm(app);
            } else {
                close(app);
            }
        }
        Keysym::Return | Keysym::KP_Enter => {
            if armed {
                fire(app);
            } else {
                let k = MODES[app.svc.power.selected].k;
                press(app, k);
            }
        }
        Keysym::Left | Keysym::ISO_Left_Tab if !armed => {
            app.svc.power.selected = (app.svc.power.selected + 4) % 5;
            redraw(app);
        }
        Keysym::Tab if !armed && shift => {
            app.svc.power.selected = (app.svc.power.selected + 4) % 5;
            redraw(app);
        }
        Keysym::Right | Keysym::Tab if !armed => {
            app.svc.power.selected = (app.svc.power.selected + 1) % 5;
            redraw(app);
        }
        _ => {
            if let Some(k) = by_key(scan) {
                press(app, k);
            }
        }
    }
}
