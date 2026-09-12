-- Default monitor profile. MonitorProfiles.sh copies a file from this directory
-- over ~/.config/hypr/monitors.lua. https://wiki.hypr.land/Configuring/Core/Monitors/
-- `hyprctl monitors` lists names, modes and positions.

-- Catch-all rule for any monitor without its own rule. mode can be
-- "preferred", "highrr" (highest refresh rate) or "highres" (highest resolution).
hl.monitor({ output = "", mode = "highres", position = "auto", scale = 1 })

-- Examples:
-- hl.monitor({ output = "eDP-1",    mode = "preferred",     position = "auto", scale = 1 })
-- hl.monitor({ output = "eDP-1",    mode = "2560x1440@165", position = "0x0",  scale = 1 })
-- hl.monitor({ output = "DP-3",     mode = "1920x1080@240", position = "auto", scale = 1 })
-- hl.monitor({ output = "HDMI-A-1", mode = "preferred",     position = "auto", scale = 1 })
-- QEMU-KVM, virtualbox or vmware:
-- hl.monitor({ output = "Virtual-1", mode = "1920x1080@60", position = "auto", scale = 1 })
-- disable a monitor:
-- hl.monitor({ output = "name", disabled = true })
-- mirror:
-- hl.monitor({ output = "DP-3", mode = "1920x1080@60", position = "0x0", scale = 1, mirror = "DP-2" })
-- hl.monitor({ output = "",     mode = "preferred", position = "auto", scale = 1, mirror = "eDP-1" })
-- 10 bit (border colours are 8 bit; some screen capture (OBS) may render black):
-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1, bitdepth = 10 })
-- hl.monitor({ output = "eDP-1", transform = 0 })
-- hl.monitor({ output = "eDP-1", reserved_area = { top = 10, right = 10, bottom = 10, left = 49 } })
