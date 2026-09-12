-- Shared paths, the main modifier and small helpers. Every config file does
--   local V = require("configs.Vars")
-- This replaces the old $mainMod / $scriptsDir / $UserScripts hyprlang variables.

local HOME = os.getenv("HOME")
local hypr = HOME .. "/.config/hypr"

local V = {
    home        = HOME,
    hypr        = hypr,
    configs     = hypr .. "/configs",
    UserConfigs = hypr .. "/UserConfigs",
    scriptsDir  = hypr .. "/scripts",
    UserScripts = hypr .. "/UserScripts",
    mainMod     = "SUPER",
}

-- Is this a laptop?
--
-- Asked so the laptop-only binds are not loaded on a desktop, where they bind
-- keys the machine does not have (XF86MonBrightness*, XF86KbdBrightness*,
-- XF86TouchpadToggle) and name a touchpad device that does not exist. None of
-- that errors - it just quietly clutters the keybind cheat sheet with entries
-- that do nothing.
--
-- A battery is the reliable signal: /sys/class/power_supply/BAT* exists on a
-- laptop and not on a desktop. DMI chassis_type is the fallback, since a
-- laptop running on a dead/removed battery would otherwise look like a desktop
-- (types 8,9,10,11,14 are the portable ones).
local function detect_laptop()
    local bat = io.popen("ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1")
    if bat then
        local found = bat:read("*l")
        bat:close()
        if found and found ~= "" then return true end
    end
    local f = io.open("/sys/class/dmi/id/chassis_type", "r")
    if f then
        local t = tonumber(f:read("*l"))
        f:close()
        if t and (t == 8 or t == 9 or t == 10 or t == 11 or t == 14) then return true end
    end
    return false
end

V.is_laptop = detect_laptop()

-- Returns a function that multiplies cursor.zoom_factor by `mult` (never below 1).
-- Used by the SUPER+ALT+scroll binds and the 4-finger swipe gestures; replaces
-- the old `hyprctl keyword cursor:zoom_factor "$(hyprctl getoption ... | awk ...)"`.
function V.zoom_by(mult)
    return function()
        local f = hl.get_config("cursor.zoom_factor")
        if type(f) ~= "number" or f < 1 then f = 1 end
        hl.config({ cursor = { zoom_factor = math.max(1, f * mult) } })
    end
end

return V
