//! The overview's window pictures, taken by the bar itself: one still per
//! window through ext-image-copy-capture, by its foreign-toplevel id - the
//! capture `grim -T` made for overview-shots.sh, covered windows and windows
//! on other workspaces too. The pictures come out as grim and magick made
//! them (pixels.rs) and are written where the script wrote them, so an open
//! still shows the last open's pictures at once. Without the three globals
//! the overview runs the script.
//!
//! A take: the foreign-toplevel list is bound for it and let go once a sync
//! says every toplevel is in, then the windows are captured a few at a time,
//! each into a buffer of its own (session, buffer constraints, wl_shm
//! buffer, frame), and made into a picture on the decode thread. When the
//! last one is made the set goes to the overview at once. Closing the
//! overview drops the take.

mod pixels;

use std::collections::{HashMap, VecDeque};
use std::fs::File;
use std::os::fd::{AsFd, FromRawFd};

use wayland_client::{
    event_created_child,
    globals::GlobalList,
    protocol::{wl_buffer::WlBuffer, wl_callback::{self, WlCallback}, wl_shm, wl_shm_pool::WlShmPool},
    Connection, Dispatch, Proxy, QueueHandle, WEnum,
};
use wayland_protocols::ext::foreign_toplevel_list::v1::client::{
    ext_foreign_toplevel_handle_v1::{self, ExtForeignToplevelHandleV1},
    ext_foreign_toplevel_list_v1::{self, ExtForeignToplevelListV1},
};
use wayland_protocols::ext::image_capture_source::v1::client::{
    ext_foreign_toplevel_image_capture_source_manager_v1::ExtForeignToplevelImageCaptureSourceManagerV1,
    ext_image_capture_source_v1::ExtImageCaptureSourceV1,
};
use wayland_protocols::ext::image_copy_capture::v1::client::{
    ext_image_copy_capture_frame_v1::{self, ExtImageCopyCaptureFrameV1},
    ext_image_copy_capture_manager_v1::{ExtImageCopyCaptureManagerV1, Options},
    ext_image_copy_capture_session_v1::{self, ExtImageCopyCaptureSessionV1},
};

use crate::app::App;

/// Windows captured at once. Each holds a buffer of its full size (15 MB
/// for a 2560x1440 window) from its capture until its picture is made; the
/// script ran a grim per window, all at once.
const AT_ONCE: usize = 3;

/// A picture's mip levels (gpu::mip_levels).
pub type Levels = Vec<(u32, u32, Vec<u8>)>;

#[derive(Default)]
pub struct Shots {
    managers: Option<(ExtForeignToplevelImageCaptureSourceManagerV1, ExtImageCopyCaptureManagerV1)>,
    take: Option<Take>,
    serial: u32,
}

impl Shots {
    pub fn bind(globals: &GlobalList, qh: &QueueHandle<App>) -> Shots {
        let sources = globals.bind(qh, 1..=1, ()).ok();
        let copy = globals.bind(qh, 1..=1, ()).ok();
        Shots { managers: sources.zip(copy), ..Default::default() }
    }
}

/// A window to take: mango's id and size, for the overview and the trim.
#[derive(Clone, Copy)]
struct Window {
    id: i64,
    width: i64,
    height: i64,
}

/// One overview open's pictures.
struct Take {
    serial: u32,
    /// The foreign-toplevel list, until the sync after its bind.
    list: Option<ExtForeignToplevelListV1>,
    listed: bool,
    /// The toplevels the list announced, with their identifier once sent.
    handles: Vec<(ExtForeignToplevelHandleV1, String)>,
    /// The windows to take, by foreign-toplevel id.
    wanted: HashMap<String, Window>,
    queue: VecDeque<(ExtForeignToplevelHandleV1, Window)>,
    active: Vec<Capture>,
    /// Pictures being made on the decode thread, each with its buffer.
    making: usize,
    done: Vec<(i64, Levels)>,
}

struct Capture {
    window: Window,
    session: ExtImageCopyCaptureSessionV1,
    size: (u32, u32),
    format: Option<wl_shm::Format>,
    frame: Option<(ExtImageCopyCaptureFrameV1, Buffer)>,
}

struct Buffer {
    pool: WlShmPool,
    buffer: WlBuffer,
    map: memmap2::MmapMut,
    rgb: [usize; 3],
}

