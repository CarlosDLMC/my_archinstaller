//! The running bar: Wayland objects, the event loop, one strip per output,
//! redraws driven by frame callbacks (nothing is drawn while nothing changes).

use std::collections::HashMap;
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::ptr::NonNull;
use std::time::{Duration, Instant};

use raw_window_handle::{RawDisplayHandle, RawWindowHandle, WaylandDisplayHandle, WaylandWindowHandle};
use smithay_client_toolkit::{
    compositor::{CompositorHandler, CompositorState},
    delegate_compositor, delegate_layer, delegate_output, delegate_pointer, delegate_registry, delegate_seat,
    output::{OutputHandler, OutputState},
    reexports::calloop::{
        generic::Generic,
        timer::{TimeoutAction, Timer},
        EventLoop, Interest, LoopHandle, Mode, PostAction,
    },
    reexports::calloop_wayland_source::WaylandSource,
    reexports::protocols::wp::cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1},
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
    seat::{
        pointer::{cursor_shape::CursorShapeManager, PointerEvent, PointerEventKind, PointerHandler},
        Capability, SeatHandler, SeatState,
    },
    shell::{
        wlr_layer::{Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface, LayerSurfaceConfigure},
        WaylandSurface,
    },
};
use wayland_client::{
    globals::registry_queue_init,
    protocol::{wl_output, wl_pointer::WlPointer, wl_seat::WlSeat, wl_surface},
    Connection, Proxy, QueueHandle,
};

use crate::bar::{self, Action, Hit};
use crate::gpu::{Gpu, Scene};
use crate::services::{Mango, Services};
use crate::text::Fonts;
use crate::theme::Theme;

pub struct Strip {
    pub output: wl_output::WlOutput,
    pub name: String,
    pub layer: LayerSurface,
    surface: Option<(wgpu::Surface<'static>, wgpu::SurfaceConfiguration)>,
    pub width: u32,
    pub height: u32,
    pub screen_width: f32,
    configured: bool,
    pub dirty: bool,
    frame_pending: bool,
    scene: Scene,
    pub hits: Vec<Hit>,
    pub pointer: Option<(f32, f32)>,
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
    compositor: CompositorState,
    layer_shell: LayerShell,
    cursor_shapes: Option<CursorShapeManager>,
    pointer: Option<(WlPointer, Option<WpCursorShapeDeviceV1>)>,
    pub instance: wgpu::Instance,
    pub gpu: Option<Gpu>,
    pub fonts: Fonts,
    pub theme: Theme,
    pub strips: Vec<Strip>,
    pub svc: Services,
    running: HashMap<String, Instant>,
    pub exit: bool,
}

impl App {
    pub fn run() {
        let conn = Connection::connect_to_env().expect("no Wayland display");
        let (globals, queue) = registry_queue_init::<App>(&conn).expect("registry");
        let qh = queue.handle();
        let mut ev: EventLoop<'static, App> = EventLoop::try_new().expect("event loop");
        WaylandSource::new(conn.clone(), queue).insert(ev.handle()).expect("wayland source");

        let mut theme = Theme::fallback();
        if let Ok(t) = std::fs::read_to_string(crate::services::palette_path()) {
            theme.apply_json(&t);
        }
        let mut app = App {
            conn: conn.clone(),
            qh: qh.clone(),
            handle: ev.handle(),
            registry: RegistryState::new(&globals),
            outputs: OutputState::new(&globals, &qh),
            seats: SeatState::new(&globals, &qh),
            compositor: CompositorState::bind(&globals, &qh).expect("wl_compositor"),
            layer_shell: LayerShell::bind(&globals, &qh).expect("wlr-layer-shell"),
            cursor_shapes: CursorShapeManager::bind(&globals, &qh).ok(),
            pointer: None,
            instance: Gpu::new_instance(),
            gpu: None,
            fonts: Fonts::new(),
            theme,
            strips: Vec::new(),
            svc: Services::default(),
            running: HashMap::new(),
            exit: false,
        };
        crate::services::start(&mut app);
        crate::ipc::listen(&mut app);
        while !app.exit {
            ev.dispatch(None, &mut app).expect("dispatch");
            app.redraw_dirty();
        }
    }

