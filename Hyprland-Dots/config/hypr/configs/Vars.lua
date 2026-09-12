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