impl Capture {
    fn destroy(self) -> Option<Buffer> {
        let buf = self.frame.map(|(frame, buf)| {
            frame.destroy();
            buf
        });
        self.session.destroy();
        buf.inspect(|b| {
            b.buffer.destroy();
            b.pool.destroy();
        })
    }
}

/// What a take's capture objects carry: the take and the window.
#[derive(Clone, Copy)]
pub struct Tag {
    take: u32,
    id: i64,
}

/// The sync after the list's bind.
pub struct Listed(u32);

/// Takes the pictures of `windows` (id, foreign-toplevel id, width,
/// height); false when the compositor has no window capture for the bar.
pub fn take(app: &mut App, windows: &[(i64, String, i64, i64)]) -> bool {
    if app.shots.managers.is_none() {
        return false;
    }
    cancel(app);
    let serial = app.shots.serial.wrapping_add(1);
    let Ok(list) = app.registry.bind_one::<ExtForeignToplevelListV1, _, _>(&app.qh, 1..=1, serial) else { return false };
    app.shots.serial = serial;
    app.conn.display().sync(&app.qh, Listed(serial));
    // The script's `rm`, on the decode thread: after the files of a take
    // that is still being made there.
    let dir = crate::overview::shot_dir();
    app.background(move || clear(&dir), |_, _| {});
    app.shots.take = Some(Take {
        serial,
        list: Some(list),
        listed: false,
        handles: Vec::new(),
        wanted: windows.iter().map(|(id, toplevel, width, height)| (toplevel.clone(), Window { id: *id, width: *width, height: *height })).collect(),
        queue: VecDeque::new(),
        active: Vec::new(),
        making: 0,
        done: Vec::new(),
    });
    true
}

/// Drops the running take: its handles, captures and buffers go now, a
/// picture still being made is written but not shown. True when the take
/// had made a picture already (the next open loads it).
pub fn cancel(app: &mut App) -> bool {
    let Some(t) = app.shots.take.take() else { return false };
    if let Some(list) = t.list {
        list.stop();
    }
    for (h, _) in t.handles {
        h.destroy();
    }
    for (h, _) in t.queue {
        h.destroy();
    }
    for c in t.active {
        c.destroy();
    }
    !t.done.is_empty()
}

fn clear(dir: &str) {
    let _ = std::fs::create_dir_all(dir);
    for e in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let name = e.file_name();
        let name = name.to_string_lossy();
        if name.ends_with(".ppm") || name.ends_with(".ppm.new") {
            let _ = std::fs::remove_file(e.path());
        }
    }
}

fn take_of(app: &mut App, serial: u32) -> Option<&mut Take> {
    app.shots.take.as_mut().filter(|t| t.serial == serial)
}

/// Every toplevel is in: the wanted ones queue up, the rest go.
fn listed(app: &mut App, serial: u32) {
    let Some(t) = take_of(app, serial) else { return };
    if let Some(list) = t.list.take() {
        list.stop();
    }
    t.listed = true;
    for (h, identifier) in std::mem::take(&mut t.handles) {
        match t.wanted.remove(&identifier) {
            Some(w) => t.queue.push_back((h, w)),
            None => h.destroy(),
        }
    }
    pump(app);
}

/// Starts captures while fewer than AT_ONCE buffers are out; hands the set
/// to the overview when the take is through.
fn pump(app: &mut App) {
    let Some((sources, copy)) = app.shots.managers.clone() else { return };
    let qh = app.qh.clone();
    let Some(t) = app.shots.take.as_mut() else { return };
    while t.active.len() + t.making < AT_ONCE {
        let Some((handle, window)) = t.queue.pop_front() else { break };
        // A window closed since has an inert handle: wlroots stops its
        // session at once. No cursor, as grim without -c.
        let source = sources.create_source(&handle, &qh, ());
        let session = copy.create_session(&source, Options::empty(), &qh, Tag { take: t.serial, id: window.id });
        source.destroy();
        handle.destroy();
        t.active.push(Capture { window, session, size: (0, 0), format: None, frame: None });
    }
    if t.listed && t.queue.is_empty() && t.active.is_empty() && t.making == 0 {
        if let Some(t) = app.shots.take.take() {
            crate::overview::shots_taken(app, t.done);
        }
    }
}

/// A capture over without a picture: the window closed, the capture
/// failed, or its buffer could not be made (grim exited then).
fn end(app: &mut App, tag: Tag) {
    let Some(t) = take_of(app, tag.take) else { return };
    let Some(i) = t.active.iter().position(|c| c.window.id == tag.id) else { return };
    t.active.swap_remove(i).destroy();
    pump(app);
}

