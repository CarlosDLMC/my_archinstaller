//! ClipboardState + ClipboardOsd: the clipboard history (SUPER ALT V) from
//! cliphist - a search line, the entries (image ones with thumbnails), the
//! selected one's preview, and pick / delete / wipe through clip.sh.

use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

use crate::app::{App, Mods};
use crate::bar::{ac, Action, Hit};
use crate::cards::{lamp, Ui, UiState};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::osd::{self, OpenParams, OsdKind};
use crate::services::{self, Services};
use crate::text::{FontKey, Line};
use crate::theme;

const FADE_MS: u64 = 160;
const UI: f32 = 1.35;
const ROW_BASE: u32 = 0x1000;
const CONTENT: FontKey = FontKey { family: theme::FONT_CONTENT, bold: false, plain: false };

fn px(v: f32) -> f32 {
    (v * UI).round()
}

#[derive(Clone)]
pub struct Entry {
    pub id: String,
    pub preview: String,
    /// An image's size text and pixel size (cliphist's "[[ binary data ... ]]").
    pub image: Option<(String, i64, i64)>,
}

/// A decoded image on the GPU: texture id and size.
#[derive(Clone, Copy)]
pub struct Tex {
    pub id: u32,
    pub w: u32,
    pub h: u32,
}

#[derive(Default)]
pub struct Clip {
    pub open: bool,
    pub entries: Vec<Entry>,
    pub filter: String,
    /// The search line's cursor (byte index) and Ctrl+A's selection.
    cursor: usize,
    select_all: bool,
    blink_since: Option<Instant>,
    pub selected: usize,
    pub loading: bool,
    /// ListView.contentY where the list comes to rest, and the wheel's glide
    /// towards it: (from, to, start).
    pub scroll: f32,
    glide: Option<(f32, f32, Instant)>,
    /// Decoded thumbnail files (id -> path), the queue, the one decoding.
    thumbs: HashMap<String, String>,
    pending: VecDeque<String>,
    decoding: Option<String>,
    /// Row thumbnails (sourceSize 96, crop) and the preview (900 x 700, fit).
    pub thumb_tex: HashMap<String, Tex>,
    pub preview_tex: Option<(String, Tex)>,
    loading_tex: Vec<String>,
    keep_index: usize,
    /// filtered()'s last answer: (filter, entries_gen, indices into entries).
    filtered_memo: std::cell::RefCell<Option<(String, u64, Vec<usize>)>>,
    /// Counts the times `entries` was replaced.
    entries_gen: u64,
}

fn script() -> String {
    format!("{}/.config/quickshell/bar/scripts/clip.sh", services::home())
}

fn thumb_dir() -> String {
    // Quickshell.env("XDG_CACHE_HOME") || HOME + "/.cache": empty counts as unset.
    let cache = std::env::var("XDG_CACHE_HOME").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| format!("{}/.cache", services::home()));
    format!("{cache}/quickshell/clip-thumbs")
}

/// parseList(): `id<TAB>preview`, image entries recognised by cliphist's
/// "[[ binary data SIZE UNIT TYPE WxH ]]".
fn parse_list(text: &str) -> Vec<Entry> {
    text.lines()
        .filter_map(|l| l.split_once('\t'))
        .map(|(id, preview)| {
            let image = preview.strip_prefix("[[ binary data ").and_then(|rest| {
                let mut it = rest.split(' ');
                let (n, unit, _ty, dims) = (it.next()?, it.next()?, it.next()?, it.next()?);
                let (w, h) = dims.split_once('x')?;
                let h: String = h.chars().take_while(|c| c.is_ascii_digit()).collect();
                Some((format!("{n} {unit}"), w.parse().ok()?, h.parse().ok()?))
            });
            Entry { id: id.into(), preview: preview.into(), image }
        })
        .collect()
}

impl Clip {
    /// The entries the filter keeps (image ones also match "image"). Like the
    /// `filtered` binding it is worked out once per change of the filter or
    /// of the history, not at each call (every redraw asks twice, each key
    /// about five times).
    pub fn filtered(&self) -> Vec<&Entry> {
        let mut memo = self.filtered_memo.borrow_mut();
        if !matches!(&*memo, Some((f, g, _)) if *f == self.filter && *g == self.entries_gen) {
            let f = self.filter.trim().to_lowercase();
            let keep = |e: &Entry| {
                let mut hay = e.preview.to_lowercase();
                if e.image.is_some() {
                    hay += " image screenshot picture";
                }
                hay.contains(&f)
            };
            let idx = (0..self.entries.len()).filter(|&i| f.is_empty() || keep(&self.entries[i])).collect();
            *memo = Some((self.filter.clone(), self.entries_gen, idx));
        }
        let Some((_, _, idx)) = memo.as_ref() else { return Vec::new() };
        idx.iter().filter_map(|&i| self.entries.get(i)).collect()
    }
    fn current(&self) -> Option<Entry> {
        self.filtered().get(self.selected).map(|e| (*e).clone())
    }
    /// ListView.contentY on the wheel's glide; None once it has ended.
    fn glide_at(&self, now: Instant) -> Option<f32> {
        let (from, to, start) = self.glide?;
        let t = now.saturating_duration_since(start).as_secs_f32() * 1000.0 / GLIDE_MS;
        (t < 1.0).then(|| from + (to - from) * out_expo(t))
    }
    /// ListView.contentY now.
    fn scroll_at(&self, now: Instant) -> f32 {
        self.glide_at(now).unwrap_or(self.scroll)
    }
}

