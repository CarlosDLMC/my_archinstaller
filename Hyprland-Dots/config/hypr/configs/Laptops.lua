-- /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
-- Laptop keys and touchpad. Addendum to Keybinds.lua.

local V    = require("configs.Vars")
local M    = V.mainMod
local S    = V.scriptsDir
local exec = hl.dsp.exec_cmd
local bind = hl.bind

-- Touchpad device name as Hyprland reports it (`hyprctl devices`, "mice"
-- section). TouchPad.sh (XF86TouchpadToggle) finds the touchpad through udev
-- at runtime, so it does not depend on this value.
local Touchpad_Device = "synaptics-tm3276-022"

bind("XF86KbdBrightnessDown", exec(S .. "/BrightnessKbd.sh --dec"), { description = "decrease keyboard brightness", repeating = true })
bind("XF86KbdBrightnessUp",   exec(S .. "/BrightnessKbd.sh --inc"), { description = "increase keyboard brightness", repeating = true })
bind("XF86Launch1",           exec("rog-control-center"),           { description = "ASUS Armoury Crate" })
bind("XF86Launch3",           exec("asusctl led-mode -n"),          { description = "switch keyboard RGB profile (FN+F4)" })
bind("XF86Launch4",           exec("asusctl profile -n"),           { description = "cycle fan profile (FN+F5)" })
bind("XF86MonBrightnessDown", exec(S .. "/Brightness.sh --dec"),    { description = "decrease monitor brightness", repeating = true })
bind("XF86MonBrightnessUp",   exec(S .. "/Brightness.sh --inc"),    { description = "increase monitor brightness", repeating = true })
bind("XF86TouchpadToggle",    exec(S .. "/TouchPad.sh"),            { description = "toggle touchpad" })

-- Screenshots on F6 (keyboards without a PrtSc key)
bind(M .. " + F6",         exec(S .. "/ScreenShot.sh --now"),    { description = "screenshot" })
bind(M .. " + SHIFT + F6", exec(S .. "/ScreenShot.sh --area"),   { description = "screenshot (area)" })
bind(M .. " + CTRL + F6",  exec(S .. "/ScreenShot.sh --in5"),    { description = "screenshot (5 secs delay)" })
bind(M .. " + ALT + F6",   exec(S .. "/ScreenShot.sh --in10"),   { description = "screenshot (10 secs delay)" })
bind("ALT + F6",           exec(S .. "/ScreenShot.sh --active"), { description = "screenshot (active window only)" })

hl.device({ name = Touchpad_Device, enabled = true })
