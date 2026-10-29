//! The centred overlays (LayoutOsd, PowerOsd, ShotOsd, RecordOsd, ClipboardOsd,
//! PolkitOsd): an Overlay-layer panel on the focused screen and, for the
//! dialogs, a dim over the whole screen behind it. QML draws a dialog as one
//! full-screen surface; here the panel gets a surface of its own size and the
//! dim is a single pixel stretched by wp_viewporter, so an open dialog costs a
//! panel's worth of buffers instead of a screen's.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use smithay_client_toolkit::{
    shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer, LayerSurface},
    shell::WaylandSurface,
    shm::slot::SlotPool,
};
use wayland_client::protocol::{wl_output::WlOutput, wl_shm};
use smithay_client_toolkit::reexports::protocols::wp::viewporter::client::{wp_viewport::WpViewport, wp_viewporter::WpViewporter};

use crate::anim::{Animated, Easing};
use crate::app::{App, Win};
use crate::bar::{Action, Hit};
use crate::cards::{Ui, UiState};
use crate::color::Color;
use crate::gpu::Scene;
use crate::services::Services;
use crate::text::{Fonts, TextMemo};
use crate::theme::Theme;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum OsdKind {
    Layout,
    Power,
    Shot,
    Record,
    Polkit,
    Clipboard,
    Wallpaper,
    /// The overview: one per screen, by index.
    Overview(u8),
}

/// Hover, focus and the animated values of an overlay's controls.
#[derive(Default)]
pub struct OsdState {
    pub pointer: Option<(f32, f32)>,
    pub focus: Option<usize>,
    pub focus_codes: Vec<u32>,
    pub tint_alert: bool,
    /// The control a button is held down on.
    pub pressed: Option<u32>,
    colors: HashMap<u32, Animated<Color>>,
    numbers: HashMap<u32, Animated<f32>>,
    pub texts: TextMemo,
    /// Sheared hit areas (x, y, w, h, slope, y ref, action): a point is in
    /// when, moved back along the slope, it falls in the rectangle.
    pub shapes: Vec<(f32, f32, f32, f32, f32, f32, Action)>,
}

impl OsdState {
    /// A Behavior with an easing curve (NumberAnimation { easing.type }).
    pub fn number_e(&mut self, id: u32, target: f32, ms: u64, easing: Easing, now: Instant) -> (f32, bool) {
        let a = self.numbers.entry(id).or_insert_with(|| Animated::new(target, ms, easing));
        a.set(target, now);
        (a.get(now), a.running(now))
    }

    /// The control under (x, y) among the sheared areas, topmost first.
    pub fn shape_at(&self, x: f32, y: f32) -> Option<Action> {
        self.shapes.iter().rev().find(|s| {
            let px = x - s.4 * (y - s.5);
            px >= s.0 && px < s.0 + s.2 && y >= s.1 && y < s.1 + s.3
        }).map(|s| s.6)
    }

    /// The animated value as it stands, without retargeting it.
    pub fn number_peek(&self, id: u32, now: Instant) -> Option<f32> {
        self.numbers.get(&id).map(|a| a.get(now))
    }

    pub fn reset_numbers(&mut self) {
        self.numbers.clear();
    }
}

impl UiState for OsdState {
    fn color(&mut self, id: u32, target: Color, ms: u64, now: Instant) -> (Color, bool) {
        let a = self.colors.entry(id).or_insert_with(|| Animated::new(target, ms, Easing::Linear));
        a.set(target, now);
        (a.get(now), a.running(now))
    }
    fn number(&mut self, id: u32, target: f32, ms: u64, now: Instant) -> (f32, bool) {
        let a = self.numbers.entry(id).or_insert_with(|| Animated::new(target, ms, Easing::Linear));
        a.set(target, now);
        (a.get(now), a.running(now))
    }
    fn pointer(&self) -> Option<(f32, f32)> {
        self.pointer
    }
    fn focus(&self) -> Option<usize> {
        self.focus
    }
    fn tint_alert(&self) -> bool {
        self.tint_alert
    }
    fn texts(&mut self) -> &mut TextMemo {
        &mut self.texts
    }
}

