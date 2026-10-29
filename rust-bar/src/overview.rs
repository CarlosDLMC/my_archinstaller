//! The overview (SUPER A; quickshell bar/overview): every screen shows its
//! ten workspaces as a 5 x 2 grid with a still picture of each window and its
//! app icon. Click a workspace to go there, a window to focus it, middle-click
//! to close it; drag a window to another workspace (or onto a neighbour to
//! swap); arrows walk the workspaces; Esc or Return leave.

use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;

use smithay_client_toolkit::reexports::calloop::RegistrationToken;
use smithay_client_toolkit::seat::pointer::PointerEventKind;

use crate::anim::Easing;
use crate::app::App;
use crate::bar::ac;
use crate::cards::Ui;
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::osd::{self, OpenParams, OsdKind, OsdState};
use crate::services::{self, Monitor, Services};
use crate::text::FontKey;
use crate::theme;

const SCALE: f32 = 0.16;
const ROWS: i64 = 2;
const COLS: i64 = 5;
const SPACING: f32 = 5.0;
/// Appearance.animation: elementMoveEnter (windows) and elementMoveFast (the frame).
const ENTER: Easing = Easing::Bezier(0.05, 0.7, 0.1, 1.0);
const FAST: Easing = Easing::Bezier(0.34, 0.8, 0.34, 1.0);
const MAIN: FontKey = FontKey { family: theme::FONT_CONTENT, bold: false, plain: false };
const NUMBER: FontKey = FontKey { family: theme::FONT, bold: false, plain: false };

#[derive(Clone, Debug, Default)]
pub struct Client {
    pub id: i64,
    pub title: String,
    pub appid: String,
    pub monitor: String,
    pub tags: Vec<i64>,
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub floating: bool,
    pub global: bool,
    pub focused: bool,
    pub minimized: bool,
    pub xwayland: bool,
    pub group: bool,
    pub group_focus: bool,
    pub fullscreen: bool,
    pub maximized: bool,
    pub scratchpad: bool,
    pub toplevel: String,
}

impl Client {
    fn ws(&self) -> i64 {
        self.tags.first().copied().unwrap_or(0)
    }
}

#[derive(Clone, Copy)]
struct Tex {
    id: u32,
}

const BTN_LEFT: u32 = 0x110;
const BTN_MIDDLE: u32 = 0x112;

/// A button held on a window's MouseArea (left or middle, both drag it) or
/// on a workspace's empty part (left only, no drag).
struct Press {
    screen: u8,
    /// The window, or -1 for a workspace's empty part.
    id: i64,
    button: u32,
    start: (f32, f32),
    pos: (f32, f32),
    /// drag.smoothed: where the pointer was on the move that passed the
    /// 10 px threshold. The tile follows from there, from the next move on.
    origin: Option<(f32, f32)>,
    dragging: bool,
    /// The workspace an empty-space press went down on.
    cell: Option<i64>,
}

impl Press {
    /// How far the dragged tile is from where it rests.
    fn offset(&self) -> (f32, f32) {
        match (self.dragging, self.origin) {
            (true, Some(o)) => (self.pos.0 - o.0, self.pos.1 - o.1),
            _ => (0.0, 0.0),
        }
    }

    /// The Drag hot spot: the point of the tile that was pressed, where the
    /// tile is now (it trails the pointer by the threshold distance).
    fn hotspot(&self) -> (f32, f32) {
        let (dx, dy) = self.offset();
        (self.start.0 + dx, self.start.1 + dy)
    }
}

/// A tile let go after a drag: followWindow() animates it back from there.
struct Dropped {
    serial: u32,
    /// Where the tile was let go and where it rested then (window space).
    at: (f32, f32),
    rest: (f32, f32),
}

#[derive(Default)]
pub struct Overview {
    pub open: bool,
    clients: Vec<Client>,
    watch: Option<(UnixStream, Option<RegistrationToken>, Vec<u8>)>,
    shots_pending: bool,
    shot_gen: u32,
    /// Each window's picture and the shot generation it is from.
    previews: HashMap<i64, (Tex, u32)>,
    /// Icon textures by icon name, then size (None: no icon to be had).
    icons: HashMap<String, HashMap<u32, Option<Tex>>>,
    icon_loading: HashSet<(String, u32)>,
    desktop: Option<HashMap<String, String>>,
    /// App id -> icon name (DesktopEntries.heuristicLookup), for drawing.
    names: HashMap<String, String>,
    /// Where an icon was found, by name and size.
    icon_paths: HashMap<(String, u32), Option<String>>,
    hovered: Option<(u8, i64)>,
    press: Option<Press>,
    drop_ws: Option<(u8, i64)>,
    /// The pointer over an overview window (screen, x, y), for hover after a
    /// list change (Qt re-delivers hover when items move under it).
    pointer: Option<(u8, f32, f32)>,
    dropped: HashMap<(u8, i64), Dropped>,
    drop_serial: u32,
    /// What the overview last took from mango's monitor list (monitor_sig).
    mon_sig: Option<u64>,
}

fn shot_dir() -> String {
    format!("{}/quickshell-overview", std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into()))
}

// ---- open / close ----

pub fn toggle(app: &mut App) {
    if app.svc.overview.open {
        close(app);
    } else {
        open(app);
    }
}

pub fn open(app: &mut App) {
    if app.svc.overview.open {
        return;
    }
    app.svc.overview.open = true;
    app.svc.overview.shots_pending = true;
    app.svc.overview_screens = app.strips.iter().map(|s| s.name.clone()).collect();
    let outputs: Vec<_> = app.strips.iter().map(|s| (s.output.clone(), s.screen_width, s.screen_height)).collect();
    for (i, out) in outputs.into_iter().enumerate() {
        osd::show(app, OpenParams { kind: OsdKind::Overview(i as u8), size: (0, 0), panel: (0.0, 0.0, 0.0, 0.0), dim: None, keyboard: true, namespace: "quickshell:overview", fade_ms: 0, min_scale: 1.0, fade_easing: Easing::Linear, pos: None, fill: true, output: Some(out) });
    }
    // A tile's Image asks for `<id>.ppm?shotGeneration` as soon as it exists:
    // once a run has finished, the last open's pictures are up at once and
    // this open's replace them when overview-shots.sh is done. Icons first
    // (monitors_changed loads them), so they do not wait behind the pictures
    // on the decode thread.
    monitors_changed(app);
    if app.svc.overview.shot_gen > 0 {
        load_shots(app);
    }
    watch(app);
}

