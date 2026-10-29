//! The running bar: Wayland objects, the event loop, the surfaces (a strip per
//! output, the open card on its full-screen surface), redraws driven by frame
//! callbacks - nothing is drawn while nothing changes.

use std::collections::HashMap;
use std::ptr::NonNull;
use std::time::Instant;

use raw_window_handle::{RawDisplayHandle, RawWindowHandle, WaylandDisplayHandle, WaylandWindowHandle};
use smithay_client_toolkit::{
    compositor::{CompositorHandler, CompositorState},
    delegate_compositor, delegate_layer, delegate_output, delegate_pointer, delegate_registry, delegate_seat,
    delegate_shm,
    output::{OutputHandler, OutputState},
    reexports::calloop::{EventLoop, LoopHandle, RegistrationToken},
    reexports::calloop_wayland_source::WaylandSource,
    reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1},
    reexports::protocols::wp::viewporter::client::{wp_viewport::WpViewport, wp_viewporter::WpViewporter},
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
    seat::{
        keyboard::{KeyEvent, KeyboardData, KeyboardHandler, Keymap, Keysym, Modifiers},
        pointer::{cursor_shape::CursorShapeManager, AxisScroll, PointerEvent, PointerEventKind, PointerHandler},
        Capability, SeatHandler, SeatState,
    },
    shell::{
        wlr_layer::{Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface, LayerSurfaceConfigure},
        WaylandSurface,
    },
    shm::{Shm, ShmHandler},
};
use wayland_client::{
    globals::{registry_queue_init, GlobalList},
    protocol::{wl_keyboard::{self, WlKeyboard}, wl_output, wl_pointer::{self, WlPointer}, wl_seat::WlSeat, wl_surface},
    Connection, Dispatch, Proxy, QueueHandle,
};

use crate::bar::{self, Action, Hit};
use crate::cards::{self, OpenCard};
use crate::gpu::{Gpu, Scene};
use crate::services::{Mango, Services};
use crate::text::Fonts;
use crate::theme::Theme;

/// Linux input button codes (Qt's Left, Right and Middle buttons).
const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const BTN_MIDDLE: u32 = 0x112;

/// A wgpu surface on a Wayland surface.
fn raw_surface(conn: &Connection, instance: &wgpu::Instance, wl: &wl_surface::WlSurface) -> wgpu::Surface<'static> {
    let dpy = NonNull::new(conn.backend().display_ptr() as *mut _).unwrap();
    let wl = NonNull::new(wl.id().as_ptr() as *mut _).unwrap();
    unsafe {
        instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::RawHandle {
            raw_display_handle: RawDisplayHandle::Wayland(WaylandDisplayHandle::new(dpy)),
            raw_window_handle: RawWindowHandle::Wayland(WaylandWindowHandle::new(wl)),
        })
    }
    .expect("wgpu surface")
}

/// Its swapchain, configured: blending in gamma space like Qt - a non-sRGB
/// format and premultiplied alpha.
fn surface_config(gpu: &Gpu, surface: &wgpu::Surface<'static>, width: u32, height: u32) -> wgpu::SurfaceConfiguration {
    let caps = surface.get_capabilities(&gpu.adapter);
    let format = caps.formats.iter().copied().find(|f| !f.is_srgb()).unwrap_or(caps.formats[0]);
    let alpha_mode = if caps.alpha_modes.contains(&wgpu::CompositeAlphaMode::PreMultiplied) {
        wgpu::CompositeAlphaMode::PreMultiplied
    } else {
        caps.alpha_modes[0]
    };
    let config = wgpu::SurfaceConfiguration {
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
        format,
        width: width.max(1),
        height: height.max(1),
        present_mode: wgpu::PresentMode::Fifo,
        desired_maximum_frame_latency: 2,
        alpha_mode,
        view_formats: vec![],
    };
    surface.configure(&gpu.device, &config);
    config
}

/// Both, for a surface that is not one of the Wins (the audio meter's).
fn gpu_surface(conn: &Connection, instance: &wgpu::Instance, gpu: &Gpu, wl: &wl_surface::WlSurface, width: u32, height: u32) -> (wgpu::Surface<'static>, wgpu::SurfaceConfiguration) {
    let surface = raw_surface(conn, instance, wl);
    let config = surface_config(gpu, &surface, width, height);
    (surface, config)
}