/// The dialogs' dim: one premultiplied pixel over the whole screen.
pub struct Dim {
    pub layer: LayerSurface,
    viewport: Option<WpViewport>,
    pool: Option<SlotPool>,
    size: (u32, u32),
    /// The alpha last attached (0-255), to skip identical frames.
    drawn: Option<u8>,
}

pub struct Osd {
    pub kind: OsdKind,
    pub output: WlOutput,
    pub screen: (f32, f32),
    pub win: Win,
    pub dim: Option<Dim>,
    /// The dim's colour at full opacity.
    pub dim_color: Color,
    pub st: OsdState,
    pub hits: Vec<Hit>,
    /// `shown`: drives the fade; the surface stays until the fade-out ends.
    pub shown: bool,
    /// Panel opacity, 0..1 OutCubic (its scale runs 0.94..1 on the same curve).
    pub fade: Animated<f32>,
    /// The dim's opacity, linear.
    pub dim_fade: Animated<f32>,
    pub fade_ms: u64,
    /// The panel's scale when hidden (it grows to 1 as it fades in).
    pub min_scale: f32,
    /// The panel's rectangle inside the surface.
    pub panel: (f32, f32, f32, f32),
}

pub struct OpenParams {
    pub kind: OsdKind,
    pub size: (u32, u32),
    pub panel: (f32, f32, f32, f32),
    pub dim: Option<Color>,
    pub keyboard: bool,
    pub namespace: &'static str,
    pub fade_ms: u64,
    pub min_scale: f32,
    /// The panel opacity's curve (OutCubic but for the clipboard's).
    pub fade_easing: Easing,
    /// Where the surface goes on the screen; None = centred by the compositor.
    pub pos: Option<(i32, i32)>,
    /// Anchored to every edge (the size comes from the compositor).
    pub fill: bool,
    /// The screen, when not the focused one.
    pub output: Option<(WlOutput, f32, f32)>,
}

impl Osd {
    /// The panel's scale animation: the fade's progress, always OutCubic.
    fn fade_scale(&self, now: Instant) -> f32 {
        if self.fade_easing_linear() {
            let t = self.fade.get(now);
            let shown = self.shown;
            // A linear fade's progress mapped onto OutCubic, direction aware.
            let p = if shown { t } else { 1.0 - t };
            let e = crate::anim::ease(Easing::OutCubic, p);
            return if shown { e } else { 1.0 - e };
        }
        self.fade.get(now)
    }
    fn fade_easing_linear(&self) -> bool {
        matches!(self.kind, OsdKind::Clipboard | OsdKind::Wallpaper)
    }
}

impl App {
    pub fn osd(&self, kind: OsdKind) -> Option<&Osd> {
        self.osds.iter().find(|o| o.kind == kind)
    }
    pub fn osd_mut(&mut self, kind: OsdKind) -> Option<&mut Osd> {
        self.osds.iter_mut().find(|o| o.kind == kind)
    }
}

/// The output the focused mango monitor is on (the strips know the names).
pub fn focused_output(app: &App) -> Option<(WlOutput, f32, f32)> {
    let name = app.svc.mango.focused().map(|m| m.name.clone()).unwrap_or_default();
    let s = app.strips.iter().find(|s| s.name == name).or(app.strips.first())?;
    Some((s.output.clone(), s.screen_width, s.screen_height))
}

