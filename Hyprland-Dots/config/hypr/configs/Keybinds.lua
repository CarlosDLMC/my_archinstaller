-- Default keybinds. https://wiki.hypr.land/Configuring/Core/Binds/
--
-- hl.bind("MODS + key", dispatcher_or_function, { flags })
--   old bindd  -> description = "..."     old bindl -> locked = true
--   old binde  -> repeating = true        old bindr -> release = true
--   old bindn  -> non_consuming = true    old bindm -> mouse binds (window.drag / window.resize)
-- Give every bind a description: KeyHints.sh / KeyBinds.sh (SUPER H / SUPER SHIFT K)
-- list the LIVE binds via `hyprctl binds`, and a bind without one shows up as
-- "(no description)". Use modifier NAMES (SUPER/CTRL/ALT/SHIFT) before the "+";
-- a keysym such as ALT_L there is ignored and the bind ends up with no modifier.

local V    = require("configs.Vars")
local D    = require("UserConfigs.01-UserDefaults")
local M    = V.mainMod
local S    = V.scriptsDir
local U    = V.UserScripts
local exec = hl.dsp.exec_cmd
local bind = hl.bind

---- STANDARD ----
bind(M .. " + D",      exec("pkill rofi || true && rofi -show drun -modi drun,filebrowser,run,window"), { description = "app launcher" })
bind(M .. " + B",      exec("librewolf"),                  { description = "open browser" })
bind(M .. " + A",      exec(S .. "/OverviewToggle.sh"),    { description = "desktop overview" }) -- quickshell overview, AGS fallback
bind(M .. " + Return", exec(D.term),                       { description = "open terminal" })
bind(M .. " + E",      exec(D.files),                      { description = "file manager" })

-- FEATURES / EXTRAS
bind(M .. " + H",         exec(S .. "/KeyHints.sh"),     { description = "cheat sheet (searchable list of keybinds)" })
bind(M .. " + ALT + R",   exec(S .. "/Refresh.sh"),      { description = "refresh bar and menus" })
bind(M .. " + ALT + E",   exec(S .. "/RofiEmoji.sh"),    { description = "emoji menu" })
bind(M .. " + S",         exec(S .. "/RofiSearch.sh"),   { description = "web search" })
bind(M .. " + CTRL + S",  exec("rofi -show window"),     { description = "window switcher" })
bind(M .. " + ALT + O",   exec(S .. "/ChangeBlur.sh"),   { description = "toggle blur" })
bind(M .. " + SHIFT + G", exec(S .. "/GameMode.sh"),     { description = "toggle game mode" })
bind(M .. " + ALT + L",   exec(S .. "/ChangeLayout.sh"), { description = "toggle master/dwindle layout" })
bind(M .. " + ALT + V",   exec(S .. "/ClipManager.sh"),  { description = "clipboard manager" })

-- The bar runs as `qs -c bar`, so its process name is "qs", not "quickshell".
-- The pattern is anchored with ^ on purpose: exec runs through `/bin/sh -c
-- '<command>'`, so that shell's own command line contains "qs -c bar" and an
-- unanchored pkill -f would kill the shell before it ever restarts the bar.
-- `;` and not `&&`, so a pkill that matches nothing still starts the bar.
bind(M .. " + CTRL + B", exec([[pkill -f "^qs -c bar"; sleep 0.5; qs -c bar]]), { description = "restart quickshell" })

bind(M .. " + SHIFT + F", hl.dsp.window.fullscreen(),                       { description = "fullscreen" })
bind(M .. " + CTRL + F",  hl.dsp.window.fullscreen({ mode = "maximized" }), { description = "maximize window" })
bind(M .. " + space",     hl.dsp.global("quickshell:layoutNext"),           { description = "switch keyboard layout", locked = true })
bind(M .. " + SHIFT + space", hl.dsp.window.float(),                        { description = "toggle floating (active window)" })

-- Float / tile every window on the current workspace (was `workspaceopt allfloat`).
bind(M .. " + ALT + space", function()
    local ws = hl.get_active_workspace()
    if not ws then return end
    local windows = hl.get_workspace_windows(ws)
    local anyTiled = false
    for _, w in ipairs(windows) do
        if not w.floating then anyTiled = true end
    end
    for _, w in ipairs(windows) do
        hl.dispatch(hl.dsp.window.float({ action = anyTiled and "set" or "unset", window = w }))
    end
end, { description = "float / tile every window on this workspace" })

bind(M .. " + SHIFT + Return", exec(S .. "/Dropterminal.sh " .. D.term), { description = "dropdown terminal" })