/// A layer surface drawn with the GPU.
pub struct Win {
    /// First: fields drop in order, and the swapchain goes before the
    /// wl_surface it presents to (create_surface_unsafe's contract).
    gpu: Option<(wgpu::Surface<'static>, wgpu::SurfaceConfiguration)>,
    pub layer: LayerSurface,
    pub width: u32,
    pub height: u32,
    pub configured: bool,
    pub dirty: bool,
    frame_pending: bool,
    scene: Scene,
}

impl Win {
    pub fn new(layer: LayerSurface, width: u32, height: u32) -> Win {
        Win { layer, gpu: None, width, height, configured: false, dirty: true, frame_pending: false, scene: Scene::new(1.0, 1.0) }
    }
}

pub struct Strip {
    pub output: wl_output::WlOutput,
    pub name: String,
    pub win: Win,
    pub screen_width: f32,
    pub screen_height: f32,
    pub hits: Vec<Hit>,
    pub pointer: Option<(f32, f32)>,
    /// Which plain Texts have changed (see TextMemo).
    pub texts: crate::text::TextMemo,
}

/// The modifiers held (Qt's event.modifiers).
#[derive(Clone, Copy, Default, Debug)]
pub struct Mods {
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum WinRef {
    Strip(usize),
    Card,
    Osd(crate::osd::OsdKind),
    Crt(usize),
    Reveal(usize),
}

/// Output of a finished helper process, routed back by its tag.
pub struct ProcDone {
    pub tag: String,
    pub stdout: String,
    pub ok: bool,
}

pub struct App {
    pub conn: Connection,
    pub qh: QueueHandle<App>,
    pub handle: LoopHandle<'static, App>,
    registry: RegistryState,
    outputs: OutputState,
    seats: SeatState,
    pub compositor: CompositorState,
    pub layer_shell: LayerShell,
    pub shm: Shm,
    pub viewporter: Option<WpViewporter>,
    pub subcompositor: Option<smithay_client_toolkit::subcompositor::SubcompositorState>,
    cursor_shapes: Option<CursorShapeManager>,
    pointer: Option<(WlPointer, Option<WpCursorShapeDeviceV1>)>,
    keyboard: Option<WlKeyboard>,
    enter_serial: u32,
    /// The surface holding the keyboard, and Shift.
    kbd_focus: Option<WinRef>,
    shift: bool,
    mods: Mods,
    /// Ctrl shortcuts on a non-Latin layout (App::key).
    latin: LatinKeys,
    /// Qt's event.isAutoRepeat: true while a held key's repeat is dispatched.
    pub key_repeat: bool,
    /// The cursor shape sent since the pointer last entered a surface.
    cursor: Option<Shape>,
    /// The widget a button went down on: a click is a release on the same one.
    pressed: Option<(WinRef, u32, Action)>,
    pub instance: wgpu::Instance,
    pub gpu: Option<Gpu>,
    pub fonts: Fonts,
    pub theme: Theme,
    pub strips: Vec<Strip>,
    pub card: Option<OpenCard>,
    pub osds: Vec<crate::osd::Osd>,
    /// `rust-bar crt`: the CRT power-off windows instead of strips.
    pub crt_mode: bool,
    pub crts: Vec<crate::crt::CrtWin>,
    /// The wallpaper reveal, one window per screen while it runs.
    pub reveals: Vec<crate::wallpaper::RevealWin>,
    pub svc: Services,
    pub(crate) running: HashMap<String, (Instant, u32)>,
    pub(crate) timers: HashMap<&'static str, RegistrationToken>,
    pub exit: bool,
    /// When the bar started: Theme.qml's palette load lands just after it.
    pub(crate) started: Instant,
    /// The weather card's Texts, kept between openings (CenterInfo's card is
    /// not a Loader: once shown, its Texts live as long as the bar).
    pub(crate) weather_texts: Option<crate::text::TextMemo>,
    /// Results of work done off the main thread, run back on the event loop.
    pub(crate) bg_tx: smithay_client_toolkit::reexports::calloop::channel::Sender<Box<dyn FnOnce(&mut App) + Send>>,
    /// The one decode thread's queue (runtime.rs, background()).
    pub(crate) bg_jobs: std::sync::mpsc::Sender<Box<dyn FnOnce() + Send>>,
}

impl App {
    pub fn run(crt_mode: bool) {
        if !crt_mode {
            crate::ipc::single_instance();
        }
        // Started outside a Wayland session (a TTY, ssh): a message and exit
        // status 1, not an abort and a core dump.
        let Ok(conn) = Connection::connect_to_env() else {
            eprintln!("rust-bar: no Wayland display (WAYLAND_DISPLAY)");
            std::process::exit(1);
        };
        let (globals, queue) = registry_queue_init::<App>(&conn).expect("registry");
        let qh = queue.handle();
        let mut ev: EventLoop<'static, App> = EventLoop::try_new().expect("event loop");
        WaylandSource::new(conn.clone(), queue).insert(ev.handle()).expect("wayland source");
        let (bg_tx, bg_rx) = smithay_client_toolkit::reexports::calloop::channel::channel::<Box<dyn FnOnce(&mut App) + Send>>();
        ev.handle()
            .insert_source(bg_rx, |e, _, app: &mut App| {
                if let smithay_client_toolkit::reexports::calloop::channel::Event::Msg(f) = e {
                    f(app);
                }
            })
            .expect("background channel");

        let mut theme = Theme::fallback();
        if let Ok(t) = std::fs::read_to_string(crate::services::palette_path()) {
            theme.apply_json(&t);
        }
        let viewporter = bind_viewporter(&globals, &qh);
        let compositor = CompositorState::bind(&globals, &qh).expect("wl_compositor");
        let subcompositor = smithay_client_toolkit::subcompositor::SubcompositorState::bind(compositor.wl_compositor().clone(), &globals, &qh).ok();
        let mut app = App {
            conn: conn.clone(),
            qh: qh.clone(),
            handle: ev.handle(),
            bg_tx,
            bg_jobs: crate::runtime::decode_thread(),
            registry: RegistryState::new(&globals),
            outputs: OutputState::new(&globals, &qh),
            seats: SeatState::new(&globals, &qh),
            compositor,
            subcompositor,
            layer_shell: LayerShell::bind(&globals, &qh).expect("wlr-layer-shell"),
            shm: Shm::bind(&globals, &qh).expect("wl_shm"),
            viewporter,
            cursor_shapes: CursorShapeManager::bind(&globals, &qh).ok(),
            pointer: None,
            keyboard: None,
            enter_serial: 0,
            cursor: None,
            pressed: None,
            instance: Gpu::new_instance(),
            gpu: None,
            fonts: Fonts::new(),
            theme,
            strips: Vec::new(),
            card: None,
            osds: Vec::new(),
            crt_mode,
            crts: Vec::new(),
            reveals: Vec::new(),
            kbd_focus: None,
            shift: false,
            mods: Mods::default(),
            latin: LatinKeys::default(),
            key_repeat: false,
            svc: Services::default(),
            running: HashMap::new(),
            timers: HashMap::new(),
            exit: false,
            started: Instant::now(),
            weather_texts: None,
        };
        if crt_mode {
            crate::crt::start(&mut app);
        } else {
            crate::services::start(&mut app);
            crate::ipc::listen(&mut app);
        }
        while !app.exit {
            // The compositor went away (a logout, mango quitting): leave
            // quietly, as Qt does - an expect here aborted with a core dump.
            // Nothing is torn down: every surface died with the connection.
            if ev.dispatch(None, &mut app).is_err() {
                std::process::exit(0);
            }
            app.redraw_dirty();
        }
    }

    pub fn mark_all_dirty(&mut self) {
        for s in &mut self.strips {
            s.win.dirty = true;
        }
        if let Some(c) = &mut self.card {
            c.win.dirty = true;
        }
    }

    fn create_strip(&mut self, output: wl_output::WlOutput) {
        let info = self.outputs.info(&output);
        let name = info.as_ref().and_then(|i| i.name.clone()).unwrap_or_default();
        let current = info.as_ref().and_then(|i| i.modes.iter().find(|m| m.current).map(|m| m.dimensions));
        let logical = info.as_ref().and_then(|i| i.logical_size);
        let (sw, sh) = logical.or(current).map(|(w, h)| (w as f32, h as f32)).unwrap_or((2560.0, 1440.0));
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self.layer_shell.create_layer_surface(&self.qh, surface, Layer::Top, Some("quickshell:bar"), Some(&output));
        let height = bar::strip_height(sw);
        layer.set_anchor(Anchor::TOP | Anchor::LEFT | Anchor::RIGHT);
        layer.set_size(0, height);
        layer.set_exclusive_zone(bar::exclusive_zone(height, self.svc.mango.game_mode));
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        layer.commit();
        self.strips.push(Strip {
            output,
            name,
            win: Win::new(layer, 0, height),
            screen_width: sw,
            screen_height: sh,
            hits: Vec::new(),
            pointer: None,
            texts: Default::default(),
        });
    }

