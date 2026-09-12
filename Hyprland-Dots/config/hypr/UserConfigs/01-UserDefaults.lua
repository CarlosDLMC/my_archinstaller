-- Your default apps and search engine.
--
-- Keep this file PURE DATA (no hl.* calls): besides Hyprland, the shell scripts
-- Quick_Settings.sh and RofiSearch.sh read it with the `lua` interpreter.
-- $EDITOR is exported from configs/ENVariables.lua using `editor` below.

return {
    editor        = "vim",    -- default editor ($EDITOR); reboot to take effect
    term          = "foot",   -- terminal (also used by the Quick Settings menu)
    files         = "thunar", -- file manager
    search_engine = "https://www.google.com/search?q={}", -- Rofi Search (SUPER S)
}
