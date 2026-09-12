-- Hyprland main config, Lua format (hyprlang .conf is deprecated since 0.55 and
-- removed in 0.57). Wiki: https://wiki.hypr.land/Configuring/
--
-- Each require() runs in its own protected scope, so an error in one file does
-- not stop the others from loading. Load order matters where the same option is
-- set twice: the LAST assignment wins, so user files come after the defaults.

local V = require("configs.Vars")

-- Initial boot script: applies wallpaper, theming etc. on the first login only.
-- It guards itself with ~/.config/hypr/.initial_startup_done - as long as that
-- marker exists it does nothing, so leave both the script and the marker alone.
hl.on("hyprland.start", function()
    hl.exec_cmd(V.hypr .. "/initial-boot.sh")
end)

-- Pre-configured keybinds
require("configs.Keybinds")

-- Startup apps: defaults, then user additions
require("configs.Startup_Apps")
require("UserConfigs.Startup_Apps")

-- Environment variables: defaults, then user overrides
require("configs.ENVariables")
require("UserConfigs.ENVariables")

-- Laptop related
require("configs.Laptops")
require("UserConfigs.Laptops")
require("UserConfigs.LaptopDisplay")

-- Window rules and layer rules: defaults, then user additions
require("configs.WindowRules")
require("UserConfigs.WindowRules")

-- Hyprland settings
require("configs.SystemSettings")      -- defaults
require("UserConfigs.UserDecorations") -- decorations (wallust colours)
require("UserConfigs.UserAnimations")  -- animations
require("UserConfigs.UserKeybinds")    -- your own keybinds
require("UserConfigs.UserSettings")    -- your overrides of SystemSettings

-- nwg-displays writes these two. Either may be missing, hence pcall.
pcall(require, "monitors")
pcall(require, "workspaces")

-- Notifications (dunst) should pop without a layer animation.
hl.layer_rule({ name = "no_anim_notifications",     match = { namespace = "dunst" },         no_anim = true })
hl.layer_rule({ name = "no_anim_notifications_alt", match = { namespace = "notifications" }, no_anim = true })
