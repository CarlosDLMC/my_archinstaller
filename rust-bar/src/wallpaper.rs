//! WallpaperState + WallpaperOsd + WallpaperReveal: the wallpaper carousel
//! (SUPER W) - sheared cards in a strip, folder tabs or a search line above,
//! the centred card's name below - and, after a pick, the reveal: the new
//! picture opening as a sheared band across every screen before
//! wallpapers.py applies it.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use smithay_client_toolkit::{
    shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer},
    shell::WaylandSurface,
};
use wayland_client::protocol::wl_output::WlOutput;

use crate::anim::{ease, Easing};
use crate::app::{App, Mods, Win};
use crate::bar::{ac, Action};
use crate::cards::Ui;
use crate::color::Color;
use crate::gpu::{Gpu, Scene, TextStyle, Xf};
use crate::osd::{self, OpenParams, OsdKind, OsdState};
use crate::services::{self, Services};
use crate::text::FontKey;
use crate::theme;

const FADE_MS: u64 = 160;
const MOVE_MS: u64 = 220;
const SKEW: f32 = -0.35;
const CENTRE_SCALE: f32 = 1.1;
const FAR_SCALE: f32 = 0.74;
const UI: f32 = 1.35;
const REVEAL_MS: u64 = 1100;
const CONTENT: FontKey = FontKey { family: theme::FONT_CONTENT, bold: false, plain: false };
pub const CARD: u32 = 0x1_0000;
pub const TAB: u32 = 0x2_0000;
/// The dim's MouseArea, under everything (a Hover: no hand cursor).
const DIM: u32 = 0x3_0000;

fn px(v: f32) -> f32 {
    (v * UI).round()
}

#[derive(Clone, Debug, Default)]
pub struct Item {
    pub id: String,
    pub name: String,
    pub dir: String,
    pub kind: String,
    pub src: String,
    pub thumb: String,
}

#[derive(Clone, Copy)]
struct Tex {
    id: u32,
    w: u32,
    h: u32,
}

/// A decode on its way to the decode thread: once set, it is skipped or its
/// result dropped (an Image that goes away cancels its request).
type Cancel = Arc<AtomicBool>;

/// QSmoothedAnimation, which ListView moves its highlight with: velocity
/// 400 px/s (highlightMoveVelocity) and highlightMoveDuration, the shorter
/// wins (qquicksmoothedanimation.cpp, recalc() and easeFollow(), reversingMode
/// Eased). It speeds up, then slows down onto the target, and a new target
/// mid-move keeps the speed it has instead of starting from rest. Checked
/// against a real ListView's contentX: two quick Rights and a Right-Left
/// reversal land on every sample to 0.01 px.
#[derive(Clone, Copy, Debug)]
struct Smoothed {
    /// This leg: from where, to where, since when, and towards smaller values.
    from: f64,
    to: f64,
    start: Option<Instant>,
    invert: bool,
    /// Its distance s and start velocity vi; acceleration a until tp (where
    /// it has velocity vp and distance sp), then braking at a until tf.
    s: f64,
    vi: f64,
    a: f64,
    tp: f64,
    vp: f64,
    sp: f64,
    tf: f64,
}

impl Smoothed {
    const VELOCITY: f64 = 400.0;

    /// At rest at `v` (also jump(): highlightMoveDuration 0 is a jump).
    fn new(v: f32) -> Smoothed {
        let v = v as f64;
        Smoothed { from: v, to: v, start: None, invert: false, s: 0.0, vi: 0.0, a: 0.0, tp: 0.0, vp: 0.0, sp: 0.0, tf: 0.0 }
    }

    /// easeFollow(): distance covered and velocity, t seconds into the leg.
    fn leg(&self, t: f64) -> (f64, f64) {
        if t < self.tp {
            (0.5 * self.a * t * t + self.vi * t, self.vi + t * self.a)
        } else if t < self.tf {
            let u = t - self.tp;
            (self.sp - 0.5 * self.a * u * u + self.vp * u, self.vp - u * self.a)
        } else {
            (self.s, 0.0)
        }
    }

    /// The value now, and the velocity along the leg's direction.
    fn state(&self, now: Instant) -> (f64, f64) {
        let Some(start) = self.start else { return (self.to, 0.0) };
        let (d, v) = self.leg(now.saturating_duration_since(start).as_secs_f64());
        (if self.invert { self.from - d } else { self.from + d }, v)
    }

    fn get(&self, now: Instant) -> f32 {
        self.state(now).0 as f32
    }

    fn target(&self) -> f32 {
        self.to as f32
    }

    fn running(&self, now: Instant) -> bool {
        self.start.map_or(false, |s| now.saturating_duration_since(s).as_secs_f64() < self.tf)
    }

    /// restart() with a new target: init() and recalc().
    fn set(&mut self, to: f32, now: Instant) {
        let to = to as f64;
        if to == self.to {
            return;
        }
        let (from, v) = self.state(now);
        self.to = to;
        if to == from {
            self.start = None;
            return;
        }
        // Turning back: the speed it has now points the other way.
        let reversed = v != 0.0 && (!self.invert == (from - to > 0.0));
        let vi = if reversed { -v } else { v };
        let invert = to < from;
        let s = (to - from).abs();
        let tf = (s / Self::VELOCITY).min(MOVE_MS as f64 / 1000.0);
        let (c1, c2, c3) = (0.25 * tf * tf, 0.5 * vi * tf - s, -0.25 * vi * vi);
        let a = (-c2 + (c2 * c2 - 4.0 * c1 * c3).sqrt()) / (2.0 * c1);
        let tp = 0.5 * tf - 0.5 * vi / a;
        let vp = a * tp + vi;
        let sp = 0.5 * a * tp * tp + vi * tp;
        *self = Smoothed { from, to, start: Some(now), invert, s, vi, a, tp, vp, sp, tf };
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Default)]
enum Pending {
    #[default]
    Current,
    First,
    Keep,
}

/// One screen's reveal window.
pub struct RevealWin {
    pub output: WlOutput,
    pub win: Win,
    tex: Option<Tex>,
    reported: bool,
}

#[derive(Default)]
pub struct Wall {
    pub open: bool,
    pub items: Vec<Item>,
    ready: HashSet<String>,
    failed: HashSet<String>,
    pub current_id: String,
    picked_id: String,
    scanning: bool,
    scanned: bool,
    navigated: bool,
    rescan: bool,
    pub folder_index: usize,
    pub filter: String,
    cursor: usize,
    // The view: list.currentIndex, contentX and what reselect() keeps.
    index: usize,
    view_x: Option<Smoothed>,
    pending: Pending,
    centred_id: String,
    wheel_acc: f32,
    tab_acc: f32,
    tab_scroll: f32,
    textures: HashMap<String, Tex>,
    loading: HashMap<String, Cancel>,
    // The reveal.
    reveal_item: Option<Item>,
    pub reveal_phase: &'static str,
    reveal_start: Option<Instant>,
    reveal_ready: usize,
    /// This reveal's decodes: one still running for an earlier pick must not
    /// land in its windows (they are found by index).
    reveal_cancel: Option<Cancel>,
}

