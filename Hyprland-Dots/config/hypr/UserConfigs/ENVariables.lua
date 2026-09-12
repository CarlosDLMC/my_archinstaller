-- Your environment variable overrides. https://wiki.hypr.land/Configuring/Core/Environment-variables/
-- Anything set here wins over configs/ENVariables.lua (loaded after it).
-- The default editor lives in UserConfigs/01-UserDefaults.lua.

---- Qt ----
-- hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
-- hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
-- hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
-- hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

---- XWayland scale fix (match your monitor scale; 1 = 100%, 1.5 = 150%) ----
-- hl.env("GDK_SCALE", "1")
-- hl.env("QT_SCALE_FACTOR", "1")

---- NVIDIA ----
-- hl.env("LIBVA_DRIVER_NAME", "nvidia")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
-- hl.env("NVD_BACKEND", "direct")
-- hl.env("GSK_RENDERER", "ngl")
-- hl.env("GBM_BACKEND", "nvidia-drm")
-- hl.env("__GL_GSYNC_ALLOWED", "1")
-- hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
-- hl.env("__VK_LAYER_NV_optimus", "NVIDIA_only")
-- hl.env("WLR_DRM_NO_ATOMIC", "1")

---- VM and possibly NVIDIA ----
-- hl.env("LIBGL_ALWAYS_SOFTWARE", "1")   -- may crash Hyprland
-- hl.env("WLR_RENDERER_ALLOW_SOFTWARE", "1")

---- nvidia firefox ----
-- hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
-- hl.env("EGL_PLATFORM", "wayland")

---- Aquamarine ----
-- hl.env("AQ_TRACE", "1")
-- hl.env("AQ_DRM_DEVICES", "/dev/dri/card1:/dev/dri/card0")
-- hl.env("AQ_MGPU_NO_EXPLICIT", "1")
-- hl.env("AQ_NO_MODIFIERS", "1")