/// Component.onCompleted: reload(); and the IPC's toggle.
pub fn start(app: &mut App) {
    reload(app);
}

fn reload(app: &mut App) {
    app.svc.clip.loading = true;
    app.spawn("cliphist", &["cliphist", "-preview-width", "800", "list"], |app, d| {
        let c = &mut app.svc.clip;
        c.loading = false;
        let next = parse_list(&d.stdout);
        if !(next.len() == c.entries.len() && (next.is_empty() || next[0].id == c.entries[0].id)) {
            c.entries = next;
            c.entries_gen += 1;
            model_reset(app);
        }
        changed(app);
    });
}

pub fn toggle(app: &mut App) {
    if app.svc.clip.open {
        close(app);
    } else {
        open(app);
    }
}

fn open(app: &mut App) {
    let c = &mut app.svc.clip;
    c.filter.clear();
    c.cursor = 0;
    c.select_all = false;
    c.selected = 0;
    c.scroll = 0.0;
    c.glide = None;
    c.open = true;
    c.blink_since = Some(Instant::now());
    reload(app);
    show(app);
    blink(app);
    ensure_thumbs(app);
}

pub fn close(app: &mut App) {
    let c = &mut app.svc.clip;
    if !c.open {
        return;
    }
    c.open = false;
    c.thumbs.clear();
    c.pending.clear();
    osd::hide(app, OsdKind::Clipboard);
    // The Loader goes with the window: so do the images.
    app.after(Duration::from_millis(FADE_MS + 20), drop_textures);
    app.debounce("clip-thumbclean", Duration::from_millis(400), |app| {
        if app.svc.clip.open || app.is_running("clip-thumbclean") {
            return;
        }
        let cmd = format!("{} thumbclean {}", script(), thumb_dir());
        app.spawn("clip-thumbclean", &["sh", "-c", &cmd], |_, _| {});
    });
}

fn drop_textures(app: &mut App) {
    if app.svc.clip.open {
        return;
    }
    let c = &mut app.svc.clip;
    let ids: Vec<u32> = c.thumb_tex.drain().map(|(_, t)| t.id).chain(c.preview_tex.take().map(|(_, t)| t.id)).collect();
    if let Some(gpu) = app.gpu.as_mut() {
        for id in ids {
            gpu.drop_image(id);
        }
    }
    unsafe { libc::malloc_trim(0) };
}

fn show(app: &mut App) {
    let Some((_, sw, sh)) = osd::focused_output(app) else { return };
    let (w, h) = (px(820.0), px(480.0));
    let fresh = app.osd(OsdKind::Clipboard).is_none();
    osd::show(app, OpenParams { kind: OsdKind::Clipboard, size: (w as u32, h as u32), panel: (0.0, 0.0, w, h), dim: Some(Color::qt_rgba(0.0, 0.0, 0.0, 0.45)), keyboard: true, namespace: "quickshell", fade_ms: FADE_MS, min_scale: 0.97, fade_easing: crate::anim::Easing::Linear, pos: Some((ac(sw, w) as i32, ac(sh, h) as i32)), fill: false, output: None });
    // The card is in the Loader (ClipboardOsd.qml:132-138), which builds it
    // when onShownChanged sets windowVisible - `shown` is already true, so
    // its opacity and scale start at 1 and their Behaviors never run: QML
    // pops the card in and only the dim fades. Reopened while it is still
    // fading out, the loaded card animates back (osd::show's re-show).
    if fresh {
        if let Some(o) = app.osd_mut(OsdKind::Clipboard) {
            o.fade.snap(1.0);
        }
    }
}

/// The model was replaced: ListView makes every delegate anew.
fn model_reset(app: &mut App) {
    if let Some(o) = app.osd_mut(OsdKind::Clipboard) {
        o.st.texts.forget_parts(&[0xD1, 0xD2]);
    }
}

fn changed(app: &mut App) {
    if let Some(o) = app.osd_mut(OsdKind::Clipboard) {
        o.win.dirty = true;
    }
    ensure_thumbs(app);
}

/// The search line's cursor blinks 500/500 while the dialog is up.
fn blink(app: &mut App) {
    if !app.svc.clip.open {
        return;
    }
    // mango closes the layer surfaces of a screen that goes away; QML's
    // ClipboardOsd is a window per screen, shown on the focused one, so the
    // open picker shows up there. Without this, `open` stayed true with no
    // dialog and the next SUPER+ALT+V only "closed" it.
    if app.osd(OsdKind::Clipboard).is_none() {
        show(app);
    }
    if let Some(o) = app.osd_mut(OsdKind::Clipboard) {
        o.win.dirty = true;
    }
    let since = app.svc.clip.blink_since.get_or_insert_with(Instant::now).elapsed().as_millis() as u64;
    app.debounce("clip-blink", Duration::from_millis(500 - since % 500), blink);
}

