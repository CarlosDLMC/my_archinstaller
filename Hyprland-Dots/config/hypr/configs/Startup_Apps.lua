-- Commands and apps executed once at launch (vendor defaults).
-- `hyprland.start` fires once per session, so a config reload does NOT re-run
-- these - same semantics as the old exec-once.

local V = require("configs.Vars")
local S = V.scriptsDir
local U = V.UserScripts

local wallDIR = V.home .. "/Pictures/wallpapers"
local livewallpaper = ""  -- WallpaperSelect.sh rewrites this line for video wallpapers

hl.on("hyprland.start", function()
    local run = hl.exec_cmd

    ---- wallpaper ----
    -- WallpaperSelect.sh comments one of the next two lines out and uncomments
    -- the other when switching between image and video wallpapers.
    run("awww-daemon --format argb")
    -- run("mpvpaper '*' -o \"load-scripts=no no-audio --loop\" " .. livewallpaper)
    -- run(U .. "/WallpaperAutoChange.sh " .. wallDIR) -- random wallpaper every 30 min

    ---- startup ----
    run("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    run("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Polkit (Polkit Gnome / KDE)
    run(S .. "/Polkit.sh")

    ---- startup apps ----
    -- run("nm-applet --indicator")  -- disabled: the bar's WiFi widget handles this
    run("dunst")
    -- run("ags")
    -- run("blueman-applet")
    -- run("rog-control-center")
    -- run("waybar")
    run("qs -c bar")          -- Quickshell bar
    -- run("qs -c overview")  -- Quickshell overview (started on demand by OverviewToggle.sh)

    -- Clipboard manager
    run("wl-paste --type text --watch cliphist store")
    run("wl-paste --type image --watch cliphist store")

    -- Rainbow borders
    -- run(U .. "/RainbowBorders.sh")

    -- Size the lock screen for whatever monitors are attached. Also run before
    -- each lock, but doing it at login means a bare `hyprlock` is covered too.
    run("python3 " .. S .. "/SovietLockGen.py")

    -- Keep this session's log readable after logout (ly truncates its own).
    run(S .. "/SessionLogKeep.sh")

    -- hypridle for hyprlock
    run("hypridle")

    -- Resume Hyprsunset if state is "on" from previous session
    run(S .. "/Hyprsunset.sh init")

    ---- available but disabled by default ----
    -- run("awww-daemon --format argb && awww img " .. V.home .. "/Pictures/wallpapers/mecha-nostalgia.png")
    -- run(S .. "/Polkit-NixOS.sh")      -- Gnome polkit for NixOS
    -- run(S .. "/PortalHyprland.sh")    -- xdg-desktop-portal-hyprland (should autostart)
end)
