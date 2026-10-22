#!/usr/bin/env bash
# hypridle's before_sleep_cmd: lock, and do not return until the lock screen is
# up. hypridle holds the suspend until this exits (inhibit_sleep = 1 in
# hypridle.conf), so the machine never sleeps with the desktop showing and
# resumes to it unlocked for a moment.
#
# Hyprland reported "locked" to hypridle itself (inhibit_sleep = 3 and its
# lock-notify protocol); mango has no such protocol, so this waits for hyprlock
# instead: started, plus a moment for its first frame. logind lets a suspend be
# held for 5 s at most (InhibitDelayMaxSec), so the wait stops before that.

pidof hyprlock >/dev/null && exit 0
loginctl lock-session
for _ in $(seq 1 40); do
    pidof hyprlock >/dev/null && break
    sleep 0.1
done
sleep 0.4