pub struct Folder {
    pub dir: Option<String>,
    pub label: String,
    pub count: usize,
}

fn home() -> String {
    services::home()
}

fn wall_dir() -> String {
    format!("{}/Pictures/wallpapers", home())
}

fn script() -> String {
    format!("{}/.config/quickshell/bar/scripts/wallpapers.py", home())
}

fn thumb_dir() -> String {
    let cache = std::env::var("XDG_CACHE_HOME").unwrap_or_else(|_| format!("{}/.cache", home()));
    format!("{cache}/quickshell/wall-thumbs")
}

/// The file behind a wallpapers.py URL. file_url() percent-encodes every
/// byte of the path but letters, digits, "_.-~" and "/" (a space, Cyrillic,
/// "#", "%"); QML's Image gets them decoded by QUrl, so decode them back to
/// the path's own bytes.
fn path_of(url: &str) -> std::path::PathBuf {
    use std::os::unix::ffi::OsStringExt;
    let s = url.strip_prefix("file://").unwrap_or(url).as_bytes();
    let hex = |b: u8| (b as char).to_digit(16);
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        match (s[i], s.get(i + 1).and_then(|&b| hex(b)), s.get(i + 2).and_then(|&b| hex(b))) {
            (b'%', Some(hi), Some(lo)) => {
                out.push((hi * 16 + lo) as u8);
                i += 3;
            }
            (b, _, _) => {
                out.push(b);
                i += 1;
            }
        }
    }
    std::ffi::OsString::from_vec(out).into()
}

impl Wall {
    pub fn folders(&self) -> Vec<Folder> {
        let mut out = vec![Folder { dir: None, label: "все".into(), count: self.items.len() }];
        let root = wall_dir();
        let root_label = root.rsplit('/').next().unwrap_or("").to_string();
        for it in &self.items {
            match out.iter_mut().skip(1).find(|f| f.dir.as_deref() == Some(&it.dir)) {
                Some(f) => f.count += 1,
                None => out.push(Folder { dir: Some(it.dir.clone()), label: if it.dir.is_empty() { root_label.clone() } else { it.dir.clone() }, count: 1 }),
            }
        }
        out
    }
    fn has_folders(&self) -> bool {
        self.folders().len() > 2
    }
    /// What the strip shows: the search's matches, else the chosen folder.
    pub fn strip(&self) -> Vec<&Item> {
        let f = self.filter.trim().to_lowercase();
        if !f.is_empty() {
            return self.items.iter().filter(|it| format!("{}/{}", it.dir, it.name).to_lowercase().contains(&f)).collect();
        }
        let folders = self.folders();
        if self.folder_index == 0 || self.folder_index >= folders.len() {
            return self.items.iter().collect();
        }
        let d = folders[self.folder_index].dir.clone();
        self.items.iter().filter(|it| Some(&it.dir) == d.as_ref()).collect()
    }
    fn folder_of(&self, id: &str) -> usize {
        let folders = self.folders();
        let Some(it) = self.items.iter().find(|it| it.id == id) else { return 0 };
        for (j, f) in folders.iter().enumerate().skip(1) {
            if f.dir.as_deref() == Some(&it.dir) {
                return if self.has_folders() { j } else { 0 };
            }
        }
        0
    }
    /// thumbUrl(): the thumbnail once made; else the picture (not a video, not failed).
    fn thumb_path(&self, it: &Item) -> Option<std::path::PathBuf> {
        if self.ready.contains(&it.id) {
            return Some(path_of(&it.thumb));
        }
        if it.kind == "video" || self.failed.contains(&it.id) {
            return None;
        }
        Some(path_of(&it.src))
    }
}

// ---- the scan ----

pub fn start(app: &mut App) {
    refresh(app);
}

fn refresh(app: &mut App) {
    if app.is_running("wall-scan") {
        app.svc.wall.rescan = true;
        return;
    }
    app.svc.wall.scanning = true;
    let (s, w, t) = (script(), wall_dir(), thumb_dir());
    app.spawn_stream("wall-scan", &[&s, "scan", &w, &t], scan_line, None, Some(|app: &mut App| {
        app.svc.wall.scanning = false;
        if std::mem::take(&mut app.svc.wall.rescan) {
            refresh(app);
        }
        redraw(app);
    }));
}

fn scan_line(app: &mut App, line: &str) {
    if line.starts_with('{') {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else { return };
        let s = |o: &serde_json::Value, k: &str| o.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
        let items: Vec<Item> = v
            .get("items")
            .and_then(|x| x.as_array())
            .map(|a| a.iter().map(|o| Item { id: s(o, "id"), name: s(o, "name"), dir: s(o, "dir"), kind: s(o, "kind"), src: s(o, "src"), thumb: s(o, "thumb") }).collect())
            .unwrap_or_default();
        let ready: HashSet<String> = v.get("items").and_then(|x| x.as_array()).map(|a| a.iter().filter(|o| o.get("ready").and_then(|r| r.as_bool()).unwrap_or(false)).map(|o| s(o, "id")).collect()).unwrap_or_default();
        let w = &mut app.svc.wall;
        let same = items.len() == w.items.len() && items.iter().zip(&w.items).all(|(a, b)| a.id == b.id && a.thumb == b.thumb && a.name == b.name);
        if !same {
            w.items = items;
        }
        w.ready = ready;
        w.failed.clear();
        w.scanned = true;
        let cur = s(&v, "current");
        if cur != w.current_id && w.picked_id.is_empty() {
            w.current_id = cur.clone();
            if w.open && !w.navigated {
                w.folder_index = w.folder_of(&cur);
                w.pending = Pending::Current;
            }
        }
        if !same || w.pending == Pending::Current {
            reselect(app);
        }
    } else if let Some(id) = line.strip_prefix("thumb ") {
        app.svc.wall.ready.insert(id.to_string());
        // The card had the picture (or was decoding it); the thumbnail replaces it.
        forget_card(app, id);
    } else if let Some(id) = line.strip_prefix("fail ") {
        app.svc.wall.failed.insert(id.to_string());
        // thumbUrl() is "" now: the Image lets go of the original too.
        forget_card(app, id);
    }
    redraw(app);
}

