#!/usr/bin/env bash
# Toggle between light and heavy blur (SUPER+ALT+O) for this session.
#
# The light values go into a file on the runtime tmpfs that mango sources
# (state/machine.conf, written by MachineConf.sh), and mango reloads when it
# appears or goes. So the toggle holds across config reloads - a wallpaper
# change reloads - and is gone with the session; heavy is the config's own.
# Heavy is radius 5 / 2 passes, as the Hyprland toggle restored it (the config
# itself has 6).
# Layer surfaces (the bar) keep the blur they were mapped with until they map
# again: mango never changes it on a mapped surface.

state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mango-blur.conf"

if grep -q '^blur_params_num_passes=1$' "$state" 2>/dev/null; then
    printf 'blur_params_radius=5\nblur_params_num_passes=2\n' >"$state"
else
    printf 'blur_params_radius=2\nblur_params_num_passes=1\n' >"$state"
fi