pub fn close(app: &mut App) {
    if !app.svc.overview.open {
        return;
    }
    let o = &mut app.svc.overview;
    o.open = false;
    o.press = None;
    o.hovered = None;
    o.drop_ws = None;
    o.pointer = None;
    o.dropped.clear();
    o.mon_sig = None;
    if let Some((_, Some(t), _)) = o.watch.take() {
        app.unwatch(t);
    }
    app.osds.retain(|o| !matches!(o.kind, OsdKind::Overview(_)));
    let ids: Vec<u32> = app.svc.overview.previews.drain().map(|(_, (t, _))| t.id).chain(app.svc.overview.icons.drain().flat_map(|(_, by)| by.into_values().flatten().map(|t| t.id))).collect();
    app.svc.overview.icon_loading.clear();
    if let Some(gpu) = app.gpu.as_mut() {
        for id in ids {
            gpu.drop_image(id);
        }
    }
    unsafe { libc::malloc_trim(0) };
}

fn redraw(app: &mut App) {
    for o in app.osds.iter_mut().filter(|o| matches!(o.kind, OsdKind::Overview(_))) {
        o.win.dirty = true;
    }
}

/// One screen's overview: what pointer changes there touch.
fn redraw_screen(app: &mut App, screen: u8) {
    if let Some(o) = app.osd_mut(OsdKind::Overview(screen)) {
        o.win.dirty = true;
    }
}

/// The hovered window, from where the pointer is. Qt delivers no hover while
/// a MouseArea holds a press, and re-delivers it when items moved under a
/// still pointer.
fn rehover(app: &mut App) {
    if app.svc.overview.press.is_some() {
        return;
    }
    let hov = app.svc.overview.pointer.and_then(|(s, x, y)| window_at(app, s, x, y).map(|id| (s, id)));
    if hov != app.svc.overview.hovered {
        for s in [app.svc.overview.hovered.map(|h| h.0), hov.map(|h| h.0)].into_iter().flatten() {
            redraw_screen(app, s);
        }
        app.svc.overview.hovered = hov;
    }
}

/// What the overview takes from mango's monitor list: each monitor's name,
/// box and scale (the panel, the window space) and its shown tags (the frame,
/// the group, which workspaces are laid out afresh).
fn monitor_sig(monitors: &[Monitor]) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    for m in monitors {
        (&m.name, m.x.to_bits(), m.y.to_bits(), m.width.to_bits(), m.height.to_bits(), m.scale.to_bits(), &m.active_tags).hash(&mut h);
    }
    h.finish()
}

/// Mango.monitor's bindings re-evaluate in QML on every monitor snapshot; the
/// open overview follows them here (services.rs on_monitors calls this; so
/// does open(), for its first look). mango pushes the window list just
/// before the monitors after each arrange (ipc.c handle_print_status), on
/// another socket: a snapshot read in a later loop turn than the windows was
/// never drawn, and the frame stayed on the last workspace. A snapshot that
/// changes nothing the overview shows draws nothing.
pub fn monitors_changed(app: &mut App) {
    if !app.svc.overview.open {
        return;
    }
    let sig = monitor_sig(&app.svc.mango.monitors);
    if app.svc.overview.mon_sig.replace(sig) == Some(sig) {
        return;
    }
    // A retile changes tiles' sizes (their icons) and what is under the pointer.
    load_icons(app);
    rehover(app);
    redraw(app);
}

/// MangoData: `watch all-clients` on mango's socket while open.
fn watch(app: &mut App) {
    let Ok(path) = std::env::var("MANGO_INSTANCE_SIGNATURE") else { return };
    let Ok(mut s) = UnixStream::connect(&path) else { return };
    let _ = s.write_all(b"watch all-clients\n");
    let _ = s.set_nonblocking(true);
    let token = app.watch_fd(s.as_raw_fd(), |app| {
        let mut lines = Vec::new();
        let mut gone = false;
        if let Some((s, _, buf)) = app.svc.overview.watch.as_mut() {
            let mut chunk = [0u8; 65536];
            loop {
                match s.read(&mut chunk) {
                    Ok(0) => {
                        gone = true;
                        break;
                    }
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                    Err(e) => {
                        gone = e.kind() != std::io::ErrorKind::WouldBlock;
                        break;
                    }
                }
            }
            while let Some(p) = buf.iter().position(|&b| b == b'\n') {
                let l: Vec<u8> = buf.drain(..=p).collect();
                lines.push(String::from_utf8_lossy(&l[..l.len() - 1]).into_owned());
            }
        }
        // mango hung up (it drops a watcher whose buffer filled, and all of
        // them when it quits): stop, as the QML Socket does. A readable EOF
        // would call this back without end. calloop takes the source out
        // after this callback; the fd stays open until close().
        if gone {
            if let Some(t) = app.svc.overview.watch.as_mut().and_then(|w| w.1.take()) {
                app.unwatch(t);
            }
        }
        for l in lines {
            on_clients(app, &l);
        }
    });
    app.svc.overview.watch = Some((s, token, Vec::new()));
}

fn on_clients(app: &mut App, line: &str) {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else { return };
    let Some(list) = v.get("clients").and_then(|c| c.as_array()) else { return };
    let b = |o: &serde_json::Value, k: &str| o.get(k).and_then(|x| x.as_bool()).unwrap_or(false);
    let f = |o: &serde_json::Value, k: &str| o.get(k).and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
    let s = |o: &serde_json::Value, k: &str| o.get(k).map(|x| x.as_str().map(String::from).unwrap_or_else(|| if x.is_null() { String::new() } else { x.to_string() })).unwrap_or_default();
    app.svc.overview.clients = list
        .iter()
        .map(|o| Client {
            id: o.get("id").and_then(|x| x.as_i64()).unwrap_or(0),
            title: s(o, "title"),
            appid: s(o, "appid"),
            monitor: s(o, "monitor"),
            tags: o.get("tags").and_then(|t| t.as_array()).map(|a| a.iter().filter_map(|x| x.as_i64()).collect()).unwrap_or_default(),
            x: f(o, "x"),
            y: f(o, "y"),
            width: f(o, "width"),
            height: f(o, "height"),
            floating: b(o, "is_floating"),
            global: b(o, "is_global"),
            focused: b(o, "is_focused"),
            minimized: b(o, "is_minimized"),
            xwayland: b(o, "is_xwayland"),
            group: b(o, "is_group"),
            group_focus: b(o, "is_group_focus"),
            fullscreen: b(o, "is_fullscreen"),
            maximized: b(o, "is_maximized"),
            scratchpad: b(o, "is_scratchpad"),
            toplevel: s(o, "foreign_toplevel_id"),
        })
        .collect();
    if std::mem::take(&mut app.svc.overview.shots_pending) {
        take_shots(app);
    }
    load_icons(app);
    rehover(app);
    redraw(app);
}

