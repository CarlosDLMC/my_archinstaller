//! The bar's IPC: what the keybinds call. `rust-bar msg <target> <function>
//! [args...]` sends one line to $XDG_RUNTIME_DIR/rust-bar.sock - the same
//! targets and functions as the QML bar's IpcHandlers (qs -c bar ipc call).

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};

use crate::app::App;

pub fn socket_path() -> String {
    format!("{}/rust-bar.sock", std::env::var("XDG_RUNTIME_DIR").unwrap_or("/tmp".into()))
}

pub fn listen(app: &mut App) {
    let path = socket_path();
    // A live bar answers; a stale socket file from a crash does not.
    if UnixStream::connect(&path).is_ok() {
        eprintln!("rust-bar: another bar is already running");
        std::process::exit(1);
    }
    let _ = std::fs::remove_file(&path);
    match UnixListener::bind(&path) {
        Ok(l) => app.listen_unix(l, on_conn),
        Err(e) => eprintln!("rust-bar: cannot listen on {path}: {e}"),
    }
}

fn on_conn(app: &mut App, c: UnixStream) {
    let _ = c.set_nonblocking(false);
    let _ = c.set_read_timeout(Some(std::time::Duration::from_millis(200)));
    let mut line = String::new();
    let _ = BufReader::new(&c).read_line(&mut line);
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
        ("layout", "next") => {
            layout_next(app);
            Ok(())
        }
        _ => Err(format!("no function {function} on target {target}")),
    }
}

/// LayoutState.cycle(): next keyboard layout (MRU order comes with the LayoutState port).
pub fn layout_next(app: &mut App) {
    app.exec_detached(&["mmsg", "dispatch", "switch_keyboard_layout"]);
}

/// The client side: one call, prints the reply, exit status 1 on error.
pub fn client(args: &[String]) -> i32 {
    let Ok(mut s) = UnixStream::connect(socket_path()) else {
        eprintln!("rust-bar: no bar running");
        return 1;
    };
    let _ = s.write_all(format!("{}\n", args.join(" ")).as_bytes());
    let mut reply = String::new();
    let _ = BufReader::new(&s).read_line(&mut reply);
    if reply.starts_with("error") {
        eprint!("{reply}");
        1
    } else {
        0
    }
}