    /// Game mode changes the gap the strip leaves for windows.
    pub fn update_exclusive_zones(&mut self) {
        for s in &self.strips {
            s.win.layer.set_exclusive_zone(bar::exclusive_zone(s.win.height, self.svc.mango.game_mode));
            s.win.layer.commit();
        }
    }

    pub fn output_name(&self, o: &wl_output::WlOutput) -> Option<String> {
        self.outputs.info(o).and_then(|i| i.name)
    }

    pub fn win_mut(&mut self, w: WinRef) -> Option<&mut Win> {
        match w {
            WinRef::Strip(i) => self.strips.get_mut(i).map(|s| &mut s.win),
            WinRef::Card => self.card.as_mut().map(|c| &mut c.win),
            WinRef::Osd(k) => self.osd_mut(k).map(|o| &mut o.win),
            WinRef::Crt(i) => self.crts.get_mut(i).map(|c| &mut c.win),
            WinRef::Reveal(i) => self.reveals.get_mut(i).map(|r| &mut r.win),
        }
    }

    fn win_of(&self, surface: &wl_surface::WlSurface) -> Option<WinRef> {
        if let Some(i) = self.strips.iter().position(|s| s.win.layer.wl_surface() == surface) {
            return Some(WinRef::Strip(i));
        }
        if self.card.as_ref().map_or(false, |c| c.win.layer.wl_surface() == surface) {
            return Some(WinRef::Card);
        }
        if let Some(o) = self.osds.iter().find(|o| o.win.layer.wl_surface() == surface) {
            return Some(WinRef::Osd(o.kind));
        }
        if let Some(i) = self.crts.iter().position(|c| c.win.layer.wl_surface() == surface) {
            return Some(WinRef::Crt(i));
        }
        if let Some(i) = self.reveals.iter().position(|r| r.win.layer.wl_surface() == surface) {
            return Some(WinRef::Reveal(i));
        }
        None
    }

    fn ensure_gpu(&mut self, w: WinRef) {
        let conn = self.conn.clone();
        let instance = self.instance.clone();
        let need_gpu = self.gpu.is_none();
        let Some(win) = self.win_mut(w) else { return };
        if win.gpu.is_some() {
            return;
        }
        let surface = raw_surface(&conn, &instance, win.layer.wl_surface());
        if need_gpu {
            self.gpu = Some(Gpu::new(Some(&surface), instance));
        }
        let win = self.win_mut(w).unwrap();
        let (width, height) = (win.width, win.height);
        let config = surface_config(self.gpu.as_ref().unwrap(), &surface, width, height);
        self.win_mut(w).unwrap().gpu = Some((surface, config));
    }

    pub fn redraw_dirty(&mut self) {
        // The Wi-Fi icon blinks while a connection attempt runs.
        let connecting = crate::wifi_card::connecting(self);
        if connecting != self.svc.wifi_connecting {
            self.svc.wifi_connecting = connecting;
            self.svc.wifi.pulse.set_running(connecting, Instant::now(), 450);
            self.mark_all_dirty();
        }
        if self.card.as_ref().and_then(|c| c.meter_win.as_ref()).map_or(false, |m| m.dirty && !m.frame_pending && m.gpu.is_some()) {
            self.draw_meter();
        }
        if self.card.as_ref().map_or(false, |c| c.win.dirty) {
            self.svc.pult_scanning = crate::pult::scanning(self);
            self.svc.vpn_busy = (crate::vpn::time_busy(self), crate::vpn::weather_busy(self));
            self.svc.agent_busy = self.is_running("agent-usage");
            cards::update_height(self);
        }
        for i in 0..self.strips.len() {
            let w = &self.strips[i].win;
            if w.configured && w.dirty && !w.frame_pending {
                self.draw(WinRef::Strip(i));
            }
        }
        if let Some(c) = &self.card {
            if c.win.configured && c.win.dirty && !c.win.frame_pending {
                self.draw(WinRef::Card);
            }
        }
        let kinds: Vec<_> = self.osds.iter().filter(|o| o.win.configured && o.win.dirty && !o.win.frame_pending).map(|o| o.kind).collect();
        for k in kinds {
            self.draw(WinRef::Osd(k));
        }
        for i in 0..self.crts.len() {
            let w = &self.crts[i].win;
            if w.configured && w.dirty && !w.frame_pending {
                self.draw(WinRef::Crt(i));
            }
        }
        for i in 0..self.reveals.len() {
            let w = &self.reveals[i].win;
            if w.configured && w.dirty && !w.frame_pending {
                self.draw(WinRef::Reveal(i));
            }
        }
    }

