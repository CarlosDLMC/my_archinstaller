#!/usr/bin/env python3
"""Herdr event hook: tell the desktop when an agent finishes or is blocked.

Herdr runs this on every pane.agent_status_changed (herdr-plugin.toml). It
sends a dunst notification when an agent

  - finished its turn: "done", or "idle" straight after "working" - herdr
    reports a finish in the pane it has focused as idle, because that pane
    counts as seen, and
  - is blocked: waiting on an approval or a question,

but only while the herdr window is NOT the focused Hyprland window. Herdr's own
popups ([ui.toast]) cannot do this: they are skipped for herdr's active tab
whatever Hyprland is showing, so an agent finishing in the tab herdr has open
while you are on another workspace never told anyone. While herdr is focused,
its sidebar already shows every agent's state, so nothing is sent.

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
import time

HERDR = os.environ.get("HERDR_BIN_PATH") or "herdr"
STATE_DIR = os.environ.get("HERDR_PLUGIN_STATE_DIR") or os.path.expanduser(
    "~/.local/state/herdr/plugins/agent-notify")
SESSION = os.environ.get("HERDR_SESSION") or "default"
# Same idea as [ui.toast] delay_seconds: a state that does not last this long
# (a blocked prompt answered at once, an idle between two steps) is not news.
SETTLE = 1.0

APP = "Агент"
TEXT = {"done": "Задание выполнено", "blocked": "Ждёт вашего решения"}


def herdr_window_focused():
    """True when the focused Hyprland window has a herdr process under it."""
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    run = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    if sig and not os.path.isdir(os.path.join(run, "hypr", sig)):
        # Hyprland was restarted under a long-lived herdr server: let hyprctl
        # find the running instance instead of the dead one.
        os.environ.pop("HYPRLAND_INSTANCE_SIGNATURE")
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"],
                             capture_output=True, text=True, timeout=3)
        win = json.loads(out.stdout).get("pid", -1)
    except (OSError, ValueError, subprocess.SubprocessError):
        return False
    if win <= 1:
        return False
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
            if ppid == win:
                return True
            ppid = procs.get(ppid, (0, ""))[0]
    return False


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


def notify(tag, urgency, summary, body):
    subprocess.run(["notify-send", "-a", APP, "-u", urgency,
                    "-h", "string:x-dunst-stack-tag:" + tag, summary, body],
                   capture_output=True, timeout=5)


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
    if not herdr_window_focused():
        notify("herdr-%s-%s" % (SESSION, pane),
               "critical" if kind == "blocked" else "normal", TEXT[kind], body)

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
    main()
