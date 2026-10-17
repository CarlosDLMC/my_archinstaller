-- Your own apps to run once at launch. Add hl.exec_cmd(...) calls inside the
-- hyprland.start handler below; a config reload does not re-run them.

local V = require("configs.Vars")

hl.on("hyprland.start", function()
    -- No tunnel at login: a red ТРЕВОГА notification that stays until it is
    -- clicked away, or turns into a short confirmation once a tunnel comes up.
    hl.exec_cmd("'" .. V.UserScripts .. "/vpn-reminder.sh'")

    -- Handy (speech-to-text) autostart is OFF to save RAM - the SUPER + CTRL + F8
    -- keybind in UserKeybinds.lua launches it on demand. Uncomment to autostart it:
    -- handy-start.sh starts it visible until a model has been chosen, hidden after.
    -- hl.exec_cmd(V.UserScripts .. "/handy-start.sh")
end)
