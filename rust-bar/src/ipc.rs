//! The bar's IPC: what the keybinds call. `rust-bar msg <target> <function>
//! [args...]` sends one line to $XDG_RUNTIME_DIR/rust-bar.sock - the same
//! targets and functions as the QML bar's IpcHandlers (qs -c bar ipc call).

use std::io::{BufRead, BufReader, Read, Write};
use std::os::fd::{AsRawFd, IntoRawFd};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::time::{Duration, Instant};

use crate::app::App;

fn runtime_dir() -> String {
    std::env::var("XDG_RUNTIME_DIR").unwrap_or("/tmp".into())
}

pub fn socket_path() -> String {
    format!("{}/rust-bar.sock", runtime_dir())
}

/// One bar a session, decided before it connects to Wayland or starts a
/// helper: checked in listen(), after services::start, a second bar had
/// already run the weather fetch, vpn-reset.sh and the polkit registration,
/// and its exit killed them mid-run. A lock held for the bar's life lets only
/// one of two bars started at once through; a live bar answering on the
/// socket (one without the lock) also counts.
pub fn single_instance() {
    let lock = std::fs::OpenOptions::new().create(true).truncate(false).write(true).mode(0o600).open(format!("{}/rust-bar.lock", runtime_dir()));
    let mut taken = false;
    if let Ok(f) = lock {
        taken = unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 && std::io::Error::last_os_error().kind() == std::io::ErrorKind::WouldBlock;
        // Open for the bar's life: the exit closes it and drops the lock
        // (CLOEXEC keeps it out of the helpers).
        let _ = f.into_raw_fd();
    }
    // A stale socket file from a crash does not answer.
    if taken || UnixStream::connect(socket_path()).is_ok() {
        eprintln!("rust-bar: another bar is already running");
        std::process::exit(1);
    }
}

pub fn listen(app: &mut App) {
    let path = socket_path();
    let _ = std::fs::remove_file(&path);
    match UnixListener::bind(&path) {
        Ok(l) => app.listen_unix(l, on_conn),
        Err(e) => eprintln!("rust-bar: cannot listen on {path}: {e}"),
    }
}

/// The request line. The event loop waits while it is read, so the wait is
/// bounded - 200 ms in all and 4 KiB - for a client that connects and sends
/// nothing, trickles bytes or never ends its line.
fn read_request(c: &UnixStream) -> String {
    let deadline = Instant::now() + Duration::from_millis(200);
    let _ = c.set_nonblocking(false);
    let mut buf = Vec::new();
    let mut chunk = [0u8; 512];
    while buf.len() < 4096 && !buf.contains(&b'\n') {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() || c.set_read_timeout(Some(left)).is_err() {
            break;
        }
        match (&*c).read(&mut chunk) {
            Ok(0) | Err(_) => break,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
        }
    }
    let end = buf.iter().position(|&b| b == b'\n').unwrap_or(buf.len());
    String::from_utf8_lossy(&buf[..end]).into_owned()
}

fn on_conn(app: &mut App, c: UnixStream) {
    let line = read_request(&c);
    let words: Vec<&str> = line.split_whitespace().collect();
    let reply = if words.len() >= 2 { call(app, words[0], words[1], &words[2..]) } else { Err("usage: <target> <function> [args]".into()) };
    let mut c = c;
    let _ = match reply {
        Ok(()) => c.write_all(b"ok\n"),
        Err(e) => c.write_all(format!("error: {e}\n").as_bytes()),
    };
}

