-- /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
-- Window rules and layer rules (vendor defaults).
-- https://wiki.hypr.land/Configuring/Core/Rules/Window-rules/
--
-- match = { class = regex, title = regex, initial_title = regex, tag = "name*" }
-- Prefix a regex with "negative:" to invert it. Rules apply top to bottom and
-- the LAST match wins. UserConfigs/WindowRules.lua is loaded after this file.

local rule = hl.window_rule

---- TAGS: group apps under a tag, then style the tag once ----
local class_tags = {
    browser         = { "^([Ff]irefox|org.mozilla.firefox|[Ff]irefox-esr|[Ff]irefox-bin)$",
                        "^([Gg]oogle-chrome(-beta|-dev|-unstable)?)$",
                        "^(chrome-.+-Default)$", -- Chrome PWAs
                        "^([Cc]hromium)$",
                        "^([Mm]icrosoft-edge(-stable|-beta|-dev|-unstable))$",
                        "^(Brave-browser(-beta|-dev|-unstable)?)$",
                        "^([Tt]horium-browser|[Cc]achy-browser)$",
                        "^(zen-alpha|zen)$" },
    notif           = { "^(swaync-control-center|swaync-notification-window|swaync-client|class)$" },
    ["KooL-Settings"] = { "^(nwg-displays|nwg-look)$" },
    terminal        = { "^(Alacritty|foot)$" },
    email           = { "^([Tt]hunderbird|org.gnome.Evolution)$", "^(eu.betterbird.Betterbird)$" },
    projects        = { "^(codium|codium-url-handler|VSCodium)$", "^(VSCode|code|code-url-handler)$", "^(jetbrains-.+)$" },
    screenshare     = { "^(com.obsproject.Studio)$" },
    im              = { "^([Dd]iscord|[Ww]ebCord|[Vv]esktop)$", "^([Ff]erdium)$", "^([Ww]hatsapp-for-linux)$",
                        "^(ZapZap|com.rtosta.zapzap)$", "^(org.telegram.desktop|io.github.tdesktop_x64.TDesktop)$",
                        "^(teams-for-linux)$", "^(im.riot.Riot|Element)$" },
    games           = { "^(gamescope)$", "^(steam_app_\\d+)$" },
    gamestore       = { "^([Ss]team)$", "^(com.heroicgameslauncher.hgl)$" },
    ["file-manager"] = { "^([Tt]hunar|org.gnome.Nautilus|[Pp]cmanfm-qt)$", "^(app.drey.Warp)$" },
    wallpaper       = { "^([Ww]aytrogen)$" },
    multimedia      = { "^([Aa]udacious)$" },
    multimedia_video = { "^([Mm]pv|vlc)$" },
    settings        = { "^(wihotspot(-gui)?)$", "^([Bb]aobab|org.gnome.[Bb]aobab)$", "^(gnome-disks|wihotspot(-gui)?)$",
                        "^(file-roller|org.gnome.FileRoller)$", "^(nm-applet|nm-connection-editor|blueman-manager)$",
                        "^(pavucontrol|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol)$", "^(qt5ct|qt6ct|[Yy]ad)$",
                        "(xdg-desktop-portal-gtk)", "^(org.kde.polkit-kde-authentication-agent-1)$", "^([Rr]ofi)$" },
    viewer          = { "^(gnome-system-monitor|org.gnome.SystemMonitor|io.missioncenter.MissionCenter)$", "^(evince)$", "^(eog|org.gnome.Loupe)$" },
}
for tag, classes in pairs(class_tags) do
    for _, re in ipairs(classes) do
        rule({ match = { class = re }, tag = "+" .. tag })
    end
end
-- tags matched on the title instead of the class
rule({ match = { title = "^(KooL Quick Cheat Sheet)$" }, tag = "+KooL_Cheat" })
rule({ match = { title = "^(KooL Hyprland Settings)$" }, tag = "+KooL_Settings" })
rule({ match = { title = "^([Ll]utris)$" },              tag = "+gamestore" })
rule({ match = { title = "^(ROG Control)$" },            tag = "+settings" })
rule({ match = { title = "(Kvantum Manager)" },          tag = "+settings" })

rule({ match = { tag = "multimedia_video*" }, no_blur = true })

---- POSITION ----
rule({ match = { tag = "KooL_Cheat*" },   center = true })
rule({ match = { class = "([Tt]hunar)", title = "negative:(.*[Tt]hunar.*)" }, center = true })
rule({ match = { title = "^(ROG Control)$" }, center = true })
rule({ match = { tag = "KooL-Settings*" }, center = true })
rule({ match = { title = "^(Keybindings)$" }, center = true })
rule({ match = { class = "^(pavucontrol|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol)$" }, center = true })
rule({ match = { class = "^([Ww]hatsapp-for-linux|ZapZap|com.rtosta.zapzap)$" }, center = true })
rule({ match = { class = "^([Ff]erdium)$" }, center = true })
rule({ match = { title = "^(Picture-in-Picture)$" }, move = "72% 7%" })