// ---- thumbnails ----

struct M {
    card_w: f32,
    card_h: f32,
    pad: f32,
    radius: f32,
    row_h: f32,
    title: f32,
    row: f32,
    hint: f32,
}

fn met() -> M {
    M { card_w: px(820.0), card_h: px(480.0), pad: px(18.0), radius: px(12.0), row_h: px(38.0), title: px(14.0), row: px(13.0), hint: px(11.0) }
}

/// The list view's height (the body Item minus the plate's 6 px insets).
fn view_h() -> f32 {
    body_h() - 12.0
}

fn body_h() -> f32 {
    let m = met();
    m.card_h - 2.0 * m.pad - (m.title * 2.0).round() - (m.hint * 2.4).round() - px(20.0)
}

/// The ListView in the panel, where draw_osd puts it: (x, y, w, h).
fn list_rect() -> (f32, f32, f32, f32) {
    let m = met();
    let list_w = ((m.card_w - 2.0 * m.pad) * 0.52).round();
    (m.pad + 6.0, m.pad + (m.title * 2.0).round() + px(10.0) + 6.0, list_w - 12.0, view_h())
}

/// contentHeight - height for `n` rows of row_h, 2 px apart.
fn max_scroll(n: usize) -> f32 {
    (n as f32 * (met().row_h + 2.0) - 2.0 - view_h()).max(0.0)
}

/// QQuickFlickable::wheelEvent's glide: 3/4 of fixupDuration (400 ms).
const GLIDE_MS: f32 = 300.0;

/// easing.cpp easeOutExpo: a hair past 1 just before the end.
fn out_expo(t: f32) -> f32 {
    if t >= 1.0 {
        1.0
    } else {
        1.001 * (1.0 - 2f32.powf(-10.0 * t))
    }
}

/// QQuickFlickablePrivate::fixup: between the ends contentY goes to a whole
/// pixel - the nearest within a quarter, else back against the motion (`dir`
/// is the sign of smoothVelocity; 0 rounds).
fn fixup(y: f32, dir: f32, max: f32) -> f32 {
    if y <= 0.0 || y >= max || y.fract() == 0.0 {
        y.clamp(0.0, max)
    } else if (y.round() - y).abs() < 0.25 || dir == 0.0 {
        y.round()
    } else if dir > 0.0 {
        y.floor()
    } else {
        y.ceil()
    }
}

/// Delegates exist for the rows in view plus ListView's cacheBuffer; each
/// image row asks for its thumbnail, and so does the preview.
fn ensure_thumbs(app: &mut App) {
    let c = &app.svc.clip;
    if !c.open {
        return;
    }
    let step = met().row_h + 2.0;
    let (lo, hi) = (c.scroll - 320.0, c.scroll + view_h() + 320.0);
    let mut want: Vec<String> = c
        .filtered()
        .iter()
        .enumerate()
        .filter(|(i, e)| e.image.is_some() && (*i as f32 * step + step) > lo && (*i as f32 * step) < hi)
        .map(|(_, e)| e.id.clone())
        .collect();
    if let Some(cur) = c.current().filter(|e| e.image.is_some()) {
        want.push(cur.id);
    }
    for id in want {
        request_thumb(app, id);
    }
    load_textures(app);
}

fn request_thumb(app: &mut App, id: String) {
    let c = &mut app.svc.clip;
    if c.thumbs.contains_key(&id) || c.decoding.as_deref() == Some(&id) || c.pending.contains(&id) {
        return;
    }
    c.pending.push_back(id);
    pump(app);
}

/// pumpThumbs(): clip.sh decodes one at a time.
fn pump(app: &mut App) {
    if app.svc.clip.decoding.is_some() || app.is_running("clip-thumb") {
        return;
    }
    let c = &mut app.svc.clip;
    let Some(id) = c.pending.pop_front() else { return };
    c.decoding = Some(id.clone());
    let cmd = format!("{} thumb {id} {}/{id}.img", script(), thumb_dir());
    app.spawn("clip-thumb", &["sh", "-c", &cmd], |app, d| {
        let c = &mut app.svc.clip;
        if let Some(id) = c.decoding.take() {
            // Only while open. close() has emptied the map and thumbclean
            // deletes the file 400 ms later: recorded after close, the entry
            // pointed at nothing, and the next open never asked for that
            // picture again - a row (and its preview) left on the glyph.
            // QML's onExited records it all the same; this keeps its intent.
            if d.ok && c.open {
                c.thumbs.insert(id.clone(), format!("{}/{id}.img", thumb_dir()));
            }
        }
        pump(app);
        load_textures(app);
    });
}

