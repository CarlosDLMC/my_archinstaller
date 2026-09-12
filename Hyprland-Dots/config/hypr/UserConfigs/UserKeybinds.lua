-- Your own keybinds. Check configs/Keybinds.lua to avoid conflicts; see also
-- configs/Laptops.lua. https://wiki.hypr.land/Configuring/Core/Binds/
--
-- To REMAP an existing default, unbind it first with the exact same key string
-- (case-insensitive, spaces ignored), then bind it again:
--   hl.unbind("SUPER + Return")
--   hl.bind("SUPER + Return", hl.dsp.exec_cmd("ghostty"), { description = "Open terminal" })
-- Always add a description: the keybind search (SUPER SHIFT K) and the cheat
-- sheet (SUPER H) list live binds by description.

local V    = require("configs.Vars")
local M    = V.mainMod
local U    = V.UserScripts
local exec = hl.dsp.exec_cmd
local bind = hl.bind

-- Workspace switching with Ctrl+Alt+Arrows (like a 3-finger swipe)
bind("CTRL + ALT + left",  hl.dsp.focus({ workspace = "r-1" }), { description = "previous workspace" })
bind("CTRL + ALT + right", hl.dsp.focus({ workspace = "r+1" }), { description = "next workspace" })

-- Custom application launchers
bind(M .. " + T", exec("Telegram"),  { description = "open telegram" })
bind(M .. " + R", exec("rustrover"), { description = "open RustRover" })
bind("CTRL + " .. M .. " + F8", exec([[notify-send -t 1500 -i audio-input-microphone "Handy" "Toggling transcription" && handy --toggle-transcription]]), { description = "Handy toggle transcription" })

-- Passthrough keyboard into a VM
-- bind(M .. " + ALT + P", hl.dsp.submap("passthru"))
-- hl.define_submap("passthru", function()
--     bind(M .. " + ALT + P", hl.dsp.submap("reset"))
-- end)

-- Move ALL windows of the current workspace into another workspace
-- (SUPER ALT + number). --follow also jumps to the target.
for i = 1, 10 do
    bind(M .. " + ALT + " .. (i % 10), exec(U .. "/MoveWorkspaceWindows.py " .. i .. " --follow"), { description = "move whole workspace to " .. i })
end
