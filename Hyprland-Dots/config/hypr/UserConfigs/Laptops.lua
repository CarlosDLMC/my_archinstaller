-- /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
-- Your laptop-specific binds. Addendum to configs/Laptops.lua and Keybinds.lua.
-- https://wiki.hypr.land/Configuring/Core/Binds/Switches/

local V = require("configs.Vars")

-- Disable the laptop screen when the lid closes (from the wiki).
-- hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd([[hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1 })']]), { locked = true })
-- hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd([[hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })']]), { locked = true })

-- WARNING! Caveats of the lid method: you have to re-pick a wallpaper (SUPER W),
-- and sometimes the laptop screen does not come back until the external monitor
-- is re-connected. One workaround: make sure the lid is OPEN before shutdown.
--
-- Variant that persists across reloads by writing UserConfigs/LaptopDisplay.lua
-- (so the internal screen does not wake up during e.g. a wallpaper change):
-- hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd([[echo 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1 })' > ]] .. V.UserConfigs .. "/LaptopDisplay.lua"), { locked = true })
-- hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd([[echo 'hl.monitor({ output = "eDP-1", disabled = true })' > ]] .. V.UserConfigs .. "/LaptopDisplay.lua"), { locked = true })