/// Maps the overlay (or, if it is already up, retargets its fade to shown).
pub fn show(app: &mut App, p: OpenParams) {
    let now = Instant::now();
    if let Some(o) = app.osd_mut(p.kind) {
        if p.keyboard && !o.shown {
            o.win.layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
            o.win.layer.commit();
        }
        o.shown = true;
        o.fade.set(1.0, now);
        o.dim_fade.set(1.0, now);
        o.win.dirty = true;
        if o.dim.is_some() {
            app.after(Duration::from_millis(0), repaint_dims);
        }
        return;
    }
    let Some((output, sw, sh)) = p.output.clone().or_else(|| focused_output(app)) else { return };
    let dim = p.dim.map(|_| {
        let surface = app.compositor.create_surface(&app.qh);
        let layer = app.layer_shell.create_layer_surface(&app.qh, surface, Layer::Overlay, Some(p.namespace), Some(&output));
        layer.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
        layer.set_exclusive_zone(-1);
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        layer.commit();
        Dim { layer, viewport: None, pool: None, size: (0, 0), drawn: None }
    });
    let surface = app.compositor.create_surface(&app.qh);
    let layer = app.layer_shell.create_layer_surface(&app.qh, surface, Layer::Overlay, Some(p.namespace), Some(&output));
    // No anchors: the compositor centres it, as it does the QML window.
    if let Some((x, y)) = p.pos {
        layer.set_anchor(Anchor::TOP | Anchor::LEFT);
        layer.set_margin(y, 0, 0, x);
    }
    if p.fill {
        layer.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
    }
    layer.set_size(p.size.0, p.size.1);
    layer.set_exclusive_zone(-1);
    layer.set_keyboard_interactivity(if p.keyboard { KeyboardInteractivity::Exclusive } else { KeyboardInteractivity::None });
    // mask: Region { item: panel } - clicks outside the panel go through. A
    // panel that is the whole surface needs none: QML's dialogs are
    // full-screen windows without a mask, and the default region grows with
    // the surface when the dialog does (capture's and polkit's reshow).
    let (x, y, w, h) = p.panel;
    let whole = x <= 0.0 && y <= 0.0 && w.ceil() as u32 >= p.size.0 && h.ceil() as u32 >= p.size.1;
    if !p.fill && !whole {
        if let Ok(region) = smithay_client_toolkit::compositor::Region::new(&app.compositor) {
            region.add(x.floor() as i32, y.floor() as i32, w.ceil() as i32, h.ceil() as i32);
            layer.wl_surface().set_input_region(Some(region.wl_region()));
        }
    }
    layer.commit();
    let mut fade = Animated::new(0.0, p.fade_ms, p.fade_easing);
    fade.set(1.0, now);
    let mut dim_fade = Animated::new(0.0, p.fade_ms, Easing::Linear);
    dim_fade.set(1.0, now);
    app.osds.push(Osd {
        kind: p.kind,
        output,
        screen: (sw, sh),
        win: Win::new(layer, p.size.0, p.size.1),
        dim,
        dim_color: p.dim.unwrap_or(Color::TRANSPARENT),
        st: OsdState::default(),
        hits: Vec::new(),
        shown: true,
        fade,
        dim_fade,
        fade_ms: p.fade_ms,
        min_scale: p.min_scale,
        panel: p.panel,
    });
}

/// shown = false: fade out, then unmap (the goneTimer).
pub fn hide(app: &mut App, kind: OsdKind) {
    let now = Instant::now();
    let Some(o) = app.osd_mut(kind) else { return };
    if !o.shown {
        return;
    }
    o.shown = false;
    // keyboardFocus: shown ? Exclusive : None - the keyboard goes back to the
    // window at once, not after the fade: clip-paste.sh types Ctrl+V 60 ms
    // after a pick, and a fading overlay that still held the keyboard ate it.
    o.win.layer.set_keyboard_interactivity(KeyboardInteractivity::None);
    o.win.layer.commit();
    o.fade.set(0.0, now);
    o.dim_fade.set(0.0, now);
    o.win.dirty = true;
    let ms = o.fade_ms;
    app.after(Duration::from_millis(0), repaint_dims);
    let gone: fn(&mut App) = match kind {
        OsdKind::Layout => |app| destroy(app, OsdKind::Layout),
        OsdKind::Power => |app| destroy(app, OsdKind::Power),
        OsdKind::Shot => |app| destroy(app, OsdKind::Shot),
        OsdKind::Record => |app| destroy(app, OsdKind::Record),
        OsdKind::Polkit => |app| destroy(app, OsdKind::Polkit),
        OsdKind::Clipboard => |app| destroy(app, OsdKind::Clipboard),
        OsdKind::Wallpaper => |app| destroy(app, OsdKind::Wallpaper),
        OsdKind::Overview(_) => |_| {},
    };
    app.debounce(gone_timer(kind), Duration::from_millis(ms), gone);
}