/// Image { asynchronous: true; sourceSize }: decode off the main thread at
/// the size QML asks for, then upload.
fn load_textures(app: &mut App) {
    let c = &app.svc.clip;
    if !c.open {
        return;
    }
    let mut jobs: Vec<(String, String, bool)> = Vec::new();
    for (id, path) in &c.thumbs {
        if !c.thumb_tex.contains_key(id) && !c.loading_tex.contains(&format!("t{id}")) {
            jobs.push((id.clone(), path.clone(), false));
        }
    }
    if let Some(cur) = c.current().filter(|e| e.image.is_some()) {
        if let Some(path) = c.thumbs.get(&cur.id) {
            if c.preview_tex.as_ref().map_or(true, |(pid, _)| *pid != cur.id) && !c.loading_tex.contains(&format!("p{}", cur.id)) {
                jobs.push((cur.id.clone(), path.clone(), true));
            }
        }
    }
    let max = app.gpu.as_ref().map_or(4096, |g| g.device.limits().max_texture_dimension_2d);
    for (id, path, preview) in jobs {
        app.svc.clip.loading_tex.push(format!("{}{id}", if preview { 'p' } else { 't' }));
        app.background(
            move || (id.clone(), preview, decode(&path, if preview { (900, 700) } else { (96, 96) }, !preview, max)),
            |app, (id, preview, img)| {
                let c = &mut app.svc.clip;
                c.loading_tex.retain(|k| *k != format!("{}{id}", if preview { 'p' } else { 't' }));
                let Some((w, h, rgba)) = img else { return };
                if !c.open {
                    return;
                }
                let Some(gpu) = app.gpu.as_mut() else { return };
                let tex = Tex { id: gpu.add_image(w, h, rgba, false), w, h };
                let c = &mut app.svc.clip;
                if preview {
                    if let Some((_, old)) = c.preview_tex.replace((id, tex)) {
                        gpu.drop_image(old.id);
                    }
                } else {
                    c.thumb_tex.insert(id, tex);
                }
                changed(app);
            },
        );
    }
}

/// QQuickImage's load at sourceSize - QQuickImageProviderWithOptions::loadSize,
/// the same for PreserveAspectCrop and PreserveAspectFit: one scale, the
/// LARGER of the two ratios, down or up, so the picture covers the box (the
/// crop or fit happens when it is drawn). Smooth, premultiplied RGBA.
/// `max` is the GPU's largest texture side: a thin strip of a picture can
/// ask for more, and wgpu aborts on a texture that big.
fn decode(path: &str, req: (u32, u32), crop: bool, max: u32) -> Option<(u32, u32, Vec<u8>)> {
    // The thumbnails are "<id>.img": the format comes from the bytes.
    let mut img = image::ImageReader::open(path).ok()?.with_guessed_format().ok()?.decode().ok()?.to_rgba8();
    let (w, h) = img.dimensions();
    let ratio = (req.0 as f64 / w as f64).max(req.1 as f64 / h as f64);
    let size = |w: u32, h: u32, r: f64| (((w as f64 * r).round() as u32).max(1), ((h as f64 * r).round() as u32).max(1));
    let (mut nw, mut nh) = size(w, h, ratio);
    if nw.max(nh) > max {
        if crop {
            // A thumbnail's box is square: only the middle square shows.
            let s = w.min(h);
            img = image::imageops::crop_imm(&img, (w - s) / 2, (h - s) / 2, s, s).to_image();
            (nw, nh) = size(s, s, ratio);
        } else {
            (nw, nh) = size(w, h, max as f64 / w.max(h) as f64);
        }
    }
    let img = crate::gpu::scale(img, nw.min(max), nh.min(max));
    let (w, h) = img.dimensions();
    Some((w, h, crate::gpu::premultiply(img.into_raw())))
}

// ---- actions ----

/// pick(): close, then copy it and paste into the window behind.
fn pick(app: &mut App, entry: Option<Entry>) {
    let Some(e) = entry else { return };
    close(app);
    let cmd = format!("{} copy {} && {}/.config/quickshell/bar/scripts/clip-paste.sh", script(), e.id, services::home());
    app.exec_detached(&["sh", "-c", &cmd]);
}

fn remove(app: &mut App, entry: Option<Entry>) {
    let Some(e) = entry else { return };
    if app.is_running("clip-action") {
        return;
    }
    app.svc.clip.keep_index = app.svc.clip.selected;
    let cmd = format!("{} delete {}", script(), e.id);
    app.spawn("clip-action", &["sh", "-c", &cmd], |_, _| {});
    app.debounce("clip-reload", Duration::from_millis(120), |app| {
        reload(app);
        app.svc.clip.selected = app.svc.clip.keep_index;
        position_view(app);
    });
}

fn wipe(app: &mut App) {
    if app.is_running("clip-action") {
        return;
    }
    app.svc.clip.keep_index = 0;
    let cmd = format!("{} wipe", script());
    app.spawn("clip-action", &["sh", "-c", &cmd], |_, _| {});
    app.debounce("clip-reload", Duration::from_millis(120), |app| {
        reload(app);
        app.svc.clip.selected = 0;
        position_view(app);
    });
}

fn move_sel(app: &mut App, delta: i64) {
    let n = app.svc.clip.filtered().len() as i64;
    if n == 0 {
        return;
    }
    app.svc.clip.selected = (app.svc.clip.selected as i64 + delta).clamp(0, n - 1) as usize;
    position_view(app);
}

