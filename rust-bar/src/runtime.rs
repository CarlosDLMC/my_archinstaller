//! The bar's runtime helpers on App: child processes (QML's Process /
//! execDetached), timers (Timer), and fd/socket sources for the event loop.

use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use smithay_client_toolkit::reexports::calloop::{
    generic::Generic,
    timer::{TimeoutAction, Timer},
    Interest, Mode, PostAction,
};

use crate::app::{App, ProcDone};

impl App {
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

    /// Process.running = false: SIGTERM to a helper started under `tag`.
    pub fn kill(&mut self, tag: &str) {
        if let Some((_, pid)) = self.running.get(tag) {
            unsafe { libc::kill(*pid as i32, libc::SIGTERM) };
        }
    }

    /// A long-running helper (nmcli monitor, dbus-monitor, systemd-inhibit):
    /// `on_line` for each line; kill(tag) stops it.
    pub fn spawn_lines(&mut self, argv: &[&str], on_line: fn(&mut App, &str)) {
        let tag = format!("lines:{}", argv.join(" "));
        self.spawn_lines_tagged(&tag, argv, on_line);
    }

    pub fn spawn_lines_tagged(&mut self, tag: &str, argv: &[&str], on_line: fn(&mut App, &str)) {
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
        let Ok(mut child) = cmd.spawn() else { return };
        let stdout = child.stdout.take().unwrap();
        let fd = stdout.as_raw_fd();
        unsafe {
            let fl = libc::fcntl(fd, libc::F_GETFL);
            libc::fcntl(fd, libc::F_SETFL, fl | libc::O_NONBLOCK);
        }
        self.running.insert(tag.into(), (Instant::now(), child.id()));
        let tag = tag.to_string();
        let mut buf = Vec::new();
        let mut child = Some(child);
        let _ = self.handle.insert_source(Generic::new(stdout, Interest::READ, Mode::Level), move |_, out, app: &mut App| {
            let mut chunk = [0u8; 4096];
            loop {
                match unsafe { out.get_mut() }.read(&mut chunk) {
                    Ok(0) => {
                        if let Some(mut c) = child.take() {
                            let _ = c.wait();
                        }
                        app.running.remove(&tag);
                        return Ok(PostAction::Remove);
                    }
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

    /// Calls `ready` whenever `fd` (owned elsewhere) is readable.
    pub fn watch_fd(&self, fd: std::os::fd::RawFd, ready: fn(&mut App)) {
        let src = Generic::new(unsafe { smithay_client_toolkit::reexports::calloop::generic::FdWrapper::new(fd) }, Interest::READ, Mode::Level);
        let _ = self.handle.insert_source(src, move |_, _, app: &mut App| {
            ready(app);
            Ok(PostAction::Continue)
        });
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

    pub fn is_running(&self, tag: &str) -> bool {
        self.running.contains_key(tag)
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
}

pub fn write_line(mut s: &UnixStream, line: &str) {
    let _ = s.write_all(line.as_bytes());
}

