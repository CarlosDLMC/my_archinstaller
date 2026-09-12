-- Environment variables. https://wiki.hypr.land/Configuring/Core/Environment-variables/
-- hl.env(NAME, VALUE) - set before the display server initialises.
-- Your default editor lives in UserConfigs/01-UserDefaults.lua (exported as $EDITOR here).

local D = require("UserConfigs.01-UserDefaults")

hl.env("EDITOR", D.editor)

-- Locale for time/date formatting (Monday start, DD/MM/YYYY, 24-hour)
hl.env("LC_TIME", "ru_RU.UTF-8")

-- Version of the upstream dotfiles this config originally started from
hl.env("DOTS_VERSION", "2.3.19")

---- Toolkit backend ----
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("CLUTTER_BACKEND", "wayland")
-- Run SDL2 applications on Wayland. Remove or set to x11 if games that ship
-- older SDL versions misbehave.
-- hl.env("SDL_VIDEODRIVER", "wayland")

---- XDG ----
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")

---- Qt ----
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

---- hyprland-qt-support ----
hl.env("QT_QUICK_CONTROLS_STYLE", "org.hyprland.style")

---- XWayland scale fix (set the same value as your monitor scale; 1 = 100%) ----
-- https://wiki.hypr.land/Configuring/Extra/XWayland/
hl.env("GDK_SCALE", "1")
hl.env("QT_SCALE_FACTOR", "1")

---- Cursor (needs the hyprcursor version of the theme) ----
-- hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
-- hl.env("HYPRCURSOR_SIZE", "24")

---- Firefox ----
hl.env("MOZ_ENABLE_WAYLAND", "1")

---- Electron > 28 (auto picks Wayland if possible, X11 otherwise) ----
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

---- NVIDIA (uncomment when an nvidia GPU is detected) ----
-- https://wiki.hypr.land/Nvidia/
-- hl.env("LIBVA_DRIVER_NAME", "nvidia")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
-- hl.env("NVD_BACKEND", "direct")
-- hl.env("GSK_RENDERER", "ngl")
-- Additional nvidia ENVs, activate with care:
-- hl.env("GBM_BACKEND", "nvidia-drm")
-- hl.env("__GL_GSYNC_ALLOWED", "1")           -- adaptive Vsync
-- hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
-- hl.env("__VK_LAYER_NV_optimus", "NVIDIA_only")
-- hl.env("WLR_DRM_NO_ATOMIC", "1")

---- VM and possibly NVIDIA ----
-- hl.env("LIBGL_ALWAYS_SOFTWARE", "1")        -- software mesa rendering; may crash Hyprland
-- hl.env("WLR_RENDERER_ALLOW_SOFTWARE", "1")

---- nvidia firefox (https://github.com/elFarto/nvidia-vaapi-driver#configuration) ----
-- hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
-- hl.env("EGL_PLATFORM", "wayland")

---- Aquamarine (https://wiki.hypr.land/Configuring/Core/Environment-variables/#aquamarine) ----
-- hl.env("AQ_TRACE", "1")                      -- more verbose logging
-- hl.env("AQ_DRM_DEVICES", "/dev/dri/card1:/dev/dri/card0") -- explicit GPU list, primary first
-- hl.env("AQ_MGPU_NO_EXPLICIT", "1")           -- disable explicit sync on mgpu buffers
-- hl.env("AQ_NO_MODIFIERS", "1")               -- disable modifiers for DRM buffers

---- Hyprland ----
-- hl.env("HYPRLAND_TRACE", "1")                -- more verbose logging
-- hl.env("HYPRLAND_NO_RT", "1")                -- disable realtime priority
-- hl.env("HYPRLAND_NO_SD_NOTIFY", "1")         -- disable sd_notify calls
-- hl.env("HYPRLAND_NO_SD_VARS", "1")           -- disable systemd/dbus env management
