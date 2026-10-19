#!/usr/bin/env python3
"""Herdr event hook: no idle while an agent is working.

Herdr runs this on every pane.agent_status_changed (herdr-plugin.toml). When an
agent starts working and nothing holds the screen awake yet, it starts

    systemd-inhibit --what=idle ... agent-awake.py --watch

an idle inhibitor, like the one a video player holds: hypridle honours it, so
the 9-minute idle timer (screensaver, lock) does not run meanwhile. The
watcher under it checks `herdr agent list` every WATCH seconds and exits once
no agent is working - or herdr cannot be reached - which releases the
inhibitor. It ends itself, so it cannot be left holding the screen awake.

Only "working" counts: an agent that is blocked (waiting on you) or done lets
the screen go idle as usual.

One watcher at a time: it holds an exclusive lock on watch.lock for as long as
it runs; the hook does not start another while it is held, and a watcher that
cannot take it exits at once. `systemd-inhibit --list` shows it as
"herdr ... An agent is working".
"""
import fcntl
import json
import os
import subprocess
import sys
import time

HERDR = os.environ.get("HERDR_BIN_PATH") or "herdr"
STATE_DIR = os.environ.get("HERDR_PLUGIN_STATE_DIR") or os.path.expanduser(
    "~/.local/state/herdr/plugins/agent-awake")
LOCK = os.path.join(STATE_DIR, "watch.lock")
LOG = os.path.join(STATE_DIR, "awake.log")
WATCH = 15  # seconds between checks while held
LOG_MAX = 64 * 1024


def log(msg):
    try:
        if os.path.getsize(LOG) > LOG_MAX:
            os.replace(LOG, LOG + ".1")
    except OSError:
        pass
    try:
        with open(LOG, "a") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
    except OSError:
        pass


def working():
    """How many agents are working; None when herdr cannot be asked."""
    try:
        out = subprocess.run([HERDR, "agent", "list"], capture_output=True,
                             text=True, timeout=10)
        agents = json.loads(out.stdout)["result"]["agents"]
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return None
    return sum(1 for a in agents if a.get("agent_status") == "working")


def lock_held():
    """True when a watcher holds watch.lock."""
    try:
        with open(LOCK, "a") as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(f, fcntl.LOCK_UN)
        return False
    except BlockingIOError:
        return True
    except OSError:
        return False


def watch():
    """Run under systemd-inhibit: return (releasing it) once nothing works."""
    f = open(LOCK, "a")
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return  # another watcher already holds the screen awake
    n = working()
    log("holding idle off: %s agent(s) working" % n)
    while n:
        time.sleep(WATCH)
        n = working()
    log("released: %s" % ("no agent working" if n == 0 else "herdr unreachable"))


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    if sys.argv[1:] == ["--watch"]:
        watch()
        return
    data = json.loads(os.environ["HERDR_PLUGIN_EVENT_JSON"])["data"]
    if data.get("agent_status") != "working" or lock_held():
        return
    # Detached, so herdr is not held up: the watcher outlives this hook.
    subprocess.Popen(
        ["systemd-inhibit", "--what=idle", "--who=herdr", "--mode=block",
         "--why=An agent is working",
         sys.executable, os.path.abspath(__file__), "--watch"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)


if __name__ == "__main__":
    main()