/// The session's constraints are in: a buffer of the size in the first
/// format the bar reads, attached to a frame, captured whole (grim's
/// session done, on the first `done` only).
fn capture(app: &mut App, tag: Tag) {
    let qh = app.qh.clone();
    let shm = app.shm.wl_shm().clone();
    let Some(t) = take_of(app, tag.take) else { return };
    let Some(c) = t.active.iter_mut().find(|c| c.window.id == tag.id) else { return };
    if c.frame.is_some() {
        return;
    }
    let made = c.format.and_then(|format| {
        let (w, h) = c.size;
        let stride = w.checked_mul(4)?;
        let len = i32::try_from(stride.checked_mul(h)?).ok().filter(|&l| l > 0)?;
        let fd = unsafe { libc::memfd_create(c"rust-bar-shot".as_ptr(), libc::MFD_CLOEXEC) };
        if fd < 0 {
            return None;
        }
        let file = unsafe { File::from_raw_fd(fd) };
        file.set_len(len as u64).ok()?;
        let map = unsafe { memmap2::MmapMut::map_mut(&file) }.ok()?;
        let pool = shm.create_pool(file.as_fd(), len, &qh, tag);
        let buffer = pool.create_buffer(0, w as i32, h as i32, stride as i32, format, &qh, tag);
        let frame = c.session.create_frame(&qh, tag);
        frame.attach_buffer(&buffer);
        frame.damage_buffer(0, 0, i32::MAX, i32::MAX);
        frame.capture();
        // Red, green and blue in a little-endian pixel of the format.
        let rgb = if matches!(format, wl_shm::Format::Argb8888 | wl_shm::Format::Xrgb8888) { [2, 1, 0] } else { [0, 1, 2] };
        Some((frame, Buffer { pool, buffer, map, rgb }))
    });
    match made {
        Some(f) => c.frame = Some(f),
        None => end(app, tag),
    }
}

