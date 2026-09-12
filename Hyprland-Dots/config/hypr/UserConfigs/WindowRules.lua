-- Your window rules and layer rules. Loaded after configs/WindowRules.lua, so
-- these win over the defaults. https://wiki.hypr.land/Configuring/Core/Rules/Window-rules/

local rule = hl.window_rule

rule({ match = { class = "^(com.gabm.satty)$" }, float = true })

-- Float all JetBrains windows, then tile back the main editor
rule({ match = { class = "(jetbrains-.+)" }, float = true })
rule({ match = { class = "(jetbrains-.+)", title = "(.*\\[~/.*)" }, tile = true })

-- Blur the wallpaper behind the bar. The bar draws no background of its own,
-- so with no ignore_alpha rule this blurs the whole strip it occupies - the
-- bar reads as a soft band rather than raw wallpaper. Needs the explicit
-- namespace set in ~/.config/quickshell/bar/shell.qml.
hl.layer_rule({ match = { namespace = "quickshell:bar" }, blur = true })

-- Thunar's rename, properties, bulk-rename and file-transfer dialogs are separate
-- toplevels carrying the same class as the browser window, so they tile and take
-- half the screen. Thunar has no in-view rename - the dialog is the only way it
-- renames - so float it instead. Only the browser window's title ends in
-- "- Thunar", so the negative title match leaves that one tiled.
rule({ match = { class = "^([Tt]hunar)$", title = "negative:(.* - Thunar$)" }, float = true, center = true })
