//! The bar's runtime helpers on App: child processes (collected or
//! detached), timers, and fd/socket sources for the event loop.

use std::io::Read;
use std::os::fd::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use smithay_client_toolkit::reexports::calloop::{
    generic::Generic,
    timer::{TimeoutAction, Timer},
    Interest, Mode, PostAction, RegistrationToken,
};

use crate::app::{App, ProcDone};

/// A child's pipe for the event loop: the reader and its fd.
struct Stream(Box<dyn Read>, std::os::fd::RawFd);

impl AsRawFd for Stream {
    fn as_raw_fd(&self) -> std::os::fd::RawFd {
        self.1
    }
}

impl std::os::fd::AsFd for Stream {
    fn as_fd(&self) -> std::os::fd::BorrowedFd<'_> {
        unsafe { std::os::fd::BorrowedFd::borrow_raw(self.1) }
    }
}

impl App {
    /// Runs `argv` with its stdout collected; `done` gets it when the process ends.
    /// Children die with the bar (PR_SET_PDEATHSIG).
    pub fn spawn(&mut self, tag: &str, argv: &[&str], done: fn(&mut App, ProcDone)) {
        if self.running.contains_key(tag) {
            return;
        }
        let mut cmd = Command::new(argv[0]);
        cmd.args(&argv[1..]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
        unsafe {
            cmd.pre_exec(|| {
                // Its own process group, for kill().
                libc::setpgid(0, 0);
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let Ok(mut child) = cmd.spawn() else {
            done(self, ProcDone { stdout: String::new(), ok: false });
            return;
        };
        let stdout = child.stdout.take().unwrap();
        let fd = stdout.as_raw_fd();
        unsafe {
            let fl = libc::fcntl(fd, libc::F_GETFL);
            libc::fcntl(fd, libc::F_SETFL, fl | libc::O_NONBLOCK);
        }
        self.running.insert(tag.into(), (Instant::now(), child.id()));
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
                        done(app, ProcDone { stdout, ok });
                        return Ok(PostAction::Remove);
                    }
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => return Ok(PostAction::Continue),
                    Err(_) => return Ok(PostAction::Remove),
                }
            }
        });
    }

    /// Stops a helper: SIGTERM to a helper started under `tag`, and
    /// to the children it left in its process group. A helper counts as
    /// running until its stdout closes, and a grandchild holding that pipe
    /// (the keep-awake inhibitor's `sleep 5`) kept the tag for seconds after
    /// the helper died, so starting it again in that time did nothing;
    /// QProcess reports the exit as soon as its child is gone.
    pub fn kill(&mut self, tag: &str) {
        if let Some((_, pid)) = self.running.get(tag) {
            let pid = *pid as i32;
            unsafe {
                if libc::kill(-pid, libc::SIGTERM) != 0 {
                    libc::kill(pid, libc::SIGTERM);
                }
            }
        }
    }

    /// A long-running helper (nmcli monitor, dbus-monitor, systemd-inhibit):
    /// `on_line` for each line; kill(tag) stops it.
    pub fn spawn_lines(&mut self, argv: &[&str], on_line: fn(&mut App, &str)) {
        let tag = format!("lines:{}", argv.join(" "));
        self.spawn_lines_tagged(&tag, argv, on_line);
    }

    pub fn spawn_lines_tagged(&mut self, tag: &str, argv: &[&str], on_line: fn(&mut App, &str)) {
        self.spawn_stream(tag, argv, on_line, None, None);
    }

    /// A helper whose stdout (and stderr, if `on_err`) is handed over line by
    /// line, and an exit callback (`on_exit`, once both streams are closed
    /// and it is reaped).
    pub fn spawn_stream(&mut self, tag: &str, argv: &[&str], on_out: fn(&mut App, &str), on_err: Option<fn(&mut App, &str)>, on_exit: Option<fn(&mut App)>) {
        if self.running.contains_key(tag) {
            return;
        }
        let mut cmd = Command::new(argv[0]);
        let stderr = if on_err.is_some() { Stdio::piped() } else { Stdio::null() };
        cmd.args(&argv[1..]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(stderr);
        unsafe {
            cmd.pre_exec(|| {
                // Its own process group, for kill().
                libc::setpgid(0, 0);
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let Ok(mut child) = cmd.spawn() else {
            if let Some(f) = on_exit {
                f(self);
            }
            return;
        };
        self.running.insert(tag.into(), (Instant::now(), child.id()));
        let stdout = child.stdout.take().unwrap();
        let stderr = child.stderr.take();
        // The child is reaped when the last open stream closes.
        let state = std::rc::Rc::new(std::cell::RefCell::new((Some(child), 1 + stderr.is_some() as u8)));
        let mut streams: Vec<(Box<dyn Read>, std::os::fd::RawFd, fn(&mut App, &str))> = Vec::new();
        let fd = stdout.as_raw_fd();
        streams.push((Box::new(stdout), fd, on_out));
        if let (Some(e), Some(f)) = (stderr, on_err) {
            let fd = e.as_raw_fd();
            streams.push((Box::new(e), fd, f));
        }
        for (reader, fd, on_line) in streams {
            unsafe {
                let fl = libc::fcntl(fd, libc::F_GETFL);
                libc::fcntl(fd, libc::F_SETFL, fl | libc::O_NONBLOCK);
            }
            let tag = tag.to_string();
            let state = state.clone();
            let mut buf = Vec::new();
            let src = Generic::new(Stream(reader, fd), Interest::READ, Mode::Level);
            let _ = self.handle.insert_source(src, move |_, out, app: &mut App| {
                let mut chunk = [0u8; 4096];
                loop {
                    let r = unsafe { out.get_mut() }.0.read(&mut chunk);
                    if matches!(&r, Err(e) if e.kind() == std::io::ErrorKind::WouldBlock) {
                        return Ok(PostAction::Continue);
                    }
                    match r {
                        Ok(0) | Err(_) => {
                            let last = {
                                let mut st = state.borrow_mut();
                                st.1 -= 1;
                                if st.1 == 0 {
                                    if let Some(mut c) = st.0.take() {
                                        let _ = c.wait();
                                    }
                                    true
                                } else {
                                    false
                                }
                            };
                            if !buf.is_empty() {
                                let line = String::from_utf8_lossy(&buf).into_owned();
                                buf.clear();
                                on_line(app, &line);
                            }
                            if last {
                                app.running.remove(&tag);
                                if let Some(f) = on_exit {
                                    f(app);
                                }
                            }
                            return Ok(PostAction::Remove);
                        }
                        Ok(n) => {
                            buf.extend_from_slice(&chunk[..n]);
                            while let Some(p) = buf.iter().position(|&b| b == b'\n') {
                                let line: Vec<u8> = buf.drain(..=p).collect();
                                on_line(app, String::from_utf8_lossy(&line[..line.len() - 1]).as_ref());
                            }
                        }
                    }
                }
            });
        }
    }

    /// Watches a directory (inotify): `changed(app, name)` for each file in
    /// it that is written, created, moved in or removed.
    pub fn watch_dir(&mut self, dir: &str, changed: fn(&mut App, &str)) {
        let fd = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
        if fd < 0 {
            return;
        }
        let Ok(c) = std::ffi::CString::new(dir) else { return };
        let mask = libc::IN_CLOSE_WRITE | libc::IN_MOVED_TO | libc::IN_CREATE | libc::IN_DELETE;
        if unsafe { libc::inotify_add_watch(fd, c.as_ptr(), mask) } < 0 {
            unsafe { libc::close(fd) };
            return;
        }
        let file = unsafe { <std::fs::File as std::os::fd::FromRawFd>::from_raw_fd(fd) };
        let _ = self.handle.insert_source(Generic::new(file, Interest::READ, Mode::Level), move |_, f, app: &mut App| {
            let mut buf = [0u8; 4096];
            loop {
                match unsafe { f.get_mut() }.read(&mut buf) {
                    Ok(n) if n > 0 => {
                        let mut off = 0;
                        while off + 16 <= n {
                            let len = u32::from_ne_bytes([buf[off + 12], buf[off + 13], buf[off + 14], buf[off + 15]]) as usize;
                            let name = &buf[off + 16..(off + 16 + len).min(n)];
                            let name = String::from_utf8_lossy(name.split(|b| *b == 0).next().unwrap_or(&[])).into_owned();
                            changed(app, &name);
                            off += 16 + len;
                        }
                    }
                    _ => return Ok(PostAction::Continue),
                }
            }
        });
    }

    /// Calls `ready` whenever `fd` (owned elsewhere) is readable.
    pub fn watch_fd(&self, fd: std::os::fd::RawFd, ready: fn(&mut App)) -> Option<RegistrationToken> {
        let src = Generic::new(unsafe { smithay_client_toolkit::reexports::calloop::generic::FdWrapper::new(fd) }, Interest::READ, Mode::Level);
        self.handle
            .insert_source(src, move |_, _, app: &mut App| {
                ready(app);
                Ok(PostAction::Continue)
            })
            .ok()
    }

    /// Stops watching an fd (before it is closed).
    pub fn unwatch(&self, token: RegistrationToken) {
        self.handle.remove(token);
    }

    /// Restarts a one-shot timer by name: a debounce (Timer.restart()).
    pub fn debounce(&mut self, name: &'static str, delay: Duration, f: fn(&mut App)) {
        if let Some(t) = self.timers.remove(name) {
            self.handle.remove(t);
        }
        let tok = self.handle.insert_source(Timer::from_duration(delay), move |_, _, app: &mut App| {
            app.timers.remove(name);
            f(app);
            TimeoutAction::Drop
        });
        if let Ok(t) = tok {
            self.timers.insert(name, t);
        }
    }

    /// Image { asynchronous: true }: `work` runs on the decode thread and
    /// `done` gets its result back on the event loop.
    pub fn background<T: Send + 'static>(&self, work: impl FnOnce() -> T + Send + 'static, done: fn(&mut App, T)) {
        let tx = self.bg_tx.clone();
        let _ = self.bg_jobs.send(Box::new(move || {
            let v = work();
            let _ = tx.send(Box::new(move |app: &mut App| done(app, v)));
        }));
    }

    /// Timer.stop() for a debounce started under `name`.
    pub fn cancel_timer(&mut self, name: &str) {
        if let Some(t) = self.timers.remove(name) {
            self.handle.remove(t);
        }
    }

    pub fn is_running(&self, tag: &str) -> bool {
        self.running.contains_key(tag)
    }

    /// Fire and forget, in a session of its own.
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
            // Builder, not thread::spawn: that one panics - an abort here - when
            // the system cannot start a thread; then the child stays a zombie
            // until the bar exits instead.
            let _ = std::thread::Builder::new().spawn(move || {
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

    /// `tick` at the start of every minute of the wall clock (a minute starts
    /// at the same instant in every zone), and at once when the wall clock is
    /// set or the machine resumes: an absolute CLOCK_REALTIME timerfd, which
    /// the kernel cancels then (ECANCELED) and which is armed again. False
    /// when there is no timerfd.
    pub fn every_minute(&self, tick: fn(&mut App)) -> bool {
        let fd = unsafe { libc::timerfd_create(libc::CLOCK_REALTIME, libc::TFD_NONBLOCK | libc::TFD_CLOEXEC) };
        if fd < 0 {
            return false;
        }
        let file = unsafe { <std::fs::File as std::os::fd::FromRawFd>::from_raw_fd(fd) };
        if !arm_minute(fd) {
            return false;
        }
        self.handle
            .insert_source(Generic::new(file, Interest::READ, Mode::Level), move |_, _, app: &mut App| {
                let mut n = [0u8; 8];
                if unsafe { libc::read(fd, n.as_mut_ptr().cast(), n.len()) } < 0 {
                    if std::io::Error::last_os_error().raw_os_error() != Some(libc::ECANCELED) {
                        return Ok(PostAction::Continue);
                    }
                    arm_minute(fd);
                }
                tick(app);
                Ok(PostAction::Continue)
            })
            .is_ok()
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
}

/// The next whole minute of CLOCK_REALTIME, then every 60 s, cancelled when
/// the clock is set.
fn arm_minute(fd: std::os::fd::RawFd) -> bool {
    let mut now = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    unsafe { libc::clock_gettime(libc::CLOCK_REALTIME, &mut now) };
    let at = libc::itimerspec { it_interval: libc::timespec { tv_sec: 60, tv_nsec: 0 }, it_value: libc::timespec { tv_sec: (now.tv_sec / 60 + 1) * 60, tv_nsec: 0 } };
    unsafe { libc::timerfd_settime(fd, libc::TFD_TIMER_ABSTIME | libc::TFD_TIMER_CANCEL_ON_SET, &at, std::ptr::null_mut()) == 0 }
}

/// The thread every background() job runs on, in order - one, as Qt's
/// QQuickPixmapReader is one. A thread per image made glibc open an arena per
/// thread, and the decode buffers they had held stayed with the process: the
/// carousel, clipboard and overview opened three times each took the bar from
/// 54 to 165 MiB. Once the queue is empty the freed memory goes back.
pub fn decode_thread() -> std::sync::mpsc::Sender<Box<dyn FnOnce() + Send>> {
    let (tx, rx) = std::sync::mpsc::channel::<Box<dyn FnOnce() + Send>>();
    let _ = std::thread::Builder::new().name("decode".into()).spawn(move || loop {
        let job = match rx.try_recv() {
            Ok(job) => job,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => break,
            Err(std::sync::mpsc::TryRecvError::Empty) => {
                unsafe { libc::malloc_trim(0) };
                match rx.recv() {
                    Ok(job) => job,
                    Err(_) => break,
                }
            }
        };
        job();
    });
    tx
}