fn gone_timer(kind: OsdKind) -> &'static str {
    match kind {
        OsdKind::Layout => "osd-gone-layout",
        OsdKind::Power => "osd-gone-power",
        OsdKind::Shot => "osd-gone-shot",
        OsdKind::Record => "osd-gone-record",
        OsdKind::Polkit => "osd-gone-polkit",
        OsdKind::Clipboard => "osd-gone-clipboard",
        OsdKind::Wallpaper => "osd-gone-wallpaper",
        OsdKind::Overview(_) => "osd-gone-overview",
    }
}

/// Unmaps the overlay now, unless it was shown again meanwhile.
pub fn destroy(app: &mut App, kind: OsdKind) {
    let Some(o) = app.osd_mut(kind).filter(|o| !o.shown) else { return };
    let hovered = o.st.pointer.is_some();
    // LayoutOsd's window is only hidden: its Texts live on (TextMemo).
    let texts = (kind == OsdKind::Layout).then(|| std::mem::take(&mut o.st.texts));
    app.osds.retain(|o| o.kind != kind);
    if let Some(t) = texts {
        crate::layout::keep_texts(app, t);
    }
    // A hidden window clears its hover (QQuickWindow::hideEvent): the
    // MouseArea still under the pointer gets onExited. No wl_pointer.leave
    // comes for a surface that is gone.
    if hovered {
        hover_changed(app, kind, false);
    }
    unsafe { libc::malloc_trim(0) };
}

/// The dims follow their fades, one pixel per frame while they run.
fn repaint_dims(app: &mut App) {
    let now = Instant::now();
    let mut again = false;
    let qh = app.qh.clone();
    let vp = app.viewporter.clone();
    let shm = &app.shm;
    for o in app.osds.iter_mut() {
        let Some(d) = o.dim.as_mut() else { continue };
        if d.size.0 == 0 {
            continue;
        }
        let a = o.dim_fade.get(now) * o.dim_color.a;
        let byte = (a * 255.0).round() as u8;
        if d.drawn != Some(byte) {
            paint_dim(d, &qh, shm, vp.as_ref(), o.dim_color, a);
        }
        again |= o.dim_fade.running(now);
    }
    if again {
        app.after(Duration::from_millis(8), repaint_dims);
    }
}

fn paint_dim(d: &mut Dim, qh: &wayland_client::QueueHandle<App>, shm: &smithay_client_toolkit::shm::Shm, vp: Option<&WpViewporter>, c: Color, a: f32) {
    let Some(vp) = vp else { return };
    if d.pool.is_none() {
        d.pool = SlotPool::new(4, shm).ok();
    }
    let Some(pool) = d.pool.as_mut() else { return };
    let Ok((buffer, canvas)) = pool.create_buffer(1, 1, 4, wl_shm::Format::Argb8888) else { return };
    // ARGB8888 little-endian, premultiplied.
    let px = [(c.b * a * 255.0).round() as u8, (c.g * a * 255.0).round() as u8, (c.r * a * 255.0).round() as u8, (a * 255.0).round() as u8];
    canvas[..4].copy_from_slice(&px);
    let wl = d.layer.wl_surface();
    if d.viewport.is_none() {
        d.viewport = Some(vp.get_viewport(wl, qh, ()));
    }
    d.viewport.as_ref().unwrap().set_destination(d.size.0.max(1) as i32, d.size.1.max(1) as i32);
    let _ = buffer.attach_to(wl);
    wl.damage_buffer(0, 0, 1, 1);
    d.layer.commit();
    d.drawn = Some(px[3]);
}

