#!/usr/bin/env bash
# Write ~/.config/mango/state/machine.conf: the settings that depend on the
# machine. mango's config has no conditions, so what the Hyprland Lua config
# decided on every load is decided here, at login (startup.conf) and by the
# installer (copy.sh). The file is only rewritten when its content changes -
# mango reloads its config whenever a sourced file does.
#
#  - Laptop keys (laptop.conf): when there is a battery or the DMI chassis is
#    portable; the ASUS keys (asus.conf) also need asusctl.
#  - NVIDIA environment: only when every GPU is NVIDIA and the proprietary
#    driver is really in use. The hardware alone is not enough: the installer
#    leaves an NVIDIA GPU on nouveau when nvidia="OFF", for Kepler and older and
#    when the DKMS build failed, and __GLX_VENDOR_LIBRARY_NAME=nvidia there
#    breaks every XWayland OpenGL app. On a hybrid laptop the iGPU drives the
#    desktop, so nothing is set there either.
#  - This session's switches, last so they win: the blur toggle
#    (ChangeBlur.sh), game mode (GameMode.sh) and the touchpad (TouchPad.sh).
#    Their files live on the runtime tmpfs, so a switch stays across config
#    reloads (a wallpaper change reloads) and is gone with the session.
#    mango expands no variables in source paths, hence the absolute paths.
#  - The special workspace's gaps for this monitor: Hyprland scaled the special
#    workspace to 80% of the work area; mango insets it with gaps, so they are
#    worked out from the monitor's size (needs mango running).

conf_dir="$HOME/.config/mango"
out="$conf_dir/state/machine.conf"
mkdir -p "$conf_dir/state"

is_laptop() {
    compgen -G '/sys/class/power_supply/BAT*' >/dev/null && return 0
    local chassis
    chassis=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)
    case "$chassis" in 8 | 9 | 10 | 11 | 14) return 0 ;; esac
    return 1
}

nvidia_only() {
    local vendors
    vendors=$(cat /sys/class/drm/card*/device/vendor 2>/dev/null | sort -u)
    [ "$vendors" = 0x10de ] &&
        [ -e /sys/module/nvidia/initstate ] && [ -e /usr/lib/libGLX_nvidia.so.0 ]
}

{
    echo "# Written by ~/.config/hypr/scripts/MachineConf.sh - edits are overwritten."
    if is_laptop; then
        echo "source=$conf_dir/laptop.conf"
        command -v asusctl >/dev/null && echo "source=$conf_dir/asus.conf"
    fi
    if nvidia_only; then
        echo "env=LIBVA_DRIVER_NAME,nvidia"
        echo "env=__GLX_VENDOR_LIBRARY_NAME,nvidia"
        echo "env=NVD_BACKEND,direct"
        echo "env=GSK_RENDERER,ngl"
    fi
    # 80% of the work area (screen minus the 34 px bar and the 12 px gaps),
    # centred: the gap is 12 + a tenth of the work area's width / height.
    if [ -n "$MANGO_INSTANCE_SIGNATURE" ] && command -v mmsg >/dev/null; then
        read -r w h < <(mmsg get all-monitors |
            jq -r '.monitors[] | select(.active) | "\(.width) \(.height)"' 2>/dev/null)
        if [ "${w:-0}" -gt 0 ] && [ "${h:-0}" -gt 0 ]; then
            echo "special_gap_outer_horizontal=$(((120 + (w - 24) + 5) / 10))"
            echo "special_gap_outer_vertical=$(((120 + (h - 46) + 5) / 10))"
        fi
    fi
    run_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    is_laptop && echo "source_optional=$run_dir/mango-touchpad.conf"
    echo "source_optional=$run_dir/mango-blur.conf"
    echo "source_optional=$run_dir/mango-gamemode.conf"
} >"$out.tmp"

if cmp -s "$out.tmp" "$out"; then
    rm -f "$out.tmp"
else
    mv -f "$out.tmp" "$out"
fi
