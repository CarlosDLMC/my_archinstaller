#!/usr/bin/env python3
"""Herdr event hook: tell the desktop when an agent finishes or is blocked.

Herdr runs this on every pane.agent_status_changed (herdr-plugin.toml). It
sends a dunst notification when an agent

  - finished its turn: "done", or "idle" straight after "working" - herdr
    reports a finish in the pane it has focused as idle, because that pane
    counts as seen, and
  - is blocked: waiting on an approval or a question,

always - also while herdr is the focused window. Herdr's own popups
([ui.toast]) cannot do this: they are skipped for herdr's active tab whatever
the desktop is showing, so an agent finishing in the tab herdr has open while you
are on another workspace never told anyone.

Clicking a notice takes you to that agent: herdr switches to its pane
(`herdr agent focus`) and mango focuses the herdr window - on whatever
workspace it is - or, with no terminal attached to herdr, opens one first. The
hook does not wait for that click (herdr would be held up): it hands the notice
to a detached copy of itself (--notice), which waits on notify-send's default
action. Left click runs it (dunstrc: mouse_left_click = do_action, ...).

Both stay until clicked (dunstrc [agent_notices]); a blocked one is sent
critical, so it has the red frame and a red АГЕНТ stamp ([look_agent_blocked]).
Each pane has its own stack tag, so an agent shows one notice at a time: when
it is blocked and then finishes, the finished notice takes the blocked one's
place rather than stacking under it.
"""
import fcntl
import html
import json
import os
import subprocess
import sys
import time

HERDR = os.environ.get("HERDR_BIN_PATH") or "herdr"
STATE_DIR = os.environ.get("HERDR_PLUGIN_STATE_DIR") or os.path.expanduser(
    "~/.local/state/herdr/plugins/agent-notify")
SESSION = os.environ.get("HERDR_SESSION") or "default"
# Same idea as [ui.toast] delay_seconds: a state that does not last this long
# (a blocked prompt answered at once, an idle between two steps) is not news.
SETTLE = 1.0
# How often a waiting notice checks that dunst is still the one holding it.
WATCH = 30

APP = "Агент"
TEXT = {"done": "Задание выполнено", "blocked": "Ждёт вашего решения"}


def herdr_window():
    """The mango id of the window with a herdr client in it, or None."""
    mango_env()
    try:
        out = subprocess.run(["mmsg", "get", "all-clients"],
                             capture_output=True, text=True, timeout=3)
        wins = {c["pid"]: c["id"] for c in json.loads(out.stdout)["clients"] if c.get("pid", -1) > 1}
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        return None
    procs = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open("/proc/%s/stat" % d) as f:
                stat = f.read()
        except OSError:
            continue
        # comm sits in parentheses and may itself contain spaces or ")".
        comm = stat[stat.index("(") + 1:stat.rindex(")")]
        procs[int(d)] = (int(stat[stat.rindex(")") + 2:].split()[1]), comm)
    for pid, (ppid, comm) in procs.items():
        if comm != "herdr":
            continue
        while ppid > 1:
            if ppid in wins:
                return wins[ppid]
            ppid = procs.get(ppid, (0, ""))[0]
    return None


def log(msg):
    """What a click did (STATE_DIR/clicks.log), for when it does not do what it
    should. Kept to its last 32KB once it passes 64KB."""
    path = os.path.join(STATE_DIR, "clicks.log")
    try:
        if os.path.getsize(path) > 65536:
            with open(path, "rb") as f:
                f.seek(-32768, os.SEEK_END)
                tail = f.read()
            with open(path, "wb") as f:
                f.write(tail[tail.find(b"\n") + 1:])
    except OSError:
        pass
    try:
        with open(path, "a") as f:
            f.write("%s %s\n" % (time.strftime("%F %T"), msg))
    except OSError:
        pass


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    log("%s -> rc=%s out=%r err=%r" % (cmd, r.returncode, r.stdout.strip()[:200], r.stderr.strip()[:200]))
    return r


def go_to(pane):
    """Show this agent: its pane in herdr, and the herdr window in mango."""
    addr = herdr_window()
    log("go_to %s: herdr window %s" % (pane, addr))
    if addr is None:
        # No terminal attached to herdr (the server runs on without one).
        # mango starts it, with the session's environment.
        subprocess.run(["mmsg", "dispatch", "spawn,foot herdr"],
                       capture_output=True, timeout=5)
        for _ in range(50):
            time.sleep(0.1)
            addr = herdr_window()
            if addr:
                break
    # The window first, then the pane: focusing the herdr terminal makes the
    # herdr client restore the pane it was showing, which undid a pane switch
    # made before it - you landed on herdr, but on whatever was open there.
    if addr:
        # focusid switches to the window's workspace, and brings a hidden tab
        # of a group to the front.
        run(["mmsg", "dispatch", "focusid", "client,%s" % addr])
        time.sleep(0.3)
    run([HERDR, "agent", "focus", pane])
    try:
        time.sleep(0.3)
        snap = json.loads(subprocess.run([HERDR, "api", "snapshot"], capture_output=True,
                                         text=True, timeout=5).stdout)["result"]["snapshot"]
        log("herdr now shows pane %s" % snap.get("focused_pane_id"))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        pass