/// overview-shots.sh: one still picture per window, then shotGeneration++.
fn take_shots(app: &mut App) {
    let script = format!("{}/.config/quickshell/bar/scripts/overview-shots.sh", services::home());
    let mut args = vec![script, shot_dir()];
    for w in &app.svc.overview.clients {
        if !w.toplevel.is_empty() && w.toplevel != "0" && !w.minimized && !(w.group && !w.group_focus) {
            args.push(format!("{}:{}:{}x{}", w.id, w.toplevel, w.width as i64, w.height as i64));
        }
    }
    let argv: Vec<&str> = args.iter().map(String::as_str).collect();
    app.spawn("overview-shots", &argv, |app, _| {
        app.svc.overview.shot_gen += 1;
        if app.svc.overview.open {
            load_shots(app);
        }
    });
}

/// The windows' pictures of the current shot generation, decoded off the
/// main thread; a picture never replaces one from a later generation. Each
/// file is opened here, so the script's `rm` at the next open cannot take
/// it away before its decode.
fn load_shots(app: &mut App) {
    let (gen, dir) = (app.svc.overview.shot_gen, shot_dir());
    let ids: Vec<i64> = app.svc.overview.clients.iter().map(|c| c.id).collect();
    for id in ids {
        let Ok(file) = std::fs::File::open(format!("{dir}/{id}.ppm")) else { continue };
        app.background(move || (id, gen, decode(file).map(|(w, h, rgba)| crate::gpu::mip_levels(w, h, rgba, true))), |app, (id, gen, img)| {
            let Some(levels) = img else { return };
            let o = &app.svc.overview;
            if !o.open || o.previews.get(&id).map_or(false, |p| p.1 > gen) {
                return;
            }
            let Some(gpu) = app.gpu.as_mut() else { return };
            let t = Tex { id: gpu.add_levels(levels) };
            if let Some((old, _)) = app.svc.overview.previews.insert(id, (t, gen)) {
                gpu.drop_image(old.id);
            }
            redraw(app);
        });
    }
}

fn decode(file: std::fs::File) -> Option<(u32, u32, Vec<u8>)> {
    let img = image::ImageReader::new(std::io::BufReader::new(file)).with_guessed_format().ok()?.decode().ok()?.to_rgba8();
    let (w, h) = img.dimensions();
    // A zero-size texture is a wgpu validation error, and a panic aborts.
    (w > 0 && h > 0).then(|| (w, h, img.into_raw()))
}

// ---- icons: DesktopEntries.heuristicLookup + Quickshell.iconPath ----

/// Desktop entries by id (and lowercase id) and by StartupWMClass: their
/// Icon, empty when they have none. As quickshell's DesktopEntryManager: the
/// data dirs in priority order, an id seen before is skipped, a later entry
/// with the same lowercase id takes that key over.
fn desktop_index() -> HashMap<String, String> {
    let mut dirs = vec![std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{}/.local/share", services::home()))];
    dirs.extend(std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into()).split(':').map(String::from));
    let mut by_id: HashMap<String, String> = HashMap::new();
    let mut by_class: HashMap<String, String> = HashMap::new();
    for d in &dirs {
        let root = format!("{d}/applications");
        let mut stack = vec![root.clone()];
        while let Some(dir) = stack.pop() {
            let Ok(rd) = std::fs::read_dir(&dir) else { continue };
            for e in rd.flatten() {
                let p = e.path();
                if p.is_dir() {
                    stack.push(p.to_string_lossy().into_owned());
                    continue;
                }
                let ps = p.to_string_lossy().into_owned();
                let Some(rel) = ps.strip_prefix(&format!("{root}/")).and_then(|r| r.strip_suffix(".desktop")) else { continue };
                let id = rel.replace('/', "-");
                if by_id.contains_key(&id) {
                    continue;
                }
                let Ok(text) = std::fs::read_to_string(&p) else { continue };
                let mut in_entry = false;
                let (mut icon, mut class) = (String::new(), String::new());
                for l in text.lines() {
                    let l = l.trim();
                    if l.starts_with('[') {
                        in_entry = l == "[Desktop Entry]";
                        continue;
                    }
                    if !in_entry {
                        continue;
                    }
                    if let Some(v) = l.strip_prefix("Icon=") {
                        icon = v.trim().into();
                    } else if let Some(v) = l.strip_prefix("StartupWMClass=") {
                        class = v.trim().into();
                    }
                }
                by_id.insert(format!("lc:{}", id.to_lowercase()), icon.clone());
                if !class.is_empty() {
                    by_class.entry(format!("wm:{class}")).or_insert(icon.clone());
                    by_class.entry(format!("wmlc:{}", class.to_lowercase())).or_insert(icon.clone());
                }
                by_id.insert(id, icon);
            }
        }
    }
    by_id.extend(by_class);
    by_id
}

/// The icon name for an app id: its desktop entry's Icon, else the app id
/// (Quickshell.iconPath(entry?.icon ?? appid, ...)).
fn icon_name(idx: &HashMap<String, String>, appid: &str) -> String {
    for k in [appid.to_string(), format!("lc:{}", appid.to_lowercase()), format!("wm:{appid}"), format!("wmlc:{}", appid.to_lowercase())] {
        if let Some(i) = idx.get(&k) {
            return i.clone();
        }
    }
    appid.into()
}

/// The theme qt6ct gives Qt, then its Inherits chain, then hicolor.
fn theme_chain() -> Vec<String> {
    let home = services::home();
    let conf = std::fs::read_to_string(format!("{home}/.config/qt6ct/qt6ct.conf")).unwrap_or_default();
    let first = conf.lines().find_map(|l| l.strip_prefix("icon_theme=")).unwrap_or("hicolor").to_string();
    let mut out = Vec::new();
    let mut queue = vec![first];
    while let Some(t) = queue.pop() {
        if out.contains(&t) {
            continue;
        }
        if let Some(dir) = icon_base_dirs().iter().map(|b| format!("{b}/{t}")).find(|d| std::path::Path::new(&format!("{d}/index.theme")).exists()) {
            let idx = std::fs::read_to_string(format!("{dir}/index.theme")).unwrap_or_default();
            if let Some(inh) = idx.lines().find_map(|l| l.strip_prefix("Inherits=")) {
                for i in inh.split(',').rev() {
                    queue.push(i.trim().into());
                }
            }
        }
        out.push(t);
    }
    if !out.contains(&"hicolor".to_string()) {
        out.push("hicolor".into());
    }
    out
}

fn icon_base_dirs() -> Vec<String> {
    let home = services::home();
    let mut v = vec![format!("{home}/.icons"), std::env::var("XDG_DATA_HOME").map(|d| format!("{d}/icons")).unwrap_or_else(|_| format!("{home}/.local/share/icons"))];
    v.extend(std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into()).split(':').map(|d| format!("{d}/icons")));
    v
}

