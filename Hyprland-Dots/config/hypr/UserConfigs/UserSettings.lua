-- Your Hyprland settings. Loaded after configs/SystemSettings.lua, so anything
-- set here overrides it. https://wiki.hypr.land/Configuring/Core/Config-options/
-- Look at configs/SystemSettings.lua to see how the options are grouped.

-- Right-side Super: remap the Menu / Context-menu key to act as a Super (Win)
-- modifier via XKB. Gives an ergonomic Super under the right hand for workspace
-- switching etc. NOTE: this replaces the key's original context-menu function.
hl.config({
    input = {
        kb_options = "altwin:menu_win",
    },
})

-- Window behaviour from omarchy (omacom/omarchy, default/hypr/looknfeel.lua).
-- focus_on_activate: an app that asks to be activated gets focus, so a link
-- clicked in Telegram brings LibreWolf forward. Apps also ask on new messages to
-- get attention - turn that off in the app (Telegram: Settings > Notifications >
-- "Draw attention to the window"; Slack and ZapZap on Linux never ask).
hl.config({
    general = {
        extend_border_grab_area = 8,
    },
    dwindle = {
        preserve_split = true,
        force_split = 2, -- new windows always split to the right/bottom
    },
    misc = {
        focus_on_activate = true,
        anr_missed_pings = 3,
        on_focus_under_fullscreen = 1,
    },
    cursor = {
        hide_on_key_press = true,
        warp_on_change_workspace = 1,
    },
    binds = {
        hide_special_on_workspace_change = true,
    },
})
