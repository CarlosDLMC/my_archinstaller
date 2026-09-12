-- NOTE: THIS FILE IS NOT LOADED by hyprland.lua. It is only a guide.
-- The file Hyprland loads is ~/.config/hypr/workspaces.lua, which nwg-displays
-- overwrites - use nwg-displays to handle your workspace rules.
-- https://wiki.hypr.land/Configuring/Core/Rules/Workspace-rules/

-- Assigning workspaces to monitors:
-- hl.workspace_rule({ workspace = "1", monitor = "eDP-1" })
-- hl.workspace_rule({ workspace = "5", monitor = "DP-2" })

-- Example rules (from the wiki):
-- hl.workspace_rule({ workspace = "3", no_rounding = true, decorate = false })
-- hl.workspace_rule({ workspace = "name:coding", no_rounding = true, decorate = false, gaps_in = 0, gaps_out = 0, no_border = true, monitor = "DP-1" })
-- hl.workspace_rule({ workspace = "8", border_size = 8 })
-- hl.workspace_rule({ workspace = "name:Hello", monitor = "DP-1", default = true })
-- hl.workspace_rule({ workspace = "name:gaming", monitor = "desc:Chimei Innolux Corporation 0x150C", default = true })
-- hl.workspace_rule({ workspace = "5", on_created_empty = "[float] firefox" })
-- hl.workspace_rule({ workspace = "special:scratchpad", on_created_empty = "foot" })