def where(snap, pane_id):
    """"№2 njorda · proxies", then the conversation title, for the notice body."""
    pane = next((p for p in snap["panes"] if p["pane_id"] == pane_id), {})
    ws = next((w for w in snap["workspaces"]
               if w["workspace_id"] == pane.get("workspace_id")), {})
    tab = next((t for t in snap["tabs"] if t["tab_id"] == pane.get("tab_id")), {})
    text = "№%s %s · %s" % (ws.get("number", "?"), ws.get("label", ""), tab.get("label", ""))
    title = (pane.get("terminal_title_stripped") or "").strip()
    if title and title.lower() not in ("claude code", (pane.get("agent") or "").lower()):
        text += "\n" + title
    return html.escape(text), pane.get("agent_status")


def notify(tag, urgency, summary, body, pane):
    """Hand the notice to a detached copy of this script that waits for its click."""
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "--notice",
                      tag, urgency, summary, body, pane],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def mango_env():
    """Point mmsg at the running mango, whatever environment herdr gave us: the
    herdr server can outlive a mango restart and keep a dead socket path."""
    run_dir = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    os.environ["XDG_RUNTIME_DIR"] = run_dir
    sig = os.environ.get("MANGO_INSTANCE_SIGNATURE")
    if sig and os.path.exists(sig):
        return
    try:
        live = [os.path.join(run_dir, d) for d in os.listdir(run_dir)
                if d.startswith("mango-") and d.endswith(".sock")]
    except OSError:
        live = []
    if live:
        live.sort(key=os.path.getmtime)
        os.environ["MANGO_INSTANCE_SIGNATURE"] = live[-1]
    log("mango_env: socket %r was not usable, now %r" % (sig, os.environ.get("MANGO_INSTANCE_SIGNATURE")))


def notifications_owner():
    """The bus name of the running notification daemon (dunst), or None."""
    try:
        out = subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus",
                              "--object-path", "/org/freedesktop/DBus",
                              "--method", "org.freedesktop.DBus.GetNameOwner",
                              "org.freedesktop.Notifications"],
                             capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def notice(tag, urgency, summary, body, pane):
    """Show the notice and wait: clicked, go to the agent. Ends without a click
    when the notice is closed or replaced (same stack tag), or when dunst exits
    or is restarted - the notice goes with it, and notify-send would otherwise
    wait for its click until logout."""
    log("notice %s waiting (pid %s)" % (tag, os.getpid()))
    mango_env()
    proc = subprocess.Popen(["notify-send", "-a", APP, "-u", urgency,
                             "-h", "string:x-dunst-stack-tag:" + tag,
                             "-A", "default=Открыть", summary, body],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    owner = None
    while True:
        try:
            action = proc.communicate(timeout=WATCH)[0].strip()
            break
        except subprocess.TimeoutExpired:
            now = notifications_owner()
            if now is None or (owner is not None and now != owner):
                proc.kill()
                proc.wait()
                log("notice %s dropped: the notification daemon is gone" % tag)
                return
            owner = now
    log("notice %s ended: rc=%s action=%r" % (tag, proc.returncode, action))
    if action == "default":
        go_to(pane)


def main():
    data = json.loads(os.environ["HERDR_PLUGIN_EVENT_JSON"])["data"]
    pane, status = data["pane_id"], data["agent_status"]
    os.makedirs(STATE_DIR, exist_ok=True)
    # The pane's last status, for telling a finish (working -> idle) from an
    # idle that follows anything else.
    key = os.path.join(STATE_DIR, "%s-%s" % (SESSION, pane.replace(":", "_")))

    with open(key + ".lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(key) as f:
                prev = f.read().strip()
        except OSError:
            prev = ""
        with open(key, "w") as f:
            f.write(status)

    if status == "blocked":
        kind = "blocked"
    elif status == "done" or (status == "idle" and prev == "working"):
        kind = "done"
    else:
        return
    time.sleep(SETTLE)

    try:
        snap = json.loads(subprocess.run(
            [HERDR, "api", "snapshot"], capture_output=True, text=True,
            timeout=5).stdout)["result"]["snapshot"]
        body, now = where(snap, pane)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        body, now = "", status
    # Superseded while settling: the newer event's run handles it.
    if now != status:
        return
    notify("herdr-%s-%s" % (SESSION, pane),
           "critical" if kind == "blocked" else "normal", TEXT[kind], body, pane)

    # Pane ids are never reused, so state for panes long gone is dead weight.
    cutoff = time.time() - 3 * 86400
    for name in os.listdir(STATE_DIR):
        path = os.path.join(STATE_DIR, name)
        try:
            if os.path.getmtime(path) < cutoff:
                os.remove(path)
        except OSError:
            pass


if __name__ == "__main__":
    if len(sys.argv) == 7 and sys.argv[1] == "--notice":
        notice(*sys.argv[2:])
    else:
        main()