/// wallust-colors.json changed: a new palette after a pick.
pub fn palette_changed(app: &mut App) {
    app.debounce("wall-palette", Duration::from_millis(400), refresh);
    if app.svc.wall.reveal_phase == "holding" {
        app.debounce("wall-reveal-drop", Duration::from_millis(250), end_reveal);
    }
}

// ---- open / close / navigation ----

pub fn toggle(app: &mut App) {
    if app.svc.wall.open {
        close(app);
    } else {
        open(app);
    }
}

pub fn open(app: &mut App) {
    if app.svc.wall.open {
        return;
    }
    let w = &mut app.svc.wall;
    w.filter.clear();
    w.cursor = 0;
    w.picked_id.clear();
    w.navigated = false;
    w.folder_index = w.folder_of(&w.current_id.clone());
    w.open = true;
    w.pending = Pending::Current;
    osd::show(app, OpenParams { kind: OsdKind::Wallpaper, size: (0, 0), panel: (0.0, 0.0, 0.0, 0.0), dim: None, keyboard: true, namespace: "quickshell:wallpaper", fade_ms: FADE_MS, min_scale: 1.0, fade_easing: Easing::Linear, pos: None, fill: true, output: None });
    if let Some(o) = app.osd_mut(OsdKind::Wallpaper) {
        o.st.reset_numbers();
    }
    reselect(app);
    refresh(app);
}

pub fn close(app: &mut App) {
    if !app.svc.wall.open {
        return;
    }
    app.svc.wall.open = false;
    // Nothing decoded now would be shown: the queue is not worked through.
    for (_, f) in app.svc.wall.loading.drain() {
        f.store(true, Ordering::Relaxed);
    }
    osd::hide(app, OsdKind::Wallpaper);
    app.after(Duration::from_millis(FADE_MS + 20), drop_textures);
}

fn drop_textures(app: &mut App) {
    if app.svc.wall.open {
        return;
    }
    let ids: Vec<u32> = app.svc.wall.textures.drain().map(|(_, t)| t.id).collect();
    for (_, f) in app.svc.wall.loading.drain() {
        f.store(true, Ordering::Relaxed);
    }
    if let Some(gpu) = app.gpu.as_mut() {
        for id in ids {
            gpu.drop_image(id);
        }
    }
    unsafe { libc::malloc_trim(0) };
}

fn redraw(app: &mut App) {
    if let Some(o) = app.osd_mut(OsdKind::Wallpaper) {
        o.win.dirty = true;
    }
    if app.svc.wall.open {
        load_visible(app);
    }
}

struct Geo {
    w: f32,
    h: f32,
    card_w: f32,
    card_h: f32,
    spacing: f32,
    list_h: f32,
    list_y: f32,
    begin: f32,
}

fn geo(w: f32, h: f32) -> Geo {
    let card_h = (h * 0.42).round();
    let card_w = (card_h * 0.72).round();
    let list_h = (card_h * 1.4).round();
    Geo { w, h, card_w, card_h, spacing: (card_w * 0.05).round(), list_h, list_y: ac(h, list_h), begin: w / 2.0 - card_w / 2.0 }
}

fn screen() -> (f32, f32) {
    (2560.0, 1440.0)
}

fn screen_of(app: &App) -> (f32, f32) {
    app.osd(OsdKind::Wallpaper).map(|o| (o.win.width as f32, o.win.height as f32)).filter(|s| s.0 > 0.0).or(osd::focused_output(app).map(|(_, w, h)| (w, h))).unwrap_or(screen())
}

/// contentX for an index under StrictlyEnforceRange.
fn content_x(g: &Geo, i: usize) -> f32 {
    i as f32 * (g.card_w + g.spacing) - g.begin
}

/// reselect(): which card is centred after the strip changed.
fn reselect(app: &mut App) {
    let w = &app.svc.wall;
    let strip = w.strip();
    if strip.is_empty() {
        app.svc.wall.pending = Pending::Keep;
        return;
    }
    let idx = |id: &str| strip.iter().position(|it| it.id == id);
    let i = match w.pending {
        Pending::First => 0,
        p => {
            let mut i = if p == Pending::Keep { idx(&w.centred_id) } else { None };
            if i.is_none() {
                i = idx(&w.current_id);
            }
            i.unwrap_or(0)
        }
    };
    app.svc.wall.pending = Pending::Keep;
    jump(app, i);
}

/// jump(): straight there, no animation.
fn jump(app: &mut App, i: usize) {
    let (sw, sh) = screen_of(app);
    let g = geo(sw, sh);
    let w = &mut app.svc.wall;
    w.index = i;
    w.view_x = Some(Smoothed::new(content_x(&g, i)));
    set_centred(app);
    if let Some(o) = app.osd_mut(OsdKind::Wallpaper) {
        o.st.reset_numbers();
    }
    redraw(app);
}

fn set_centred(app: &mut App) {
    let w = &mut app.svc.wall;
    if let Some(id) = w.strip().get(w.index).map(|it| it.id.clone()) {
        w.centred_id = id;
    }
}

/// The highlight moves there in 220 ms (a SmoothedAnimation).
fn move_to(app: &mut App, i: usize) {
    let (sw, sh) = screen_of(app);
    let g = geo(sw, sh);
    let w = &mut app.svc.wall;
    w.index = i;
    let target = content_x(&g, i);
    let now = Instant::now();
    match w.view_x.as_mut() {
        Some(a) => a.set(target, now),
        None => w.view_x = Some(Smoothed::new(target)),
    }
    set_centred(app);
    redraw(app);
    // Once the strip has come to rest, the cards it passed are let go.
    app.debounce("wall-settle", Duration::from_millis(MOVE_MS + 10), |app| {
        if app.svc.wall.open {
            load_visible(app);
        }
    });
}

fn step(app: &mut App, delta: i64) {
    let n = app.svc.wall.strip().len() as i64;
    if n == 0 {
        return;
    }
    app.svc.wall.navigated = true;
    let i = ((app.svc.wall.index as i64 + delta) % n + n) % n;
    move_to(app, i as usize);
}

fn go_to(app: &mut App, i: i64) {
    let n = app.svc.wall.strip().len() as i64;
    if n == 0 {
        return;
    }
    app.svc.wall.navigated = true;
    move_to(app, i.clamp(0, n - 1) as usize);
}

fn random(app: &mut App) {
    let n = app.svc.wall.strip().len();
    if n < 2 {
        return;
    }
    let cur = app.svc.wall.index;
    let mut seed = Instant::now().elapsed().as_nanos() as usize ^ std::process::id() as usize;
    let mut i = cur;
    while i == cur {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        i = (seed >> 33) % n;
    }
    go_to(app, i as i64);
}