-- Desktop zooming / magnifier
bind(M .. " + ALT + mouse_up",   V.zoom_by(2.0), { description = "zoom in" })
bind(M .. " + ALT + mouse_down", V.zoom_by(0.5), { description = "zoom out" })

-- Quickshell bar
bind(M .. " + CTRL + ALT + B", exec(S .. "/ToggleQuickshellBar.sh"), { description = "toggle quickshell bar on/off" })

-- Night light toggle (Hyprsunset)
bind(M .. " + N", exec(S .. "/Hyprsunset.sh toggle"), { description = "toggle night light" })

-- FEATURES / EXTRAS (UserScripts)
bind(M .. " + SHIFT + M", exec(U .. "/RofiBeats.sh"),         { description = "online music" })
bind(M .. " + W",         exec(U .. "/WallpaperSelect.sh"),   { description = "select wallpaper" })
bind(M .. " + SHIFT + W", exec(U .. "/WallpaperEffects.sh"),  { description = "wallpaper effects" })
bind("CTRL + ALT + W",    exec(U .. "/WallpaperRandom.sh"),   { description = "random wallpaper" })
bind(M .. " + CTRL + O",  hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }), { description = "toggle opaque (no transparency) for active window" })
bind(M .. " + SHIFT + K", exec(S .. "/KeyBinds.sh"),          { description = "search keybinds (rofi)" })
bind(M .. " + SHIFT + A", exec(S .. "/Animations.sh"),        { description = "animations menu" })

-- Both press orders of ALT+SHIFT, so the gesture works whichever modifier lands
-- first. Both go through quickshell, which owns the MRU ordering and the OSD -
-- a direct `hyprctl switchxkblayout` here would switch the layout but leave the
-- bar showing the old one. Both are locked, so they work on the lock screen.
-- The modifier half must be a modifier NAME (ALT / SHIFT): "ALT_L" and
-- "SHIFT_L" are keysyms, and hl.bind("ALT_L + SHIFT_L") silently gave a bind
-- with no modifier at all (`hyprctl binds` showed modmask 0), so it never fired
-- and the cheat sheet listed a bare "SHIFT_L".
bind("ALT + SHIFT_L", hl.dsp.global("quickshell:layoutNext"), { description = "switch keyboard layout", locked = true })
bind("SHIFT + ALT_L", hl.dsp.global("quickshell:layoutNext"), { description = "switch keyboard layout", locked = true, non_consuming = true })

bind(M .. " + ALT + C", exec(U .. "/RofiCalc.sh"), { description = "calculator" })

-- Move current workspace to a monitor (left right up down)
bind(M .. " + CTRL + F9",  hl.dsp.workspace.move({ monitor = "l" }), { description = "move workspace to left monitor" })
bind(M .. " + CTRL + F10", hl.dsp.workspace.move({ monitor = "r" }), { description = "move workspace to right monitor" })
bind(M .. " + CTRL + F11", hl.dsp.workspace.move({ monitor = "u" }), { description = "move workspace to up monitor" })
bind(M .. " + CTRL + F12", hl.dsp.workspace.move({ monitor = "d" }), { description = "move workspace to down monitor" })

---- SYSTEM ----
bind("CTRL + ALT + Delete", hl.dsp.exit(),                          { description = "exit Hyprland" })
bind(M .. " + Q",           hl.dsp.window.close(),                  { description = "close active window" })
bind(M .. " + SHIFT + Q",   exec(S .. "/KillActiveProcess.sh"),     { description = "kill active window process (force)" })
bind("CTRL + ALT + L",      exec(S .. "/LockScreen.sh"),            { description = "lock screen" })
bind("CTRL + ALT + P",      exec(S .. "/Wlogout.sh"),               { description = "powermenu" })
bind(M .. " + SHIFT + E",   exec(S .. "/Quick_Settings.sh"),   { description = "quick settings menu" })

-- Master layout
bind(M .. " + CTRL + D",      hl.dsp.layout("removemaster"),   { description = "remove master" })
bind(M .. " + I",             hl.dsp.layout("addmaster"),      { description = "add master" })
bind(M .. " + CTRL + Return", hl.dsp.layout("swapwithmaster"), { description = "swap with master" })

-- SUPER+J/K cycle windows the same way on every layout. They used to be set at
-- startup by KeybindsLayoutInit.sh through `hyprctl keyword bind`, which no
-- longer exists with the Lua config; a plain bind here does the same thing.
bind(M .. " + J", hl.dsp.window.cycle_next(),                 { description = "cycle next window" })
bind(M .. " + K", hl.dsp.window.cycle_next({ next = false }), { description = "cycle previous window" })