/// QIcon::fromTheme(name): the first theme that has it - scalable first,
/// else the closest PNG at or above the size; /usr/share/pixmaps last.
fn find_icon(name: &str, size: u32) -> Option<String> {
    if name.is_empty() {
        return None;
    }
    if name.starts_with('/') {
        return std::path::Path::new(name).exists().then(|| name.to_string());
    }
    for theme in theme_chain() {
        let mut best: Option<(i64, String)> = None;
        for base in icon_base_dirs() {
            let root = format!("{base}/{theme}");
            let Ok(top) = std::fs::read_dir(&root) else { continue };
            for a in top.flatten().filter(|e| e.path().is_dir()) {
                let Ok(sub) = std::fs::read_dir(a.path()) else { continue };
                for b in sub.flatten().filter(|e| e.path().is_dir()) {
                    for ext in ["svg", "png"] {
                        let f = b.path().join(format!("{name}.{ext}"));
                        if !f.exists() {
                            continue;
                        }
                        let dirs = format!("{}/{}", a.file_name().to_string_lossy(), b.file_name().to_string_lossy());
                        let px = dirs.split(['/', 'x', '@']).filter_map(|p| p.parse::<i64>().ok()).max();
                        let score = if ext == "svg" { 0 } else { px.map_or(10_000, |p| if p >= size as i64 { p - size as i64 } else { 5_000 + size as i64 - p }) };
                        if best.as_ref().map_or(true, |(s, _)| score < *s) {
                            best = Some((score, f.to_string_lossy().into_owned()));
                        }
                    }
                }
            }
        }
        if let Some((_, p)) = best {
            return Some(p);
        }
    }
    ["png", "svg", "xpm"].iter().map(|e| format!("/usr/share/pixmaps/{name}.{e}")).find(|p| std::path::Path::new(p).exists())
}

/// The icon at size x size, premultiplied RGBA.
fn render_icon(path: &str, size: u32) -> Option<(u32, u32, Vec<u8>)> {
    let size = size.max(1);
    if path.ends_with(".svg") {
        let data = std::fs::read(path).ok()?;
        let tree = resvg::usvg::Tree::from_data(&data, &resvg::usvg::Options::default()).ok()?;
        let mut pm = resvg::tiny_skia::Pixmap::new(size, size)?;
        let s = tree.size();
        let k = (size as f32 / s.width()).min(size as f32 / s.height());
        let (dx, dy) = ((size as f32 - s.width() * k) / 2.0, (size as f32 - s.height() * k) / 2.0);
        resvg::render(&tree, resvg::tiny_skia::Transform::from_row(k, 0.0, 0.0, k, dx, dy), &mut pm.as_mut());
        return Some((size, size, pm.take()));
    }
    let img = image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.decode().ok()?.to_rgba8();
    let img = crate::gpu::scale(img, size, size);
    Some((size, size, crate::gpu::premultiply(img.into_raw())))
}

/// The icons the open overview needs, looked up and rendered off the main
/// thread.
fn load_icons(app: &mut App) {
    let mut jobs = Vec::new();
    let monitors = app.svc.mango.monitors.clone();
    for m in &monitors {
        let g = geo(m);
        for (c, _) in visible(&app.svc.overview, m, &g) {
            let o = &mut app.svc.overview;
            if !o.names.contains_key(&c.appid) {
                let name = icon_name(o.desktop.get_or_insert_with(desktop_index), &c.appid);
                o.names.insert(c.appid.clone(), name);
            }
            let Some(name) = o.names.get(&c.appid).cloned() else { continue };
            let size = icon_size(&c, m, &g).round() as u32;
            if o.icons.get(&name).map_or(false, |by| by.contains_key(&size)) || !o.icon_loading.insert((name.clone(), size)) {
                continue;
            }
            let known = o.icon_paths.get(&(name.clone(), size)).cloned();
            jobs.push((name, size, known));
        }
    }
    for (name, size, known) in jobs {
        app.background(
            move || {
                // Quickshell.iconPath(name, "image-missing"): QIcon::fromTheme(name), else the fallback's.
                let path = known.unwrap_or_else(|| find_icon(&name, size).or_else(|| find_icon("image-missing", size)));
                let img = path.as_deref().and_then(|p| render_icon(p, size));
                (name, size, path, img)
            },
            |app, (name, size, path, img)| {
                let o = &mut app.svc.overview;
                o.icon_loading.remove(&(name.clone(), size));
                o.icon_paths.insert((name.clone(), size), path);
                if !o.open {
                    return;
                }
                let tex = match (img, app.gpu.as_mut()) {
                    (Some((w, h, rgba)), Some(gpu)) => Some(Tex { id: gpu.add_image(w, h, rgba, false) }),
                    _ => None,
                };
                // A job queued before a quick close and reopen can land after
                // the reopen's own: the first texture is freed, not dropped.
                if let Some(Some(old)) = app.svc.overview.icons.entry(name).or_default().insert(size, tex) {
                    if let Some(gpu) = app.gpu.as_mut() {
                        gpu.drop_image(old.id);
                    }
                }
                redraw(app);
            },
        );
    }
}

// ---- layout ----

/// The panel's geometry on one monitor (whole pixels, as the layouts snap it).
struct Geo {
    reserved_top: f32,
    ws_w: f32,
    ws_h: f32,
    cell_w: f32,
    cell_h: f32,
    root: (f32, f32, f32, f32),
    grid: (f32, f32),
}

fn geo(m: &Monitor) -> Geo {
    let (w, h) = (m.width, m.height);
    let reserved_top = (34.0 * (w / 2560.0).clamp(0.9, 1.0)).round();
    let (ws_w, ws_h) = (w * SCALE, (h - reserved_top) * SCALE);
    let (cell_w, cell_h) = (ws_w.ceil(), ws_h.ceil());
    let grid_w = COLS as f32 * cell_w + (COLS - 1) as f32 * SPACING;
    let grid_h = ROWS as f32 * cell_h + (ROWS - 1) as f32 * SPACING;
    let (rw, rh) = (grid_w + 40.0, grid_h + 40.0);
    // anchors.horizontalCenter of the full-screen window: mango's monitor box
    // is already logical (wlr_output_layout), the window's own width.
    let root = (ac(w, rw), 100.0, rw, rh);
    Geo { reserved_top, ws_w, ws_h, cell_w, cell_h, root, grid: (root.0 + 20.0, root.1 + 20.0) }
}

fn active_ws(m: &Monitor) -> i64 {
    m.active_tags.first().copied().unwrap_or(1)
}

fn group(m: &Monitor) -> i64 {
    (active_ws(m) - 1) / (ROWS * COLS)
}