/// The dim's configure: its size, then its first pixel.
pub fn configure_dim(app: &mut App, layer: &LayerSurface, size: (u32, u32)) -> bool {
    let Some(o) = app.osds.iter_mut().find(|o| o.dim.as_ref().map_or(false, |d| &d.layer == layer)) else { return false };
    let d = o.dim.as_mut().unwrap();
    d.size = size;
    d.drawn = None;
    app.after(Duration::from_millis(0), repaint_dims);
    true
}

pub fn is_dim(app: &App, surface: &wayland_client::protocol::wl_surface::WlSurface) -> Option<OsdKind> {
    app.osds.iter().find(|o| o.dim.as_ref().map_or(false, |d| d.layer.wl_surface() == surface)).map(|o| o.kind)
}

/// Draws an overlay; true while something in it animates.
pub fn draw(o: &mut Osd, scene: &mut Scene, fonts: &mut Fonts, theme: &Theme, svc: &Services) -> bool {
    let now = Instant::now();
    let fade = o.fade.get(now);
    let mut animating = o.fade.running(now);
    // A full-screen overlay's panel is the window.
    let (px, py, pw, ph) = if o.panel.2 > 0.0 { o.panel } else { (0.0, 0.0, o.win.width as f32, o.win.height as f32) };
    // The scale always runs OutCubic; the opacity may be linear.
    let scale = o.min_scale + (1.0 - o.min_scale) * o.fade_scale(now);
    o.st.texts.begin_frame();
    o.st.shapes.clear();
    scene.save();
    // Item.scale about the panel's centre, and the panel's opacity.
    scene.translate(px + pw / 2.0, py + ph / 2.0);
    scene.scale(scale, scale);
    scene.translate(-(px + pw / 2.0), -(py + ph / 2.0));
    scene.multiply_opacity(fade);
    // Hover is tested in the panel's own coordinates, before the scale.
    let pointer = o.st.pointer;
    o.st.pointer = pointer.map(|(x, y)| (px + pw / 2.0 + (x - px - pw / 2.0) / scale, py + ph / 2.0 + (y - py - ph / 2.0) / scale));
    let pressed = o.st.pressed;
    let mut ui = Ui { card: &mut o.st, scene, fonts, theme, now, animating: false, hits: Vec::new(), focus_codes: Vec::new() };
    match o.kind {
        OsdKind::Layout => crate::layout::draw_osd(&mut ui, (px, py, pw, ph), svc),
        OsdKind::Power => crate::power::draw_osd(&mut ui, (px, py, pw, ph), svc),
        OsdKind::Shot => crate::capture::draw_osd(&mut ui, false, (px, py, pw, ph), svc, pressed),
        OsdKind::Record => crate::capture::draw_osd(&mut ui, true, (px, py, pw, ph), svc, pressed),
        OsdKind::Polkit => crate::polkit::draw_osd(&mut ui, (px, py, pw, ph), svc),
        OsdKind::Clipboard => crate::clip::draw_osd(&mut ui, (px, py, pw, ph), svc),
        OsdKind::Wallpaper => crate::wallpaper::draw_osd(&mut ui, (px, py, pw, ph), svc),
        OsdKind::Overview(i) => crate::overview::draw_osd(&mut ui, i, (px, py, pw, ph), svc),
    }
    let (hits, codes) = (std::mem::take(&mut ui.hits), std::mem::take(&mut ui.focus_codes));
    animating |= ui.animating;
    scene.restore();
    o.st.pointer = pointer;
    o.hits = hits;
    o.st.focus_codes = codes;
    animating
}

/// Pointer and keyboard events, routed by kind.
pub fn click(app: &mut App, kind: OsdKind, action: Action, button: u32) {
    match kind {
        OsdKind::Layout => crate::layout::osd_click(app, action, button),
        OsdKind::Power => crate::power::osd_click(app, action, button),
        OsdKind::Shot | OsdKind::Record => crate::capture::click(app, kind, action),
        OsdKind::Polkit => {}
        OsdKind::Clipboard => crate::clip::click(app, action),
        OsdKind::Wallpaper => crate::wallpaper::click(app, action),
        OsdKind::Overview(_) => {}
    }
}