    pub fn mark_all_dirty(&mut self) {
        for s in &mut self.strips {
            s.dirty = true;
        }
    }

    fn create_strip(&mut self, output: wl_output::WlOutput) {
        let info = self.outputs.info(&output);
        let name = info.as_ref().and_then(|i| i.name.clone()).unwrap_or_default();
        let screen_width = info
            .as_ref()
            .and_then(|i| i.logical_size.map(|s| s.0 as f32))
            .or_else(|| info.as_ref().and_then(|i| i.modes.iter().find(|m| m.current).map(|m| m.dimensions.0 as f32)))
            .unwrap_or(2560.0);
        let surface = self.compositor.create_surface(&self.qh);
        let layer = self.layer_shell.create_layer_surface(&self.qh, surface, Layer::Top, Some("quickshell:bar"), Some(&output));
        let height = bar::strip_height(screen_width);
        layer.set_anchor(Anchor::TOP | Anchor::LEFT | Anchor::RIGHT);
        layer.set_size(0, height);
        layer.set_exclusive_zone(bar::exclusive_zone(height, self.svc.mango.game_mode));
        layer.set_keyboard_interactivity(KeyboardInteractivity::None);
        layer.commit();
        self.strips.push(Strip {
            output,
            name,
            layer,
            surface: None,
            width: 0,
            height,
            screen_width,
            configured: false,
            dirty: true,
            frame_pending: false,
            scene: Scene::new(1.0, 1.0),
            hits: Vec::new(),
            pointer: None,
        });
    }

    /// Game mode changes the gap the strip leaves for windows.
    pub fn update_exclusive_zones(&mut self) {
        for s in &self.strips {
            s.layer.set_exclusive_zone(bar::exclusive_zone(s.height, self.svc.mango.game_mode));
            s.layer.commit();
        }
    }

    fn ensure_surface(&mut self, i: usize) {
        if self.strips[i].surface.is_some() {
            return;
        }
        let s = &self.strips[i];
        let dpy = NonNull::new(self.conn.backend().display_ptr() as *mut _).unwrap();
        let win = NonNull::new(s.layer.wl_surface().id().as_ptr() as *mut _).unwrap();
        let surface = unsafe {
            self.instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::RawHandle {
                raw_display_handle: RawDisplayHandle::Wayland(WaylandDisplayHandle::new(dpy)),
                raw_window_handle: RawWindowHandle::Wayland(WaylandWindowHandle::new(win)),
            })
        }
        .expect("wgpu surface");
        if self.gpu.is_none() {
            self.gpu = Some(Gpu::new(Some(&surface), self.instance.clone()));
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
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width: s.width.max(1),
            height: s.height.max(1),
            present_mode: wgpu::PresentMode::Fifo,
            desired_maximum_frame_latency: 2,
            alpha_mode,
            view_formats: vec![],
        };
        surface.configure(&gpu.device, &config);
        self.strips[i].surface = Some((surface, config));
    }

    pub fn redraw_dirty(&mut self) {
        for i in 0..self.strips.len() {
            let s = &self.strips[i];
            if s.configured && s.dirty && !s.frame_pending {
                self.draw(i);
            }
        }
    }

    fn draw(&mut self, i: usize) {
        self.ensure_surface(i);
        let qh = self.qh.clone();
        let s = &mut self.strips[i];
        let (surface, config) = s.surface.as_mut().unwrap();
        if config.width != s.width || config.height != s.height {
            config.width = s.width.max(1);
            config.height = s.height.max(1);
            surface.configure(&self.gpu.as_ref().unwrap().device, config);
        }
        let format = config.format;
        let frame = match surface.get_current_texture() {
            Ok(f) => f,
            Err(_) => {
                surface.configure(&self.gpu.as_ref().unwrap().device, config);
                return;
            }
        };
        let view = frame.texture.create_view(&Default::default());
        s.scene.clear(s.width as f32, s.height as f32);
        let ctx = bar::Ctx { width: s.width as f32, screen_width: s.screen_width, name: &s.name, pointer: s.pointer };
        s.hits = bar::draw(&mut s.scene, &mut self.fonts, &self.theme, &self.svc, &ctx);
        let wl = s.layer.wl_surface();
        wl.frame(&qh, wl.clone());
        let gpu = self.gpu.as_mut().unwrap();
        gpu.render(&mut self.fonts, &mut s.scene, &view, format, (s.width, s.height), [0.0, 0.0, 0.0, 0.0]);
        frame.present();
        s.dirty = false;
        s.frame_pending = true;
    }