-- Dwindle layout
bind(M .. " + SHIFT + I", hl.dsp.layout("togglesplit"), { description = "toggle split (dwindle)" })
bind(M .. " + P",         hl.dsp.window.pseudo(),        { description = "toggle pseudo (dwindle)" })

-- Works on either layout
bind(M .. " + M", hl.dsp.layout("splitratio 0.3"), { description = "set split ratio to 0.3" })

-- Cycle windows; if floating bring to top
bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.bring_to_top())
end, { description = "cycle windows (floating ones come to top)" })

-- Special keys / hot keys
bind("XF86AudioRaiseVolume", exec(S .. "/Volume.sh --inc"),        { description = "volume up",       repeating = true, locked = true })
bind("XF86AudioLowerVolume", exec(S .. "/Volume.sh --dec"),        { description = "volume down",     repeating = true, locked = true })
bind("XF86AudioMicMute",     exec(S .. "/Volume.sh --toggle-mic"), { description = "toggle mic mute", locked = true, non_consuming = true })
bind("XF86AudioMute",        exec(S .. "/Volume.sh --toggle"),     { description = "toggle mute",     locked = true, non_consuming = true })
bind("XF86Sleep",            exec("systemctl suspend"),            { description = "sleep",           locked = true, non_consuming = true })
bind("XF86RFKill",           exec(S .. "/AirplaneMode.sh"),        { description = "airplane mode",   locked = true, non_consuming = true })

-- Media controls
bind("XF86AudioPause", exec(S .. "/MediaCtrl.sh --pause"), { description = "play / pause",   locked = true, non_consuming = true })
bind("XF86AudioPlay",  exec(S .. "/MediaCtrl.sh --pause"), { description = "play / pause",   locked = true, non_consuming = true })
bind("XF86AudioNext",  exec(S .. "/MediaCtrl.sh --nxt"),   { description = "next track",     locked = true, non_consuming = true })
bind("XF86AudioPrev",  exec(S .. "/MediaCtrl.sh --prv"),   { description = "previous track", locked = true, non_consuming = true })
bind("XF86AudioStop",  exec(S .. "/MediaCtrl.sh --stop"),  { description = "stop",           locked = true, non_consuming = true })

-- Screenshots. NOTE: you may need to press Fn as well.
-- Bare Print: instant shot of whichever monitor the pointer is on - deliberately
-- the pointer and not the focused monitor, they can be on different screens.
bind("Print",                    exec(S .. "/ScreenShot.sh --mouse"),  { description = "screenshot (monitor under pointer)" })
bind(M .. " + Print",            hl.dsp.global("quickshell:shotMenu"), { description = "screenshot dialog", locked = true })
bind(M .. " + SHIFT + Print",    exec(S .. "/ScreenShot.sh --area"),   { description = "screenshot (area)" })
bind(M .. " + CTRL + Print",     exec(S .. "/ScreenShot.sh --in5"),    { description = "screenshot in 5s" })
bind(M .. " + CTRL + SHIFT + Print", exec(S .. "/ScreenShot.sh --in10"), { description = "screenshot in 10s" })
bind("ALT + Print",              exec(S .. "/ScreenShot.sh --active"), { description = "screenshot active window" })
bind(M .. " + SHIFT + S",        hl.dsp.global("quickshell:shotMenu"), { description = "screenshot dialog", locked = true })
bind(M .. " + ALT + S",          exec(S .. "/ScreenShot.sh --swappy"), { description = "screenshot (annotate with satty)" })

-- Screen recording
bind(M .. " + SHIFT + R",        hl.dsp.global("quickshell:recordMenu"),    { description = "screen recording dialog", locked = true })
bind(M .. " + CTRL + R",         exec(S .. "/ScreenRecord.sh --fullscreen"), { description = "screen record (focused monitor)" })
bind("ALT + R",                  exec(S .. "/ScreenRecord.sh --active"),     { description = "screen record (active window)" })
bind(M .. " + CTRL + SHIFT + R", exec(S .. "/ScreenRecord.sh --stop"),       { description = "stop recording" })

-- Resize windows
bind(M .. " + SHIFT + left",  hl.dsp.window.resize({ x = -50, y = 0,   relative = true }), { description = "resize left (-50)",  repeating = true })
bind(M .. " + SHIFT + right", hl.dsp.window.resize({ x = 50,  y = 0,   relative = true }), { description = "resize right (+50)", repeating = true })
bind(M .. " + SHIFT + up",    hl.dsp.window.resize({ x = 0,   y = -50, relative = true }), { description = "resize up (-50)",    repeating = true })
bind(M .. " + SHIFT + down",  hl.dsp.window.resize({ x = 0,   y = 50,  relative = true }), { description = "resize down (+50)",  repeating = true })