    fn draw(&mut self, w: WinRef) {
        self.ensure_gpu(w);
        let Some(win) = self.win_mut(w) else { return };
        let (width, height) = (win.width, win.height);
        let mut scene = std::mem::replace(&mut win.scene, Scene::new(1.0, 1.0));
        scene.clear(width as f32, height as f32);
        let animating = match w {
            WinRef::Strip(i) => {
                let mut memo = std::mem::take(&mut self.strips[i].texts);
                let s = &self.strips[i];
                let ctx = bar::Ctx {
                    width: width as f32,
                    screen_width: s.screen_width,
                    name: &s.name,
                    pointer: s.pointer,
                    open: self.card.as_ref().filter(|c| c.strip == i).map(|c| c.kind),
                    wifi_pulse: self.svc.wifi_card.strip == Some(i),
                };
                // Theme.qml loads the wallust palette just after the QML bar's
                // first frame, and to Qt that is a change: every strip text whose
                // colour it moved is gray from then on (TextMemo). A silent pass
                // in the built-in colours gives this bar the same history.
                if memo.is_empty() && self.started.elapsed() < std::time::Duration::from_secs(5) {
                    let mut dry = Scene::new(1.0, 1.0);
                    dry.clear(width as f32, height as f32);
                    let _ = bar::draw(&mut dry, &mut self.fonts, &Theme::fallback(), &self.svc, &ctx, &mut memo);
                }
                let (hits, animating) = bar::draw(&mut scene, &mut self.fonts, &self.theme, &self.svc, &ctx, &mut memo);
                self.strips[i].hits = hits;
                self.strips[i].texts = memo;
                // The open card hangs from an icon of this strip: it follows it.
                if self.card.as_ref().map_or(false, |c| c.strip == i) {
                    cards::follow_strip(self);
                }
                animating
            }
            WinRef::Card => {
                let gpu = self.gpu.as_mut().unwrap();
                let card = self.card.as_mut().unwrap();
                cards::draw(card, &mut scene, &mut self.fonts, gpu, &self.theme, &self.svc)
            }
            WinRef::Osd(k) => {
                let o = self.osds.iter_mut().find(|o| o.kind == k).unwrap();
                crate::osd::draw(o, &mut scene, &mut self.fonts, &self.theme, &self.svc)
            }
            WinRef::Crt(i) => {
                let gpu = self.gpu.as_mut().unwrap();
                crate::crt::draw(&mut self.crts[i], &mut scene, gpu)
            }
            WinRef::Reveal(i) => {
                let gpu = self.gpu.as_mut().unwrap();
                crate::wallpaper::draw_reveal(&mut self.reveals[i], &mut scene, gpu, &self.svc, &self.theme)
            }
        };
        let qh = self.qh.clone();
        let device = self.gpu.as_ref().unwrap().device.clone();
        let win = self.win_mut(w).unwrap();
        let (surface, config) = win.gpu.as_mut().unwrap();
        if config.width != width.max(1) || config.height != height.max(1) {
            config.width = width.max(1);
            config.height = height.max(1);
            surface.configure(&device, config);
        }
        let format = config.format;
        let frame = match surface.get_current_texture() {
            Ok(f) => f,
            Err(_) => {
                surface.configure(&device, config);
                win.scene = scene;
                return;
            }
        };
        let view = frame.texture.create_view(&Default::default());
        let wl = win.layer.wl_surface().clone();
        wl.frame(&qh, wl.clone());
        let gpu = self.gpu.as_mut().unwrap();
        gpu.render(&mut self.fonts, &mut scene, &view, format, (width, height), [0.0, 0.0, 0.0, 0.0]);
        frame.present();
        let win = self.win_mut(w).unwrap();
        win.scene = scene;
        // Still animating: the next frame callback draws again.
        win.dirty = animating;
        win.frame_pending = true;
        if w == WinRef::Card {
            self.place_meter();
        }
    }

    /// The audio card's meter onto its own surface once the card has placed it.
    fn place_meter(&mut self) {
        // Its clock runs while the meter has a node (LevelMeter.qml:61).
        if self.card.as_ref().map_or(false, |c| c.kind == cards::CardKind::Audio && c.meter_node) {
            crate::audio_card::start_meter(self);
        }
        let Some(card) = self.card.as_mut() else { return };
        if card.kind != cards::CardKind::Audio {
            return;
        }
        if card.meter_win.is_none() && card.meter_at.is_some() {
            let parent = card.win.layer.wl_surface().clone();
            let m = crate::audio_card::MeterWin::new(self, &parent);
            self.card.as_mut().unwrap().meter_win = m;
        }
        let card = self.card.as_mut().unwrap();
        let at = card.meter_at;
        let Some(m) = card.meter_win.as_mut() else { return };
        if m.place(at) {
            card.win.dirty = true;
        }
        // A new palette (the card redraws for it) or the node going: this
        // surface paints the plate and segments too. Otherwise a card frame
        // leaves it alone; meter_tick asks for a frame when the level moves.
        if m.look != Some(crate::audio_card::meter_look(&self.theme, card.meter_node)) {
            m.dirty = true;
        }
        if m.dirty && !m.frame_pending {
            self.draw_meter();
        }
    }

    /// One frame of the meter's own surface.
    fn draw_meter(&mut self) {
        let (conn, instance) = (self.conn.clone(), self.instance.clone());
        let Some(gpu) = self.gpu.as_mut() else { return };
        let Some(card) = self.card.as_mut() else { return };
        let (level, hold) = if card.meter_node { (card.meter.0, card.meter.1) } else { (0.0, 0.0) };
        let Some(m) = card.meter_win.as_mut() else { return };
        let (w, h) = (m.size.0.max(1), m.size.1.max(1));
        if m.gpu.is_none() {
            m.gpu = Some(gpu_surface(&conn, &instance, gpu, &m.surface, w, h));
        }
        let (surface, config) = m.gpu.as_mut().unwrap();
        if (config.width, config.height) != (w, h) {
            (config.width, config.height) = (w, h);
            surface.configure(&gpu.device, config);
        }
        let Ok(frame) = surface.get_current_texture() else {
            surface.configure(&gpu.device, config);
            return;
        };
        let format = config.format;
        let mut scene = Scene::new(1.0, 1.0);
        scene.clear(w as f32, h as f32);
        if m.live {
            // What the card's hole leaves out: its plate, then the segments.
            scene.fill(0.0, 0.0, w as f32, h as f32, self.theme.col_plate);
            crate::audio_card::meter_cells(&mut scene, &self.theme, m.frac.0, m.frac.1, m.width, level, hold);
        }
        let view = frame.texture.create_view(&Default::default());
        m.surface.frame(&self.qh, m.surface.clone());
        gpu.render(&mut self.fonts, &mut scene, &view, format, (w, h), [0.0, 0.0, 0.0, 0.0]);
        frame.present();
        m.look = Some(crate::audio_card::meter_look(&self.theme, card.meter_node));
        m.dirty = false;
        m.frame_pending = true;
    }

    fn set_cursor(&mut self, shape: Shape) {
        if self.cursor == Some(shape) {
            return;
        }
        self.cursor = Some(shape);
        if let Some((_, Some(dev))) = &self.pointer {
            dev.set_shape(self.enter_serial, shape);
        }
    }

    /// The cursor over a hit: QQuickTextInput's I-beam over a text field, the
    /// hand of the MouseAreas' cursorShape over a control, else the arrow.
    fn cursor_at(&self, w: WinRef, hit: Option<Action>) -> Shape {
        match hit {
            Some(Action::Hover(bar::TEXT_FIELD)) => Shape::Text,
            // The Wi-Fi password TextInput is a control of the card's chain.
            Some(Action::Card(crate::wifi_card::INPUT)) if w == WinRef::Card && self.card.as_ref().map_or(false, |c| c.kind == cards::CardKind::Wifi) => Shape::Text,
            Some(Action::Hover(_)) | None => Shape::Default,
            Some(_) => Shape::Pointer,
        }
    }

    fn hit_at(&self, w: WinRef, x: f32, y: f32) -> Option<Action> {
        let hits = match w {
            WinRef::Strip(i) => &self.strips[i].hits,
            WinRef::Card => &self.card.as_ref()?.hits,
            WinRef::Osd(k) => {
                let o = self.osd(k)?;
                if let Some(a) = o.st.shape_at(x, y) {
                    return Some(a);
                }
                &o.hits
            }
            WinRef::Crt(_) | WinRef::Reveal(_) => return None,
        };
        hits.iter().rev().find(|h| h.contains(x, y)).map(|h| h.action)
    }

