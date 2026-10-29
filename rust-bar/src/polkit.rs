//! PolkitState + PolkitOsd, and the agent quickshell's PolkitAgent was: the
//! bar registers as the session's polkit authentication agent on the system
//! bus, queues BeginAuthentication requests, runs each through polkit's
//! helper (the socket-activated polkit-agent-helper-1, as libpolkit-agent-1
//! does) and asks for the password in its own dialog.

use std::collections::{HashMap, VecDeque};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;
use std::time::Duration;

use dbus::arg::{PropMap, RefArg, Variant};
use dbus::channel::{BusType, Channel};
use dbus::message::{Message, MessageType};
use smithay_client_toolkit::reexports::calloop::RegistrationToken;

use crate::app::App;
use crate::bar::{ac, Action, Hit};
use crate::cards::{lamp_tinted, Ui, UiState};
use crate::color::Color;
use crate::gpu::TextStyle;
use crate::osd::{self, OpenParams, OsdKind};
use crate::services::Services;
use crate::text::FontKey;
use crate::theme;

const AGENT_PATH: &str = "/org/rustbar/PolkitAgent";
const AUTHORITY: &str = "org.freedesktop.PolicyKit1";
const HELPER_SOCKET: &str = "/run/polkit/agent-helper.socket";
const FADE_MS: u64 = 160;
const UI: f32 = 1.35;

fn px(v: f32) -> f32 {
    (v * UI).round()
}

/// A BeginAuthentication call, answered when its flow ends.
struct Request {
    action_id: String,
    message: String,
    cookie: String,
    uids: Vec<u32>,
    call: Message,
}

/// One PAM conversation with the helper.
struct Session {
    stream: UnixStream,
    token: Option<RegistrationToken>,
    buf: Vec<u8>,
}

/// AuthFlow: the active request and what the helper last asked.
pub struct Flow {
    req: Request,
    user: String,
    session: Option<Session>,
    pub response_required: bool,
    pub input_prompt: String,
    pub response_visible: bool,
    pub supplementary: String,
    pub supplementary_is_error: bool,
    cancelled: bool,
}

#[derive(Default)]
pub struct Polkit {
    chan: Option<Channel>,
    pub registered: bool,
    /// A registration sent after polkitd came back, until it is answered.
    register_serial: Option<u32>,
    queue: VecDeque<Request>,
    pub flow: Option<Flow>,
    /// PolkitState.error / checking, and the password field.
    pub error: String,
    pub checking: bool,
    pub field: String,
    /// When the cursor's blink last restarted (focus, a key).
    blink_since: Option<std::time::Instant>,
}

fn session_id() -> Option<String> {
    if let Ok(id) = std::env::var("XDG_SESSION_ID") {
        if !id.is_empty() {
            return Some(id);
        }
    }
    // A process inside a logind session sits in its session-N.scope.
    let cg = std::fs::read_to_string("/proc/self/cgroup").ok()?;
    cg.split('/').find_map(|p| p.strip_prefix("session-").and_then(|s| s.strip_suffix(".scope")).map(|s| s.trim().to_string()))
}

fn user_name(uid: u32) -> Option<String> {
    let mut pw: libc::passwd = unsafe { std::mem::zeroed() };
    let mut buf = vec![0 as libc::c_char; 4096];
    let mut out: *mut libc::passwd = std::ptr::null_mut();
    let rc = unsafe { libc::getpwuid_r(uid, &mut pw, buf.as_mut_ptr(), buf.len(), &mut out) };
    if rc != 0 || out.is_null() {
        return None;
    }
    Some(unsafe { std::ffi::CStr::from_ptr(pw.pw_name) }.to_string_lossy().into_owned())
}

