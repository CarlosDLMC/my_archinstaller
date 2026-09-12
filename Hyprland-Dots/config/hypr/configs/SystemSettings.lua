-- /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
-- Default Hyprland settings. Put your own overrides in UserConfigs/UserSettings.lua
-- (loaded after this file) - the last assignment of an option wins.
-- https://wiki.hypr.land/Configuring/Core/Config-options/
-- Decorations and colours are in UserConfigs/UserDecorations.lua.

local V = require("configs.Vars")

hl.config({
    dwindle = {
        preserve_split = true,
        -- smart_split = true,
        special_scale_factor = 0.8,
    },

    master = {
        new_status = "master",
        new_on_top = true,
        mfact      = 0.5,
    },

    general = {
        resize_on_border = true,
        layout = "dwindle",
    },

    input = {
        -- SwitchKeyboardLayout.sh reads the kb_layout line below, keep it on one line
        kb_layout  = "us,es,ru",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",
        repeat_rate  = 50,
        repeat_delay = 300,
        sensitivity  = 0,     -- mouse sensitivity
        -- accel_profile = "", -- flat / adaptive / empty = libinput default
        numlock_by_default = true,
        left_handed  = false,
        follow_mouse = 1,
        float_switch_override_focus = false,
        touchpad = {
            disable_while_typing    = true,
            natural_scroll          = true,
            clickfinger_behavior    = false,
            middle_button_emulation = false,
            tap_to_click            = true,
            drag_lock               = false,
        },
        -- touchscreens
        touchdevice = {
            enabled = true,
        },
        -- tablets, see the wiki for the variables
        tablet = {
            transform   = 0,
            left_handed = false,
        },
    },

    gestures = {
        workspace_swipe_distance           = 500,
        workspace_swipe_invert             = true,
        workspace_swipe_min_speed_to_force = 30,
        workspace_swipe_cancel_ratio       = 0.5,
        workspace_swipe_create_new         = true,
        workspace_swipe_forever            = true,
        -- workspace_swipe_use_r = true, -- swipe right always creates a new workspace
    },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        vrr = 2,
        mouse_move_enables_dpms = true,
        enable_swallow = false,
        swallow_regex  = "^(foot)$",
        focus_on_activate = false,
        initial_workspace_tracking = 0,
        middle_click_paste = false,
        enable_anr_dialog = true, -- Application Not Responding dialog
        anr_missed_pings  = 15,   -- ANR threshold; the default of 1 is too low
        allow_session_lock_restore = true, -- prevent lockscreen crash when resuming from suspend
    },

    -- opengl = { nvidia_anti_flicker = true },

    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles   = true,
        pass_mouse_when_bound    = false,
    },

    -- helps when scaling and not pixelating
    xwayland = {
        enabled = true,
        force_zero_scaling = true,
    },

    render = {
        direct_scanout = 0,
    },

    cursor = {
        sync_gsettings_theme = true,
        no_hardware_cursors  = 2, -- 1 to disable hardware cursors
        enable_hyprcursor    = false,
        warp_on_change_workspace = 2,
        no_warps = true,
    },
})

---- Trackpad gestures ----
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
-- 4-finger swipe up/down: zoom the desktop in/out (replaces the old
-- `hyprctl keyword cursor:zoom_factor` shell one-liners)
hl.gesture({ fingers = 4, direction = "up",   action = V.zoom_by(1.5) })
hl.gesture({ fingers = 4, direction = "down", action = V.zoom_by(1 / 1.5) })
-- 3-finger swipe up: desktop overview
hl.gesture({ fingers = 3, direction = "up", action = function() hl.exec_cmd(V.scriptsDir .. "/OverviewToggle.sh") end })