    fn set_pointer(&mut self, w: WinRef, p: Option<(f32, f32)>) {
        match w {
            WinRef::Strip(i) => self.strips[i].pointer = p,
            WinRef::Card => {
                if let Some(c) = &mut self.card {
                    c.pointer = p;
                }
            }
            WinRef::Osd(k) => {
                if let Some(o) = self.osd_mut(k) {
                    o.st.pointer = p;
                }
            }
            WinRef::Crt(_) | WinRef::Reveal(_) => {}
        }
    }

    fn pointer_of(&self, w: WinRef) -> Option<(f32, f32)> {
        match w {
            WinRef::Strip(i) => self.strips[i].pointer,
            WinRef::Card => self.card.as_ref()?.pointer,
            WinRef::Osd(k) => self.osd(k)?.st.pointer,
            WinRef::Crt(_) | WinRef::Reveal(_) => None,
        }
    }

    /// A key press, or a repeat of a held one (key_repeat): Keys.onPressed of
    /// the overlay holding the keyboard, else of the open card.
    fn key(&mut self, mut event: KeyEvent) {
        // QXkbCommon::keysymToQtKey: with Ctrl held, a key whose keysym is not
        // Latin-1 is the Latin key it is in another layout - Ctrl+К on the ru
        // layout is Ctrl+R (the carousel's random card), Ctrl+Ф Ctrl+A. The
        // text stays as typed.
        if self.mods.ctrl && !is_latin1(event.keysym.raw()) {
            if let Some(sym) = self.latin.lookup(event.raw_code + 8) {
                event.keysym = Keysym::new(sym);
            }
        }
        if let Some(WinRef::Osd(k)) = self.kbd_focus {
            if self.osd(k).is_some() {
                // Qt's nativeScanCode is the XKB keycode: evdev + 8.
                crate::osd::key(self, k, event.keysym, event.raw_code + 8, self.mods, event.utf8.as_deref());
                return;
            }
        }
        if self.card.is_some() {
            cards::key(self, event.keysym, self.mods, event.utf8.as_deref());
        }
    }
}

fn bind_viewporter(globals: &GlobalList, qh: &QueueHandle<App>) -> Option<WpViewporter> {
    globals.bind::<WpViewporter, _, _>(qh, 1..=1, ()).ok()
}

impl Dispatch<WpViewporter, ()> for App {
    fn event(_: &mut App, _: &WpViewporter, _: <WpViewporter as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<App>) {}
}

impl Dispatch<WpViewport, ()> for App {
    fn event(_: &mut App, _: &WpViewport, _: <WpViewport as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<App>) {}
}

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: i32) {}
    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: wl_output::Transform) {}
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &wl_surface::WlSurface, _: u32) {
        if let Some(m) = self.card.as_mut().and_then(|c| c.meter_win.as_mut()).filter(|m| &m.surface == surface) {
            m.frame_pending = false;
            if m.dirty {
                self.draw_meter();
            }
            return;
        }
        if let Some(w) = self.win_of(surface) {
            let win = self.win_mut(w).unwrap();
            win.frame_pending = false;
            if win.dirty {
                self.draw(w);
            }
        }
    }
    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
}

impl OutputHandler for App {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }
    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, output: wl_output::WlOutput) {
        if self.crt_mode {
            crate::crt::create(self, output);
        } else {
            self.create_strip(output);
        }
    }
    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, output: wl_output::WlOutput) {
        let info = self.outputs.info(&output);
        let game_mode = self.svc.mango.game_mode;
        if let Some(i) = self.strips.iter().position(|s| s.output == output) {
            let s = &mut self.strips[i];
            if let Some(n) = info.as_ref().and_then(|i| i.name.clone()) {
                s.name = n;
            }
            if let Some((w, h)) = info.as_ref().and_then(|i| i.logical_size) {
                if (w as f32, h as f32) != (s.screen_width, s.screen_height) {
                    // The card open on it: its height bindings read the
                    // screen (the agent and network cards: 85% of it), so
                    // update_height runs again; its place follows the strip's
                    // next draw (cards::follow_strip).
                    if let Some(c) = self.card.as_mut().filter(|c| c.strip == i) {
                        c.win.dirty = true;
                    }
                }
                s.screen_width = w as f32;
                s.screen_height = h as f32;
                // shell.qml: implicitHeight and exclusiveZone are bindings on
                // the width (uiScale) - a new mode or scale resizes the strip.
                let height = bar::strip_height(s.screen_width);
                if height != s.win.height {
                    s.win.layer.set_size(0, height);
                    s.win.layer.set_exclusive_zone(bar::exclusive_zone(height, game_mode));
                    s.win.layer.commit();
                }
            }
            s.win.dirty = true;
        }
    }
    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, output: wl_output::WlOutput) {
        if let Some(i) = self.strips.iter().position(|s| s.output == output) {
            self.remove_strip(i);
        }
    }
}

impl App {
    /// A strip goes with its output: the card open on it closes, and the open
    /// card, a held press and the Wi-Fi connect's bar keep pointing at their
    /// strips as the later ones move down.
    fn remove_strip(&mut self, i: usize) {
        if self.card.as_ref().map_or(false, |c| c.strip == i) {
            cards::close(self);
        }
        self.strips.remove(i);
        if let Some(c) = self.card.as_mut().filter(|c| c.strip > i) {
            c.strip -= 1;
        }
        let s = &mut self.svc.wifi_card.strip;
        *s = match *s {
            Some(j) if j == i => None,
            Some(j) if j > i => Some(j - 1),
            s => s,
        };
        match self.pressed {
            Some((WinRef::Strip(j), ..)) if j == i => self.pressed = None,
            Some((WinRef::Strip(j), button, action)) if j > i => self.pressed = Some((WinRef::Strip(j - 1), button, action)),
            _ => {}
        }
    }
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        if self.card.as_ref().map_or(false, |c| &c.win.layer == layer) {
            cards::close(self);
        }
        if let Some(i) = self.strips.iter().position(|s| &s.win.layer == layer) {
            self.remove_strip(i);
        }
        self.osds.retain(|o| &o.win.layer != layer && o.dim.as_ref().map_or(true, |d| &d.layer != layer));
    }
    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, c: LayerSurfaceConfigure, _: u32) {
        if crate::osd::configure_dim(self, layer, c.new_size) {
            return;
        }
        let w = if let Some(i) = self.strips.iter().position(|s| &s.win.layer == layer) {
            WinRef::Strip(i)
        } else if self.card.as_ref().map_or(false, |k| &k.win.layer == layer) {
            WinRef::Card
        } else if let Some(o) = self.osds.iter().find(|o| &o.win.layer == layer) {
            WinRef::Osd(o.kind)
        } else if let Some(i) = self.crts.iter().position(|c| &c.win.layer == layer) {
            crate::crt::configured(self, i);
            WinRef::Crt(i)
        } else if let Some(i) = self.reveals.iter().position(|r| &r.win.layer == layer) {
            WinRef::Reveal(i)
        } else {
            return;
        };
        let win = self.win_mut(w).unwrap();
        if c.new_size.0 > 0 {
            win.width = c.new_size.0;
        }
        if c.new_size.1 > 0 {
            win.height = c.new_size.1;
        }
        win.configured = true;
        win.dirty = true;
        if !win.frame_pending {
            self.draw(w);
        }
    }
}