/// IpcHandler next()/prev(): open, or step when open.
pub fn next(app: &mut App, delta: i64) {
    if !app.svc.wall.open {
        open(app);
    } else {
        step(app, delta);
    }
}

pub fn folder(app: &mut App, delta: i64) {
    step_folder(app, delta);
}

fn step_folder(app: &mut App, delta: i64) {
    let w = &mut app.svc.wall;
    if !w.has_folders() {
        return;
    }
    w.navigated = true;
    w.filter.clear();
    w.cursor = 0;
    let n = w.folders().len() as i64;
    w.folder_index = ((w.folder_index as i64 + delta) % n + n) as usize % n as usize;
    w.pending = Pending::Current;
    reselect(app);
}

/// pick(): the card flies up, the dialog goes; a picture is revealed, a video applied.
fn pick(app: &mut App) {
    let w = &app.svc.wall;
    let Some(it) = w.strip().get(w.index).map(|it| (*it).clone()) else { return };
    if !w.picked_id.is_empty() {
        return;
    }
    app.svc.wall.picked_id = it.id.clone();
    app.svc.wall.current_id = it.id.clone();
    app.debounce("wall-pick-close", Duration::from_millis(260), |app| {
        close(app);
        app.svc.wall.picked_id.clear();
    });
    if it.kind == "video" {
        apply(app, &it, "");
    } else {
        start_reveal(app, it);
    }
    redraw(app);
}

fn apply(app: &mut App, it: &Item, transition: &str) {
    let (s, w) = (script(), wall_dir());
    if transition.is_empty() {
        app.exec_detached(&[&s, "apply", &w, &it.id]);
    } else {
        let t = format!("WALLPAPER_TRANSITION={transition}");
        app.exec_detached(&["env", &t, &s, "apply", &w, &it.id]);
    }
}

// ---- keys, wheel, clicks ----

pub fn key(app: &mut App, sym: smithay_client_toolkit::seat::keyboard::Keysym, mods: Mods, utf8: Option<&str>) {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    match sym {
        Keysym::Escape => {
            if !app.svc.wall.filter.is_empty() {
                set_filter(app, String::new());
            } else {
                close(app);
            }
        }
        Keysym::Left => step(app, -1),
        Keysym::Right => step(app, 1),
        Keysym::Up | Keysym::ISO_Left_Tab => step_folder(app, -1),
        Keysym::Tab if mods.shift => step_folder(app, -1),
        Keysym::Down | Keysym::Tab => step_folder(app, 1),
        Keysym::Home => go_to(app, 0),
        Keysym::End => go_to(app, app.svc.wall.strip().len() as i64 - 1),
        Keysym::Prior => go_to(app, app.svc.wall.index as i64 - 5),
        Keysym::Next => go_to(app, app.svc.wall.index as i64 + 5),
        Keysym::Return | Keysym::KP_Enter => pick(app),
        Keysym::r | Keysym::R if mods.ctrl => random(app),
        Keysym::BackSpace => {
            let mut f = app.svc.wall.filter.clone();
            let c = app.svc.wall.cursor.min(f.len());
            let from = f[..c].char_indices().last().map_or(0, |(p, _)| p);
            f.replace_range(from..c, "");
            app.svc.wall.cursor = from;
            set_filter(app, f);
        }
        _ => {
            if mods.ctrl {
                return;
            }
            if let Some(s) = utf8.filter(|s| !s.is_empty() && !s.chars().any(char::is_control)) {
                let mut f = app.svc.wall.filter.clone();
                let c = app.svc.wall.cursor.min(f.len());
                f.insert_str(c, s);
                app.svc.wall.cursor = c + s.len();
                set_filter(app, f);
            }
        }
    }
}

/// onFilterChanged: the first match is centred; clearing it goes back home.
fn set_filter(app: &mut App, f: String) {
    let w = &mut app.svc.wall;
    if f.is_empty() {
        w.cursor = 0;
    }
    w.pending = if f.is_empty() { Pending::Current } else { Pending::First };
    w.filter = f;
    reselect(app);
}

pub fn wheel(app: &mut App, delta: f32) {
    // Over the tabs the wheel walks the folders; elsewhere, the cards.
    let over_tabs = app.osd(OsdKind::Wallpaper).and_then(|o| o.st.pointer).map_or(false, |(_, y)| {
        let (sw, sh) = screen_of(app);
        let g = geo(sw, sh);
        let band_top = ac(sh, g.card_h * CENTRE_SCALE);
        let top_h = (24.0f32 * 2.2).round();
        y >= band_top - px(22.0) - top_h && y < band_top - px(22.0)
    });
    if over_tabs {
        app.svc.wall.tab_acc += delta;
        while app.svc.wall.tab_acc >= 120.0 {
            app.svc.wall.tab_acc -= 120.0;
            step_folder(app, -1);
        }
        while app.svc.wall.tab_acc <= -120.0 {
            app.svc.wall.tab_acc += 120.0;
            step_folder(app, 1);
        }
        return;
    }
    app.svc.wall.wheel_acc += delta;
    while app.svc.wall.wheel_acc >= 120.0 {
        app.svc.wall.wheel_acc -= 120.0;
        step(app, -1);
    }
    while app.svc.wall.wheel_acc <= -120.0 {
        app.svc.wall.wheel_acc += 120.0;
        step(app, 1);
    }
}

pub fn click(app: &mut App, action: Action) {
    if action == Action::Hover(DIM) {
        return close(app);
    }
    let Action::Card(code) = action else { return };
    if code >= TAB {
        let w = &mut app.svc.wall;
        w.navigated = true;
        w.filter.clear();
        w.cursor = 0;
        w.folder_index = (code - TAB) as usize;
        w.pending = Pending::Current;
        reselect(app);
    } else if code >= CARD {
        let i = (code - CARD) as usize;
        if i == app.svc.wall.index {
            pick(app);
        } else {
            go_to(app, i as i64);
        }
    }
}

// ---- thumbnails ----

/// A card's Image lost its source or its delegate: its picture goes, and a
/// decode still on its way is cancelled.
fn forget_card(app: &mut App, id: &str) {
    if let Some(f) = app.svc.wall.loading.remove(id) {
        f.store(true, Ordering::Relaxed);
    }
    if let Some(t) = app.svc.wall.textures.remove(id) {
        if let Some(gpu) = app.gpu.as_mut() {
            gpu.drop_image(t.id);
        }
    }
}

