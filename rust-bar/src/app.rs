//! The running bar: Wayland objects, the event loop, the surfaces (a strip per
//! output, the open card and its click catcher), redraws driven by frame
//! callbacks - nothing is drawn while nothing changes.

use std::collections::HashMap;
use std::ptr::NonNull;
use std::time::Instant;

use raw_window_handle::{RawDisplayHandle, RawWindowHandle, WaylandDisplayHandle, WaylandWindowHandle};
use smithay_client_toolkit::{
    compositor::{CompositorHandler, CompositorState},
    delegate_compositor, delegate_keyboard, delegate_layer, delegate_output, delegate_pointer, delegate_registry, delegate_seat,
    delegate_shm,
    output::{OutputHandler, OutputState},
    reexports::calloop::{EventLoop, LoopHandle, RegistrationToken},
    reexports::calloop_wayland_source::WaylandSource,
    reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1},
    reexports::protocols::wp::viewporter::client::{wp_viewport::WpViewport, wp_viewporter::WpViewporter},
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
    seat::{
        keyboard::{KeyEvent, KeyboardHandler, Keysym, Modifiers},
        pointer::{cursor_shape::CursorShapeManager, PointerEvent, PointerEventKind, PointerHandler},
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
    protocol::{wl_keyboard::WlKeyboard, wl_output, wl_pointer::WlPointer, wl_seat::WlSeat, wl_surface},
    Connection, Dispatch, Proxy, QueueHandle,
};

use crate::bar::{self, Action, Hit};
use crate::cards::{self, OpenCard};
use crate::gpu::{Gpu, Scene};
use crate::services::{Mango, Services};
use crate::text::Fonts;
use crate::theme::Theme;

/// A layer surface drawn with the GPU.
pub struct Win {
    pub layer: LayerSurface,
    gpu: Option<(wgpu::Surface<'static>, wgpu::SurfaceConfiguration)>,
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
    cursor_shapes: Option<CursorShapeManager>,
    pointer: Option<(WlPointer, Option<WpCursorShapeDeviceV1>)>,
    keyboard: Option<WlKeyboard>,
    enter_serial: u32,
    /// The surface holding the keyboard, and Shift.
    kbd_focus: Option<WinRef>,
    shift: bool,
    mods: Mods,
    hand: bool,
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
    /// Results of work done off the main thread, run back on the event loop.
    pub(crate) bg_tx: smithay_client_toolkit::reexports::calloop::channel::Sender<Box<dyn FnOnce(&mut App) + Send>>,
    /// The one decode thread's queue (runtime.rs, background()).
    pub(crate) bg_jobs: std::sync::mpsc::Sender<Box<dyn FnOnce() + Send>>,
}

impl App {
    pub fn run(crt_mode: bool) {
        let conn = Connection::connect_to_env().expect("no Wayland display");
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
        let mut app = App {
            conn: conn.clone(),
            qh: qh.clone(),
            handle: ev.handle(),
            bg_tx,
            bg_jobs: crate::runtime::decode_thread(),
            registry: RegistryState::new(&globals),
            outputs: OutputState::new(&globals, &qh),
            seats: SeatState::new(&globals, &qh),
            compositor: CompositorState::bind(&globals, &qh).expect("wl_compositor"),
            layer_shell: LayerShell::bind(&globals, &qh).expect("wlr-layer-shell"),
            shm: Shm::bind(&globals, &qh).expect("wl_shm"),
            viewporter,
            cursor_shapes: CursorShapeManager::bind(&globals, &qh).ok(),
            pointer: None,
            keyboard: None,
            enter_serial: 0,
            hand: false,
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
            svc: Services::default(),
            running: HashMap::new(),
            timers: HashMap::new(),
            exit: false,
        };
        if crt_mode {
            crate::crt::start(&mut app);
        } else {
            crate::services::start(&mut app);
            crate::ipc::listen(&mut app);
        }
        while !app.exit {
            ev.dispatch(None, &mut app).expect("dispatch");
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
        let dpy = NonNull::new(conn.backend().display_ptr() as *mut _).unwrap();
        let wl = NonNull::new(win.layer.wl_surface().id().as_ptr() as *mut _).unwrap();
        let surface = unsafe {
            instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::RawHandle {
                raw_display_handle: RawDisplayHandle::Wayland(WaylandDisplayHandle::new(dpy)),
                raw_window_handle: RawWindowHandle::Wayland(WaylandWindowHandle::new(wl)),
            })
        }
        .expect("wgpu surface");
        if need_gpu {
            self.gpu = Some(Gpu::new(Some(&surface), instance));
        }
        let gpu = self.gpu.as_ref().unwrap();
        let caps = surface.get_capabilities(&gpu.adapter);
        // Blend in gamma space like Qt: a non-sRGB format, premultiplied alpha.
        let format = caps.formats.iter().copied().find(|f| !f.is_srgb()).unwrap_or(caps.formats[0]);
        let alpha_mode = if caps.alpha_modes.contains(&wgpu::CompositeAlphaMode::PreMultiplied) {
            wgpu::CompositeAlphaMode::PreMultiplied
        } else {
            caps.alpha_modes[0]
        };
        let win = self.win_mut(w).unwrap();
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width: win.width.max(1),
            height: win.height.max(1),
            present_mode: wgpu::PresentMode::Fifo,
            desired_maximum_frame_latency: 2,
            alpha_mode,
            view_formats: vec![],
        };
        surface.configure(&self.gpu.as_ref().unwrap().device, &config);
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
                let ctx = bar::Ctx { width: width as f32, screen_width: s.screen_width, name: &s.name, pointer: s.pointer, open: self.card.as_ref().filter(|c| c.strip == i).map(|c| c.kind) };
                let (hits, animating) = bar::draw(&mut scene, &mut self.fonts, &self.theme, &self.svc, &ctx, &mut memo);
                self.strips[i].hits = hits;
                self.strips[i].texts = memo;
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
    }