/// A click on the dim, outside the panel.
pub fn dim_clicked(app: &mut App, kind: OsdKind) {
    match kind {
        OsdKind::Layout => {}
        OsdKind::Power => crate::power::close(app),
        OsdKind::Shot | OsdKind::Record => crate::capture::dim_clicked(app, kind),
        // MouseArea { anchors.fill: parent }: the dim takes clicks and does nothing.
        OsdKind::Polkit => {}
        OsdKind::Clipboard => crate::clip::close(app),
        OsdKind::Wallpaper => crate::wallpaper::close(app),
        OsdKind::Overview(_) => {}
    }
}

/// A key while the overlay has the keyboard; `scan` is Qt's nativeScanCode.
pub fn key(app: &mut App, kind: OsdKind, sym: smithay_client_toolkit::seat::keyboard::Keysym, scan: u32, mods: crate::app::Mods, utf8: Option<&str>) {
    let shift = mods.shift;
    match kind {
        OsdKind::Layout => {}
        OsdKind::Power => crate::power::key(app, sym, scan, shift),
        OsdKind::Shot | OsdKind::Record => crate::capture::key(app, kind, sym, scan),
        OsdKind::Polkit => crate::polkit::key(app, sym, utf8),
        OsdKind::Clipboard => crate::clip::key(app, sym, mods, utf8),
        OsdKind::Wallpaper => crate::wallpaper::key(app, sym, mods, utf8),
        OsdKind::Overview(_) => crate::overview::key(app, sym),
    }
}

/// Every pointer event on an overlay, before the generic hit handling; true
/// when the overlay took it (the overview's drags, the buttons QML ignores).
pub fn raw_pointer(app: &mut App, kind: OsdKind, ev: &smithay_client_toolkit::seat::pointer::PointerEventKind, x: f32, y: f32) -> bool {
    use smithay_client_toolkit::seat::pointer::PointerEventKind as P;
    match kind {
        OsdKind::Overview(i) => crate::overview::pointer(app, i, ev, x, y),
        // Their MouseAreas keep acceptedButtons' default, Qt.LeftButton
        // (LayoutOsd.qml:216, PowerOsd.qml:123,263, BigButton.qml:88,
        // ToggleRow.qml:94, ShotOsd.qml:219, RecordOsd.qml:232): a right,
        // middle or side button neither presses nor clicks anything.
        OsdKind::Layout | OsdKind::Power | OsdKind::Shot | OsdKind::Record => {
            matches!(ev, P::Press { button, .. } | P::Release { button, .. } if *button != BTN_LEFT)
        }
        _ => false,
    }
}

const BTN_LEFT: u32 = 0x110;

/// The wheel over the panel (QML angleDelta: +120 per notch away from you).
pub fn wheel(app: &mut App, kind: OsdKind, delta: f32) {
    if kind == OsdKind::Clipboard {
        crate::clip::wheel(app, delta);
    }
    if kind == OsdKind::Wallpaper {
        crate::wallpaper::wheel(app, delta);
    }
}

/// Pointer motion over a control (MouseArea.onEntered).
pub fn hovered(app: &mut App, kind: OsdKind, action: Option<Action>) {
    match kind {
        OsdKind::Layout => {}
        OsdKind::Power => crate::power::hovered(app, action),
        OsdKind::Shot | OsdKind::Record | OsdKind::Polkit | OsdKind::Clipboard | OsdKind::Wallpaper | OsdKind::Overview(_) => {}
    }
}

pub fn hover_changed(app: &mut App, kind: OsdKind, inside: bool) {
    match kind {
        OsdKind::Layout => crate::layout::osd_hover(app, inside),
        OsdKind::Power | OsdKind::Shot | OsdKind::Record | OsdKind::Polkit | OsdKind::Clipboard | OsdKind::Wallpaper | OsdKind::Overview(_) => {}
    }
}