/// The frame is copied: the buffer goes to the decode thread, which makes
/// the picture as the script did - grim's quarter size, magick's trim when
/// it came out bigger than the window - writes it for the next open, and
/// its mip levels come back.
fn ready(app: &mut App, tag: Tag) {
    let Some(t) = take_of(app, tag.take) else { return };
    let Some(i) = t.active.iter().position(|c| c.window.id == tag.id) else { return };
    let c = t.active.swap_remove(i);
    let (window, (w, h)) = (c.window, c.size);
    let Some(buf) = c.destroy() else { return pump(app) };
    t.making += 1;
    let (serial, path) = (tag.take, format!("{}/{}.ppm", crate::overview::shot_dir(), window.id));
    app.background(
        move || {
            let cap = pixels::Capture { data: &buf.map, width: w as usize, height: h as usize, stride: w as usize * 4, rgb: buf.rgb };
            let pic = pixels::quarter(&cap);
            drop(buf);
            let pic = pic.map(|(pw, ph, rgb)| {
                if pw as i64 > window.width / 4 + 2 || ph as i64 > window.height / 4 + 2 {
                    pixels::trim_black(pw, ph, rgb)
                } else {
                    (pw, ph, rgb)
                }
            });
            let levels = pic.map(|(pw, ph, rgb)| {
                let tmp = format!("{path}.new");
                if std::fs::write(&tmp, pixels::ppm(pw, ph, &rgb)).is_ok() {
                    let _ = std::fs::rename(&tmp, &path);
                }
                let rgba = rgb.chunks_exact(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect();
                crate::gpu::mip_levels(pw as u32, ph as u32, rgba, true)
            });
            (serial, window.id, levels)
        },
        |app, (serial, id, levels)| {
            let Some(t) = take_of(app, serial) else { return };
            t.making -= 1;
            if let Some(l) = levels {
                t.done.push((id, l));
            }
            pump(app);
        },
    );
    pump(app);
}

impl Dispatch<ExtForeignToplevelListV1, u32> for App {
    fn event(app: &mut App, list: &ExtForeignToplevelListV1, event: ext_foreign_toplevel_list_v1::Event, serial: &u32, _: &Connection, _: &QueueHandle<App>) {
        match event {
            ext_foreign_toplevel_list_v1::Event::Toplevel { toplevel } => match take_of(app, *serial) {
                Some(t) if t.list.is_some() => t.handles.push((toplevel, String::new())),
                _ => toplevel.destroy(),
            },
            ext_foreign_toplevel_list_v1::Event::Finished => list.destroy(),
            _ => {}
        }
    }

    event_created_child!(App, ExtForeignToplevelListV1, [
        ext_foreign_toplevel_list_v1::EVT_TOPLEVEL_OPCODE => (ExtForeignToplevelHandleV1, ()),
    ]);
}

impl Dispatch<ExtForeignToplevelHandleV1, ()> for App {
    fn event(app: &mut App, handle: &ExtForeignToplevelHandleV1, event: ext_foreign_toplevel_handle_v1::Event, _: &(), _: &Connection, _: &QueueHandle<App>) {
        if let ext_foreign_toplevel_handle_v1::Event::Identifier { identifier } = event {
            if let Some(h) = app.shots.take.as_mut().and_then(|t| t.handles.iter_mut().find(|(h, _)| *h == *handle)) {
                h.1 = identifier;
            }
        }
    }
}

impl Dispatch<WlCallback, Listed> for App {
    fn event(app: &mut App, _: &WlCallback, event: wl_callback::Event, data: &Listed, _: &Connection, _: &QueueHandle<App>) {
        if let wl_callback::Event::Done { .. } = event {
            listed(app, data.0);
        }
    }
}

impl Dispatch<ExtImageCopyCaptureSessionV1, Tag> for App {
    fn event(app: &mut App, _: &ExtImageCopyCaptureSessionV1, event: ext_image_copy_capture_session_v1::Event, tag: &Tag, _: &Connection, _: &QueueHandle<App>) {
        use ext_image_copy_capture_session_v1::Event;
        let c = app.shots.take.as_mut().filter(|t| t.serial == tag.take).and_then(|t| t.active.iter_mut().find(|c| c.window.id == tag.id));
        match (event, c) {
            (Event::BufferSize { width, height }, Some(c)) => c.size = (width, height),
            // The first format the bar reads, as grim takes the first it
            // reads (mango offers RGBx, then XRGB and ARGB).
            (Event::ShmFormat { format: WEnum::Value(f) }, Some(c)) => {
                if c.format.is_none() && matches!(f, wl_shm::Format::Argb8888 | wl_shm::Format::Xrgb8888 | wl_shm::Format::Abgr8888 | wl_shm::Format::Xbgr8888) {
                    c.format = Some(f);
                }
            }
            (Event::Done, _) => capture(app, *tag),
            (Event::Stopped, _) => end(app, *tag),
            _ => {}
        }
    }
}

impl Dispatch<ExtImageCopyCaptureFrameV1, Tag> for App {
    fn event(app: &mut App, _: &ExtImageCopyCaptureFrameV1, event: ext_image_copy_capture_frame_v1::Event, tag: &Tag, _: &Connection, _: &QueueHandle<App>) {
        match event {
            ext_image_copy_capture_frame_v1::Event::Ready => ready(app, *tag),
            ext_image_copy_capture_frame_v1::Event::Failed { .. } => end(app, *tag),
            _ => {}
        }
    }
}

impl Dispatch<ExtForeignToplevelImageCaptureSourceManagerV1, ()> for App {
    fn event(_: &mut App, _: &ExtForeignToplevelImageCaptureSourceManagerV1, _: <ExtForeignToplevelImageCaptureSourceManagerV1 as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<App>) {}
}

impl Dispatch<ExtImageCopyCaptureManagerV1, ()> for App {
    fn event(_: &mut App, _: &ExtImageCopyCaptureManagerV1, _: <ExtImageCopyCaptureManagerV1 as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<App>) {}
}

impl Dispatch<ExtImageCaptureSourceV1, ()> for App {
    fn event(_: &mut App, _: &ExtImageCaptureSourceV1, _: <ExtImageCaptureSourceV1 as Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<App>) {}
}

impl Dispatch<WlShmPool, Tag> for App {
    fn event(_: &mut App, _: &WlShmPool, _: <WlShmPool as Proxy>::Event, _: &Tag, _: &Connection, _: &QueueHandle<App>) {}
}

impl Dispatch<WlBuffer, Tag> for App {
    fn event(_: &mut App, _: &WlBuffer, _: <WlBuffer as Proxy>::Event, _: &Tag, _: &Connection, _: &QueueHandle<App>) {}
}