impl SeatHandler for App {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seats
    }
    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat) {}
    fn new_capability(&mut self, _: &Connection, qh: &QueueHandle<Self>, seat: WlSeat, cap: Capability) {
        if cap == Capability::Pointer && self.pointer.is_none() {
            if let Ok(p) = self.seats.get_pointer(qh, &seat) {
                let dev = self.cursor_shapes.as_ref().map(|m| m.get_shape_device(&p, qh));
                self.pointer = Some((p, dev));
            }
        }
        if cap == Capability::Keyboard && self.keyboard.is_none() {
            // QtWayland repeats a held key itself, at the compositor's
            // repeat_info (mango: 50 a second after 300 ms), and the QML key
            // handlers take every repeat as a press: sctk's repeat timer
            // feeds them through the same path.
            let repeat = Box::new(|app: &mut App, _: &WlKeyboard, event: KeyEvent| {
                app.key_repeat = true;
                app.key(event);
                app.key_repeat = false;
            });
            self.keyboard = self.seats.get_keyboard_with_repeat(qh, &seat, None, self.handle.clone(), repeat).ok();
        }
    }
    fn remove_capability(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat, cap: Capability) {
        if cap == Capability::Pointer {
            if let Some((p, dev)) = self.pointer.take() {
                if let Some(d) = dev {
                    d.destroy();
                }
                p.release();
            }
        }
        if cap == Capability::Keyboard {
            if let Some(k) = self.keyboard.take() {
                k.release();
            }
        }
    }
    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat) {}
}

impl KeyboardHandler for App {
    fn enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlKeyboard, surface: &wl_surface::WlSurface, _: u32, _: &[u32], _: &[Keysym]) {
        self.kbd_focus = self.win_of(surface);
    }
    fn leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlKeyboard, _: &wl_surface::WlSurface, _: u32) {
        self.kbd_focus = None;
    }
    fn press_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlKeyboard, _: u32, event: KeyEvent) {
        self.key(event);
    }
    fn release_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlKeyboard, _: u32, _: KeyEvent) {}
    fn update_modifiers(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlKeyboard, _: u32, m: Modifiers, _: u32) {
        self.shift = m.shift;
        self.mods = Mods { shift: m.shift, ctrl: m.ctrl, alt: m.alt };
        if let Some(c) = &mut self.card {
            c.shift = m.shift;
        }
    }
    fn update_keymap(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlKeyboard, keymap: Keymap<'_>) {
        self.latin.keymap = std::ffi::CString::new(keymap.as_string()).ok();
        self.latin.found.clear();
    }
}