/// positionViewAtIndex(currentIndex, ListView.Contain), from where the list
/// is now: a glide stops there (cancelFlick), and fixupPosition() puts the
/// list on a whole pixel.
fn position_view(app: &mut App) {
    let step = met().row_h + 2.0;
    let c = &mut app.svc.clip;
    let now = Instant::now();
    let dir = c.glide.filter(|_| c.glide_at(now).is_some()).map_or(0.0, |(from, to, _)| to - from);
    let mut y = c.scroll_at(now);
    c.glide = None;
    let top = c.selected as f32 * step;
    let bottom = top + met().row_h;
    if top < y {
        y = top;
    } else if bottom > y + view_h() {
        y = bottom - view_h();
    }
    let max = max_scroll(c.filtered().len());
    c.scroll = fixup(y.clamp(0.0, max), dir, max);
    changed(app);
}

/// The filter changed: the model is new, the first entry is selected.
fn filter_changed(app: &mut App) {
    let c = &mut app.svc.clip;
    c.selected = 0;
    c.scroll = 0.0;
    c.glide = None;
    model_reset(app);
    changed(app);
}

/// The wheel: QQuickFlickable::wheelEvent (Qt 6.12; wheelDeceleration is past
/// _q_MaximumWheelDeceleration): wheelScrollLines (3) x 24 px per 120 of
/// angleDelta, glided 300 ms OutExpo from where the list is now and cut at its
/// ends (StopAtBounds). Only the ListView takes it: over the preview, the
/// search line or the hints no item accepts the wheel.
pub fn wheel(app: &mut App, delta: f32) {
    let Some((x, y)) = app.osd(OsdKind::Clipboard).and_then(|o| o.st.pointer) else { return };
    let (lx, ly, lw, lh) = list_rect();
    if x < lx || x >= lx + lw || y < ly || y >= ly + lh {
        return;
    }
    let now = Instant::now();
    let c = &mut app.svc.clip;
    let max = max_scroll(c.filtered().len());
    let from = c.scroll_at(now);
    let step = -delta / 120.0 * 72.0;
    // At an end in that direction the list lets the wheel go.
    if step == 0.0 || (step < 0.0 && from <= 0.0) || (step > 0.0 && from >= max) {
        return;
    }
    let to = (from + step).clamp(0.0, max);
    c.glide = Some((from, to, now));
    // Where fixup() leaves it when the glide ends.
    c.scroll = fixup(to, step, max);
    changed(app);
}

pub fn click(app: &mut App, action: Action) {
    if let Action::Card(code) = action {
        if code >= ROW_BASE {
            app.svc.clip.selected = (code - ROW_BASE) as usize;
            let e = app.svc.clip.current();
            pick(app, e);
        }
    }
}

/// handleKey(), then the search line (TextInput).
pub fn key(app: &mut App, sym: smithay_client_toolkit::seat::keyboard::Keysym, mods: Mods, utf8: Option<&str>) {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    // NumLock off, the keypad's keys reach Qt as Key_Up .. Key_Delete (with
    // KeypadModifier, which handleKey and TextInput's key matching ignore).
    let sym = match sym {
        Keysym::KP_Up => Keysym::Up,
        Keysym::KP_Down => Keysym::Down,
        Keysym::KP_Prior => Keysym::Prior,
        Keysym::KP_Next => Keysym::Next,
        Keysym::KP_Left => Keysym::Left,
        Keysym::KP_Right => Keysym::Right,
        Keysym::KP_Home => Keysym::Home,
        Keysym::KP_End => Keysym::End,
        Keysym::KP_Delete => Keysym::Delete,
        s => s,
    };
    match sym {
        Keysym::Escape => return close(app),
        Keysym::Down => return move_sel(app, 1),
        Keysym::Up => return move_sel(app, -1),
        Keysym::Next => return move_sel(app, 8),
        Keysym::Prior => return move_sel(app, -8),
        Keysym::Return | Keysym::KP_Enter => {
            let e = app.svc.clip.current();
            return pick(app, e);
        }
        Keysym::Delete if mods.ctrl => {
            let e = app.svc.clip.current();
            return remove(app, e);
        }
        Keysym::Delete if mods.alt => return wipe(app),
        _ => {}
    }
    let before = app.svc.clip.filter.clone();
    edit_line(&mut app.svc.clip, sym, mods, utf8);
    app.svc.clip.blink_since = Some(Instant::now());
    if app.svc.clip.filter != before {
        filter_changed(app);
    } else {
        changed(app);
    }
}

