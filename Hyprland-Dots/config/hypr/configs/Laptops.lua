-- Laptop keys and touchpad. Addendum to Keybinds.lua.

local V    = require("configs.Vars")
local M    = V.mainMod
local S    = V.scriptsDir
local exec = hl.dsp.exec_cmd
local bind = hl.bind

bind("XF86KbdBrightnessDown", exec(S .. "/BrightnessKbd.sh --dec"), { description = "decrease keyboard brightness", repeating = true })
bind("XF86KbdBrightnessUp",   exec(S .. "/BrightnessKbd.sh --inc"), { description = "increase keyboard brightness", repeating = true })
bind("XF86Launch1",           exec("rog-control-center"),           { description = "ASUS Armoury Crate" })
-- asusctl 6.x spellings. The 5.x ones these keys used (`led-mode -n`,
-- `profile -n`) are rejected outright by 6.x ("Unrecognized argument").
bind("XF86Launch3",           exec("asusctl aura effect --next-mode"), { description = "switch keyboard RGB profile (FN+F4)" })
bind("XF86Launch4",           exec("asusctl profile next"),         { description = "cycle fan profile (FN+F5)" })
bind("XF86MonBrightnessDown", exec(S .. "/Brightness.sh --dec"),    { description = "decrease monitor brightness", repeating = true })
bind("XF86MonBrightnessUp",   exec(S .. "/Brightness.sh --inc"),    { description = "increase monitor brightness", repeating = true })
bind("XF86TouchpadToggle",    exec(S .. "/TouchPad.sh"),            { description = "toggle touchpad" })

-- Screenshots on F6 (keyboards without a PrtSc key)
bind(M .. " + F6",         exec(S .. "/ScreenShot.sh --now"),    { description = "screenshot" })
bind(M .. " + SHIFT + F6", exec(S .. "/ScreenShot.sh --area"),   { description = "screenshot (area)" })
bind(M .. " + CTRL + F6",  exec(S .. "/ScreenShot.sh --in5"),    { description = "screenshot (5 secs delay)" })
bind(M .. " + ALT + F6",   exec(S .. "/ScreenShot.sh --in10"),   { description = "screenshot (10 secs delay)" })
bind("ALT + F6",           exec(S .. "/ScreenShot.sh --active"), { description = "screenshot (active window only)" })

-- What TouchPad.sh last set, so a config reload (every save of a .lua here)
-- does not turn a switched-off touchpad back on behind its back - the next
-- press then "enabled" it again and did nothing. Applied to the touchpads
-- TouchPad.sh found through udev and wrote down next to the state: this file
-- used to name the T480's touchpad, so on any other laptop the state was put
-- back on nothing. Neither file (both live on the runtime tmpfs) means no
-- toggle yet this session, and the touchpad keeps its default: on.
local rt = os.getenv("XDG_RUNTIME_DIR") or ""
local tp_enabled = true
local tp_status = io.open(rt .. "/touchpad.status", "r")
if tp_status then
    tp_enabled = tp_status:read("l") ~= "false"
    tp_status:close()
end
local tp_devices = io.open(rt .. "/touchpad.devices", "r")
if tp_devices then
    for name in tp_devices:lines() do
        if name ~= "" then
            hl.device({ name = name, enabled = tp_enabled })
        end
    end
    tp_devices:close()
end