/// retileHidden(): a hidden workspace's tiled windows laid out afresh, as
/// mango would (halves, alternating), unless they already fill it.
fn retile(list: Vec<Client>, m: &Monitor, g: &Geo) -> Vec<Client> {
    let gap = 12.0;
    let area = (m.x + gap, m.y + g.reserved_top, m.width - 2.0 * gap, m.height - g.reserved_top - gap);
    let mut by_ws: HashMap<i64, Vec<usize>> = HashMap::new();
    for (i, w) in list.iter().enumerate() {
        if m.active_tags.contains(&w.ws()) || w.floating || w.fullscreen || w.maximized || w.global || w.scratchpad {
            continue;
        }
        by_ws.entry(w.ws()).or_default().push(i);
    }
    let mut placed: HashMap<i64, (f32, f32, f32, f32)> = HashMap::new();
    for (_, idx) in by_ws {
        let tiled: Vec<&Client> = idx.iter().map(|&i| &list[i]).collect();
        let mut covered = 0.0;
        let mut overlap = false;
        for (i, a) in tiled.iter().enumerate() {
            covered += a.width * a.height;
            for b in &tiled[i + 1..] {
                if a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height {
                    overlap = true;
                }
            }
        }
        if tiled.len() > 1 && !overlap && covered > 0.9 * area.2 * area.3 {
            continue;
        }
        let mut tiled = tiled;
        tiled.sort_by(|a, b| a.x.partial_cmp(&b.x).unwrap().then(a.y.partial_cmp(&b.y).unwrap()));
        let mut bx = area;
        for (i, w) in tiled.iter().enumerate() {
            let mut mine = bx;
            if i < tiled.len() - 1 {
                if bx.2 >= bx.3 {
                    let ww = (bx.2 - gap) / 2.0;
                    mine = (bx.0, bx.1, ww, bx.3);
                    bx = (bx.0 + ww + gap, bx.1, bx.2 - ww - gap, bx.3);
                } else {
                    let hh = (bx.3 - gap) / 2.0;
                    mine = (bx.0, bx.1, bx.2, hh);
                    bx = (bx.0, bx.1 + hh + gap, bx.2, bx.3 - hh - gap);
                }
            }
            placed.insert(w.id, mine);
        }
    }
    list.into_iter()
        .map(|mut w| {
            if let Some(&(x, y, ww, hh)) = placed.get(&w.id) {
                (w.x, w.y, w.width, w.height) = (x, y, ww, hh);
            }
            w
        })
        .collect()
}

/// The windows on this monitor's shown group, in drawing order, with their
/// resting rectangles in the window space.
fn visible(o: &Overview, m: &Monitor, g: &Geo) -> Vec<(Client, (f32, f32, f32, f32))> {
    let n = ROWS * COLS;
    let (lo, hi) = (group(m) * n, (group(m) + 1) * n);
    let list: Vec<Client> = o.clients.iter().filter(|w| w.monitor == m.name && !w.minimized && !(w.group && !w.group_focus) && lo < w.ws() && w.ws() <= hi).cloned().collect();
    let mut list = retile(list, m, g);
    list.sort_by_key(|w| (w.global, w.floating, w.focused));
    list.into_iter()
        .map(|w| {
            let col = (w.ws() - 1) % COLS;
            let row = (w.ws() - 1) % n / COLS;
            let x = ((w.x - m.x) * SCALE).max(0.0) + (g.ws_w + SPACING) * col as f32;
            let y = ((w.y - m.y - g.reserved_top) * SCALE).max(0.0) + (g.ws_h + SPACING) * row as f32;
            let r = (x, y, (w.width * SCALE).min(g.ws_w), (w.height * SCALE).min(g.ws_h));
            (w, r)
        })
        .collect()
}

fn icon_size(c: &Client, m: &Monitor, _g: &Geo) -> f32 {
    let (tw, th) = (c.width * SCALE, c.height * SCALE);
    let compact = 12.0 * 4.0 > th || 12.0 * 4.0 > tw;
    tw.min(th) * if compact { 0.45 } else { 0.25 } / m.scale.max(0.1)
}

fn monitor_of<'a>(svc: &'a Services, screen: &str) -> Option<&'a Monitor> {
    svc.mango.monitor(screen)
}

// ---- drawing ----

