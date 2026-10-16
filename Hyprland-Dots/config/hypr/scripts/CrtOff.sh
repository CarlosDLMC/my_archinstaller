#!/usr/bin/env bash
# CRT power-off for the «ПУСК · ПУЛЬТ» power menu: every monitor's picture
# collapses to a line, then to a dot, and the screen stays black while the
# session goes down. Put in front of the command that ends it:
#
#     CrtOff.sh systemctl poweroff
#
# The animation is quickshell/crt, a config of its own - not part of the bar.
# The command runs once the picture is gone. If it fails (an inhibitor, a refused
# reboot) the black overlay is taken down and the desktop comes back; if the
# overlay never starts, the command still runs after 3s.

dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/crt-off"
rm -rf "$dir" && mkdir -p "$dir"

# The collapse starts from one frame of each monitor, exactly as it stands.
# PPM, not PNG: grim spent 658ms compressing a 1080p PNG, 37ms writing this.
while read -r name; do
    grim -t ppm -o "$name" "$dir/$name.ppm" &
done < <(hyprctl monitors -j | jq -r '.[].name')
wait

cursor() { hyprctl eval "hl.config({ cursor = { invisible = $1 } })" >/dev/null 2>&1; }
cursor true
qs -c crt >/dev/null 2>&1 &
crt=$!

# quickshell/crt touches $dir/done once the dot has faded.
for _ in $(seq 1 30); do
    [ -e "$dir/done" ] && break
    sleep 0.1
done

"$@"
rc=$?
if [ "$rc" -ne 0 ]; then
    kill "$crt" 2>/dev/null
    cursor false
fi
exit "$rc"
