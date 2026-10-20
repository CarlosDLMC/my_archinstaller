-- Ctrl+Delete as foot sends it. foot.ini's [text-bindings] turns it into Alt+D
-- (Esc d, readline's "delete the next word") for every program, and nvim
-- leaves an unmapped Alt+D to mean Esc then d: insert mode ended with a delete
-- pending, so the next keys ran as commands (a word starting with "d" deleted
-- the line). Here it deletes the next word, in every mode it can reach.
--
-- Installed by install-scripts/neovim.sh from assets/nvim/foot-keys.lua and
-- overwritten on every run, like colors/pycharm-dark.lua.

-- Insert: to the start of the next word, like Ctrl+Delete in other editors
-- (the black-hole register keeps what you yanked). At the end of a line it
-- joins the next one, as Delete does there.
vim.keymap.set("i", "<M-d>", function()
  if vim.fn.col(".") > #vim.fn.getline(".") then
    return "<Del>"
  end
  return '<C-o>"_dw'
end, { expr = true, desc = "Delete the next word" })

-- Normal and visual: the same word, or the selection.
vim.keymap.set("n", "<M-d>", '"_dw', { desc = "Delete the next word" })
vim.keymap.set("x", "<M-d>", '"_d', { desc = "Delete the selection" })

-- The : line: the text after the cursor up to the end of the next word.
vim.keymap.set("c", "<M-d>", function()
  local line, pos = vim.fn.getcmdline(), vim.fn.getcmdpos()
  local rest = line:sub(pos)
  local cut = rest:match("^%s*[%w_]+") or rest:match("^%s*[^%w_%s]+") or rest:match("^%s+") or ""
  vim.fn.setcmdline(line:sub(1, pos - 1) .. rest:sub(#cut + 1), pos)
end, { desc = "Delete the next word" })