pub fn draw_osd(ui: &mut Ui<OsdState>, screen: u8, panel: (f32, f32, f32, f32), svc: &Services) {
    let Some(name) = svc.overview_screens.get(screen as usize) else { return };
    let Some(m) = monitor_of(svc, name) else { return };
    let o = &svc.overview;
    let t = ui.theme;
    let g = geo(m);
    let now = ui.now;
    let white = t.col_white;
    let wa = |a: f32| Color { a, ..white };
    let layer1 = Color { r: t.pal_bg.r * 0.5, g: t.pal_bg.g * 0.5, b: t.pal_bg.b * 0.5, a: 1.0 };
    let (rx, ry, rw, rh) = g.root;
    let (bx, by, bw, bh) = (rx + 10.0, ry + 10.0, rw - 20.0, rh - 20.0);
    ui.scene.shadow(bx, by, bw, bh, Color::qt_rgba(0.0, 0.0, 0.0, 0.3), 9.0, 1.0, (0.0, 1.0));
    ui.scene.rect(bx, by, bw, bh, t.pal_bg, 0.0, 1.0, wa(0.14), false);
    let (gx, gy) = g.grid;
    let n = ROWS * COLS;
    // The workspaces: a dark well each, its number faint in the middle.
    for r in 0..ROWS {
        for c in 0..COLS {
            let value = group(m) * n + r * COLS + c + 1;
            let (x, y) = (gx + c as f32 * (g.cell_w + SPACING), gy + r as f32 * (g.cell_h + SPACING));
            let drop = o.drop_ws == Some((screen, value)) && o.press.as_ref().map_or(false, |p| p.dragging);
            let hover_c = Color { r: 0.08 * white.r + 0.92 * layer1.r, g: 0.08 * white.g + 0.92 * layer1.g, b: 0.08 * white.b + 0.92 * layer1.b, a: 1.0 };
            let fill = if drop { Color { r: 0.1 * layer1.r + 0.9 * hover_c.r, g: 0.1 * layer1.g + 0.9 * hover_c.g, b: 0.1 * layer1.b + 0.9 * hover_c.b, a: 1.0 } } else { layer1 };
            ui.scene.rect(x, y, g.cell_w, g.cell_h, fill, 0.0, 2.0, if drop { wa(0.4) } else { Color::TRANSPARENT }, false);
            let num = ui.fonts.layout(&value.to_string(), NUMBER, (250.0 * m.scale * SCALE).round(), 0.0);
            ui.text(&num, x + (g.cell_w - num.adv) / 2.0, y + (g.cell_h - num.height()) / 2.0, wa(0.2), TextStyle::Native(1));
        }
    }
    // The windows, then the frame on the active workspace.
    let wins = visible(o, m, &g);
    // Where each tile is. A window whose data changed is a new delegate in
    // QML (ScriptModel compares structurally), so a new resting place is
    // taken at once and the size never animates; only followWindow() after
    // a drag animates, from where the tile was let go. The dragged tile is
    // where the drag puts it (setPosition, no Behavior).
    let press = o.press.as_ref().filter(|p| p.screen == screen);
    let mut at: Vec<(f32, f32)> = Vec::with_capacity(wins.len());
    for (c, (tx, ty, _, _)) in &wins {
        if let Some(p) = press.filter(|p| p.dragging && p.id == c.id) {
            let (dx, dy) = p.offset();
            at.push((tx + dx, ty + dy));
            continue;
        }
        let from = o.dropped.get(&(screen, c.id)).filter(|d| d.rest == (*tx, *ty));
        let (kx, ky) = tile_keys(c.id, (*tx, *ty), from.map(|d| d.serial));
        if let Some(d) = from {
            if ui.card.number_peek(kx, now).is_none() {
                ui.card.number_e(kx, d.at.0, 400, ENTER, now);
                ui.card.number_e(ky, d.at.1, 400, ENTER, now);
            }
        }
        let (x, r1) = ui.card.number_e(kx, *tx, 400, ENTER, now);
        let (y, r2) = ui.card.number_e(ky, *ty, 400, ENTER, now);
        ui.animating |= r1 || r2;
        at.push((x, y));
    }
    // z: windowZ + index at rest, windowDraggingZ while away from it; the
    // frame (windowZ, declared after the windows) right above the first.
    let away: Vec<bool> = wins.iter().zip(&at).map(|((_, r), a)| *a != (r.0, r.1)).collect();
    let first_rests = away.first() == Some(&false);
    if !first_rests {
        draw_indicator(ui, m, &g, white);
    }
    let order: Vec<usize> = (0..wins.len()).filter(|&i| !away[i]).chain((0..wins.len()).filter(|&i| away[i])).collect();
    for i in order {
        let (c, (_, _, w, h)) = &wins[i];
        let (x, y, w, h) = (gx + at[i].0, gy + at[i].1, *w, *h);
        ui.scene.save();
        ui.scene.clip_rect(x, y, w, h);
        if let Some((tex, _)) = o.previews.get(&c.id) {
            ui.scene.image(tex.id, x, y, w, h, [0.0, 0.0, 1.0, 1.0]);
        }
        let pressed = press.map_or(false, |p| p.id == c.id);
        let hovered = o.hovered == Some((screen, c.id));
        let wash = if pressed { wa(0.22) } else if hovered { wa(0.12) } else { wa(0.0) };
        ui.scene.rect(x, y, w, h, wash, 0.0, 1.0, Color { a: 0.3, ..t.col_grey }, false);
        // The icon at its size; until that is rendered, the closest one there
        // is (QML's new tile loads its icon synchronously, nothing blinks).
        let s = icon_size(c, m, &g);
        let want = s.round() as u32;
        let tex = o.names.get(&c.appid).and_then(|n| o.icons.get(n)).and_then(|by| match by.get(&want) {
            Some(t) => *t,
            None => by.iter().filter_map(|(k, t)| t.map(|t| (k.abs_diff(want), t))).min_by_key(|e| e.0).map(|e| e.1),
        });
        if let Some(tex) = tex {
            ui.scene.image(tex.id, x + ac(w, s), y + ac(h, s), s, s, [0.0, 0.0, 1.0, 1.0]);
        }
        ui.scene.restore();
        if i == 0 && first_rests {
            draw_indicator(ui, m, &g, white);
        }
    }
    // The hovered window's tooltip (StyledToolTip, a Basic ToolTip), shown
    // while the pointer is in the tile and no button is held (Drag.active
    // goes up on the press). Each show grows the plate from its bottom
    // centre and fades it in (elementMoveFast); a hide is at once.
    let tip = if o.press.is_none() { o.hovered.filter(|h| h.0 == screen).and_then(|h| wins.iter().position(|(c, _)| c.id == h.1)) } else { None };
    let mut prog = 0.0;
    for (i, (c, _)) in wins.iter().enumerate() {
        let key = 0x4000_0000 | (c.id as u32 & 0x3FFF_FFFF);
        if ui.card.number_peek(key, now).is_none() {
            ui.card.number_e(key, 0.0, 200, FAST, now);
        }
        let (v, run) = ui.card.number_e(key, if tip == Some(i) { 1.0 } else { 0.0 }, 200, FAST, now);
        if tip == Some(i) {
            prog = v;
            ui.animating |= run;
        }
    }
    if let Some(i) = tip {
        let (c, (_, _, tw, _)) = &wins[i];
        let (x, y) = (gx + at[i].0, gy + at[i].1);
        // `?? "Unknown"` only catches null, and mango always sends strings.
        let text = format!("{}\n[{}] {}", c.title, c.appid, if c.xwayland { "[XWayland] " } else { "" });
        // One left-aligned Text; a line's trailing spaces take no width.
        let lines: Vec<_> = text.lines().map(|l| ui.fonts.layout(l.trim_end(), MAIN, 12.0, 0.0)).collect();
        let tw_ = lines.iter().map(|l| l.width).fold(0.0, f32::max);
        let th_: f32 = lines.iter().map(|l| l.height()).sum();
        // The plate is the content item: text + 10/5 padding. The popup pads
        // it once more: x = (tile w - implicitWidth) / 2, y = -implicitHeight
        // - 3, kept 6 px inside the window (margins: 6).
        let (pw, ph) = (tw_ + 20.0, th_ + 10.0);
        let (ow, oh) = (pw + 20.0, ph + 10.0);
        let mut ox = x + (tw - ow) / 2.0;
        if panel.2 - 12.0 >= ow {
            ox = ox.max(6.0).min(panel.2 - 6.0 - ow);
        }
        let (cx, cy) = (ox + 10.0, y - oh - 3.0 + 5.0);
        let (bw, bh) = (pw * prog, ph * prog);
        let (bx, by) = (cx + ac(pw, bw), cy + ph - bh);
        ui.scene.save();
        ui.scene.multiply_opacity(prog);
        ui.scene.rect(bx, by, bw, bh, t.pal_bg, 0.0, 1.0, wa(0.14), false);
        ui.scene.clip_rect(bx, by, bw, bh);
        let (lx, mut ly) = (bx + ac(bw, tw_), by + ac(bh, th_));
        for l in &lines {
            ui.text(l, lx, ly, white, TextStyle::Native(2));
            ly += l.height();
        }
        ui.scene.restore();
    }
}