/// Registers with polkitd for this session (RegisterAuthenticationAgent).
/// RUST_BAR_POLKIT_DEMO=1 shows a made-up request instead (the parity test).
pub fn start(app: &mut App) {
    if std::env::var("RUST_BAR_POLKIT_DEMO").is_ok() {
        let Ok(call) = Message::new_method_call("org.example", "/", "org.example", "Demo") else { return };
        let req = Request { action_id: "org.freedesktop.policykit.exec".into(), message: "Authentication is needed to run `/usr/bin/true' as the super user".into(), cookie: "demo".into(), uids: vec![0], call };
        let p = &mut app.svc.polkit;
        p.flow = Some(Flow { req, user: "root".into(), session: None, response_required: true, input_prompt: "Password: ".into(), response_visible: false, supplementary: String::new(), supplementary_is_error: false, cancelled: false });
        app.after(Duration::from_millis(500), show_osd);
        return;
    }
    let Ok(mut ch) = Channel::get_private(BusType::System) else { return };
    let Some(msg) = register_msg() else { return };
    match ch.send_with_reply_and_block(msg, Duration::from_secs(5)) {
        Ok(_) => app.svc.polkit.registered = true,
        Err(e) => {
            eprintln!("rust-bar: polkit agent not registered: {}", e.message().unwrap_or(""));
            return;
        }
    }
    // A restarted polkitd has forgotten its agents; libpolkit-agent registers
    // again when the name has an owner again (on_notify_authority_owner).
    if let Ok(m) = Message::new_method_call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch") {
        let _ = ch.send(m.append1(format!("type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='{AUTHORITY}'")));
        ch.flush();
    }
    ch.set_watch_enabled(true);
    let fd = ch.watch().fd;
    app.svc.polkit.chan = Some(ch);
    app.watch_fd(fd, dbus_ready);
}

/// RegisterAuthenticationAgent for this session, in the locale polkitd
/// translates its messages to - libpolkit-agent's: the first of LC_ALL,
/// LC_MESSAGES and LANG that is set and not empty.
fn register_msg() -> Option<Message> {
    let sid = session_id()?;
    let mut details: PropMap = HashMap::new();
    details.insert("session-id".into(), Variant(Box::new(sid) as Box<dyn RefArg>));
    let subject = ("unix-session".to_string(), details);
    let locale = ["LC_ALL", "LC_MESSAGES", "LANG"].iter().find_map(|v| std::env::var(v).ok().filter(|l| !l.is_empty())).unwrap_or_else(|| "en_US.UTF-8".into());
    let msg = Message::new_method_call(AUTHORITY, "/org/freedesktop/PolicyKit1/Authority", "org.freedesktop.PolicyKit1.Authority", "RegisterAuthenticationAgent").ok()?;
    Some(msg.append3(subject, locale, AGENT_PATH))
}

/// polkitd left the bus or came back: back, it has no agents, so register
/// again.
fn owner_changed(app: &mut App, m: &Message) {
    if m.member().as_deref() != Some("NameOwnerChanged") {
        return;
    }
    let Ok((name, _, owner)) = m.read3::<&str, &str, &str>() else { return };
    if name != AUTHORITY {
        return;
    }
    let p = &mut app.svc.polkit;
    if owner.is_empty() {
        p.registered = false;
        return;
    }
    if p.registered || p.register_serial.is_some() {
        return;
    }
    let Some(msg) = register_msg() else { return };
    if let Some(ch) = p.chan.as_ref() {
        p.register_serial = ch.send(msg).ok();
        ch.flush();
    }
}

/// The answer to that registration.
fn registered_again(app: &mut App, m: &Message) {
    let p = &mut app.svc.polkit;
    if p.register_serial.is_none() || m.get_reply_serial() != p.register_serial {
        return;
    }
    p.register_serial = None;
    if m.msg_type() == MessageType::Error {
        eprintln!("rust-bar: polkit agent not registered again: {}", m.read1::<&str>().unwrap_or(""));
    } else {
        p.registered = true;
    }
}

fn send(app: &mut App, msg: Message) {
    if let Some(ch) = app.svc.polkit.chan.as_ref() {
        let _ = ch.send(msg);
        ch.flush();
    }
}

/// The system bus has data: polkitd's calls to the agent.
fn dbus_ready(app: &mut App) {
    let mut calls = Vec::new();
    if let Some(ch) = app.svc.polkit.chan.as_mut() {
        let _ = ch.read_write(Some(Duration::ZERO));
        while let Some(m) = ch.pop_message() {
            calls.push(m);
        }
    }
    for m in calls {
        match m.msg_type() {
            MessageType::MethodCall => {}
            MessageType::Signal => {
                owner_changed(app, &m);
                continue;
            }
            _ => {
                registered_again(app, &m);
                continue;
            }
        }
        let member = m.member().map(|s| s.to_string()).unwrap_or_default();
        match member.as_str() {
            "BeginAuthentication" => begin(app, m),
            "CancelAuthentication" => {
                let cookie: String = m.read1().unwrap_or_default();
                let reply = m.method_return();
                send(app, reply);
                cancel_from_agent(app, &cookie);
            }
            _ => {
                let err = m.error(&"org.freedesktop.DBus.Error.UnknownMethod".into(), &std::ffi::CString::new("Unknown method").unwrap());
                send(app, err);
            }
        }
    }
}