/// The delegates that exist: the strip in view plus cacheBuffer (2 card
/// widths) each side. A card coming into that range has its picture decoded;
/// one that left it - where the view is, where it is going, and on the way
/// there - loses it, as ListView destroys the delegate and its Image drops
/// the texture and cancels a request still queued.
fn load_visible(app: &mut App) {
    let (sw, sh) = screen_of(app);
    let g = geo(sw, sh);
    let now = Instant::now();
    let w = &app.svc.wall;
    let (cur, vx) = w.view_x.as_ref().map_or((content_x(&g, w.index), content_x(&g, w.index)), |a| (a.get(now), a.target()));
    let alive = |x: f32, from: f32, to: f32| x + g.card_w >= from - 2.0 * g.card_w && x <= to + g.w + 2.0 * g.card_w;
    let step_w = g.card_w + g.spacing;
    let strip = w.strip();
    let mut keep: HashSet<&str> = HashSet::new();
    let mut jobs = Vec::new();
    for (i, it) in strip.iter().enumerate() {
        let x = i as f32 * step_w;
        if !alive(x, cur.min(vx), cur.max(vx)) {
            continue;
        }
        keep.insert(&it.id);
        if !alive(x, vx, vx) || w.textures.contains_key(&it.id) || w.loading.contains_key(&it.id) {
            continue;
        }
        if let Some(p) = w.thumb_path(it) {
            jobs.push((it.id.clone(), p));
        }
    }
    let gone: Vec<String> = w.textures.keys().chain(w.loading.keys()).filter(|id| !keep.contains(id.as_str())).cloned().collect();
    for id in gone {
        forget_card(app, &id);
    }
    let (target_h, max) = (g.card_h as u32, max_texture(app));
    for (id, path) in jobs {
        let cancel = Cancel::default();
        app.svc.wall.loading.insert(id.clone(), cancel.clone());
        app.background(
            move || {
                let img = if cancel.load(Ordering::Relaxed) { None } else { decode_height(&path, target_h, max).map(|(w, h, rgba)| crate::gpu::mip_levels(w, h, rgba, true)) };
                (id, cancel, img)
            },
            |app, (id, cancel, img)| {
                // Only the decode the card still waits for: not a cancelled
                // one, nor an older one for the same card.
                if !app.svc.wall.loading.get(&id).is_some_and(|c| Arc::ptr_eq(c, &cancel)) {
                    return;
                }
                app.svc.wall.loading.remove(&id);
                let Some(levels) = img else { return };
                let Some(gpu) = app.gpu.as_mut() else { return };
                let (w, h) = (levels[0].0, levels[0].1);
                let t = Tex { id: gpu.add_levels(levels), w, h };
                if let Some(old) = app.svc.wall.textures.insert(id, t) {
                    gpu.drop_image(old.id);
                }
                if let Some(o) = app.osd_mut(OsdKind::Wallpaper) {
                    o.win.dirty = true;
                }
            },
        );
    }
}

/// The GPU's largest texture side (8192, wgpu's downlevel floor, before the
/// GPU is up).
fn max_texture(app: &App) -> u32 {
    app.gpu.as_ref().map_or(8192, |g| g.device.limits().max_texture_dimension_2d)
}

/// Each side cut down to the GPU's limit: a texture past it is a wgpu
/// validation error, which aborts the bar (panic = "abort") where Qt carries on.
fn fit_texture(img: image::RgbaImage, max: u32) -> image::RgbaImage {
    let (w, h) = img.dimensions();
    if w <= max && h <= max {
        return img;
    }
    crate::gpu::scale(img, w.min(max), h.min(max))
}

/// sourceSize.height only: scaled down (never up) to that height.
fn decode_height(path: &std::path::Path, h: u32, max: u32) -> Option<(u32, u32, Vec<u8>)> {
    let img = image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.decode().ok()?.to_rgba8();
    let (iw, ih) = img.dimensions();
    let img = if ih > h {
        let nw = ((iw as f32 * h as f32 / ih as f32).round() as u32).max(1);
        crate::gpu::scale(img, nw, h)
    } else {
        img
    };
    let img = fit_texture(img, max);
    let (w, hh) = img.dimensions();
    Some((w, hh, crate::gpu::premultiply(img.into_raw())))
}

/// sourceSize width and height with PreserveAspectCrop: scaled to cover.
fn decode_cover(path: &std::path::Path, w: u32, h: u32, max: u32) -> Option<(u32, u32, Vec<u8>)> {
    let img = image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.decode().ok()?.to_rgba8();
    let (iw, ih) = img.dimensions();
    let s = (w as f32 / iw as f32).max(h as f32 / ih as f32);
    let img = if s < 1.0 {
        crate::gpu::scale(img, ((iw as f32 * s).round() as u32).max(1), ((ih as f32 * s).round() as u32).max(1))
    } else {
        img
    };
    let img = fit_texture(img, max);
    let (ow, oh) = img.dimensions();
    Some((ow, oh, crate::gpu::premultiply(img.into_raw())))
}

/// PreserveAspectCrop of a texture into (w, h): the uv window.
fn crop_uv(t: Tex, w: f32, h: f32) -> [f32; 4] {
    let s = (w / t.w as f32).max(h / t.h as f32);
    let (vw, vh) = (w / s / t.w as f32, h / s / t.h as f32);
    let (u0, v0) = ((1.0 - vw) / 2.0, (1.0 - vh) / 2.0);
    [u0, v0, u0 + vw, v0 + vh]
}

// ---- drawing ----

/// x' = x + s y - s c: a shear about the line y = c.
fn shear(s: f32, c: f32) -> Xf {
    Xf { a: 1.0, b: 0.0, c: s, d: 1.0, tx: -s * c, ty: 0.0 }
}