/// A tile's x and y animation keys: a pair per resting place (and per drop),
/// so a new place is a new item that starts where it rests, as QML's new
/// delegate does. Bit 31 keeps them apart from the frame's and the tooltips'.
fn tile_keys(id: i64, rest: (f32, f32), drop: Option<u32>) -> (u32, u32) {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    (id, rest.0.to_bits(), rest.1.to_bits(), drop).hash(&mut h);
    let k = (h.finish() as u32 | 0x8000_0000) & !1;
    (k, k | 1)
}

/// The frame on the active workspace (z = windowZ: above the first window,
/// under the others).
fn draw_indicator(ui: &mut Ui<OsdState>, m: &Monitor, g: &Geo, white: Color) {
    let n = ROWS * COLS;
    let (gx, gy) = g.grid;
    let now = ui.now;
    let active = active_ws(m) - group(m) * n;
    let (ar, ac_) = ((active - 1) / COLS, (active - 1) % COLS);
    let (fx, r1) = ui.card.number_e(0xF00_0001, (g.ws_w + SPACING) * ac_ as f32, 200, FAST, now);
    let (fy, r2) = ui.card.number_e(0xF00_0002, (g.ws_h + SPACING) * ar as f32, 200, FAST, now);
    ui.animating |= r1 || r2;
    ui.scene.rect(gx + fx, gy + fy, g.ws_w, g.ws_h, Color::TRANSPARENT, 0.0, 2.0, white, false);
}

// ---- input ----

/// The window under the pointer on a screen: the topmost by drawing order.
fn window_at(app: &App, screen: u8, x: f32, y: f32) -> Option<i64> {
    let name = app.svc.overview_screens.get(screen as usize)?;
    let m = app.svc.mango.monitor(name)?;
    let g = geo(m);
    let (gx, gy) = g.grid;
    visible(&app.svc.overview, m, &g).into_iter().rev().find(|(_, (wx, wy, ww, wh))| x >= gx + wx && x < gx + wx + ww && y >= gy + wy && y < gy + wy + wh).map(|(c, _)| c.id)
}

/// A window's tile where it rests, in the overview window's coordinates.
fn tile_rect(app: &App, screen: u8, id: i64) -> Option<(f32, f32, f32, f32)> {
    let name = app.svc.overview_screens.get(screen as usize)?;
    let m = app.svc.mango.monitor(name)?;
    let g = geo(m);
    let (gx, gy) = g.grid;
    visible(&app.svc.overview, m, &g).into_iter().find(|(c, _)| c.id == id).map(|(_, (x, y, w, h))| (gx + x, gy + y, w, h))
}

fn workspace_at(app: &App, screen: u8, x: f32, y: f32) -> Option<i64> {
    let name = app.svc.overview_screens.get(screen as usize)?;
    let m = app.svc.mango.monitor(name)?;
    let g = geo(m);
    let (gx, gy) = g.grid;
    for r in 0..ROWS {
        for c in 0..COLS {
            let (wx, wy) = (gx + c as f32 * (g.cell_w + SPACING), gy + r as f32 * (g.cell_h + SPACING));
            if x >= wx && x < wx + g.cell_w && y >= wy && y < wy + g.cell_h {
                return Some(group(m) * ROWS * COLS + r * COLS + c + 1);
            }
        }
    }
    None
}

/// Every pointer event on an overview window: the window tiles' MouseAreas
/// (left and middle, drag.target: the tile), the workspaces' (left, click
/// only) and the background's press beside the panel (OverviewWidget.qml,
/// Overview.qml).
pub fn pointer(app: &mut App, screen: u8, ev: &PointerEventKind, x: f32, y: f32) -> bool {
    match ev {
        PointerEventKind::Motion { .. } | PointerEventKind::Enter { .. } => {
            app.svc.overview.pointer = Some((screen, x, y));
            if let Some(p) = app.svc.overview.press.as_mut() {
                if p.screen != screen {
                    return !matches!(ev, PointerEventKind::Enter { .. });
                }
                p.pos = (x, y);
                // MouseArea drag (threshold 10, smoothed): the move that passes
                // the threshold re-bases the drag, the next one starts it.
                if p.id >= 0 && !p.dragging {
                    if p.origin.is_some() {
                        p.dragging = true;
                    } else if (x - p.start.0).abs() > 10.0 || (y - p.start.1).abs() > 10.0 {
                        p.origin = Some((x, y));
                    }
                }
                if p.dragging {
                    // DropArea: the workspace under the hot spot lights up,
                    // unless it is the window's own.
                    let (id, hot) = (p.id, p.hotspot());
                    let own = app.svc.overview.clients.iter().find(|c| c.id == id).map(|c| c.ws());
                    app.svc.overview.drop_ws = workspace_at(app, screen, hot.0, hot.1).filter(|w| Some(*w) != own).map(|w| (screen, w));
                    redraw_screen(app, screen);
                }
            } else {
                rehover(app);
            }
            // An enter goes on to app.rs, which shows the arrow: QtWayland sets
            // the window's cursor on every enter, and nothing here has a hand.
            !matches!(ev, PointerEventKind::Enter { .. })
        }
        PointerEventKind::Leave { .. } => {
            if app.svc.overview.pointer.map_or(false, |p| p.0 == screen) {
                app.svc.overview.pointer = None;
            }
            if app.svc.overview.hovered.map_or(false, |h| h.0 == screen) {
                app.svc.overview.hovered = None;
                redraw_screen(app, screen);
            }
            true
        }
        PointerEventKind::Press { button, .. } => {
            // The MouseArea that took a press keeps the pointer until it ends.
            // The same button going down again means its release went to
            // another surface (a grab the compositor broke, e.g. a lock
            // screen): that press is over, and this one counts.
            match app.svc.overview.press.as_ref().map(|p| (p.button, p.screen)) {
                Some((b, _)) if b != *button => return true,
                Some((_, s)) => {
                    app.svc.overview.press = None;
                    app.svc.overview.drop_ws = None;
                    redraw_screen(app, s);
                }
                None => {}
            }
            // A press beside the panel (outside its width) leaves.
            if let Some(m) = app.svc.overview_screens.get(screen as usize).and_then(|n| app.svc.mango.monitor(n)) {
                let g = geo(m);
                let half = g.root.2 / 2.0;
                let centre = m.width / 2.0;
                if x < centre - half || x > centre + half {
                    close(app);
                    return true;
                }
            }
            let base = Press { screen, id: -1, button: *button, start: (x, y), pos: (x, y), origin: None, dragging: false, cell: None };
            if let Some(id) = window_at(app, screen, x, y).filter(|_| *button == BTN_LEFT || *button == BTN_MIDDLE) {
                app.svc.overview.press = Some(Press { id, ..base });
                redraw_screen(app, screen);
            } else if *button == BTN_LEFT {
                app.svc.overview.press = Some(Press { cell: workspace_at(app, screen, x, y), ..base });
            }
            true
        }
        PointerEventKind::Release { button, .. } => {
            if app.svc.overview.press.as_ref().map_or(true, |p| p.button != *button) {
                return true;
            }
            let Some(p) = app.svc.overview.press.take() else { return true };
            app.svc.overview.drop_ws = None;
            redraw_screen(app, screen);
            rehover(app);
            if p.id < 0 {
                // The workspace's onClicked: released on the workspace it went
                // down on, however far it moved.
                if let Some(ws) = p.cell.filter(|c| workspace_at(app, screen, x, y) == Some(*c)) {
                    let name = app.svc.overview_screens.get(screen as usize).cloned().unwrap_or_default();
                    close(app);
                    services::mango_dispatch(app, &format!("viewcrossmon,{ws},^{name}$"));
                }
                return true;
            }
            let Some(win) = app.svc.overview.clients.iter().find(|c| c.id == p.id).cloned() else { return true };
            if p.dragging {
                // onReleased: the workspace under the hot spot takes the
                // window; its own keeps it (dropInside). No click after a drag.
                remember_drop(app, screen, &p);
                let hot = p.hotspot();
                match workspace_at(app, screen, hot.0, hot.1) {
                    Some(t) if t != win.ws() => services::mango_dispatch_client(app, &format!("tagsilent,{t}"), win.id),
                    Some(_) => drop_inside(app, screen, &win, &p),
                    None => {}
                }
                return true;
            }
            // onClicked: released inside the tile it went down on.
            if !tile_rect(app, screen, win.id).map_or(false, |(tx, ty, tw, th)| x >= tx && x < tx + tw && y >= ty && y < ty + th) {
                return true;
            }
            match p.button {
                BTN_LEFT => {
                    close(app);
                    services::mango_dispatch_client(app, "focusid", win.id);
                }
                BTN_MIDDLE => services::mango_dispatch_client(app, "killclient", win.id),
                _ => {}
            }
            true
        }
        _ => true,
    }
}