/// TextInput's editing keys on the search line.
fn edit_line(c: &mut Clip, sym: smithay_client_toolkit::seat::keyboard::Keysym, mods: Mods, utf8: Option<&str>) {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    let prev = |s: &str, i: usize| s[..i].char_indices().last().map_or(0, |(p, _)| p);
    let next = |s: &str, i: usize| s[i..].chars().next().map_or(i, |ch| i + ch.len_utf8());
    let word_left = |s: &str, i: usize| {
        let t = s[..i].trim_end_matches(char::is_whitespace);
        // Past the blank, whatever its length: a no-break space is 2 bytes,
        // and an index inside it panics in replace_range / the slicing.
        t.char_indices().rev().find(|(_, ch)| ch.is_whitespace()).map_or(0, |(p, ch)| p + ch.len_utf8())
    };
    let word_right = |s: &str, i: usize| {
        let rest = &s[i..];
        let skip = rest.len() - rest.trim_start_matches(char::is_whitespace).len();
        let r = &rest[skip..];
        i + skip + r.find(char::is_whitespace).unwrap_or(r.len())
    };
    // QInputControl::isAcceptableInput: printable text, unless typed with Ctrl
    // or Ctrl+Shift (Ctrl+1 is no input; Ctrl+Alt is AltGr to it).
    let typed = utf8.filter(|s| !s.is_empty() && !s.chars().any(char::is_control) && !(mods.ctrl && !mods.alt));
    if c.select_all && !matches!(sym, Keysym::Left | Keysym::Right | Keysym::Home | Keysym::End) && (matches!(sym, Keysym::BackSpace | Keysym::Delete) || typed.is_some()) {
        c.filter.clear();
        c.cursor = 0;
        c.select_all = false;
        if matches!(sym, Keysym::BackSpace | Keysym::Delete) {
            return;
        }
    }
    match sym {
        // QKeySequence::SelectAll is Ctrl+A alone.
        Keysym::a | Keysym::A if mods.ctrl && !mods.shift && !mods.alt => {
            c.select_all = true;
            c.cursor = c.filter.len();
        }
        Keysym::BackSpace => {
            let from = if mods.ctrl { word_left(&c.filter, c.cursor) } else { prev(&c.filter, c.cursor) };
            c.filter.replace_range(from..c.cursor, "");
            c.cursor = from;
        }
        Keysym::Delete => {
            let to = if mods.ctrl { word_right(&c.filter, c.cursor) } else { next(&c.filter, c.cursor) };
            c.filter.replace_range(c.cursor..to, "");
        }
        // With Ctrl+A's selection a plain arrow lands on that side of it
        // (QQuickTextInputPrivate::processKeyEvent: moveCursor(selectionStart()
        // / selectionEnd())); Ctrl+arrow moves a word from the cursor.
        Keysym::Left => {
            c.cursor = if mods.ctrl { word_left(&c.filter, c.cursor) } else if c.select_all { 0 } else { prev(&c.filter, c.cursor) };
            c.select_all = false;
        }
        Keysym::Right => {
            c.cursor = if mods.ctrl { word_right(&c.filter, c.cursor) } else if c.select_all { c.filter.len() } else { next(&c.filter, c.cursor) };
            c.select_all = false;
        }
        Keysym::Home => {
            c.select_all = false;
            c.cursor = 0;
        }
        Keysym::End => {
            c.select_all = false;
            c.cursor = c.filter.len();
        }
        _ => {
            if let Some(s) = typed {
                c.filter.insert_str(c.cursor, s);
                c.cursor += s.len();
            }
        }
    }
}

// ---- drawing ----

fn keycap<S: UiState>(ui: &mut Ui<S>, x: f32, y: f32, row_h: f32, keys: &str, label: &str, size: f32) -> f32 {
    let t = ui.theme;
    let kl = ui.fonts.layout(keys, theme::bar_font(true), size, 0.0);
    let ll = ui.fonts.layout(label, theme::bar_font(true), size, 1.0);
    let (rw, rh) = (kl.width + 12.0, kl.height() + 4.0);
    let ry = y + ac(row_h, rh);
    ui.scene.rect(x, ry, rw, rh, t.col_plate.lighter(1.4), 3.0, 0.0, Color::TRANSPARENT, true);
    ui.scene.rect(x, ry + rh - 2.0, rw, 2.0, Color::qt_rgba(0.0, 0.0, 0.0, 0.45), 3.0, 0.0, Color::TRANSPARENT, true);
    ui.text(&kl, x + ac(rw, kl.width), ry + ac(rh, kl.height()) - 1.0, t.col_white, TextStyle::Normal);
    ui.text(&ll, x + rw + 6.0, y + ac(row_h, ll.height()), t.col_grey, TextStyle::Normal);
    rw + 6.0 + ll.width
}

const HINTS: [(&str, &str); 5] = [("↑↓", "ВЫБОР"), ("ENTER", "ВСТАВИТЬ"), ("CTRL+DEL", "УДАЛИТЬ"), ("ALT+DEL", "ОЧИСТИТЬ"), ("ESC", "ЗАКРЫТЬ")];