-- Move windows
bind(M .. " + CTRL + left",  hl.dsp.window.move({ direction = "left" }),  { description = "move window left" })
bind(M .. " + CTRL + right", hl.dsp.window.move({ direction = "right" }), { description = "move window right" })
bind(M .. " + CTRL + up",    hl.dsp.window.move({ direction = "up" }),    { description = "move window up" })
bind(M .. " + CTRL + down",  hl.dsp.window.move({ direction = "down" }),  { description = "move window down" })

-- Swap windows
bind(M .. " + ALT + left",  hl.dsp.window.swap({ direction = "left" }),  { description = "swap window left" })
bind(M .. " + ALT + right", hl.dsp.window.swap({ direction = "right" }), { description = "swap window right" })
bind(M .. " + ALT + up",    hl.dsp.window.swap({ direction = "up" }),    { description = "swap window up" })
bind(M .. " + ALT + down",  hl.dsp.window.swap({ direction = "down" }),  { description = "swap window down" })

-- Groups
bind(M .. " + G",           hl.dsp.group.toggle(), { description = "toggle group" })
bind(M .. " + Tab",         hl.dsp.group.next(),   { description = "next window in group" })
bind(M .. " + CTRL + Tab",  hl.dsp.group.next(),   { description = "next window in group" })
bind(M .. " + SHIFT + Tab", hl.dsp.group.prev(),   { description = "previous window in group" })
bind(M .. " + CTRL + K",    hl.dsp.window.move({ into_group = "l" }),    { description = "move window into the group on the left" })
bind(M .. " + CTRL + L",    hl.dsp.window.move({ into_group = "r" }),    { description = "move window into the group on the right" })
bind(M .. " + CTRL + H",    hl.dsp.window.move({ out_of_group = true }), { description = "move window out of its group" })

-- Move focus
bind(M .. " + left",  hl.dsp.focus({ direction = "left" }),  { description = "focus left" })
bind(M .. " + right", hl.dsp.focus({ direction = "right" }), { description = "focus right" })
bind(M .. " + up",    hl.dsp.focus({ direction = "up" }),    { description = "focus up" })
bind(M .. " + down",  hl.dsp.focus({ direction = "down" }),  { description = "focus down" })

-- Special workspace (scratchpad)
bind(M .. " + SHIFT + U", hl.dsp.window.move({ workspace = "special" }), { description = "move to special workspace" })
bind(M .. " + U",         hl.dsp.workspace.toggle_special(),            { description = "toggle special workspace" })

-- Workspaces 1-10 on the number row. Bound by keysym ("1".."0"), not by
-- keycode ("code:10".."code:19") as before: binds resolve against the FIRST
-- layout in input.kb_layout unless resolve_binds_by_sym is set, so on us/es/ru
-- both forms hit the same physical keys - but `hyprctl binds` cannot report a
-- keycode for a Lua bind, and the cheat sheet (SUPER H / SUPER SHIFT K) would
-- list these 30 binds with an empty key.
for i = 1, 10 do
    local key = tostring(i % 10) -- 10 -> the "0" key
    bind(M .. " + " .. key,             hl.dsp.focus({ workspace = tostring(i) }),                       { description = "workspace " .. i })
    bind(M .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = tostring(i) }),                 { description = "move to workspace " .. i })
    bind(M .. " + CTRL + " .. key,      hl.dsp.window.move({ workspace = tostring(i), follow = false }), { description = "move silently to workspace " .. i })
end
bind(M .. " + SHIFT + bracketleft",  hl.dsp.window.move({ workspace = "-1" }),                { description = "move to previous workspace" })
bind(M .. " + SHIFT + bracketright", hl.dsp.window.move({ workspace = "+1" }),                { description = "move to next workspace" })
bind(M .. " + CTRL + bracketleft",   hl.dsp.window.move({ workspace = "-1", follow = false }), { description = "move silently to previous workspace" })
bind(M .. " + CTRL + bracketright",  hl.dsp.window.move({ workspace = "+1", follow = false }), { description = "move silently to next workspace" })

-- Scroll through existing workspaces
bind(M .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "next workspace" })
bind(M .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "previous workspace" })
bind(M .. " + period",     hl.dsp.focus({ workspace = "e+1" }), { description = "next workspace" })
bind(M .. " + comma",      hl.dsp.focus({ workspace = "e-1" }), { description = "previous workspace" })

-- Move/resize windows with SUPER + LMB/RMB and dragging (mouse:272 = left, 273 = right)
bind(M .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "move window" })
bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "resize window" })