-- idle inhibit for fullscreen apps
-- rule({ match = { fullscreen = true }, idle_inhibit = "fullscreen" })

-- move to workspace
-- rule({ match = { tag = "email*" },   workspace = "1" })
-- rule({ match = { tag = "browser*" }, workspace = "2" })
-- rule({ match = { class = "^([Tt]hunar)$" }, workspace = "3" })
-- rule({ match = { tag = "projects*" }, workspace = "3" })
-- rule({ match = { tag = "gamestore*" }, workspace = "5" })
-- rule({ match = { tag = "im*" },      workspace = "7" })
-- rule({ match = { tag = "games*" },   workspace = "8" })
-- move to workspace (silent)
-- rule({ match = { tag = "screenshare*" }, workspace = "4 silent" })
-- rule({ match = { class = "^(virt-manager)$" }, workspace = "6 silent" })
-- rule({ match = { class = "^(.virt-manager-wrapped)$" }, workspace = "6 silent" })
-- rule({ match = { tag = "multimedia*" }, workspace = "9 silent" })

---- FLOAT ----
rule({ match = { tag = "KooL_Cheat*" },    float = true })
rule({ match = { tag = "wallpaper*" },     float = true })
rule({ match = { tag = "settings*" },      float = true })
rule({ match = { tag = "viewer*" },        float = true })
rule({ match = { tag = "KooL-Settings*" }, float = true })
rule({ match = { class = "([Zz]oom|onedriver|onedriver-launcher)$" }, float = true })
rule({ match = { class = "(org.gnome.Calculator)", title = "(Calculator)" }, float = true })
rule({ match = { class = "^(mpv|com.github.rafostar.Clapper)$" }, float = true })
rule({ match = { class = "^([Qq]alculate-gtk)$" }, float = true })
-- rule({ match = { class = "^([Ww]hatsapp-for-linux|ZapZap|com.rtosta.zapzap)$" }, float = true })
rule({ match = { class = "^([Ff]erdium)$" }, float = true })
rule({ match = { title = "^(Picture-in-Picture)$" }, float = true })

---- float popups and dialogs ----
rule({ match = { title = "^(Authentication Required)$" }, float = true, center = true })
rule({ match = { class = "(codium|codium-url-handler|VSCodium)", title = "negative:(.*codium.*|.*VSCodium.*)" }, float = true })
rule({ match = { class = "^(com.heroicgameslauncher.hgl)$", title = "negative:(Heroic Games Launcher)" }, float = true })
rule({ match = { class = "^([Ss]team)$", title = "negative:^([Ss]team)$" }, float = true })
rule({ match = { class = "([Tt]hunar)", title = "negative:(.*[Tt]hunar.*)" }, float = true })
rule({ match = { title = "^(Add Folder to Workspace)$" }, float = true, size = "70% 60%", center = true })
rule({ match = { title = "^(Save As)$" },                 float = true, size = "70% 60%", center = true })
rule({ match = { initial_title = "(Open Files)" },        float = true, size = "70% 60%" })
rule({ match = { title = "^(SDDM Background)$" },         float = true, center = true, size = "16% 12%" }) -- KooL's YAD for the SDDM background

---- OPACITY ----
rule({ match = { tag = "terminal*" }, opacity = "0.9 0.7" })

---- SIZE ----
rule({ match = { tag = "KooL_Cheat*" }, size = "65% 90%" })
rule({ match = { tag = "wallpaper*" },  size = "70% 70%" })
rule({ match = { tag = "settings*" },   size = "70% 70%" })
rule({ match = { class = "^([Ww]hatsapp-for-linux|ZapZap|com.rtosta.zapzap)$" }, size = "60% 70%" })
rule({ match = { class = "^([Ff]erdium)$" }, size = "60% 70%" })
-- rule({ match = { title = "^(Picture-in-Picture)$" }, size = "25% 25%" })

---- PINNING / extras ----
rule({ match = { title = "^(Picture-in-Picture)$" }, pin = true, keep_aspect_ratio = true })

---- BLUR & FULLSCREEN ----
rule({ match = { tag = "games*" }, no_blur = true, fullscreen = true })

-- Do not steal focus for the popups IntelliJ products open on hover
rule({ match = { class = "^(jetbrains-*)" }, no_initial_focus = true })
rule({ match = { title = "^(wind.*)$" },     no_initial_focus = true })

-- rule({ match = { fullscreen = true }, border_color = "rgb(EE4B55) rgb(880808)" })
-- rule({ match = { float = true },      border_color = "rgb(282737) rgb(1E1D2D)" })

---- LAYER RULES ----
hl.layer_rule({ match = { namespace = "rofi" },                blur = true, ignore_alpha = 1 })
hl.layer_rule({ match = { namespace = "notifications" },       blur = true, ignore_alpha = 1 })
hl.layer_rule({ match = { namespace = "quickshell:overview" }, blur = true, ignore_alpha = 0.5 })