    fn set_cursor(&mut self, hand: bool) {
        if hand == self.hand {
            return;
        }
        self.hand = hand;
        if let Some((_, Some(dev))) = &self.pointer {
            dev.set_shape(self.enter_serial, if hand { Shape::Pointer } else { Shape::Default });
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
        if let Some(s) = self.strips.iter_mut().find(|s| s.output == output) {
            if let Some(n) = info.as_ref().and_then(|i| i.name.clone()) {
                s.name = n;
            }
            if let Some((w, h)) = info.as_ref().and_then(|i| i.logical_size) {
                s.screen_width = w as f32;
                s.screen_height = h as f32;
            }
            s.win.dirty = true;
        }
    }
    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, output: wl_output::WlOutput) {
        if let Some(i) = self.strips.iter().position(|s| s.output == output) {
            if self.card.as_ref().map_or(false, |c| c.strip == i) {
                cards::close(self);
            }
            self.strips.remove(i);
        }
    }
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        if self.card.as_ref().map_or(false, |c| &c.win.layer == layer || &c.catcher.layer == layer) {
            cards::close(self);
        }
        self.strips.retain(|s| &s.win.layer != layer);
        self.osds.retain(|o| &o.win.layer != layer && o.dim.as_ref().map_or(true, |d| &d.layer != layer));
    }
    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, c: LayerSurfaceConfigure, _: u32) {
        if self.card.as_ref().map_or(false, |k| &k.catcher.layer == layer) {
            cards::configure_catcher(self, c.new_size);
            return;
        }
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
            self.keyboard = self.seats.get_keyboard(qh, &seat, None).ok();
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
        if let Some(WinRef::Osd(k)) = self.kbd_focus {
            if self.osd(k).is_some() {
                // Qt's nativeScanCode is the XKB keycode: evdev + 8.
                crate::osd::key(self, k, event.keysym, event.raw_code + 8, self.mods, event.utf8.as_deref());
                return;
            }
        }
        if self.card.is_some() {
            cards::key(self, event.keysym, event.utf8.as_deref());
        }
    }
    fn release_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlKeyboard, _: u32, _: KeyEvent) {}
    fn update_modifiers(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlKeyboard, _: u32, m: Modifiers, _: u32) {
        self.shift = m.shift;
        self.mods = Mods { shift: m.shift, ctrl: m.ctrl, alt: m.alt };
        if let Some(c) = &mut self.card {
            c.shift = m.shift;
        }
    }
}

impl PointerHandler for App {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlPointer, events: &[PointerEvent]) {
        for e in events {
            if self.card.as_ref().map_or(false, |c| c.catcher.layer.wl_surface() == &e.surface) {
                // CardSurface: a press anywhere outside the card dismisses it.
                if let PointerEventKind::Enter { serial } = e.kind {
                    self.enter_serial = serial;
                    self.hand = true;
                    self.set_cursor(false);
                }
                if let PointerEventKind::Press { .. } = e.kind {
                    cards::close(self);
                }
                continue;
            }
            if let Some(k) = crate::osd::is_dim(self, &e.surface) {
                // The dialog's dim: a click outside the panel.
                match e.kind {
                    PointerEventKind::Enter { serial } => {
                        self.enter_serial = serial;
                        self.hand = true;
                        self.set_cursor(false);
                    }
                    PointerEventKind::Press { button, .. } => self.pressed = Some((WinRef::Osd(k), button, Action::Hover(u32::MAX))),
                    PointerEventKind::Release { button, .. } => {
                        if self.pressed.take() == Some((WinRef::Osd(k), button, Action::Hover(u32::MAX))) {
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
                    self.hand = !self.hit_at(w, x, y).is_some();
                    self.set_pointer(w, Some((x, y)));
                    self.win_mut(w).unwrap().dirty = true;
                    let hand = self.hit_at(w, x, y).map_or(false, |a| !matches!(a, Action::Hover(_)));
                    self.set_cursor(hand);
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
                    self.set_cursor(after.map_or(false, |a| !matches!(a, Action::Hover(_))));
                }
                PointerEventKind::Press { button, .. } => {
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
                PointerEventKind::Axis { vertical, .. } => {
                    // Qt's angleDelta: 120 per notch, positive away from the user.
                    let delta = if vertical.discrete != 0 { -(vertical.discrete as f32) * 120.0 } else { -(vertical.absolute as f32) * 8.0 };
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

delegate_compositor!(App);
delegate_output!(App);
delegate_layer!(App);
delegate_seat!(App);
delegate_pointer!(App);
delegate_keyboard!(App);
delegate_shm!(App);
delegate_registry!(App);

pub fn mango_of(app: &App) -> &Mango {
    &app.svc.mango
}
