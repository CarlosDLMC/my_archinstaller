#!/usr/bin/env bash
# Show one of the two soviet flags on a spare TTY, WITHOUT touching /etc/ly.
#
# Use this to compare them before committing to one. It copies the live ly
# config, points dur_file_path at the variant you asked for, and runs a second
# ly on a free VT. Your real login manager is never signalled: every kill here
# matches only processes started with this preview config path.
#
#   flag-preview.sh static      # or: animated
#   flag-preview.sh animated 9  # on VT 9 instead of 8
#   flag-preview.sh --stop      # kill the preview and free the VT
#
# F1/F2/F3 are stubbed to /bin/true in the preview, so pressing them cannot
# power off or reboot the machine. Do not type a password: it is a real
# greeter and would start a second session.

set -euo pipefail

VARIANT="${1:-static}"
VT="${2:-8}"
# /run, not /tmp. ly-dm is started as root below and reads config.ini from this
# directory - and config.ini names commands ly executes (login_cmd, setup_cmd,
# shutdown_cmd...). A fixed path in world-writable /tmp meant anything that could
# create /tmp/ly-flag-preview first - a symlink, or a directory owned by someone
# else - chose where `sudo tee` wrote and what root then ran. /run is writable
# only by root, so the path cannot be claimed before this script gets there, and
# it is tmpfs so nothing survives a reboot.
PREVIEW_DIR=/run/ly-flag-preview
PATTERN="ly-dm -c $PREVIEW_DIR"

if [ "$VARIANT" = "--stop" ]; then
    stopped=0
    for pid in $(pgrep -f "$PATTERN" 2>/dev/null || true); do
        sudo kill -9 "$pid" 2>/dev/null && stopped=$((stopped + 1)) || true
    done
    sudo deallocvt "$VT" 2>/dev/null || true
    echo "stopped $stopped preview process(es); real ly untouched"
    exit 0
fi

case "$VARIANT" in
    static|animated) ;;
    *) echo "usage: $0 [static|animated] [vt]   |   $0 --stop" >&2; exit 2 ;;
esac

DUR="/etc/ly/soviet-flag-$VARIANT.dur"
[ -r "$DUR" ] || { echo "missing $DUR - run install-scripts/ly_config.sh" >&2; exit 1; }

# Where to return to afterwards: whichever VT is in front right now.
HOME_VT=$(sed 's/[^0-9]//g' /sys/class/tty/tty0/active)
[ -n "$HOME_VT" ] || HOME_VT=1

command -v openvt >/dev/null || { echo "openvt not found (kbd package)" >&2; exit 1; }

# install -d rather than mkdir -p: the mode and ownership are stated rather than
# inherited from root's umask, so the directory is root-owned 0755 on every run.
sudo install -d -o root -g root -m 0755 "$PREVIEW_DIR"
sudo cp -rT /etc/ly/lang "$PREVIEW_DIR/lang" 2>/dev/null || true
# The greeter's own action keys would really fire, so neutralise them.
sudo sed -e "s#^dur_file_path.*#dur_file_path = $DUR#" \
         -e 's#^shutdown_cmd.*#shutdown_cmd = /bin/true#' \
         -e 's#^restart_cmd.*#restart_cmd = /bin/true#' \
         -e 's#^sleep_cmd.*#sleep_cmd = /bin/true#' \
         /etc/ly/config.ini | sudo tee "$PREVIEW_DIR/config.ini" >/dev/null

# Clear out any previous preview, real ly untouched.
for pid in $(pgrep -f "$PATTERN" 2>/dev/null || true); do sudo kill -9 "$pid" 2>/dev/null || true; done
sudo deallocvt "$VT" 2>/dev/null || true

sudo setsid openvt -c "$VT" -- /usr/bin/ly-dm -c "$PREVIEW_DIR" >/dev/null 2>&1 </dev/null &

pid=""
# Poll for up to ~6s. The sleep is load-bearing: without it all 60 iterations ran
# in a few milliseconds - long before openvt had spawned ly-dm - so the loop fell
# through to the failure message below even when the preview came up fine a
# moment later. Sleeping after the test, not before it, keeps an already-running
# preview instant.
for _ in $(seq 60); do
    pid=$(pgrep -f "$PATTERN" 2>/dev/null | head -1 || true)
    [ -n "$pid" ] && break
    sleep 0.1
done
if [ -z "$pid" ]; then
    echo "preview failed to start on VT $VT (already in use?)" >&2
    exit 1
fi

# Printed BEFORE the switch: chvt takes the terminal away with it, so
# anything echoed afterwards is never seen.
cat <<MSG
showing: $VARIANT  ($DUR)
  return: Ctrl+Alt+F$HOME_VT
  look again: Ctrl+Alt+F$VT
  stop:   $0 --stop
MSG

# Give the message a moment to land on screen before the VT changes.
sleep 1
sudo chvt "$VT"