/// initiateAuthentication(): queue it; start it if nothing else runs.
fn begin(app: &mut App, call: Message) {
    type Args = (String, String, String, HashMap<String, String>, String, Vec<(String, PropMap)>);
    let Ok((action_id, message, _icon, _details, cookie, identities)) = call.read_all::<Args>() else {
        let err = call.error(&"org.freedesktop.PolicyKit1.Error.Failed".into(), &std::ffi::CString::new("Bad arguments").unwrap());
        send(app, err);
        return;
    };
    let uids = identities
        .iter()
        .filter(|(kind, _)| kind == "unix-user")
        .filter_map(|(_, d)| d.get("uid").and_then(|v| v.0.as_u64()).map(|u| u as u32))
        .collect();
    app.svc.polkit.queue.push_back(Request { action_id, message, cookie, uids, call });
    if app.svc.polkit.flow.is_none() {
        activate(app);
    }
}

/// activateAuthenticationRequest(): the next queued request becomes the flow.
fn activate(app: &mut App) {
    while let Some(req) = app.svc.polkit.queue.pop_front() {
        let Some(user) = req.uids.first().and_then(|&u| user_name(u)) else {
            let err = req.call.error(&"org.freedesktop.PolicyKit1.Error.Failed".into(), &std::ffi::CString::new("Error requesting authentication: no supported identities available.").unwrap());
            send(app, err);
            continue;
        };
        let p = &mut app.svc.polkit;
        p.flow = Some(Flow { req, user, session: None, response_required: false, input_prompt: String::new(), response_visible: false, supplementary: String::new(), supplementary_is_error: false, cancelled: false });
        p.error.clear();
        p.checking = false;
        p.field.clear();
        setup_session(app);
        // A helper that cannot be reached ends the request at once (and may
        // have started the next one, which showed itself).
        if app.svc.polkit.flow.is_some() {
            show_osd(app);
        }
        return;
    }
}

/// setupSession(): a fresh conversation with the helper.
fn setup_session(app: &mut App) {
    close_session(app);
    let Some(f) = app.svc.polkit.flow.as_ref() else { return };
    let (user, cookie) = (f.user.clone(), f.req.cookie.clone());
    let mut stream = match UnixStream::connect(HELPER_SOCKET) {
        Ok(s) => s,
        Err(e) => {
            // libpolkit-agent would spawn the setuid helper instead, but polkit
            // 128 installs it without the setuid bit. Treating this as a failed
            // attempt (completed(false)) started a new session at once, which
            // failed the same way: the recursion overflowed the stack and took
            // the bar down. The request ends with an error, so polkitd is not
            // left waiting for it.
            eprintln!("rust-bar: polkit: cannot reach {HELPER_SOCKET}: {e}");
            if let Some(f) = app.svc.polkit.flow.as_ref() {
                let err = f.req.call.error(&"org.freedesktop.PolicyKit1.Error.Failed".into(), &std::ffi::CString::new("Cannot reach polkit-agent-helper-1").unwrap());
                send(app, err);
            }
            finish(app);
            return;
        }
    };
    let _ = stream.write_all(format!("{user}\n{cookie}\n").as_bytes());
    let _ = stream.set_nonblocking(true);
    let token = app.watch_fd(stream.as_raw_fd(), helper_ready);
    if let Some(f) = app.svc.polkit.flow.as_mut() {
        f.session = Some(Session { stream, token, buf: Vec::new() });
    }
}

fn close_session(app: &mut App) {
    let Some(s) = app.svc.polkit.flow.as_mut().and_then(|f| f.session.take()) else { return };
    if let Some(t) = s.token {
        app.unwatch(t);
    }
}