fn call(app: &mut App, target: &str, function: &str, args: &[&str]) -> Result<(), String> {
    match (target, function) {
        ("gamemode", "set") => {
            app.svc.mango.game_mode = args.first().map_or(false, |a| *a == "true");
            app.update_exclusive_zones();
            app.mark_all_dirty();
            Ok(())
        }
        ("cards", "toggle") => {
            cards_toggle(app, args.first().copied().unwrap_or(""));
            Ok(())
        }
        ("power", "toggle") => {
            crate::power::toggle(app);
            Ok(())
        }
        ("power", "exit") => {
            crate::power::open_on(app, "E");
            Ok(())
        }
        ("overview", f) => {
            match f {
                "toggle" => crate::overview::toggle(app),
                "open" => crate::overview::open(app),
                "close" => crate::overview::close(app),
                _ => return Err(format!("no function {f} on overview")),
            }
            Ok(())
        }
        ("wallpaper", f) => {
            match f {
                "toggle" => crate::wallpaper::toggle(app),
                "open" => crate::wallpaper::open(app),
                "close" => crate::wallpaper::close(app),
                "next" => crate::wallpaper::next(app, 1),
                "prev" => crate::wallpaper::next(app, -1),
                "nextFolder" => crate::wallpaper::folder(app, 1),
                "prevFolder" => crate::wallpaper::folder(app, -1),
                _ => return Err(format!("no function {f} on wallpaper")),
            }
            Ok(())
        }
        ("clipboard", "toggle") => {
            crate::clip::toggle(app);
            Ok(())
        }
        ("shot", "open") => {
            crate::capture::shot_open(app);
            Ok(())
        }
        ("record", "open") => {
            crate::capture::rec_open(app);
            Ok(())
        }
        ("record", "stop") => {
            crate::capture::rec_stop(app);
            Ok(())
        }
        ("layout", "next") => {
            layout_next(app);
            Ok(())
        }
        _ => Err(format!("no function {function} on target {target}")),
    }
}

/// BarCards.qml: SUPER+CTRL+<letter> opens a card on the focused monitor's
/// strip with its first control focused; the same shortcut closes it.
fn cards_toggle(app: &mut App, card: &str) {
    use crate::cards::CardKind;
    let kind = match card {
        "power" => CardKind::Power,
        "calendar" => CardKind::Calendar,
        "weather" => CardKind::Weather,
        "audio" => CardKind::Audio,
        // Bluetooth and the power profile live in the ПУЛЬТ card; both shortcuts open it.
        "bluetooth" | "profile" => CardKind::Pult,
        "vpn" => CardKind::Vpn,
        "agent" => CardKind::Agent,
        "network" => CardKind::Wifi,
        "battery" => CardKind::Battery,
        _ => return,
    };
    let action = crate::cards::icon_action(kind);
    // Each bar takes the request only when it names its screen (shell.qml:51-55):
    // with no strip on the focused monitor (no snapshot yet, an unknown name)
    // nothing opens.
    let focused = app.svc.mango.focused().map(|m| m.name.clone()).unwrap_or_default();
    let Some(strip) = app.strips.iter().position(|s| s.name == focused) else { return };
    let Some(hit) = app.strips[strip].hits.iter().find(|h| h.action == action).cloned() else { return };
    crate::cards::toggle(app, strip, kind, &hit, true);
}

/// LayoutState.cycle(): next keyboard layout (MRU order comes with the LayoutState port).
pub fn layout_next(app: &mut App) {
    crate::layout::switch_next(app);
}

/// The client side: one call, prints the reply, exit status 1 on error.
pub fn client(args: &[String]) -> i32 {
    let Ok(mut s) = UnixStream::connect(socket_path()) else {
        eprintln!("rust-bar: no bar running");
        return 1;
    };
    let _ = s.write_all(format!("{}\n", args.join(" ")).as_bytes());
    // A bar that hangs must not hang the caller: LayoutNext.sh falls back to
    // mango when this fails, which is what gets a password typed on the lock screen.
    let _ = s.set_read_timeout(Some(std::time::Duration::from_secs(2)));
    let mut reply = String::new();
    let _ = BufReader::new(&s).read_line(&mut reply);
    if reply.is_empty() {
        eprintln!("rust-bar: the bar did not answer");
        return 1;
    }
    if reply.starts_with("error") {
        eprint!("{reply}");
        1
    } else {
        0
    }
}