impl PointerHandler for App {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlPointer, events: &[PointerEvent]) {
        for e in events {
            if self.card.as_ref().map_or(false, |c| c.win.layer.wl_surface() == &e.surface) && self.pressed.is_none() {
                // CardSurface: around the card, a press dismisses it and the
                // wheel is eaten; the pointer is not over the card there. (A
                // drag that started on the card keeps going.) Its MouseArea
                // takes the left, right and middle buttons (CardSurface.qml:47):
                // a side button reaches nothing.
                let (x, y) = (e.position.0 as f32, e.position.1 as f32);
                if !matches!(e.kind, PointerEventKind::Leave { .. }) && !cards::inside(self, x, y) {
                    match e.kind {
                        PointerEventKind::Press { button: BTN_LEFT | BTN_RIGHT | BTN_MIDDLE, .. } => cards::close(self),
                        PointerEventKind::Enter { serial } => {
                            self.enter_serial = serial;
                            self.cursor = None;
                            self.set_cursor(Shape::Default);
                        }
                        PointerEventKind::Motion { .. } => {
                            if self.card.as_ref().map_or(false, |c| c.pointer.is_some()) {
                                self.set_pointer(WinRef::Card, None);
                                self.win_mut(WinRef::Card).unwrap().dirty = true;
                                self.set_cursor(Shape::Default);
                            }
                        }
                        _ => {}
                    }
                    continue;
                }
            }
            if let Some(k) = crate::osd::is_dim(self, &e.surface) {
                // The dialog's dim: a click outside the panel. Every dim's
                // MouseArea keeps acceptedButtons' default, the left button
                // (PowerOsd.qml:88, ShotOsd.qml:72, RecordOsd.qml:80,
                // ClipboardOsd.qml:121, PolkitOsd.qml:82): the others do nothing.
                match e.kind {
                    PointerEventKind::Enter { serial } => {
                        self.enter_serial = serial;
                        self.cursor = None;
                        self.set_cursor(Shape::Default);
                    }
                    PointerEventKind::Press { button: BTN_LEFT, .. } => self.pressed = Some((WinRef::Osd(k), BTN_LEFT, Action::Hover(u32::MAX))),
                    PointerEventKind::Release { button: BTN_LEFT, .. } => {
                        if self.pressed.take() == Some((WinRef::Osd(k), BTN_LEFT, Action::Hover(u32::MAX))) {
                            crate::osd::dim_clicked(self, k);
                        }
                    }
                    _ => {}
                }
                continue;
            }
            let Some(w) = self.win_of(&e.surface) else { continue };
            if let WinRef::Osd(k) = w {
                let (x, y) = (e.position.0 as f32, e.position.1 as f32);
                if let PointerEventKind::Enter { serial } = e.kind {
                    self.enter_serial = serial;
                }
                if crate::osd::raw_pointer(self, k, &e.kind, x, y) {
                    continue;
                }
            }
            if let WinRef::Reveal(_) = w {
                continue;
            }
            if let WinRef::Crt(_) = w {
                // Qt.BlankCursor: no pointer over the picture while it collapses.
                if let (PointerEventKind::Enter { serial }, Some((p, _))) = (&e.kind, &self.pointer) {
                    p.set_cursor(*serial, None, 0, 0);
                }
                continue;
            }
            let (x, y) = (e.position.0 as f32, e.position.1 as f32);
            match e.kind {
                PointerEventKind::Enter { serial } => {
                    if let WinRef::Osd(k) = w {
                        crate::osd::hover_changed(self, k, true);
                    }
                    self.enter_serial = serial;
                    self.set_pointer(w, Some((x, y)));
                    self.win_mut(w).unwrap().dirty = true;
                    // wl_pointer.enter leaves the image to the client, and
                    // mango keeps the last app's (an I-beam) until one comes:
                    // send it every time, as Qt does - also over a Hover area.
                    self.cursor = None;
                    let shape = self.cursor_at(w, self.hit_at(w, x, y));
                    self.set_cursor(shape);
                }
                PointerEventKind::Leave { .. } => {
                    if let WinRef::Osd(k) = w {
                        crate::osd::hover_changed(self, k, false);
                    }
                    if self.win_mut(w).is_none() {
                        continue;
                    }
                    self.set_pointer(w, None);
                    self.win_mut(w).unwrap().dirty = true;
                    self.pressed = None;
                }
                PointerEventKind::Motion { .. } => {
                    if let Some((WinRef::Card, 0x110, act)) = self.pressed {
                        if w == WinRef::Card {
                            cards::drag(self, act, x);
                        }
                    }
                    let before = self.pointer_of(w).and_then(|(px, py)| self.hit_at(w, px, py));
                    self.set_pointer(w, Some((x, y)));
                    let after = self.hit_at(w, x, y);
                    if before != after {
                        self.win_mut(w).unwrap().dirty = true;
                        if let WinRef::Osd(k) = w {
                            crate::osd::hovered(self, k, after);
                        }
                    }
                    let shape = self.cursor_at(w, after);
                    self.set_cursor(shape);
                }
                PointerEventKind::Press { button, .. } => {
                    // The card's own MouseArea and its controls take the left
                    // button only (DropdownWidget.qml:160): a right or middle
                    // press falls through to CardSurface's, under the card,
                    // and closes it - unless the control there takes that
                    // button: a VolumeSlider the right one (its mute,
                    // VolumeSlider.qml:104), the Wi-Fi password TextInput the
                    // middle one (the primary selection's paste).
                    if w == WinRef::Card && matches!(button, BTN_RIGHT | BTN_MIDDLE) {
                        let takes = match (self.card.as_ref().map(|c| c.kind), self.hit_at(w, x, y)) {
                            (Some(cards::CardKind::Audio), Some(Action::Card(c))) => button == BTN_RIGHT && crate::audio_card::is_slider(c),
                            (Some(cards::CardKind::Wifi), Some(Action::Card(crate::wifi_card::INPUT))) => button == BTN_MIDDLE,
                            _ => false,
                        };
                        if !takes {
                            cards::close(self);
                            continue;
                        }
                    }
                    self.pressed = self.hit_at(w, x, y).map(|a| (w, button, a));
                    if let (WinRef::Osd(k), Some(Action::Card(code))) = (w, self.hit_at(w, x, y)) {
                        if let Some(o) = self.osd_mut(k) {
                            o.st.pressed = Some(code);
                            o.win.dirty = true;
                        }
                    }
                    if let (WinRef::Card, Some(a)) = (w, self.hit_at(w, x, y)) {
                        cards::press(self, a, x, button);
                    }
                }
                PointerEventKind::Axis { horizontal, vertical, source, .. } => {
                    // Qt's angleDelta (QtWayland's FrameData::angleDelta), positive
                    // away from the user: 120 a notch, else a continuous axis'
                    // value times -12, rounded. A finger's scroll over a
                    // Flickable - a card's body or list, the clipboard's list -
                    // is a 1:1 drag in Qt instead (pixelDelta in ScrollUpdate
                    // phases), which the port does not do: there it keeps the
                    // x8 it had.
                    let drag = source == Some(wl_pointer::AxisSource::Finger)
                        && match w {
                            WinRef::Card => self.card.as_ref().map_or(false, |c| c.kind != cards::CardKind::Calendar),
                            WinRef::Osd(k) => k == crate::osd::OsdKind::Clipboard,
                            _ => false,
                        };
                    let notches = vertical.discrete != 0 || horizontal.discrete != 0;
                    let angle = |a: &AxisScroll| {
                        if notches {
                            -(a.discrete as f32) * 120.0
                        } else if drag {
                            -(a.absolute as f32) * 8.0
                        } else {
                            (-(a.absolute as f32) * 12.0 + 0.5).floor()
                        }
                    };
                    // WallpaperOsd's two WheelHandlers take angleDelta.x when y
                    // is 0 (WallpaperOsd.qml:295,496), the only ones that do.
                    let dy = angle(&vertical);
                    let delta = if dy == 0.0 && w == WinRef::Osd(crate::osd::OsdKind::Wallpaper) { angle(&horizontal) } else { dy };
                    if delta != 0.0 {
                        match w {
                            WinRef::Card => cards::wheel(self, delta),
                            WinRef::Osd(k) => crate::osd::wheel(self, k, delta),
                            WinRef::Crt(_) | WinRef::Reveal(_) => {}
                            WinRef::Strip(i) => {
                                if let Some(act) = self.hit_at(w, x, y) {
                                    bar::wheel(self, i, act, delta);
                                }
                            }
                        }
                    }
                }
                PointerEventKind::Release { button, .. } => {
                    if let WinRef::Osd(k) = w {
                        if let Some(o) = self.osd_mut(k) {
                            o.st.pressed = None;
                            o.win.dirty = true;
                        }
                    }
                    // MouseArea.onClicked: released over the widget it was pressed on.
                    if let Some((pw, pb, action)) = self.pressed.take() {
                        if pw == w && pb == button && self.hit_at(w, x, y) == Some(action) {
                            match w {
                                WinRef::Strip(i) => bar::activate(self, i, action, button),
                                WinRef::Card => cards::click(self, action, button),
                                WinRef::Osd(k) => crate::osd::click(self, k, action, button),
                                WinRef::Crt(_) | WinRef::Reveal(_) => {}
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    }
}

impl ShmHandler for App {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

impl ProvidesRegistryState for App {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState, SeatState];
}

/// delegate_keyboard!, except for one event. sctk 0.19 drops every press of a
/// repeating key while the compositor has repeat turned off (repeat_rate 0:
/// its key handler returns before press_key), where QtWayland just does not
/// repeat. Off becomes a delay of 24 days, so the presses come through. The
/// raw modifier state is noted for LatinKeys on the way.
impl Dispatch<WlKeyboard, KeyboardData<App>> for App {
    fn event(app: &mut App, kbd: &WlKeyboard, event: wl_keyboard::Event, data: &KeyboardData<App>, conn: &Connection, qh: &QueueHandle<App>) {
        let event = match event {
            wl_keyboard::Event::RepeatInfo { rate: 0, .. } => wl_keyboard::Event::RepeatInfo { rate: 1, delay: i32::MAX },
            e => e,
        };
        if let wl_keyboard::Event::Modifiers { mods_depressed, mods_latched, mods_locked, group, .. } = event {
            app.latin.mods = [mods_depressed, mods_latched, mods_locked, group];
        }
        <SeatState as Dispatch<WlKeyboard, KeyboardData<App>, App>>::event(app, kbd, event, data, conn, qh)
    }
}

/// QXkbCommon::lookupLatinKeysym, for the Ctrl shortcuts of App::key: the
/// first Latin-1 keysym the key has in the other layouts, in their order, at
/// the level the modifiers give - unless a key of a layout before that one
/// gives the same keysym. It needs the keymap and the modifier state, which
/// sctk keeps to itself: the keymap's text is kept (41 KB for us,es,ru) and
/// compiled only to answer (0.7 ms; compiled it holds 180 KB), and the
/// answers are kept until the next keymap.
#[derive(Default)]
struct LatinKeys {
    keymap: Option<std::ffi::CString>,
    /// wl_keyboard.modifiers: depressed, latched, locked, the layout.
    mods: [u32; 4],
    found: HashMap<(u32, [u32; 4]), Option<u32>>,
}

impl LatinKeys {
    fn lookup(&mut self, keycode: u32) -> Option<u32> {
        let text = self.keymap.as_ref()?;
        if self.found.len() >= 64 {
            self.found.clear();
        }
        let mods = self.mods;
        *self.found.entry((keycode, mods)).or_insert_with(|| unsafe { latin_keysym(text, keycode, mods) })
    }
}

/// QXkbCommon's isLatin1.
fn is_latin1(sym: u32) -> bool {
    (0x20..=0xff).contains(&sym)
}

#[link(name = "xkbcommon")]
extern "C" {
    fn xkb_context_new(flags: std::ffi::c_int) -> *mut std::ffi::c_void;
    fn xkb_context_unref(context: *mut std::ffi::c_void);
    fn xkb_keymap_new_from_string(context: *mut std::ffi::c_void, string: *const std::ffi::c_char, format: std::ffi::c_int, flags: std::ffi::c_int) -> *mut std::ffi::c_void;
    fn xkb_keymap_unref(keymap: *mut std::ffi::c_void);
    fn xkb_keymap_num_layouts_for_key(keymap: *mut std::ffi::c_void, key: u32) -> u32;
    fn xkb_keymap_key_get_syms_by_level(keymap: *mut std::ffi::c_void, key: u32, layout: u32, level: u32, syms_out: *mut *const u32) -> std::ffi::c_int;
    fn xkb_keymap_min_keycode(keymap: *mut std::ffi::c_void) -> u32;
    fn xkb_keymap_max_keycode(keymap: *mut std::ffi::c_void) -> u32;
    fn xkb_state_new(keymap: *mut std::ffi::c_void) -> *mut std::ffi::c_void;
    fn xkb_state_unref(state: *mut std::ffi::c_void);
    fn xkb_state_update_mask(state: *mut std::ffi::c_void, depressed: u32, latched: u32, locked: u32, depressed_layout: u32, latched_layout: u32, locked_layout: u32) -> std::ffi::c_int;
    fn xkb_state_key_get_one_sym(state: *mut std::ffi::c_void, key: u32) -> u32;
    fn xkb_state_key_get_layout(state: *mut std::ffi::c_void, key: u32) -> u32;
    fn xkb_state_key_get_level(state: *mut std::ffi::c_void, key: u32, layout: u32) -> u32;
}

/// The lookup itself, on a keymap compiled from the compositor's text (it
/// includes nothing: no include paths, no environment names).
unsafe fn latin_keysym(text: &std::ffi::CStr, keycode: u32, [depressed, latched, locked, layout_now]: [u32; 4]) -> Option<u32> {
    const NO_DEFAULT_INCLUDES_OR_ENVIRONMENT: std::ffi::c_int = 3;
    const KEYMAP_FORMAT_TEXT_V1: std::ffi::c_int = 1;
    let context = xkb_context_new(NO_DEFAULT_INCLUDES_OR_ENVIRONMENT);
    if context.is_null() {
        return None;
    }
    let keymap = xkb_keymap_new_from_string(context, text.as_ptr(), KEYMAP_FORMAT_TEXT_V1, 0);
    xkb_context_unref(context);
    if keymap.is_null() {
        return None;
    }
    let (state, query) = (xkb_state_new(keymap), xkb_state_new(keymap));
    let mut found = None;
    if !state.is_null() && !query.is_null() {
        xkb_state_update_mask(state, depressed, latched, locked, 0, 0, layout_now);
        let current = xkb_state_key_get_layout(state, keycode);
        for layout in (0..xkb_keymap_num_layouts_for_key(keymap, keycode)).filter(|&l| l != current) {
            let level = xkb_state_key_get_level(state, keycode, layout);
            let mut syms: *const u32 = std::ptr::null();
            if xkb_keymap_key_get_syms_by_level(keymap, keycode, layout, level, &mut syms) == 1 && is_latin1(*syms) {
                found = Some((layout, *syms));
                break;
            }
        }
        // Unique: no key gives it in a layout before that one (with the
        // latched and locked modifiers only), as Qt checks.
        if let Some((layout, sym)) = found {
            let (min, max) = (xkb_keymap_min_keycode(keymap), xkb_keymap_max_keycode(keymap));
            let taken = (0..layout).any(|before| {
                xkb_state_update_mask(query, 0, latched, locked, 0, 0, before);
                (min..max).any(|code| xkb_state_key_get_one_sym(query, code) == sym)
            });
            if taken {
                found = None;
            }
        }
    }
    xkb_state_unref(state);
    xkb_state_unref(query);
    xkb_keymap_unref(keymap);
    found.map(|(_, sym)| sym)
}

delegate_compositor!(App);
smithay_client_toolkit::delegate_subcompositor!(App);
delegate_output!(App);
delegate_layer!(App);
delegate_seat!(App);
delegate_pointer!(App);
delegate_shm!(App);
delegate_registry!(App);

pub fn mango_of(app: &App) -> &Mango {
    &app.svc.mango
}
