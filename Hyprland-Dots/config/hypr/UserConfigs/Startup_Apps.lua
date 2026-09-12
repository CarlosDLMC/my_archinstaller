-- Your own apps to run once at launch. Add hl.exec_cmd(...) calls inside the
-- hyprland.start handler below; a config reload does not re-run them.

local V = require("configs.Vars")

hl.on("hyprland.start", function()
    hl.exec_cmd([[yad --text="\n<span font='72' weight='bold'>TURN ON VPN / PROXY !!!</span>\n" --text-align=center --title="REMINDER" --button="OK":0 --width=900 --height=400 --center --on-top --fixed --undecorated]])

    -- Handy (speech-to-text) autostart is OFF to save RAM - the SUPER + CTRL + F8
    -- keybind in UserKeybinds.lua launches it on demand. Uncomment to autostart it:
    -- handy-start.sh starts it visible until a model has been chosen, hidden after.
    -- hl.exec_cmd(V.UserScripts .. "/handy-start.sh")
end)