    fn strip_of(&self, surface: &wl_surface::WlSurface) -> Option<usize> {
        self.strips.iter().position(|s| s.layer.wl_surface() == surface)
    }

    fn set_cursor(&self, serial: u32, hand: bool) {
        if let Some((_, Some(dev))) = &self.pointer {
            dev.set_shape(serial, if hand { Shape::Pointer } else { Shape::Default });
        }
    }

    /// Runs `argv` with its stdout collected; `done` gets it when the process ends.
    /// Children die with the bar (PR_SET_PDEATHSIG), as setpriv --pdeathsig does for the QML bar.
    pub fn spawn(&mut self, tag: &str, argv: &[&str], done: fn(&mut App, ProcDone)) {
        if self.running.contains_key(tag) {
            return;
        }
        let mut cmd = Command::new(argv[0]);
        cmd.args(&argv[1..]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
        unsafe {
            cmd.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let Ok(mut child) = cmd.spawn() else {
            done(self, ProcDone { tag: tag.into(), stdout: String::new(), ok: false });
            return;
        };
        let stdout = child.stdout.take().unwrap();
        let fd = stdout.as_raw_fd();
        unsafe {
            let fl = libc::fcntl(fd, libc::F_GETFL);
            libc::fcntl(fd, libc::F_SETFL, fl | libc::O_NONBLOCK);
        }
        self.running.insert(tag.into(), Instant::now());
        let tag = tag.to_string();
        let mut buf = Vec::new();
        let mut child: Option<Child> = Some(child);
        let _ = self.handle.insert_source(Generic::new(stdout, Interest::READ, Mode::Level), move |_, out, app: &mut App| {
            let mut chunk = [0u8; 4096];
            loop {
                match unsafe { out.get_mut() }.read(&mut chunk) {
                    Ok(0) => {
                        let ok = child.take().and_then(|mut c| c.wait().ok()).map_or(false, |s| s.success());
                        app.running.remove(&tag);
                        let stdout = String::from_utf8_lossy(&buf).into_owned();
                        done(app, ProcDone { tag: tag.clone(), stdout, ok });
                        return Ok(PostAction::Remove);
                    }
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => return Ok(PostAction::Continue),
                    Err(_) => return Ok(PostAction::Remove),
                }
            }
        });
    }

    /// Fire and forget (Quickshell.execDetached).
    pub fn exec_detached(&self, argv: &[&str]) {
        let mut cmd = Command::new(argv[0]);
        cmd.args(&argv[1..]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
        unsafe {
            cmd.pre_exec(|| {
                libc::setsid();
                Ok(())
            });
        }
        if let Ok(mut c) = cmd.spawn() {
            std::thread::spawn(move || {
                let _ = c.wait();
            });
        }
    }

    /// A repeating timer; `tick` returns false to stop it.
    pub fn every(&self, period: Duration, tick: fn(&mut App) -> bool) {
        let _ = self.handle.insert_source(Timer::from_duration(period), move |_, _, app| {
            if tick(app) {
                TimeoutAction::ToDuration(period)
            } else {
                TimeoutAction::Drop
            }
        });
    }

    pub fn after(&self, delay: Duration, f: fn(&mut App)) {
        let _ = self.handle.insert_source(Timer::from_duration(delay), move |_, _, app| {
            f(app);
            TimeoutAction::Drop
        });
    }

    /// Reads lines from a connected stream socket for as long as it is open.
    pub fn watch_lines(&self, stream: UnixStream, on_line: fn(&mut App, &str)) {
        let _ = stream.set_nonblocking(true);
        let mut buf = Vec::new();
        let _ = self.handle.insert_source(Generic::new(stream, Interest::READ, Mode::Level), move |_, s, app: &mut App| {
            let mut chunk = [0u8; 16384];
            loop {
                match unsafe { s.get_mut() }.read(&mut chunk) {
                    Ok(0) => return Ok(PostAction::Remove),
                    Ok(n) => {
                        buf.extend_from_slice(&chunk[..n]);
                        while let Some(p) = buf.iter().position(|&b| b == b'\n') {
                            let line: Vec<u8> = buf.drain(..=p).collect();
                            on_line(app, String::from_utf8_lossy(&line[..line.len() - 1]).as_ref());
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => return Ok(PostAction::Continue),
                    Err(_) => return Ok(PostAction::Remove),
                }
            }
        });
    }

    pub fn listen_unix(&self, listener: UnixListener, on_conn: fn(&mut App, UnixStream)) {
        let _ = listener.set_nonblocking(true);
        let _ = self.handle.insert_source(Generic::new(listener, Interest::READ, Mode::Level), move |_, l, app: &mut App| {
            while let Ok((c, _)) = l.accept() {
                on_conn(app, c);
            }
            Ok(PostAction::Continue)
        });
    }

    fn click(&mut self, i: usize, button: u32, x: f32, y: f32) {
        let hit = self.strips[i].hits.iter().rev().find(|h| h.contains(x, y)).cloned();
        if let Some(h) = hit {
            bar::activate(self, i, h.action, button);
        }
    }
}

pub fn write_line(mut s: &UnixStream, line: &str) {
    let _ = s.write_all(line.as_bytes());
}

impl CompositorHandler for App {
    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: i32) {}
    fn transform_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: wl_output::Transform) {}
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, surface: &wl_surface::WlSurface, _: u32) {
        if let Some(i) = self.strip_of(surface) {
            self.strips[i].frame_pending = false;
            if self.strips[i].dirty {
                self.draw(i);
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
        self.create_strip(output);
    }
    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, output: wl_output::WlOutput) {
        let info = self.outputs.info(&output);
        if let Some(s) = self.strips.iter_mut().find(|s| s.output == output) {
            if let Some(n) = info.as_ref().and_then(|i| i.name.clone()) {
                s.name = n;
            }
            if let Some(w) = info.as_ref().and_then(|i| i.logical_size.map(|l| l.0 as f32)) {
                s.screen_width = w;
            }
            s.dirty = true;
        }
    }
    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, output: wl_output::WlOutput) {
        self.strips.retain(|s| s.output != output);
    }
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface) {
        self.strips.retain(|s| &s.layer != layer);
    }
    fn configure(&mut self, _: &Connection, _: &QueueHandle<Self>, layer: &LayerSurface, c: LayerSurfaceConfigure, _: u32) {
        if let Some(i) = self.strips.iter().position(|s| &s.layer == layer) {
            let s = &mut self.strips[i];
            if c.new_size.0 > 0 {
                s.width = c.new_size.0;
            }
            if c.new_size.1 > 0 {
                s.height = c.new_size.1;
            }
            s.configured = true;
            s.dirty = true;
            if !s.frame_pending {
                self.draw(i);
            }
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
    }
    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: WlSeat) {}
}

impl PointerHandler for App {
    fn pointer_frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &WlPointer, events: &[PointerEvent]) {
        for e in events {
            let Some(i) = self.strip_of(&e.surface) else { continue };
            let (x, y) = (e.position.0 as f32, e.position.1 as f32);
            match e.kind {
                PointerEventKind::Enter { serial } => {
                    self.strips[i].pointer = Some((x, y));
                    self.strips[i].dirty = true;
                    let hand = self.strips[i].hits.iter().any(|h| h.contains(x, y));
                    self.set_cursor(serial, hand);
                }
                PointerEventKind::Leave { .. } => {
                    self.strips[i].pointer = None;
                    self.strips[i].dirty = true;
                }
                PointerEventKind::Motion { .. } => {
                    let before = self.strips[i].hits.iter().position(|h| self.strips[i].pointer.map_or(false, |(px, py)| h.contains(px, py)));
                    self.strips[i].pointer = Some((x, y));
                    let after = self.strips[i].hits.iter().position(|h| h.contains(x, y));
                    if before != after {
                        self.strips[i].dirty = true;
                    }
                }
                PointerEventKind::Press { button, serial, .. } => {
                    let _ = serial;
                    self.click(i, button, x, y);
                }
                _ => {}
            }
        }
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
delegate_registry!(App);

pub fn mango_of<'a>(app: &'a App) -> &'a Mango {
    &app.svc.mango
}