/// followWindow() after a drag: the tile goes back from where it was let go.
fn remember_drop(app: &mut App, screen: u8, p: &Press) {
    let Some(name) = app.svc.overview_screens.get(screen as usize) else { return };
    let Some(m) = app.svc.mango.monitor(name) else { return };
    let g = geo(m);
    let Some((_, (tx, ty, ..))) = visible(&app.svc.overview, m, &g).into_iter().find(|(c, _)| c.id == p.id) else { return };
    let (dx, dy) = p.offset();
    let o = &mut app.svc.overview;
    o.drop_serial = o.drop_serial.wrapping_add(1);
    o.dropped.insert((screen, p.id), Dropped { serial: o.drop_serial, at: (tx + dx, ty + dy), rest: (tx, ty) });
}

/// dropInside(): a floating window moves there; a tiled one swaps with the
/// tiled window under the hot spot.
fn drop_inside(app: &mut App, screen: u8, win: &Client, p: &Press) {
    let (dx, dy) = p.offset();
    if dx.abs() < 8.0 && dy.abs() < 8.0 {
        return;
    }
    let Some(name) = app.svc.overview_screens.get(screen as usize).cloned() else { return };
    let Some(m) = app.svc.mango.monitor(&name).cloned() else { return };
    let g = geo(&m);
    let (gx, gy) = g.grid;
    let list = visible(&app.svc.overview, &m, &g);
    // The tile's windowData: on a hidden workspace, laid out afresh.
    let Some((me, (tx, ty, ..))) = list.iter().find(|(c, _)| c.id == win.id) else { return };
    if me.floating {
        let col = (me.ws() - 1) % COLS;
        let row = (me.ws() - 1) % (ROWS * COLS) / COLS;
        let (xo, yo) = ((g.ws_w + SPACING) * col as f32, (g.ws_h + SPACING) * row as f32);
        let x = (m.x + (tx + dx - xo).max(0.0) / SCALE).round();
        let y = (m.y + g.reserved_top + (ty + dy - yo).max(0.0) / SCALE).round();
        services::mango_dispatch_client(app, &format!("movewin,{x},{y}"), win.id);
        return;
    }
    let (hx, hy) = (p.hotspot().0 - gx, p.hotspot().1 - gy);
    let target = list.iter().filter(|(c, _)| c.id != me.id && c.ws() == me.ws() && !c.floating).filter(|(_, (x, y, w, h))| hx >= *x && hx < x + w && hy >= *y && hy < y + h).map(|(c, _)| c).last();
    let Some(t) = target else { return };
    let (cx, cy) = ((t.x + t.width / 2.0) - (me.x + me.width / 2.0), (t.y + t.height / 2.0) - (me.y + me.height / 2.0));
    let dir = if cx.abs() >= cy.abs() { if cx > 0.0 { "right" } else { "left" } } else if cy > 0.0 { "down" } else { "up" };
    let swap = format!("mmsg dispatch exchange_client,{dir} client,{}", me.id);
    if m.active_tags.contains(&me.ws()) {
        app.exec_detached(&["sh", "-c", &swap]);
    } else {
        let cmd = format!("mmsg dispatch 'viewcrossmon,{},^{}$' && {swap}", me.ws(), m.name);
        app.exec_detached(&["sh", "-c", &cmd]);
    }
}

/// Esc / Return leave; the arrows walk the shown group's workspaces.
pub fn key(app: &mut App, sym: smithay_client_toolkit::seat::keyboard::Keysym) {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    match sym {
        Keysym::Escape | Keysym::Return => close(app),
        // Qt's xkb table gives the keypad's arrows (Num Lock off) the arrow
        // keys' codes (qxkbcommon.cpp:107-110), so Overview.qml:72 takes them.
        Keysym::Left | Keysym::Right | Keysym::Up | Keysym::Down | Keysym::KP_Left | Keysym::KP_Right | Keysym::KP_Up | Keysym::KP_Down => {
            let n = ROWS * COLS;
            let cur = app.svc.mango.focused().and_then(|m| m.active_tags.first().copied()).unwrap_or(1);
            let grp = (cur - 1) / n;
            let (lo, hi) = (grp * n + 1, grp * n + n);
            let target = match sym {
                Keysym::Left | Keysym::KP_Left => if cur - 1 < lo { hi } else { cur - 1 },
                Keysym::Right | Keysym::KP_Right => if cur + 1 > hi { lo } else { cur + 1 },
                Keysym::Up | Keysym::KP_Up => if cur - COLS < lo { cur - COLS + n } else { cur - COLS },
                _ => if cur + COLS > hi { cur + COLS - n } else { cur + COLS },
            };
            services::mango_dispatch(app, &format!("view,{target},0"));
        }
        _ => {}
    }
}