/// g_strcompress: the helper escapes its lines like C strings (g_strescape),
/// every byte outside printable ASCII as \ooo - the escapes are bytes, and a
/// localized PAM prompt is UTF-8 again only once they are put back together.
/// The result is a C string: a \000 ends it.
fn unescape(s: &[u8]) -> String {
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        let c = s[i];
        i += 1;
        if c != b'\\' {
            out.push(c);
            continue;
        }
        // A trailing backslash ends the string.
        let Some(&e) = s.get(i) else { break };
        i += 1;
        match e {
            b'0'..=b'7' => {
                let mut v = e - b'0';
                for _ in 0..2 {
                    match s.get(i) {
                        Some(&d @ b'0'..=b'7') => {
                            v = v.wrapping_mul(8).wrapping_add(d - b'0');
                            i += 1;
                        }
                        _ => break,
                    }
                }
                out.push(v);
            }
            b'b' => out.push(0x08),
            b'f' => out.push(0x0c),
            b'n' => out.push(b'\n'),
            b'r' => out.push(b'\r'),
            b't' => out.push(b'\t'),
            b'v' => out.push(0x0b),
            // \" and \\ too.
            o => out.push(o),
        }
    }
    if let Some(n) = out.iter().position(|&b| b == 0) {
        out.truncate(n);
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// io_watch_have_data(): the helper's lines.
fn helper_ready(app: &mut App) {
    let mut lines = Vec::new();
    let mut eof = false;
    if let Some(s) = app.svc.polkit.flow.as_mut().and_then(|f| f.session.as_mut()) {
        let mut chunk = [0u8; 1024];
        loop {
            match s.stream.read(&mut chunk) {
                Ok(0) => {
                    eof = true;
                    break;
                }
                Ok(n) => s.buf.extend_from_slice(&chunk[..n]),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                Err(_) => {
                    eof = true;
                    break;
                }
            }
        }
        while let Some(p) = s.buf.iter().position(|&b| b == b'\n') {
            let l: Vec<u8> = s.buf.drain(..=p).collect();
            lines.push(unescape(&l[..l.len() - 1]));
        }
    } else {
        return;
    }
    for l in lines {
        if let Some(m) = l.strip_prefix("PAM_PROMPT_ECHO_OFF ") {
            request(app, m, false);
        } else if let Some(m) = l.strip_prefix("PAM_PROMPT_ECHO_ON ") {
            request(app, m, true);
        } else if let Some(m) = l.strip_prefix("PAM_ERROR_MSG ") {
            supplementary(app, m, true);
        } else if let Some(m) = l.strip_prefix("PAM_TEXT_INFO ") {
            supplementary(app, m, false);
        } else if l.starts_with("SUCCESS") {
            completed(app, true);
            return;
        } else {
            completed(app, false);
            return;
        }
    }
    if eof {
        completed(app, false);
    }
}

/// The field's `enabled` (PolkitOsd.qml:168): it has the keyboard focus then.
fn enabled(p: &Polkit) -> bool {
    p.flow.as_ref().map_or(false, |f| f.response_required) && !p.checking
}

fn request(app: &mut App, prompt: &str, echo: bool) {
    let p = &mut app.svc.polkit;
    let was = enabled(p);
    if let Some(f) = p.flow.as_mut() {
        f.response_required = true;
        f.input_prompt = prompt.into();
        f.response_visible = echo;
        // onIsResponseRequiredChanged: a prompt ends the checking state.
        p.checking = false;
    }
    // Enabled again, the field gets the focus back: focusInEvent shows the
    // cursor and starts its blink over (QQuickTextInputPrivate::
    // handleFocusEvent -> updateCursorBlinking).
    if !was && enabled(&app.svc.polkit) {
        restart_blink(app);
    }
    redraw(app);
}

fn supplementary(app: &mut App, msg: &str, is_error: bool) {
    if let Some(f) = app.svc.polkit.flow.as_mut() {
        f.supplementary = msg.into();
        f.supplementary_is_error = is_error;
    }
    redraw(app);
}

/// AuthFlow::completed(): success answers polkitd; a cancel just ends; a
/// failure says so and starts a new conversation.
fn completed(app: &mut App, gained: bool) {
    close_session(app);
    let Some(f) = app.svc.polkit.flow.as_ref() else { return };
    if gained {
        let reply = f.req.call.method_return();
        send(app, reply);
        app.svc.polkit.error.clear();
        app.svc.polkit.checking = false;
        finish(app);
    } else if f.cancelled {
        finish(app);
    } else {
        app.svc.polkit.error = "Неверный пароль - попробуйте ещё раз".into();
        app.svc.polkit.checking = false;
        setup_session(app);
        redraw(app);
    }
}

/// finishAuthenticationRequest(): the dialog goes, the next one comes.
fn finish(app: &mut App) {
    app.svc.polkit.flow = None;
    app.svc.polkit.field.clear();
    // PolkitState.onFlowChanged.
    app.svc.polkit.error.clear();
    app.svc.polkit.checking = false;
    osd::hide(app, OsdKind::Polkit);
    if !app.svc.polkit.queue.is_empty() {
        activate(app);
    }
}

fn reply_cancelled(app: &mut App, text: &str) {
    if let Some(f) = app.svc.polkit.flow.as_ref() {
        let err = f.req.call.error(&"org.freedesktop.PolicyKit1.Error.Cancelled".into(), &std::ffi::CString::new(text).unwrap());
        send(app, err);
    }
}

/// cancelAuthenticationRequest(): Esc.
pub fn cancel(app: &mut App) {
    let Some(f) = app.svc.polkit.flow.as_mut() else { return };
    f.cancelled = true;
    reply_cancelled(app, "Authentication request cancelled by user.");
    close_session(app);
    completed(app, false);
}

/// CancelAuthentication from polkitd (the caller went away).
fn cancel_from_agent(app: &mut App, cookie: &str) {
    if app.svc.polkit.flow.as_ref().map_or(false, |f| f.req.cookie == cookie) {
        app.svc.polkit.flow.as_mut().unwrap().cancelled = true;
        app.svc.polkit.error.clear();
        app.svc.polkit.checking = false;
        reply_cancelled(app, "Authentication request cancelled by agent.");
        close_session(app);
        completed(app, false);
    } else if let Some(i) = app.svc.polkit.queue.iter().position(|r| r.cookie == cookie) {
        let r = app.svc.polkit.queue.remove(i).unwrap();
        let err = r.call.error(&"org.freedesktop.PolicyKit1.Error.Cancelled".into(), &std::ffi::CString::new("Authentication request was cancelled").unwrap());
        send(app, err);
    }
}

/// accept(): the field's text goes to the helper.
fn submit(app: &mut App) {
    let text = std::mem::take(&mut app.svc.polkit.field);
    let p = &mut app.svc.polkit;
    let Some(f) = p.flow.as_mut() else { return };
    if !f.response_required {
        return;
    }
    p.error.clear();
    p.checking = true;
    if let Some(s) = f.session.as_mut() {
        let _ = s.stream.write_all(format!("{text}\n").as_bytes());
    }
    f.response_required = false;
    f.input_prompt.clear();
    f.response_visible = false;
    redraw(app);
}

fn redraw(app: &mut App) {
    if let Some(o) = app.osd_mut(OsdKind::Polkit) {
        o.win.dirty = true;
    }
    reshow(app);
}

// ---- the dialog ----

struct M {
    card_w: f32,
    pad: f32,
    gap: f32,
    radius: f32,
    title: f32,
    body: f32,
    small: f32,
    field_h: f32,
}

fn met() -> M {
    M { card_w: px(560.0), pad: px(22.0), gap: px(12.0), radius: px(12.0), title: px(14.0), body: px(13.0), small: px(11.0), field_h: px(40.0) }
}

const CONTENT: FontKey = FontKey { family: theme::FONT_CONTENT, bold: false, plain: false };
const FIELD: FontKey = FontKey { family: theme::FONT_CONTENT, bold: false, plain: true };

/// What the dialog shows of the flow. Once PolkitState.flow is null - the
/// card fading out after its request ended - QML's bindings read "" and
/// false: no message, no action id, the field disabled with «Пароль».
struct View<'a> {
    message: &'a str,
    action_id: &'a str,
    prompt: &'a str,
    response_required: bool,
    response_visible: bool,
}