pub fn draw_osd(ui: &mut Ui<OsdState>, panel: (f32, f32, f32, f32), svc: &Services) {
    let (_, _, sw, sh) = panel;
    let t = ui.theme;
    let w = &svc.wall;
    let g = geo(sw, sh);
    let now = ui.now;
    // The dim under everything; a click anywhere out there dismisses
    // (WallpaperOsd.qml's dim MouseArea - first, so every other hit wins).
    ui.scene.fill(0.0, 0.0, sw, sh, Color::qt_rgba(0.0, 0.0, 0.0, 0.6));
    ui.hits.push(crate::bar::Hit { x: 0.0, y: 0.0, w: sw, h: sh, action: Action::Hover(DIM) });
    let strip = w.strip();
    let vx = w.view_x.as_ref().map_or(content_x(&g, w.index), |a| a.get(now));
    if w.view_x.as_ref().map_or(false, |a| a.running(now)) {
        ui.animating = true;
    }
    let band_w = g.card_w * CENTRE_SCALE;
    let band_h = g.card_h * CENTRE_SCALE;
    let (band_x, band_y) = (ac(sw, band_w), ac(sh, band_h));
    let step_w = g.card_w + g.spacing;
    let skew_pad = (SKEW.abs() * g.card_h).ceil();

    // The cards, painted in z order: others by distance, the centre, the picked one.
    let pointer = ui.card.pointer;
    let mut order: Vec<(f32, usize)> = Vec::new();
    for (i, it) in strip.iter().enumerate() {
        let x = i as f32 * step_w - vx;
        if x + g.card_w < -g.card_w || x > sw + g.card_w {
            continue;
        }
        let dist = (i as i64 - w.index as i64).unsigned_abs() as f32;
        let z = if it.id == w.picked_id { 200.0 } else if i == w.index { 100.0 } else { 50.0 - dist };
        order.push((z, i));
    }
    order.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());
    // Which card the pointer is over: the topmost whose sheared face holds
    // it, at the scale it had last frame.
    let mut hovered: Option<usize> = None;
    if let Some((px0, py0)) = pointer {
        for &(_, i) in order.iter().rev() {
            let x = i as f32 * step_w - vx;
            let cy = g.list_y + ac(g.list_h, g.card_h);
            let sc = ui.card.number_peek(0x10_0000 + i as u32, now).unwrap_or(FAR_SCALE);
            if let Some((lx, ly)) = invert(&card_xf(x, cy, &g, sc), px0, py0) {
                if lx >= 0.0 && lx < g.card_w && ly >= 0.0 && ly < g.card_h {
                    hovered = Some(i);
                    break;
                }
            }
        }
    }
    for &(_, i) in &order {
        let it = strip[i];
        let x = i as f32 * step_w - vx;
        let cy = g.list_y + ac(g.list_h, g.card_h);
        let dist = (i as i64 - w.index as i64).unsigned_abs() as f32;
        let falloff = 1.0 / (1.0 + dist * dist);
        let is_centre = i == w.index;
        let picked = it.id == w.picked_id;
        let other_picked = !w.picked_id.is_empty() && !picked;
        let hover = hovered == Some(i);
        let target_scale = if picked { 1.3 } else { (FAR_SCALE + (CENTRE_SCALE - FAR_SCALE) * falloff) * if hover && !is_centre { 1.04 } else { 1.0 } };
        let target_op = if picked || other_picked { 0.0 } else if hover { 1.0 } else { 0.12 + 0.88 * falloff };
        let (sc, r1) = ui.card.number_e(0x10_0000 + i as u32, target_scale, 260, Easing::OutCubic, now);
        let (op, r2) = ui.card.number_e(0x20_0000 + i as u32, target_op, 260, Easing::Linear, now);
        ui.animating |= r1 || r2;
        let m = card_xf(x, cy, &g, sc);
        ui.scene.save();
        ui.scene.transform(m);
        ui.scene.multiply_opacity(op);
        ui.scene.fill(0.0, 0.0, g.card_w, g.card_h, t.col_bg);
        // The face: un-sheared again, clipped by the sheared card.
        ui.scene.save();
        ui.scene.clip_rect(0.0, 0.0, g.card_w, g.card_h);
        let fw = g.card_w + skew_pad;
        ui.scene.translate(-skew_pad / 2.0, 0.0);
        ui.scene.transform(shear(-SKEW, g.card_h / 2.0));
        match w.textures.get(&it.id) {
            Some(&tex) => ui.scene.image(tex.id, 0.0, 0.0, fw, g.card_h, crop_uv(tex, fw, g.card_h)),
            None => {
                let gl = ui.fonts.layout(if it.kind == "video" { "\u{f040a}" } else { "\u{f02e9}" }, CONTENT, px(36.0), 0.0);
                ui.text_of(i as u32, 0xA1, &gl, ac(fw, gl.width), ac(g.card_h, gl.height()), t.col_grey);
            }
        }
        if it.kind != "image" {
            let label = if it.kind == "video" { "\u{f040a} VIDEO" } else { "GIF" };
            let bl = ui.fonts.layout(label, theme::bar_font(false), px(11.0), 1.0);
            let (bw, bh) = (bl.width + 14.0, bl.height() + 6.0);
            let by = g.card_h - bh - 12.0;
            let bx = SKEW.abs() * (g.card_h - by) + 12.0;
            ui.scene.rect(bx, by, bw, bh, Color::qt_rgba(0.0, 0.0, 0.0, 0.55), 4.0, 0.0, Color::TRANSPARENT, true);
            ui.text_of(i as u32, 0xA2, &bl, bx + ac(bw, bl.width), by + ac(bh, bl.height()), t.col_white);
        }
        ui.scene.restore();
        if is_centre {
            ui.scene.rect(0.0, 0.0, g.card_w, g.card_h, Color::TRANSPARENT, 0.0, 2.0, t.col_white, true);
        }
        ui.scene.restore();
        // The hit area: the card's sheared face on screen.
        let (l, top) = (m.a * 0.0 + m.c * 0.0 + m.tx, m.ty);
        let (r, bottom) = (m.a * g.card_w + m.tx, m.d * g.card_h + m.ty);
        ui.card.shapes.push((l, top, r - l, bottom - top, m.c / m.d, m.ty, Action::Card(CARD + i as u32)));
    }

    if strip.is_empty() {
        let home = home();
        let text = if !w.filter.is_empty() {
            format!("Nothing matches “{}”", w.filter)
        } else if w.scanning || !w.scanned {
            format!("Reading {}…", wall_dir().replace(&home, "~"))
        } else {
            format!("No wallpapers in {}", wall_dir().replace(&home, "~"))
        };
        let l = ui.fonts.layout(&text, CONTENT, px(13.0), 0.0);
        ui.text(&l, band_x + (band_w - l.adv) / 2.0, band_y + ac(band_h, l.height()), t.col_grey, TextStyle::Normal);
    }

    // Above: the folder tabs, or the search line.
    let gap = px(22.0);
    let top_h = (24.0f32 * 2.2).round();
    let top_y = band_y - gap - top_h;
    let top_w = sw - 2.0 * gap;
    if w.filter.is_empty() && w.has_folders() {
        draw_tabs(ui, w, gap, top_y, top_w, top_h);
    }
    if !w.filter.is_empty() {
        let sp = px(12.0);
        let cap = ui.fonts.layout("ПОИСК", theme::bar_font(false), 24.0, 2.0);
        let fl = ui.fonts.layout(&w.filter, CONTENT, px(13.0), 0.0);
        let iw = (fl.adv + 4.0).max(px(40.0));
        let n = strip.len();
        let cnt = ui.fonts.layout(&format!("{n}{}", if n == 1 { " match" } else { " matches" }), theme::bar_font(false), px(11.0), 0.0);
        let row_w = cap.width + sp + iw + sp + cnt.width;
        let row_h = cap.height().max(fl.height()).max(cnt.height());
        let (rx, ry) = (gap + ac(top_w, row_w), top_y + ac(top_h, row_h));
        ui.text(&cap, rx, ry + ac(row_h, cap.height()), t.col_grey, TextStyle::Normal);
        let fx = rx + cap.width + sp;
        let fy = ry + ac(row_h, fl.height());
        ui.text(&fl, fx, fy, t.col_white, TextStyle::Normal);
        let cx = ui.fonts.layout(&w.filter[..w.cursor.min(w.filter.len())], CONTENT, px(13.0), 0.0).adv;
        ui.scene.fill(fx + cx, fy, 1.0, fl.height(), t.col_white);
        ui.text(&cnt, fx + iw + sp, ry + ac(row_h, cnt.height()), t.col_grey, TextStyle::Normal);
    }

    // Below: the centred card's folder, name, position and whether it is on.
    if let Some(c) = strip.get(w.index) {
        let fm_ch = ui.fonts.average_char_width(CONTENT, 24.0);
        let (dir_cols, pos_cols, stamp_cols) = (26.0, 13.0, 16.0);
        let name_cols = 16f32.max(40f32.min(((sw - 2.0 * gap) / fm_ch).floor() - dir_cols - pos_cols - stamp_cols));
        let cap_w = (fm_ch * (dir_cols + name_cols + pos_cols + stamp_cols)).round();
        let probe = ui.fonts.layout("Н", CONTENT, 24.0, 0.0);
        let cap_h = (probe.ascent + probe.descent).ceil();
        let cap_x = ac(sw, cap_w);
        let cap_y = band_y + band_h + gap;
        let dir_w = (fm_ch * dir_cols).round();
        let name_w = (fm_ch * name_cols).round();
        let pos_w = (fm_ch * pos_cols).round();
        if !c.dir.is_empty() {
            let text = format!("{}  /  ", c.dir);
            let full = ui.fonts.layout(&text, CONTENT, 24.0, 0.0);
            let line = if full.width <= dir_w { full } else { elide_left(ui, &text, dir_w) };
            ui.text(&line, cap_x + dir_w - line.adv, cap_y, t.col_grey, TextStyle::Normal);
        }
        let nl = ui.fonts.elide_middle(&c.name, CONTENT, 24.0, 0.0, name_w);
        ui.text(&nl, cap_x + dir_w, cap_y, t.col_white, TextStyle::Normal);
        let pl = ui.fonts.layout(&format!("  ·  {} ИЗ {}", w.index + 1, strip.len()), CONTENT, 24.0, 0.0);
        ui.text(&pl, cap_x + dir_w + name_w, cap_y, t.col_grey, TextStyle::Normal);
        if w.current_id == c.id {
            let sl = ui.fonts.layout("  ·  УСТАНОВЛЕНО", CONTENT, 24.0, 0.0);
            ui.text(&sl, cap_x + dir_w + name_w + pos_w, cap_y, t.col_grey, TextStyle::Normal);
        }
        let keys = format!("←→ ЛИСТАТЬ{}    ENTER УСТАНОВИТЬ    CTRL+R НАУГАД    ПОИСК ПРИ НАБОРЕ    ESC ОТМЕНА", if w.has_folders() { "    ↑↓ КАТАЛОГ" } else { "" });
        let kl = ui.fonts.layout(&keys, theme::bar_font(false), 20.0, 1.0);
        ui.text(&kl, ac(sw, kl.width), cap_y + cap_h + (gap * 0.7).round(), t.col_grey, TextStyle::Normal);
    }
}

