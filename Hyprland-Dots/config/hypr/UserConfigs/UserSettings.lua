-- /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
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