fn view(p: &Polkit) -> View<'_> {
    match p.flow.as_ref() {
        Some(f) => View { message: &f.req.message, action_id: &f.req.action_id, prompt: &f.input_prompt, response_required: f.response_required, response_visible: f.response_visible },
        None => View { message: "", action_id: "", prompt: "", response_required: false, response_visible: false },
    }
}

/// The Column's blocks: (height, what).
fn blocks(fonts: &mut crate::text::Fonts, svc: &Services) -> Vec<f32> {
    let m = met();
    let p = &svc.polkit;
    let f = view(p);
    let cw = m.card_w - 2.0 * m.pad;
    let cap = fonts.layout("ТРЕБУЕТСЯ ПАРОЛЬ", theme::bar_font(true), m.title, 1.0);
    let mut v = vec![cap.height().max(10.0)];
    let iw = cw - 2.0 * m.gap;
    let msg: f32 = fonts.wrap(f.message, CONTENT, m.body, 0.0, iw).iter().map(|l| l.height()).sum();
    let mut plate = msg;
    if !f.action_id.is_empty() {
        plate += (m.gap * 0.5).round() + fonts.layout(f.action_id, CONTENT, m.small, 0.0).height();
    }
    v.push(plate + 2.0 * m.gap);
    v.push(m.field_h);
    let note = note(p);
    if !note.0.is_empty() {
        v.push(fonts.wrap(&note.0, CONTENT, m.small, 0.0, cw).iter().map(|l| l.height()).sum());
    }
    v.push(keycaps_h(fonts, m.small));
    v
}