/// The image drawn into a box: PreserveAspectCrop (cover, clipped) or
/// PreserveAspectFit (inside, centred).
fn draw_image<S: UiState>(ui: &mut Ui<S>, tex: Tex, x: f32, y: f32, w: f32, h: f32, crop: bool) {
    let (tw, th) = (tex.w as f32, tex.h as f32);
    if crop {
        let s = (w / tw).max(h / th);
        let (vw, vh) = (w / s / tw, h / s / th);
        let (u0, v0) = ((1.0 - vw) / 2.0, (1.0 - vh) / 2.0);
        ui.scene.image(tex.id, x, y, w, h, [u0, v0, u0 + vw, v0 + vh]);
    } else {
        let s = (w / tw).min(h / th);
        let (dw, dh) = (tw * s, th * s);
        ui.scene.image(tex.id, x + (w - dw) / 2.0, y + (h - dh) / 2.0, dw, dh, [0.0, 0.0, 1.0, 1.0]);
    }
}

pub fn draw_osd<S: UiState>(ui: &mut Ui<S>, panel: (f32, f32, f32, f32), svc: &Services) {
    let m = met();
    let t = ui.theme;
    let c = &svc.clip;
    let (x0, y0, w, h) = panel;
    ui.scene.rect(x0, y0, w, h, t.col_bg, m.radius, 0.0, Color::TRANSPARENT, true);
    ui.hits.push(Hit { x: x0, y: y0, w, h, action: Action::Hover(0) });
    let (cx, cw) = (x0 + m.pad, w - 2.0 * m.pad);
    let mut y = y0 + m.pad;
    let filtered = c.filtered();

    // Header: lamp + caption, the search line, the count.
    let head_h = (m.title * 2.0).round();
    let cap = ui.fonts.layout("БУФЕР ОБМЕНА", theme::bar_font(true), m.title, 1.0);
    let rh = cap.height().max(10.0);
    let ry = y + ac(head_h, rh);
    lamp(ui, 0x7000, cx, ry + ac(rh, 10.0), true);
    ui.text(&cap, cx + 22.0, ry + ac(rh, cap.height()), t.col_dim, TextStyle::Normal);
    let count = if c.loading { "…".to_string() } else { format!("{} / {}", filtered.len(), c.entries.len()) };
    let cl = ui.fonts.layout(&count, CONTENT, m.hint, 0.0);
    let count_x = cx + cw - cl.width;
    ui.text(&cl, count_x, y + ac(head_h, cl.height()), t.col_grey, TextStyle::Normal);
    let (sx, sw) = (cx + 22.0 + cap.width + 20.0, (count_x - 10.0) - (cx + 22.0 + cap.width + 20.0));
    let line = ui.fonts.layout(&c.filter, CONTENT, m.title, 0.0);
    let ih = ui.fonts.layout("Н", CONTENT, m.title, 0.0).height();
    let sy = y + ac(head_h, ih);
    ui.scene.save();
    // QQuickTextInput::clipRect: one cursor width wider on the right.
    ui.scene.clip_rect(sx, sy, sw + 1.0, ih);
    if c.filter.is_empty() {
        let pl = ui.fonts.layout("Поиск…", CONTENT, m.title, 0.0);
        ui.text(&pl, sx, sy + (ih - pl.height()) / 2.0, t.col_grey, TextStyle::Normal);
    }
    let cursor_x = ui.fonts.layout(&c.filter[..c.cursor.min(c.filter.len())], CONTENT, m.title, 0.0).adv;
    // TextInput scrolls to keep its cursor in view: ensureVisible's hscroll =
    // cursorX - width, the cursor just past the box, inside the wider clip.
    let shift = (cursor_x - sw).max(0.0);
    if !c.filter.is_empty() {
        ui.text(&line, sx - shift, sy, t.col_white, TextStyle::Normal);
    }
    // No cursor once closed: the keyboard leaves with `shown`, and an
    // unfocused TextInput draws none while the card fades out.
    if c.open && c.blink_since.map_or(true, |s| s.elapsed().as_millis() / 500 % 2 == 0) {
        ui.scene.fill(sx + cursor_x - shift, sy, 1.0, ih, t.col_white);
    }
    ui.scene.restore();
    y += head_h + px(10.0);

    // The list on its plate, the preview beside it.
    let bh = body_h();
    let list_w = (cw * 0.52).round();
    ui.scene.rect(cx, y, list_w, bh, t.col_plate, 5.0, 0.0, Color::TRANSPARENT, true);
    let (lx, ly, lw, lh) = (cx + 6.0, y + 6.0, list_w - 12.0, bh - 12.0);
    ui.scene.save();
    ui.scene.clip_rect(lx, ly, lw, lh);
    let step = m.row_h + 2.0;
    // contentY, on its way while the wheel's glide runs.
    let glide = c.glide_at(ui.now);
    ui.animating |= glide.is_some();
    let scroll = glide.unwrap_or(c.scroll);
    for (i, e) in filtered.iter().enumerate() {
        let ry = ly + i as f32 * step - scroll;
        if ry + m.row_h < ly || ry > ly + lh {
            continue;
        }
        let sel = i == c.selected;
        let hot = ui.hovered(lx, ry, lw, m.row_h) && ui.hovered(lx, ly, lw, lh);
        let bg = if sel { t.col_accent } else if hot { t.col_plate.lighter(1.6) } else { Color::TRANSPARENT };
        ui.scene.rect(lx, ry, lw, m.row_h, bg, 4.0, 0.0, Color::TRANSPARENT, true);
        let fg = if sel { t.col_bg } else { t.col_grey };
        let ib = m.row_h - 10.0;
        let (ix, iy) = (lx + 8.0, ry + ac(m.row_h, ib));
        // close() empties `thumbs`: thumbFor() is "" for every row at once,
        // so the glyphs stand in for the pictures while the card fades out.
        match c.thumb_tex.get(&e.id).filter(|_| e.image.is_some() && c.open) {
            Some(&tex) => {
                ui.scene.save();
                ui.scene.clip_rect(ix, iy, ib, ib);
                draw_image(ui, tex, ix, iy, ib, ib, true);
                ui.scene.restore();
            }
            None => {
                let g = ui.fonts.layout(if e.image.is_some() { "\u{f02e9}" } else { "\u{f09a8}" }, CONTENT, m.row + 2.0, 0.0);
                ui.text_of(ROW_BASE + i as u32, 0xD1, &g, ix + ac(ib, g.width), iy + ac(ib, g.height()), fg);
            }
        }
        let text = match &e.image {
            Some((size, iw, ih)) => format!("Изображение  {iw}×{ih}  ·  {size}"),
            None => e.preview.clone(),
        };
        let tw = (lw - 16.0) - ib - 16.0;
        let full = ui.fonts.layout(&text, CONTENT, m.row, 0.0);
        let tl = ui.fonts.elide_right(&full, &text, CONTENT, tw, 0.0);
        ui.text_of(ROW_BASE + i as u32, 0xD2, &tl, ix + ib + 8.0, ry + ac(m.row_h, tl.height()), fg);
        let (hy0, hy1) = (ry.max(ly), (ry + m.row_h).min(ly + lh));
        ui.hits.push(Hit { x: lx, y: hy0, w: lw, h: hy1 - hy0, action: Action::Card(ROW_BASE + i as u32) });
    }
    ui.scene.restore();

    let (px0, pw) = (cx + list_w + m.pad, cw - list_w - m.pad);
    ui.scene.rect(px0, y, pw, bh, t.col_plate, 5.0, 0.0, Color::TRANSPARENT, true);
    match c.current() {
        None => {
            let l = ui.fonts.layout(if c.loading { "Чтение истории…" } else { "Ничего не найдено" }, CONTENT, m.row, 0.0);
            ui.text(&l, px0 + ac(pw, l.width), y + ac(bh, l.height()), t.col_grey, TextStyle::Normal);
        }
        // The preview's source empties with the rows' (see above).
        Some(e) if e.image.is_some() => match c.preview_tex.as_ref().filter(|(id, _)| *id == e.id && c.open) {
            Some((_, tex)) => draw_image(ui, *tex, px0 + 10.0, y + 10.0, pw - 20.0, bh - 20.0, false),
            None => {
                let g = ui.fonts.layout("\u{f02e9}", CONTENT, px(48.0), 0.0);
                ui.text(&g, px0 + ac(pw, g.width), y + ac(bh, g.height()), t.col_grey, TextStyle::Normal);
            }
        },
        Some(e) => {
            // Text.Wrap + ElideRight: the lines that fit, the last one elided.
            let (tx, tw, th) = (px0 + 12.0, pw - 24.0, bh - 24.0);
            let lines = ui.fonts.wrap_strings(&e.preview, CONTENT, m.row, 0.0, tw, true);
            let lh = ui.fonts.layout("Н", CONTENT, m.row, 0.0).height();
            let fit = ((th / lh).floor() as usize).max(1);
            let mut shown: Vec<Line> = Vec::new();
            for (i, l) in lines.iter().take(fit).enumerate() {
                if i + 1 == fit && lines.len() > fit {
                    let rest: String = lines[i..].join(" ");
                    let full = ui.fonts.layout(&rest, CONTENT, m.row, 0.0);
                    shown.push(ui.fonts.elide_right(&full, &rest, CONTENT, tw, 0.0));
                } else {
                    shown.push(ui.fonts.layout(l, CONTENT, m.row, 0.0));
                }
            }
            ui.text_block(1, 0xE0, &shown, tx, y + 12.0, t.col_grey);
        }
    }
    y += bh + px(10.0);

    // The key hints, centred.
    let kh = {
        let k = ui.fonts.layout("ESC", theme::bar_font(true), m.hint, 0.0);
        let l = ui.fonts.layout("ЗАКРЫТЬ", theme::bar_font(true), m.hint, 1.0);
        (k.height() + 4.0).max(l.height())
    };
    let sp = px(14.0);
    let total: f32 = HINTS
        .iter()
        .map(|(k, l)| ui.fonts.layout(k, theme::bar_font(true), m.hint, 0.0).width + 12.0 + 6.0 + ui.fonts.layout(l, theme::bar_font(true), m.hint, 1.0).width)
        .sum::<f32>()
        + sp * (HINTS.len() - 1) as f32;
    let mut kx = cx + ac(cw, total);
    for (k, l) in HINTS {
        kx += keycap(ui, kx, y, kh, k, l, m.hint) + sp;
    }
}