/// Text.ElideLeft: "…" and as much of the end as fits.
fn elide_left(ui: &mut Ui<OsdState>, text: &str, max: f32) -> crate::text::Line {
    let dots = ui.fonts.layout("…", CONTENT, 24.0, 0.0).width;
    let chars: Vec<char> = text.chars().collect();
    let mut keep = 0;
    for k in 1..=chars.len() {
        let tail: String = chars[chars.len() - k..].iter().collect();
        if ui.fonts.layout(&tail, CONTENT, 24.0, 0.0).width + dots > max {
            break;
        }
        keep = k;
    }
    let s: String = std::iter::once('…').chain(chars[chars.len() - keep..].iter().copied()).collect();
    ui.fonts.layout(&s, CONTENT, 24.0, 0.0)
}

/// The card's place: in its cell, sheared about its middle, scaled about its centre.
fn card_xf(x: f32, y: f32, g: &Geo, sc: f32) -> Xf {
    let (cx, cy) = (g.card_w / 2.0, g.card_h / 2.0);
    let scale = Xf { a: sc, b: 0.0, c: 0.0, d: sc, tx: (1.0 - sc) * cx, ty: (1.0 - sc) * cy };
    let place = Xf { a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: x, ty: y };
    scale.then(&shear(SKEW, g.card_h / 2.0)).then(&place)
}

fn invert(m: &Xf, x: f32, y: f32) -> Option<(f32, f32)> {
    let det = m.a * m.d - m.b * m.c;
    if det.abs() < 1e-9 {
        return None;
    }
    let (dx, dy) = (x - m.tx, y - m.ty);
    Some(((m.d * dx - m.c * dy) / det, (-m.b * dx + m.a * dy) / det))
}

fn draw_tabs(ui: &mut Ui<OsdState>, w: &Wall, x0: f32, y0: f32, width: f32, h: f32) {
    let t = ui.theme;
    let folders = w.folders();
    let sp = px(26.0);
    let inner = px(6.0);
    let mut cells = Vec::new();
    for (i, f) in folders.iter().enumerate() {
        let chosen = i == w.folder_index;
        let label = ui.fonts.layout(&f.label.to_uppercase(), theme::bar_font(chosen), 24.0, 2.0);
        let count = ui.fonts.layout(&f.count.to_string(), theme::bar_font(false), (24.0f32 * 0.75).round(), 0.0);
        cells.push((label, count, chosen));
    }
    let widths: Vec<f32> = cells.iter().map(|(l, c, _)| l.width + inner + c.width).collect();
    let total = widths.iter().sum::<f32>() + sp * (widths.len().saturating_sub(1)) as f32;
    let vw = total.min(width);
    let fx = x0 + ac(width, vw);
    ui.scene.save();
    ui.scene.clip_rect(fx, y0, vw, h);
    let mut tx = fx - w.tab_scroll;
    for (i, (label, count, chosen)) in cells.iter().enumerate() {
        let tw = widths[i];
        let hot = ui.hovered(tx, y0, tw, h);
        let row_h = label.height().max(count.height());
        let ry = y0 + ac(h, row_h);
        let ly = ry;
        ui.text_of(i as u32, 0xB1, label, tx, ly, if *chosen || hot { t.col_white } else { t.col_grey });
        // anchors.baseline: the count sits on the label's baseline.
        let base = ly + label.ascent;
        ui.text_of(i as u32, 0xB2, count, tx + label.width + inner, base - count.ascent, t.col_grey);
        if *chosen {
            ui.scene.fill(tx, y0 + h - 2.0, tw, 2.0, t.col_white);
        }
        ui.hits.push(crate::bar::Hit { x: tx, y: y0, w: tw, h, action: Action::Card(TAB + i as u32) });
        tx += tw + sp;
    }
    ui.scene.restore();
}