fn note(p: &Polkit) -> (String, bool) {
    if !p.error.is_empty() {
        return (p.error.clone(), true);
    }
    match p.flow.as_ref() {
        Some(f) => (f.supplementary.clone(), f.supplementary_is_error),
        None => (String::new(), false),
    }
}

fn keycaps_h(fonts: &mut crate::text::Fonts, size: f32) -> f32 {
    let k = fonts.layout("ESC", theme::bar_font(true), size, 0.0);
    let l = fonts.layout("ОТМЕНА", theme::bar_font(true), size, 1.0);
    (k.height() + 4.0).max(l.height())
}

fn card_h(fonts: &mut crate::text::Fonts, svc: &Services) -> f32 {
    let m = met();
    let b = blocks(fonts, svc);
    b.iter().sum::<f32>() + m.gap * (b.len().saturating_sub(1)) as f32 + 2.0 * m.pad
}

fn show_osd(app: &mut App) {
    map_osd(app);
    app.svc.polkit.blink_since = Some(std::time::Instant::now());
    blink(app);
}

/// The dialog on the focused screen.
fn map_osd(app: &mut App) {
    let Some((_, sw, sh)) = osd::focused_output(app) else { return };
    let m = met();
    let h = card_h(&mut app.fonts, &app.svc);
    osd::show(app, OpenParams { kind: OsdKind::Polkit, size: (m.card_w as u32, h.ceil() as u32), panel: (0.0, 0.0, m.card_w, h), dim: Some(Color::qt_rgba(0.0, 0.0, 0.0, 0.45)), keyboard: true, namespace: "quickshell", fade_ms: FADE_MS, min_scale: 0.96, fade_easing: crate::anim::Easing::OutCubic, pos: Some((ac(sw, m.card_w) as i32, ac(sh, h) as i32)), fill: false, output: None });
    // A dialog still up (the next queued request follows the last at once)
    // keeps its old size in osd::show: the card's height is this request's.
    reshow(app);
}

/// The card's height follows its texts (the error line comes and goes).
fn reshow(app: &mut App) {
    if app.svc.polkit.flow.is_none() || app.osd(OsdKind::Polkit).map_or(true, |o| !o.shown) {
        return;
    }
    let m = met();
    let h = card_h(&mut app.fonts, &app.svc);
    let Some(o) = app.osd_mut(OsdKind::Polkit) else { return };
    if (o.panel.3 - h).abs() >= 0.5 {
        use smithay_client_toolkit::shell::WaylandSurface;
        o.panel.3 = h;
        o.win.height = h.ceil() as u32;
        o.win.layer.set_size(m.card_w as u32, h.ceil() as u32);
        // anchors.centerIn on the dialog's own screen (not the focused one,
        // which may have changed since it opened).
        let (sw, sh) = o.screen;
        o.win.layer.set_margin(ac(sh, h) as i32, 0, 0, ac(sw, m.card_w) as i32);
        o.win.layer.commit();
    }
}

