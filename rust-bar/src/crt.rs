//! `rust-bar crt`: the CRT power-off (quickshell/crt). Every monitor's
//! picture folds into a bright horizontal line, the line draws in to a point,
//! and the point dies away like phosphor; the screen then stays black until
//! the session ends. CrtOff.sh puts one frame of each monitor in
//! $XDG_RUNTIME_DIR/crt-off/<name>.ppm first and waits for `done`.

use std::time::{Duration, Instant};

use smithay_client_toolkit::{
    shell::wlr_layer::{Anchor, KeyboardInteractivity, Layer},
    shell::WaylandSurface,
};
use wayland_client::protocol::wl_output::WlOutput;

use crate::anim::{ease, Easing};
use crate::app::{App, Win};
use crate::color::Color;
use crate::gpu::{Gpu, Scene};

pub struct CrtWin {
    pub win: Win,
    /// The frame as decoded (RGBA, premultiplied), until it is on the GPU.
    frame: Option<(u32, u32, Vec<u8>)>,
    tex: Option<u32>,
    /// When the collapse started (the Timer 60 ms after mapping).
    start: Option<Instant>,
    done: bool,
}

pub fn dir() -> String {
    format!("{}/crt-off", std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".into()))
}

/// A frame from grim -t ppm, ready for the GPU.
fn load(name: &str) -> Option<(u32, u32, Vec<u8>)> {
    let img = image::ImageReader::open(format!("{}/{name}.ppm", dir())).ok()?.with_guessed_format().ok()?.decode().ok()?.to_rgba8();
    let (w, h) = img.dimensions();
    Some((w, h, img.into_raw()))
}

/// The Variants: one black Overlay window per screen, keyboard taken.
pub fn create(app: &mut App, output: WlOutput) {
    let name = app.output_name(&output).unwrap_or_default();
    let surface = app.compositor.create_surface(&app.qh);
    let layer = app.layer_shell.create_layer_surface(&app.qh, surface, Layer::Overlay, Some("quickshell:crt"), Some(&output));
    layer.set_anchor(Anchor::TOP | Anchor::BOTTOM | Anchor::LEFT | Anchor::RIGHT);
    layer.set_exclusive_zone(-1);
    layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
    layer.commit();
    let frame = load(&name);
    app.crts.push(CrtWin { win: Win::new(layer, 0, 0), frame, tex: None, start: None, done: false });
}

/// Starts the 30 s safety timer: if the machine has not gone down by then,
/// something refused it - give the desktop back.
pub fn start(app: &mut App) {
    app.after(Duration::from_secs(30), |app| app.exit = true);
}

/// Configured: the collapse starts a beat later, so its first frame is the picture.
pub fn configured(app: &mut App, i: usize) {
    if app.crts[i].start.is_none() {
        app.crts[i].start = Some(Instant::now() + Duration::from_millis(60));
    }
}

/// One frame of the collapse; true while it still moves.
pub fn draw(c: &mut CrtWin, scene: &mut Scene, gpu: &mut Gpu) -> bool {
    let (w, h) = (c.win.width as f32, c.win.height as f32);
    scene.fill(0.0, 0.0, w, h, Color::qt_rgba(0.0, 0.0, 0.0, 1.0));
    if c.tex.is_none() {
        if let Some((fw, fh, rgba)) = c.frame.take() {
            c.tex = Some(gpu.add_image(fw, fh, rgba, false));
        }
    }
    let t = c.start.map_or(0.0, |s| Instant::now().saturating_duration_since(s).as_millis() as f32);
    // yScale 1 -> .004 with the flare rising (140 ms), then xScale (160 ms), InQuad.
    let p1 = (t / 140.0).clamp(0.0, 1.0);
    let p2 = ((t - 140.0) / 160.0).clamp(0.0, 1.0);
    let ys = 1.0 + (0.004 - 1.0) * ease(Easing::InQuad, p1);
    let xs = 1.0 + (0.004 - 1.0) * ease(Easing::InQuad, p2);
    if t < 300.0 {
        scene.save();
        scene.translate(w / 2.0, h / 2.0);
        scene.scale(xs, ys);
        scene.translate(-w / 2.0, -h / 2.0);
        if let Some(id) = c.tex {
            scene.image(id, 0.0, 0.0, w, h, [0.0, 0.0, 1.0, 1.0]);
        }
        scene.save();
        scene.multiply_opacity(ease(Easing::InQuad, p1));
        scene.fill(0.0, 0.0, w, h, Color::qt_rgba(1.0, 1.0, 1.0, 1.0));
        scene.restore();
        scene.restore();
        return true;
    }
    // The last point of light and its glow, fading out (450 ms OutQuad).
    let p3 = ((t - 300.0) / 450.0).clamp(0.0, 1.0);
    let o = 1.0 - ease(Easing::OutQuad, p3);
    if o > 0.0 {
        let (dx, dy) = (crate::bar::ac(w, 32.0), crate::bar::ac(h, 32.0));
        scene.save();
        scene.multiply_opacity(o);
        scene.rect(dx, dy, 32.0, 32.0, Color::qt_rgba(1.0, 1.0, 1.0, 0.22), 16.0, 0.0, Color::TRANSPARENT, true);
        scene.rect(dx + 12.0, dy + 12.0, 8.0, 8.0, Color::qt_rgba(1.0, 1.0, 1.0, 1.0), 4.0, 0.0, Color::TRANSPARENT, true);
        scene.restore();
    }
    if p3 >= 1.0 && !c.done {
        // Tells CrtOff.sh the picture is gone and the real command can run.
        c.done = true;
        let _ = std::fs::write(format!("{}/done", dir()), b"");
    }
    p3 < 1.0
}