// ---- the reveal ----

/// startReveal(): load the picture on every screen first.
fn start_reveal(app: &mut App, it: Item) {
    end_reveal_windows(app);
    let cancel = Cancel::default();
    let w = &mut app.svc.wall;
    w.reveal_cancel = Some(cancel.clone());
    w.reveal_item = Some(it.clone());
    w.reveal_phase = "loading";
    w.reveal_ready = 0;
    w.reveal_start = None;
    let outputs: Vec<(WlOutput, f32, f32)> = app.strips.iter().map(|s| (s.output.clone(), s.screen_width, s.screen_height)).collect();
    let max = max_texture(app);
    for (output, sw, sh) in outputs {
        let surface = app.compositor.create_surface(&app.qh);
        let layer = app.layer_shell.create_layer_surface(&app.qh, surface, Layer::Bottom, Some("quickshell:wallpaper-reveal"), Some(&output));
        layer.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
        layer.set_exclusive_zone(-1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        if let Ok(region) = smithay_client_toolkit::compositor::Region::new(&app.compositor) {
            layer.wl_surface().set_input_region(Some(region.wl_region()));
        }
        layer.commit();
        let i = app.reveals.len();
        app.reveals.push(RevealWin { output, win: Win::new(layer, sw as u32, sh as u32), tex: None, reported: false });
        let path = path_of(&it.src);
        let (w, h) = (sw as u32, sh as u32);
        let cancel = cancel.clone();
        app.background(
            move || {
                let img = if cancel.load(Ordering::Relaxed) { None } else { decode_cover(&path, w, h, max) };
                (i, cancel, img)
            },
            |app, (i, cancel, img)| {
                // An earlier pick's picture goes nowhere.
                if !app.svc.wall.reveal_cancel.as_ref().is_some_and(|c| Arc::ptr_eq(c, &cancel)) {
                    return;
                }
                let Some(r) = app.reveals.get_mut(i) else { return };
                if let (Some((w, h, rgba)), Some(gpu)) = (img, app.gpu.as_mut()) {
                    r.tex = Some(Tex { id: gpu.add_image(w, h, rgba, false), w, h });
                }
                if !r.reported {
                    r.reported = true;
                    app.svc.wall.reveal_ready += 1;
                    if app.svc.wall.reveal_phase == "loading" && app.svc.wall.reveal_ready >= app.reveals.len() {
                        open_reveal(app);
                    }
                }
            },
        );
    }
    app.debounce("wall-reveal-load", Duration::from_millis(1500), open_reveal);
}

fn open_reveal(app: &mut App) {
    if app.svc.wall.reveal_phase != "loading" {
        return;
    }
    app.cancel_timer("wall-reveal-load");
    app.svc.wall.reveal_phase = "opening";
    app.svc.wall.reveal_start = Some(Instant::now());
    for r in &mut app.reveals {
        r.win.dirty = true;
    }
    app.debounce("wall-reveal-done", Duration::from_millis(REVEAL_MS), |app| {
        app.svc.wall.reveal_phase = "holding";
        if let Some(it) = app.svc.wall.reveal_item.clone() {
            apply(app, &it, "none");
        }
        for r in &mut app.reveals {
            r.win.dirty = true;
        }
        app.debounce("wall-reveal-hold", Duration::from_secs(6), end_reveal);
    });
}

fn end_reveal(app: &mut App) {
    app.cancel_timer("wall-reveal-hold");
    let w = &mut app.svc.wall;
    w.reveal_phase = "";
    w.reveal_item = None;
    w.reveal_start = None;
    end_reveal_windows(app);
}

fn end_reveal_windows(app: &mut App) {
    if let Some(c) = app.svc.wall.reveal_cancel.take() {
        c.store(true, Ordering::Relaxed);
    }
    let ids: Vec<u32> = app.reveals.drain(..).filter_map(|r| r.tex.map(|t| t.id)).collect();
    if let Some(gpu) = app.gpu.as_mut() {
        for id in ids {
            gpu.drop_image(id);
        }
    }
    unsafe { libc::malloc_trim(0) };
}

/// One frame of the reveal band; true while it opens.
pub fn draw_reveal(r: &mut RevealWin, scene: &mut Scene, _gpu: &mut Gpu, svc: &Services, theme: &crate::theme::Theme) -> bool {
    let w = &svc.wall;
    let (sw, sh) = (r.win.width as f32, r.win.height as f32);
    let progress = match w.reveal_phase {
        "opening" => ease(Easing::InOutCubic, w.reveal_start.map_or(0.0, |s| s.elapsed().as_millis() as f32 / REVEAL_MS as f32)),
        "holding" => 1.0,
        _ => 0.0,
    };
    let full_w = sw + SKEW.abs() * sh + 8.0;
    let (bw, bh) = (full_w * progress, sh + 8.0);
    if bw <= 0.0 {
        return w.reveal_phase == "opening";
    }
    let (bx, by) = (ac(sw, bw), ac(sh, bh));
    scene.save();
    scene.translate(bx, by);
    scene.transform(shear(SKEW, bh / 2.0));
    scene.clip_rect(0.0, 0.0, bw, bh);
    if let Some(t) = r.tex {
        // The picture stays put on the screen: un-sheared, at the screen's origin.
        scene.save();
        scene.transform(Xf { a: 1.0, b: 0.0, c: -SKEW, d: 1.0, tx: SKEW * bh / 2.0 + SKEW * by - bx, ty: -by });
        scene.image(t.id, 0.0, 0.0, sw, sh, crop_uv(t, sw, sh));
        scene.restore();
    }
    if w.reveal_phase == "opening" {
        scene.rect(0.0, 0.0, bw, bh, Color::TRANSPARENT, 0.0, 2.0, theme.col_white, true);
    }
    scene.restore();
    w.reveal_phase == "opening"
}