/// TextInput's cursor blink: a redraw at each 500 ms flip while the field has focus.
fn blink(app: &mut App) {
    if app.svc.polkit.flow.is_none() {
        return;
    }
    // mango closes the layer surfaces of a screen that goes away, and a
    // request can come while there is no screen at all. PolkitOsd is a window
    // per screen, shown on the focused one, so QML shows the dialog again
    // there; without it here the flow would wait for a dialog nobody sees,
    // polkitd with it, and every later request behind it.
    if app.osd(OsdKind::Polkit).is_none() {
        map_osd(app);
    }
    if let Some(o) = app.osd_mut(OsdKind::Polkit) {
        o.win.dirty = true;
    }
    let since = app.svc.polkit.blink_since.get_or_insert_with(std::time::Instant::now).elapsed().as_millis() as u64;
    app.debounce("polkit-blink", Duration::from_millis(500 - since % 500), blink);
}

/// Typing shows the cursor and restarts its blink.
fn restart_blink(app: &mut App) {
    app.svc.polkit.blink_since = Some(std::time::Instant::now());
    blink(app);
}

pub fn draw_osd<S: UiState>(ui: &mut Ui<S>, panel: (f32, f32, f32, f32), svc: &Services) {
    let m = met();
    let t = ui.theme;
    let p = &svc.polkit;
    let (x0, mut y0, w, mut h) = panel;
    if p.flow.is_none() {
        // Fading out after its request: the card is QML's without a flow,
        // smaller, still centred (anchors.centerIn) - the surface keeps its
        // size until it goes.
        let ch = card_h(ui.fonts, svc);
        if ch < h {
            y0 += ac(h, ch);
            h = ch;
        }
    }
    ui.scene.rect(x0, y0, w, h, t.col_bg, m.radius, 0.0, Color::TRANSPARENT, true);
    let f = view(p);
    let (cx, cw) = (x0 + m.pad, w - 2.0 * m.pad);
    let mut y = y0 + m.pad;

    let cap = ui.fonts.layout("ТРЕБУЕТСЯ ПАРОЛЬ", theme::bar_font(true), m.title, 1.0);
    let rh = cap.height().max(10.0);
    lamp_tinted(ui, 0x7000, cx, y + ac(rh, 10.0), true, t.col_alert);
    ui.text(&cap, cx + 22.0, y + ac(rh, cap.height()), t.col_dim, TextStyle::Normal);
    y += rh + m.gap;

    // The plate: polkit's message and the action id.
    let iw = cw - 2.0 * m.gap;
    let lines = ui.fonts.wrap(f.message, CONTENT, m.body, 0.0, iw);
    let mut ph: f32 = lines.iter().map(|l| l.height()).sum();
    let action = (!f.action_id.is_empty()).then(|| ui.fonts.elide_middle(f.action_id, CONTENT, m.small, 0.0, iw));
    if let Some(a) = &action {
        ph += (m.gap * 0.5).round() + a.height();
    }
    crate::cards::plate(ui, cx, y, cw, ph + 2.0 * m.gap);
    let mut ly = y + m.gap;
    for l in &lines {
        ui.text(l, cx + m.gap, ly, t.col_white, TextStyle::Normal);
        ly += l.height();
    }
    if let Some(a) = &action {
        ly += (m.gap * 0.5).round();
        ui.text(a, cx + m.gap, ly, t.col_grey, TextStyle::Normal);
    }
    y += ph + 2.0 * m.gap + m.gap;

    // The field: plate, the accent border while it can take input.
    let enabled = f.response_required && !p.checking;
    ui.scene.rect(cx, y, cw, m.field_h, t.col_plate, 5.0, 1.0, if enabled { t.col_accent } else { Color::TRANSPARENT }, true);
    let (fx, fw) = (cx + m.gap, cw - 2.0 * m.gap);
    ui.scene.save();
    // QQuickTextInput::clipRect: one cursor width wider on the right.
    ui.scene.clip_rect(fx, y, fw + 1.0, m.field_h);
    if p.field.is_empty() {
        // inputPrompt.replace(/:\s*$/, ""): one colon at the end and the
        // blanks after it; a prompt without one keeps its own blanks.
        let prompt = f.prompt.trim_end().strip_suffix(':').unwrap_or(f.prompt);
        let ph_text = if p.checking {
            "Проверка…"
        } else if prompt.is_empty() || prompt.eq_ignore_ascii_case("password") {
            "Пароль"
        } else {
            prompt
        };
        let pl = ui.fonts.layout(ph_text, CONTENT, m.body, 0.0);
        ui.text(&pl, fx, y + ac(m.field_h, pl.height()), t.col_grey, TextStyle::Normal);
    }
    let shown: String = if f.response_visible { p.field.clone() } else { "\u{2022}".repeat(p.field.chars().count()) };
    let fl = ui.fonts.layout(&shown, FIELD, m.body, 0.0);
    let fy = y + (m.field_h - fl.height()) / 2.0;
    // TextInput.autoScroll: a line longer than the field slides left so the
    // cursor at its end stays in view - ensureVisible's hscroll = cursorX -
    // width, the cursor just past the box, inside the wider clip.
    let shift = (fl.adv - fw).max(0.0);
    if !shown.is_empty() {
        ui.text(&fl, fx - shift, fy, t.col_white, TextStyle::Normal);
    }
    if enabled {
        // 1 px, the text colour, 500 ms on / 500 ms off.
        let on = p.blink_since.map_or(true, |s| s.elapsed().as_millis() / 500 % 2 == 0);
        if on {
            ui.scene.fill(fx + fl.adv - shift, fy, 1.0, fl.height(), t.col_white);
        }
    }
    ui.scene.restore();
    y += m.field_h + m.gap;

    let (n, is_err) = note(p);
    if !n.is_empty() {
        for l in ui.fonts.wrap(&n, CONTENT, m.small, 0.0, cw) {
            ui.text(&l, cx, y, if is_err { t.col_alert } else { t.col_grey }, TextStyle::Normal);
            y += l.height();
        }
        y += m.gap;
    }

    // Keycaps.
    let kh = keycaps_h(ui.fonts, m.small);
    let mut kx = cx;
    for (i, (k, l)) in [("ENTER", "ПОДТВЕРДИТЬ"), ("ESC", "ОТМЕНА")].iter().enumerate() {
        if i > 0 {
            kx += m.gap;
        }
        let kl = ui.fonts.layout(k, theme::bar_font(true), m.small, 0.0);
        let ll = ui.fonts.layout(l, theme::bar_font(true), m.small, 1.0);
        let (rw, rhh) = (kl.width + 12.0, kl.height() + 4.0);
        let ry = y + ac(kh, rhh);
        ui.scene.rect(kx, ry, rw, rhh, t.col_plate.lighter(1.4), 3.0, 0.0, Color::TRANSPARENT, true);
        ui.scene.rect(kx, ry + rhh - 2.0, rw, 2.0, Color::qt_rgba(0.0, 0.0, 0.0, 0.45), 3.0, 0.0, Color::TRANSPARENT, true);
        ui.text(&kl, kx + ac(rw, kl.width), ry + ac(rhh, kl.height()) - 1.0, t.col_white, TextStyle::Normal);
        kx += rw + 6.0;
        ui.text(&ll, kx, y + ac(kh, ll.height()), t.col_grey, TextStyle::Normal);
        kx += ll.width;
    }
    ui.hits.push(Hit { x: x0, y: y0, w, h, action: Action::Hover(0) });
}

/// The field's keys: Enter submits, Esc cancels, Backspace, and text.
pub fn key(app: &mut App, sym: smithay_client_toolkit::seat::keyboard::Keysym, utf8: Option<&str>) {
    use smithay_client_toolkit::seat::keyboard::Keysym;
    match sym {
        Keysym::Return | Keysym::KP_Enter => submit(app),
        Keysym::Escape => cancel(app),
        _ => {
            // A disabled TextInput takes no keys. Every key the field takes
            // starts the cursor's blink over (processKeyEvent ->
            // updateCursorBlinking), Shift and the arrows too.
            if !enabled(&app.svc.polkit) {
                return;
            }
            if sym == Keysym::BackSpace {
                app.svc.polkit.field.pop();
            } else if let Some(s) = utf8.filter(|s| !s.is_empty() && !s.chars().any(char::is_control)) {
                app.svc.polkit.field.push_str(s);
            }
            restart_blink(app);
            redraw(app);
        }
    }
}
