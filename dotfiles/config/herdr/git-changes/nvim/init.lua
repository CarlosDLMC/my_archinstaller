-- git-changes: a PyCharm-style Commit window for one git worktree, run by the
-- herdr plugin of the same name (ALT+G). Not a normal nvim config: it builds
-- one screen - the changed files (top), the commit message and the Commit
-- buttons (bottom) - and opens a side-by-side diff in floating windows over
-- it: HEAD on the left, the working file on the right (editable, saved like
-- PyCharm saves: when you leave the diff or press Ctrl+S).
-- Colours are PyCharm's "Dark" (new UI) scheme, read from the installed IDE:
-- themes/expUI/expUI_darkScheme.xml + its Darcula parent (DIFF_*).

local api, fn = vim.api, vim.fn
local ROOT = vim.env.GIT_CHANGES_ROOT or fn.getcwd()
ROOT = (ROOT:gsub("/+$", ""))
if ROOT == "" then ROOT = "/" end

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------
local o = vim.opt
o.termguicolors = true
o.mouse = "a"
o.mousemodel = "extend"
o.mousescroll = "ver:3,hor:6"
o.swapfile = false
o.hidden = true
o.autoread = true
o.laststatus = 3
o.cmdheight = 0
o.showmode = false
o.ruler = false
o.showcmd = false
o.shortmess:append("IsFWcCO")
o.fillchars = { eob = " ", diff = " ", fold = " ", horiz = "─", horizup = "─", horizdown = "─", vert = "│", vertleft = "│", vertright = "│", verthoriz = "│" }
o.diffopt = "internal,filler,closeoff,algorithm:histogram,indent-heuristic,linematch:60,inline:word"
o.splitbelow = true
o.wrap = false
o.scrolloff = 3
o.updatetime = 400
o.timeoutlen = 600
o.ttimeoutlen = 10
o.undofile = false
o.confirm = false

-- Reuse the normal nvim's treesitter parsers + queries (read-only) and its
-- file icons, if they are installed.
local data = fn.expand("~/.local/share/nvim")
for _, p in ipairs({ data .. "/site", data .. "/lazy/mini.icons" }) do
  if fn.isdirectory(p) == 1 then o.rtp:append(p) end
end
local icons_ok, icons = pcall(require, "mini.icons")
if icons_ok then pcall(icons.setup, {}) end

----------------------------------------------------------------------------
-- Colours (PyCharm Dark)
----------------------------------------------------------------------------
local C = {
  editor = "#1e1f22", panel = "#2b2d30", line = "#393b40", border = "#4e5157",
  text = "#bcbec4", bright = "#dfe1e5", dim = "#6f737a", dim2 = "#868a91", dim3 = "#5a5d63",
  sel = "#2e436e", caret = "#26282e", lnr = "#4b5059", lnrc = "#a1a3ab",
  visual = "#214283", blue6 = "#3574f0", white = "#ffffff",
  -- FILESTATUS_*
  modified = "#70aeff", added = "#73bd79", deleted = "#6f737a", unknown = "#e88f89", conflict = "#de6a66",
  -- DIFF_* backgrounds, and their stripe colours for the changed words
  ins = "#294436", del = "#484a4a", mod = "#385570",
  ins_w = "#447152", del_w = "#656e76", mod_w = "#43698d",
  fill_ins = "#212827", fill_del = "#28292a",
}

local function hl(name, spec) api.nvim_set_hl(0, name, spec) end
local function colours()
  hl("Normal", { fg = C.text, bg = C.panel })
  hl("NormalNC", { fg = C.text, bg = C.panel })
  hl("NormalFloat", { fg = C.text, bg = C.editor })
  hl("FloatBorder", { fg = C.border, bg = C.editor })
  hl("FloatTitle", { fg = C.bright, bg = C.editor, bold = true })
  hl("FloatFooter", { fg = C.dim2, bg = C.editor })
  hl("CursorLine", { bg = C.sel })
  hl("LineNr", { fg = C.lnr })
  hl("CursorLineNr", { fg = C.lnrc })
  hl("WinSeparator", { fg = C.line, bg = C.panel })
  hl("StatusLine", { fg = C.dim2, bg = C.panel })
  hl("StatusLineNC", { fg = C.dim2, bg = C.panel })
  hl("WinBar", { fg = C.text, bg = C.panel })
  hl("WinBarNC", { fg = C.text, bg = C.panel })
  hl("Visual", { bg = C.visual })
  hl("Search", { bg = "#114957" })
  hl("CurSearch", { bg = "#1a6b80" })
  hl("IncSearch", { bg = "#1a6b80" })
  hl("NonText", { fg = C.line })
  hl("EndOfBuffer", { fg = C.panel })
  hl("MatchParen", { bg = "#43454a", bold = true })
  hl("Pmenu", { fg = C.text, bg = C.panel })
  hl("PmenuSel", { bg = C.sel })
  hl("ErrorMsg", { fg = C.conflict })
  hl("WarningMsg", { fg = "#d6ae58" })

  -- the file list
  hl("PcTitle", { fg = C.bright, bold = true })
  hl("PcGroup", { fg = C.text, bold = true })
  hl("PcCount", { fg = C.dim })
  hl("PcDir", { fg = C.dim })
  hl("PcArrow", { fg = C.dim2 })
  hl("PcCheckOn", { fg = C.blue6 })
  hl("PcCheckOff", { fg = C.dim3 })
  hl("PcModified", { fg = C.modified })
  hl("PcAdded", { fg = C.added })
  hl("PcDeleted", { fg = C.deleted })
  hl("PcUnversioned", { fg = C.unknown })
  hl("PcConflict", { fg = C.conflict })
  hl("PcEmpty", { fg = C.dim, italic = true })
  hl("PcPlaceholder", { fg = C.dim })
  hl("PcBtnPrimary", { fg = C.white, bg = C.blue6, bold = true })
  hl("PcBtn", { fg = C.text, bg = C.line })
  hl("PcHint", { fg = C.dim, bg = C.panel })
  hl("PcHintKey", { fg = C.text, bg = C.panel, bold = true })
  hl("PcToast", { fg = C.text, bg = C.line })
  hl("PcToastBorder", { fg = C.border, bg = C.line })
  hl("PcHiddenCursor", { blend = 100, nocombine = true })

  -- the diff
  hl("PcEditor", { fg = C.text, bg = C.editor })
  hl("PcCaret", { bg = C.caret })
  hl("PcBorder", { fg = C.border, bg = C.editor })
  hl("PcDiffIns", { bg = C.ins })
  hl("PcDiffDel", { bg = C.del })
  hl("PcDiffMod", { bg = C.mod })
  hl("PcDiffWordMod", { bg = C.mod_w })
  hl("PcFillIns", { bg = C.fill_ins })
  hl("PcFillDel", { bg = C.fill_del })
  hl("PcTitleOld", { fg = C.dim2, bg = C.editor })
  hl("PcTitleNew", { fg = C.bright, bg = C.editor, bold = true })
  hl("PcRevert", { fg = C.modified, bg = C.editor, bold = true })

  -- syntax (PyCharm Dark): treesitter captures + the regex fallback groups
  local syn = {
    keyword = "#cf8e6d", string = "#6aab73", comment = "#7a7e85", doc = "#5f826b",
    number = "#2aacb8", func = "#56a8f5", const = "#c77dbb", field = "#c77dbb",
    meta = "#b3ae60", self = "#94558d", builtin = "#8888c6", tag = "#d5b778", attr = "#bababa",
    escape = "#cf8e6d",
  }
  for g, c in pairs({
    ["@keyword"] = syn.keyword, ["@keyword.function"] = syn.keyword, ["@keyword.return"] = syn.keyword,
    ["@keyword.operator"] = syn.keyword, ["@keyword.import"] = syn.keyword, ["@keyword.conditional"] = syn.keyword,
    ["@keyword.repeat"] = syn.keyword, ["@keyword.exception"] = syn.keyword, ["@boolean"] = syn.keyword,
    ["@constant.builtin"] = syn.keyword, ["@string"] = syn.string, ["@string.escape"] = syn.escape,
    ["@character"] = syn.string, ["@comment"] = syn.comment, ["@number"] = syn.number, ["@number.float"] = syn.number,
    ["@function"] = syn.func, ["@function.method"] = syn.func, ["@function.call"] = C.text,
    ["@function.method.call"] = C.text, ["@function.builtin"] = syn.builtin, ["@constructor"] = C.text,
    ["@constant"] = syn.const, ["@property"] = syn.field, ["@variable.member"] = syn.field,
    ["@attribute"] = syn.meta, ["@variable.builtin"] = syn.self, ["@type.builtin"] = syn.builtin,
    ["@tag"] = syn.tag, ["@tag.attribute"] = syn.attr, ["@label"] = syn.meta,
    ["@variable"] = C.text, ["@variable.parameter"] = C.text, ["@type"] = C.text, ["@module"] = C.text,
    ["@punctuation"] = C.text, ["@operator"] = C.text,
    Keyword = syn.keyword, Statement = syn.keyword, Conditional = syn.keyword, Repeat = syn.keyword,
    Exception = syn.keyword, Boolean = syn.keyword, Include = syn.keyword, Define = syn.keyword,
    PreProc = syn.keyword, StorageClass = syn.keyword, Structure = syn.keyword,
    String = syn.string, Character = syn.string, Comment = syn.comment, SpecialComment = syn.doc,
    Number = syn.number, Float = syn.number, Function = syn.func, Constant = syn.const,
    Identifier = C.text, Type = C.text, Special = syn.escape, Operator = C.text, Delimiter = C.text,
    Title = syn.func, Tag = syn.tag,
  }) do hl(g, { fg = c }) end
  hl("@comment.documentation", { fg = syn.doc, italic = true })
  hl("@string.documentation", { fg = syn.doc, italic = true })

  for name, c in pairs({ Azure = "#56a8f5", Blue = "#548af7", Cyan = "#2aacb8", Green = "#6aab73",
    Grey = "#9da0a8", Orange = "#e5a05d", Purple = "#c77dbb", Red = "#f75464", Yellow = "#d6ae58" }) do
    hl("MiniIcons" .. name, { fg = c })
  end
end
colours()

----------------------------------------------------------------------------
-- State + helpers
----------------------------------------------------------------------------
local S = {
  entries = {},      -- { path, orig, kind } from git status
  checked = {},      -- path -> bool, only what the user changed
  collapsed = {},    -- group id -> bool
  rows = {},         -- list line -> row
  order = {},        -- file entries in display order
  sig = nil,         -- last git status output, to skip identical redraws
  head = nil, branch = "", is_repo = true,
  diff = nil,        -- the open diff
}
local ns = api.nvim_create_namespace("git-changes")
local ns_diff = api.nvim_create_namespace("git-changes-diff")
local ns_hunk = api.nvim_create_namespace("git-changes-hunks")
local diff_aug = api.nvim_create_augroup("git-changes-diff", { clear = true })
local CHECK_ON, CHECK_OFF, CHECK_SOME = "\u{F0132}", "\u{F0131}", "\u{F0375}"
local OPEN, SHUT = "\u{EAB4}", "\u{EAB6}"
local BRANCH = "\u{E725}"

local function git(args, opts)
  local cmd = { "git", "-C", ROOT }
  vim.list_extend(cmd, args)
  local r = vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
  return r.code == 0, r.stdout or "", r.stderr or ""
end

local function split_lines(s)
  local lines = vim.split(s, "\n", { plain = true })
  if lines[#lines] == "" then lines[#lines] = nil end
  for i, l in ipairs(lines) do lines[i] = l:gsub("\r$", "") end
  return lines
end

local toast_win
local function toast(msg, level)
  if toast_win and api.nvim_win_is_valid(toast_win) then api.nvim_win_close(toast_win, true) end
  local lines = split_lines(msg)
  local width = 10
  for _, l in ipairs(lines) do width = math.max(width, fn.strdisplaywidth(l) + 2) end
  width = math.min(width, vim.o.columns - 4)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.tbl_map(function(l) return " " .. l end, lines))
  vim.bo[buf].bufhidden = "wipe"
  local colour = level == "error" and "ErrorMsg" or level == "warn" and "WarningMsg" or "PcToast"
  toast_win = api.nvim_open_win(buf, false, {
    relative = "editor", anchor = "SE", row = vim.o.lines - 2, col = vim.o.columns - 1,
    width = width, height = #lines, style = "minimal", border = "rounded", zindex = 250, focusable = false,
  })
  vim.wo[toast_win].winhl = "Normal:PcToast,FloatBorder:PcToastBorder"
  if colour ~= "PcToast" then api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_row = #lines, hl_group = colour, hl_eol = false }) end
  local w = toast_win
  vim.defer_fn(function()
    if api.nvim_win_is_valid(w) then api.nvim_win_close(w, true) end
  end, level == "error" and 6000 or 3000)
  vim.cmd("redraw")
end

-- A float with the full text of a git error (hook output etc.).
local function show_output(title, text)
  local lines = split_lines(text)
  if #lines == 0 then lines = { "(no output)" } end
  local w = math.min(vim.o.columns - 8, 110)
  local h = math.min(vim.o.lines - 8, #lines)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  local win = api.nvim_open_win(buf, true, {
    relative = "editor", row = math.floor((vim.o.lines - h) / 2) - 1, col = math.floor((vim.o.columns - w) / 2),
    width = w, height = h, border = "rounded", title = " " .. title .. " ", title_pos = "center",
    footer = " Esc close ", footer_pos = "center", zindex = 200,
  })
  vim.wo[win].winhl = "Normal:PcEditor,FloatBorder:PcBorder"
  for _, k in ipairs({ "<Esc>", "q", "<CR>" }) do
    vim.keymap.set("n", k, function() api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
  end
end

----------------------------------------------------------------------------
-- git status -> entries
----------------------------------------------------------------------------
local function load_status()
  local ok, out = git({ "status", "--porcelain=v1", "-z", "--untracked-files=all" })
  if not ok then
    S.is_repo = false
    return out
  end
  S.is_repo = true
  local parts = vim.split(out, "\0", { plain = true })
  local list, i = {}, 1
  while i <= #parts and parts[i] ~= "" do
    local p = parts[i]
    local x, y, path = p:sub(1, 1), p:sub(2, 2), p:sub(4)
    local orig
    if x == "R" or x == "C" or y == "R" or y == "C" then
      orig = parts[i + 1]
      i = i + 1
    end
    i = i + 1
    local kind
    if x == "?" then kind = "unversioned"
    elseif x == "!" then kind = nil
    elseif x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D") then kind = "conflict"
    elseif x == "A" and y == "D" then kind = nil -- added, then deleted again: nothing vs HEAD
    elseif x == "D" or y == "D" then kind = "deleted"
    elseif x == "A" or x == "C" then kind = "added"
    elseif x == "R" or y == "R" then kind = "renamed"
    else kind = "modified" end
    if kind then list[#list + 1] = { path = path, orig = orig, kind = kind } end
  end
  table.sort(list, function(a, b) return a.path:lower() < b.path:lower() end)
  S.entries = list
  local hok, hout = git({ "rev-parse", "--short", "HEAD" })
  S.head = hok and vim.trim(hout) or nil
  local _, bout = git({ "branch", "--show-current" })
  S.branch = vim.trim(bout)
  if S.branch == "" then S.branch = S.head and ("detached at " .. S.head) or "no commits yet" end
  return out
end

local function group_of(e)
  if e.kind == "conflict" then return "conflicts" end
  if e.kind == "unversioned" then return "unversioned" end
  return "changes"
end
local GROUPS = {
  { id = "conflicts", title = "Merge Conflicts" },
  { id = "changes", title = "Changes" },
  { id = "unversioned", title = "Unversioned Files" },
}
local KIND_HL = {
  modified = "PcModified", renamed = "PcModified", added = "PcAdded", deleted = "PcDeleted",
  unversioned = "PcUnversioned", conflict = "PcConflict",
}

local function is_checked(e)
  local v = S.checked[e.path]
  if v ~= nil then return v end
  return e.kind ~= "unversioned"   -- PyCharm: new unversioned files start unticked
end

----------------------------------------------------------------------------
-- Layout: list (top), commit message, buttons, global statusline (hints)
----------------------------------------------------------------------------
local W = {}   -- list, msg, btn windows
local B = {}   -- list, msg, btn buffers

local function scratch(name)
  local b = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(b, name)
  vim.bo[b].bufhidden = "hide"
  return b
end

-- render one line from { {text, hl}, ... }; returns text + highlight spans
local function build(segs)
  local text, marks = "", {}
  for _, s in ipairs(segs) do
    if s[2] then marks[#marks + 1] = { #text, #text + #s[1], s[2] } end
    text = text .. s[1]
  end
  return text, marks
end

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function file_icon(path)
  if icons_ok and _G.MiniIcons then
    local ok, ic, ichl = pcall(_G.MiniIcons.get, "file", path)
    if ok and ic then return ic, ichl end
  end
  return "\u{F0214}", "PcDir"
end

local function render()
  if not (B.list and api.nvim_buf_is_valid(B.list)) then return end
  local lines, marks, rows, order = {}, {}, {}, {}
  local function add(segs, row)
    local t, m = build(segs)
    lines[#lines + 1] = t
    marks[#lines] = m
    rows[#lines] = row
  end

  if not S.is_repo then
    add({ { "  Not a git repository: ", "PcEmpty" }, { ROOT, "PcDir" } }, nil)
  elseif #S.entries == 0 then
    add({ { "  No changes", "PcEmpty" } }, nil)
  end

  for _, g in ipairs(GROUPS) do
    local items = {}
    for _, e in ipairs(S.entries) do if group_of(e) == g.id then items[#items + 1] = e end end
    if #items > 0 then
      local on = 0
      for _, e in ipairs(items) do if is_checked(e) then on = on + 1 end end
      local box = on == #items and CHECK_ON or on == 0 and CHECK_OFF or CHECK_SOME
      local shut = S.collapsed[g.id]
      add({
        { "  " }, { shut and SHUT or OPEN, "PcArrow" }, { " " },
        { box, on > 0 and "PcCheckOn" or "PcCheckOff" }, { " " },
        { g.title, "PcGroup" }, { "  " .. plural(#items, "file"), "PcCount" },
      }, { type = "group", id = g.id, items = items })
      for _, e in ipairs(items) do
        order[#order + 1] = e
        if not shut then
          local name = fn.fnamemodify(e.path, ":t")
          local dir = fn.fnamemodify(e.path, ":h")
          dir = dir == "." and "" or dir
          local ic, ichl = file_icon(e.path)
          local segs = {
            { "      " }, { is_checked(e) and CHECK_ON or CHECK_OFF, is_checked(e) and "PcCheckOn" or "PcCheckOff" },
            { " " }, { ic, ichl }, { " " }, { name, KIND_HL[e.kind] },
          }
          if dir ~= "" then segs[#segs + 1] = { "  " .. dir, "PcDir" } end
          if e.orig then segs[#segs + 1] = { "  ← " .. e.orig, "PcDir" } end
          add(segs, { type = "file", entry = e })
        end
      end
    end
  end

  -- keep the cursor on the same item
  local keep
  if W.list and api.nvim_win_is_valid(W.list) then
    local cur = S.rows[api.nvim_win_get_cursor(W.list)[1]]
    if cur then keep = cur.type == "file" and ("f:" .. cur.entry.path) or ("g:" .. cur.id) end
  end

  vim.bo[B.list].modifiable = true
  api.nvim_buf_set_lines(B.list, 0, -1, false, lines)
  vim.bo[B.list].modifiable = false
  api.nvim_buf_clear_namespace(B.list, ns, 0, -1)
  for l, ms in pairs(marks) do
    for _, m in ipairs(ms) do
      api.nvim_buf_set_extmark(B.list, ns, l - 1, m[1], { end_col = m[2], hl_group = m[3] })
    end
  end
  S.rows, S.order = rows, order

  if W.list and api.nvim_win_is_valid(W.list) then
    local target
    for l, r in pairs(rows) do
      local key = r.type == "file" and ("f:" .. r.entry.path) or ("g:" .. r.id)
      if key == keep then target = l end
    end
    if not target then
      for l = 1, #lines do if rows[l] and rows[l].type == "file" then target = l break end end
    end
    target = math.min(target or 1, #lines)
    api.nvim_win_set_cursor(W.list, { target, 0 })
  end
  vim.cmd("redrawstatus")
end

local function refresh(force)
  local out = load_status()
  if force or out ~= S.sig then
    S.sig = out
    render()
  end
end

local function winbar()
  local path = fn.fnamemodify(ROOT, ":~")
  local label = vim.env.GIT_CHANGES_LABEL
  local t = "%#PcTitle#  Commit  %#PcDir#" .. BRANCH .. " " .. S.branch:gsub("%%", "%%%%") .. "   " .. path:gsub("%%", "%%%%")
  if label and label ~= "" then t = t .. "   · " .. label:gsub("%%", "%%%%") end
  return t
end
_G.GitChangesWinbar = winbar

local function hint(pairs_)
  local s = "%#PcHint# "
  for i, p in ipairs(pairs_) do
    s = s .. "%#PcHintKey#" .. p[1] .. "%#PcHint# " .. p[2] .. (i < #pairs_ and "   " or "")
  end
  return s
end
function _G.GitChangesStatus()
  if S.diff then
    return hint({ { "F7", "next change" }, { "⇧F7", "previous" }, { "Alt+→/←", "next/prev file" },
      { "Ctrl+Alt+Z / «", "revert change" }, { "Ctrl+S", "save" }, { "Esc", "back to files" } })
  end
  local cur = api.nvim_get_current_win()
  local n = 0
  for _, e in ipairs(S.entries) do if is_checked(e) then n = n + 1 end end
  local right = "%=%#PcHint#" .. plural(n, "file") .. " selected "
  if cur == W.msg then
    return hint({ { "Ctrl+K", "commit" }, { "Ctrl+Alt+K", "commit and push" }, { "Esc", "back to files" } }) .. right
  end
  return hint({ { "Enter", "show diff" }, { "Space", "include" }, { "Tab", "message" }, { "Ctrl+K", "commit" },
    { "Ctrl+Alt+K", "commit+push" }, { "P", "push" }, { "F5", "refresh" }, { "Esc", "close" } }) .. right
end
o.statusline = "%!v:lua.GitChangesStatus()"

local BTN = { { " Commit ", "PcBtnPrimary", "commit" }, { " Commit and Push… ", "PcBtn", "push" } }
local btn_ranges = {}
local function render_buttons()
  local segs, x = { { "  " } }, 2
  btn_ranges = {}
  for i, b in ipairs(BTN) do
    segs[#segs + 1] = { b[1], b[2] }
    btn_ranges[#btn_ranges + 1] = { x + 1, x + fn.strdisplaywidth(b[1]), b[3] }
    x = x + fn.strdisplaywidth(b[1])
    if i < #BTN then segs[#segs + 1] = { "  " } x = x + 2 end
  end
  local t, m = build(segs)
  vim.bo[B.btn].modifiable = true
  api.nvim_buf_set_lines(B.btn, 0, -1, false, { t })
  vim.bo[B.btn].modifiable = false
  api.nvim_buf_clear_namespace(B.btn, ns, 0, -1)
  for _, s in ipairs(m) do api.nvim_buf_set_extmark(B.btn, ns, 0, s[1], { end_col = s[2], hl_group = s[3] }) end
end

local function placeholder()
  api.nvim_buf_clear_namespace(B.msg, ns, 0, -1)
  local l = api.nvim_buf_get_lines(B.msg, 0, -1, false)
  if #l <= 1 and (l[1] or "") == "" then
    api.nvim_buf_set_extmark(B.msg, ns, 0, 0, { virt_text = { { "Commit Message", "PcPlaceholder" } }, virt_text_pos = "overlay" })
  end
end

local MSG_H = 5
local function layout()
  if not (W.list and api.nvim_win_is_valid(W.list)) then return end
  api.nvim_win_set_height(W.btn, 1)
  api.nvim_win_set_height(W.msg, MSG_H)
end

-- hide the cursor while the file list or buttons have focus (rows are selected, not edited)
local DEFAULT_CURSOR = vim.o.guicursor
local function cursor_style()
  local w = api.nvim_get_current_win()
  if (w == W.list or w == W.btn) and not S.diff then
    vim.o.guicursor = "a:PcHiddenCursor"
  else
    vim.o.guicursor = DEFAULT_CURSOR
  end
end

----------------------------------------------------------------------------
-- The diff
----------------------------------------------------------------------------
local function filetype_for(path, lines)
  local ok, ft = pcall(vim.filetype.match, { filename = path, contents = lines })
  return ok and ft or nil
end

local function syntax(buf, ft)
  if not ft or ft == "" then return end
  local lang = vim.treesitter.language.get_lang(ft) or ft
  if not pcall(vim.treesitter.start, buf, lang) then vim.bo[buf].syntax = ft end
end

local function binary(s) return s:find("\0", 1, true) ~= nil end

local function diff_geometry()
  local cols, lines = vim.o.columns, vim.o.lines
  local inner = cols - 6                      -- 1 margin each side + 2 borders each float
  local wl = math.floor(inner / 2)
  local wr = inner - wl
  local h = math.max(3, lines - 5)            -- top margin, 2 borders, statusline, 1 spare
  return {
    left = { relative = "editor", row = 1, col = 1, width = wl, height = h },
    right = { relative = "editor", row = 1, col = wl + 3, width = wr, height = h },
  }
end

local close_diff, update_hunks

local function first_change(win)
  api.nvim_win_call(win, function()
    api.nvim_win_set_cursor(win, { 1, 0 })
    if fn.diff_hlID(1, 1) == 0 and fn.diff_filler(1) == 0 and fn.diff_filler(2) == 0 then
      pcall(vim.cmd, "normal! ]c")
    end
    vim.cmd("normal! zz")
  end)
end

local function open_diff(e)
  if S.diff then close_diff(true) end
  local abs = ROOT .. "/" .. e.path
  local short = e.orig and (e.orig .. " → " .. e.path) or e.path

  -- left: the HEAD version
  local left, left_title = {}, nil
  if e.kind == "unversioned" or e.kind == "added" or not S.head then
    left_title = " (did not exist in HEAD) "
  else
    local ok, out = git({ "show", "HEAD:" .. (e.orig or e.path) })
    if not ok then left_title = " (not in HEAD) "
    elseif binary(out) then left = { "Binary file" }
    else left = split_lines(out) end
  end

  -- right: the working file (real, editable buffer), unless deleted
  local rb, real, right_lines = nil, false, nil
  if e.kind == "deleted" or fn.filereadable(abs) == 0 then
    right_lines = {}
  else
    local fh = io.open(abs, "rb")
    local head = fh and fh:read(8000) or ""
    if fh then fh:close() end
    if binary(head) then right_lines = { "Binary file" } else real = true end
  end

  local lb = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(lb, 0, -1, false, left)
  vim.bo[lb].bufhidden = "wipe"
  vim.bo[lb].modifiable = false
  pcall(api.nvim_buf_set_name, lb, "HEAD:" .. (e.orig or e.path))

  if real then
    rb = fn.bufadd(abs)
    fn.bufload(rb)
    vim.bo[rb].buflisted = false
    vim.bo[rb].swapfile = false
  else
    rb = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(rb, 0, -1, false, right_lines)
    vim.bo[rb].bufhidden = "wipe"
    vim.bo[rb].modifiable = false
  end

  local ft = filetype_for(e.path, api.nvim_buf_get_lines(real and rb or lb, 0, 200, false))
  if ft then
    vim.bo[lb].filetype = ft
    if vim.bo[rb].filetype == "" then vim.bo[rb].filetype = ft end
  end
  syntax(lb, ft)
  syntax(rb, ft)

  -- a new or deleted file: no diff alignment, just the one side in its colour
  -- and an empty pane on the other, like PyCharm
  local left_empty = #left == 0
  local right_empty = not real and #right_lines == 0
  local one_sided = left_empty or right_empty

  local count = 0
  local okd, hunks = pcall(vim.text.diff,
    table.concat(api.nvim_buf_get_lines(lb, 0, -1, false), "\n") .. "\n",
    table.concat(api.nvim_buf_get_lines(rb, 0, -1, false), "\n") .. "\n",
    { result_type = "indices", algorithm = "histogram" })
  if okd and hunks then count = #hunks end

  local g = diff_geometry()
  local lw = api.nvim_open_win(lb, false, vim.tbl_extend("force", g.left, {
    border = "rounded", zindex = 60,
    title = { { " HEAD ", "PcTitleNew" }, { (S.head and (S.head .. " · ") or "") .. short .. " ", "PcTitleOld" }, left_title and { left_title, "PcTitleOld" } or nil },
    title_pos = "left",
  }))
  local rw = api.nvim_open_win(rb, true, vim.tbl_extend("force", g.right, {
    border = "rounded", zindex = 60,
    title = { { " Your version ", "PcTitleNew" }, { short .. " ", "PcTitleOld" }, right_empty and { " (deleted) ", "PcTitleOld" } or nil },
    title_pos = "left",
    footer = { { " " .. plural(count, "difference") .. " ", "PcTitleOld" } },
    footer_pos = "right",
  }))

  local base = "Normal:PcEditor,NormalNC:PcEditor,CursorLine:PcCaret,FloatBorder:PcBorder,FloatTitle:PcTitleNew,"
    .. "DiffChange:PcDiffMod,DiffText:PcDiffWordMod,DiffTextAdd:PcDiffWordMod,EndOfBuffer:PcEditor"
  vim.wo[lw].winhl = base .. ",DiffAdd:PcDiffDel,DiffDelete:PcFillIns"   -- only-on-the-left lines = deleted (grey)
  vim.wo[rw].winhl = base .. ",DiffAdd:PcDiffIns,DiffDelete:PcFillDel"   -- only-on-the-right lines = inserted (green)
  for _, w in ipairs({ lw, rw }) do
    local wo = vim.wo[w]
    wo.number, wo.cursorline, wo.signcolumn, wo.wrap, wo.list = true, true, "no", false, false
    wo.foldcolumn, wo.numberwidth, wo.statuscolumn = "0", 4, ""
    if not one_sided then api.nvim_win_call(w, function() vim.cmd("diffthis") end) end
    wo.foldenable = false
    wo.scrollbind = not one_sided
  end
  if one_sided then
    local full = left_empty and rb or lb
    if not (left_empty and right_empty) then
      api.nvim_buf_set_extmark(full, ns_diff, 0, 0, {
        end_row = api.nvim_buf_line_count(full), line_hl_group = left_empty and "PcDiffIns" or "PcDiffDel",
      })
    end
    if left_empty then vim.wo[lw].number = false end
    if right_empty then vim.wo[rw].number = false end
    count = 1
    api.nvim_win_set_config(rw, { footer = { { " 1 difference ", "PcTitleOld" } }, footer_pos = "right" })
  else
    api.nvim_win_call(lw, function() vim.cmd("syncbind") end)
  end

  S.diff = { entry = e, lb = lb, rb = rb, real = real, lw = lw, rw = rw, revertable = real and not one_sided }
  if S.diff.revertable then
    vim.wo[rw].signcolumn = "yes:1"
    update_hunks()
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufReadPost", "FileChangedShellPost" }, {
      group = diff_aug, buffer = rb, callback = function() vim.schedule(update_hunks) end,
    })
  end
  if one_sided then
    api.nvim_set_current_win(right_empty and lw or rw)
  else
    first_change(rw)
  end
  cursor_style()
  vim.cmd("redrawstatus")
end

-- The changes, the way the diff shows them (same algorithm and linematch as
-- 'diffopt'): { a_start, a_count, b_start, b_count }, left = a (HEAD), right =
-- b (the file). A count of 0 means "after line start".
local function diff_hunks(d)
  local ok, h = pcall(vim.text.diff,
    table.concat(api.nvim_buf_get_lines(d.lb, 0, -1, false), "\n") .. "\n",
    table.concat(api.nvim_buf_get_lines(d.rb, 0, -1, false), "\n") .. "\n",
    { result_type = "indices", algorithm = "histogram", indent_heuristic = true, linematch = 60 })
  if not ok or not h then return {} end
  -- linematch splits one block into touching pieces (lines removed, then a
  -- line changed): merge pieces with no unchanged line between them, so a
  -- block is one change, as in PyCharm
  local function range(start, count) -- inclusive lo..hi; empty = start+1..start
    return count == 0 and start + 1 or start, start + count - (count == 0 and 0 or 1)
  end
  local merged = {}
  for _, k in ipairs(h) do
    local alo, ahi = range(k[1], k[2])
    local blo, bhi = range(k[3], k[4])
    local m = merged[#merged]
    if m and alo == m.ahi + 1 and blo == m.bhi + 1 then
      m.ahi, m.bhi = ahi, bhi
    else
      merged[#merged + 1] = { alo = alo, ahi = ahi, blo = blo, bhi = bhi }
    end
  end
  local out = {}
  for _, m in ipairs(merged) do
    local ac, bc = m.ahi - m.alo + 1, m.bhi - m.blo + 1
    out[#out + 1] = { ac == 0 and m.alo - 1 or m.alo, ac, bc == 0 and m.blo - 1 or m.blo, bc }
  end
  return out
end

-- A « on the first line of every change in the right pane (PyCharm's revert
-- arrows): click it, or Ctrl+Alt+Z on the change, to put HEAD's lines back.
update_hunks = function()
  local d = S.diff
  if not (d and d.revertable and api.nvim_buf_is_valid(d.rb)) then return end
  local h = diff_hunks(d)
  d.hunks = h
  api.nvim_buf_clear_namespace(d.rb, ns_hunk, 0, -1)
  local last = api.nvim_buf_line_count(d.rb)
  for _, k in ipairs(h) do
    -- a pure deletion sits between lines: mark the line after the gap
    local line = k[4] == 0 and k[3] + 1 or k[3]
    local row = math.min(math.max(line, 1), last) - 1
    pcall(api.nvim_buf_set_extmark, d.rb, ns_hunk, row, 0, { sign_text = "«", sign_hl_group = "PcRevert", priority = 20 })
  end
  if api.nvim_win_is_valid(d.rw) then
    api.nvim_win_set_config(d.rw, { footer = { { " " .. plural(#h, "difference") .. " ", "PcTitleOld" } }, footer_pos = "right" })
  end
end

-- the change at a line of the right (or left) pane
local function hunk_at(line, side)
  local d = S.diff
  for _, k in ipairs(d and d.hunks or {}) do
    local start, count = k[3], k[4]
    if side == "left" then start, count = k[1], k[2] end
    if count == 0 then
      if line == start or line == start + 1 or (start == 0 and line == 1) then return k end
    elseif line >= start and line < start + count then
      return k
    end
  end
end

local function revert_hunk(line, side)
  local d = S.diff
  if not d then return end
  if not d.revertable then
    return toast(d.real and "Nothing to revert here" or "New or deleted file - revert it with git", "warn")
  end
  update_hunks()
  local k = hunk_at(line, side)
  if not k then return toast("Put the cursor on a change (or click its «)", "warn") end
  local a_start, a_count, b_start, b_count = k[1], k[2], k[3], k[4]
  local old = a_count > 0 and api.nvim_buf_get_lines(d.lb, a_start - 1, a_start - 1 + a_count, false) or {}
  local from = b_count > 0 and b_start - 1 or b_start   -- 0-based: replace these, or insert after b_start
  api.nvim_buf_set_lines(d.rb, from, from + b_count, false, old)
  update_hunks()
  pcall(vim.cmd, "diffupdate")
  if api.nvim_win_is_valid(d.rw) then
    api.nvim_set_current_win(d.rw)
    local target = math.min(math.max(from + 1, 1), api.nvim_buf_line_count(d.rb))
    api.nvim_win_set_cursor(d.rw, { target, 0 })
  end
  toast("Change reverted - u undoes it")
end

close_diff = function(switching)
  local d = S.diff
  if not d then return end
  S.diff = nil
  if d.real and api.nvim_buf_is_valid(d.rb) and vim.bo[d.rb].modified then
    api.nvim_buf_call(d.rb, function() vim.cmd("silent! noautocmd write") end)
  end
  for _, w in ipairs({ d.lw, d.rw }) do
    if api.nvim_win_is_valid(w) then
      api.nvim_win_call(w, function() vim.cmd("diffoff") end)
      api.nvim_win_close(w, true)
    end
  end
  api.nvim_clear_autocmds({ group = diff_aug })
  if d.real and api.nvim_buf_is_valid(d.rb) then
    api.nvim_buf_clear_namespace(d.rb, ns_diff, 0, -1)
    api.nvim_buf_clear_namespace(d.rb, ns_hunk, 0, -1)
  end
  if d.real and api.nvim_buf_is_valid(d.rb) and not vim.bo[d.rb].modified then
    pcall(api.nvim_buf_delete, d.rb, { force = false })
  end
  if not switching then
    if W.list and api.nvim_win_is_valid(W.list) then api.nvim_set_current_win(W.list) end
    refresh(true)
    -- put the cursor back on the file we were looking at
    for l, r in pairs(S.rows) do
      if r.type == "file" and r.entry.path == d.entry.path then
        api.nvim_win_set_cursor(W.list, { l, 0 })
        break
      end
    end
    cursor_style()
    vim.cmd("redrawstatus")
  end
end

local function step_file(delta)
  local d = S.diff
  if not d or #S.order == 0 then return end
  local idx = 1
  for i, e in ipairs(S.order) do if e.path == d.entry.path then idx = i break end end
  local nxt = S.order[((idx - 1 + delta) % #S.order) + 1]
  if nxt then open_diff(nxt) end
end

local function step_change(dir)
  if not S.diff then return end
  local w = api.nvim_get_current_win()
  if w ~= S.diff.lw and w ~= S.diff.rw then api.nvim_set_current_win(S.diff.rw) end
  local before = api.nvim_win_get_cursor(0)[1]
  pcall(vim.cmd, "normal! " .. (dir > 0 and "]c" or "[c"))
  if api.nvim_win_get_cursor(0)[1] == before then
    toast(dir > 0 and "Last change - Alt+→ for the next file" or "First change - Alt+← for the previous file")
  end
  vim.cmd("normal! zz")
end

local function save_right()
  if S.diff and S.diff.real and api.nvim_buf_is_valid(S.diff.rb) then
    api.nvim_buf_call(S.diff.rb, function() vim.cmd("silent! write") end)
    toast("Saved " .. S.diff.entry.path)
  end
end

----------------------------------------------------------------------------
-- Commit / push
----------------------------------------------------------------------------
local function selected()
  local entries, paths = {}, {}
  for _, e in ipairs(S.entries) do
    if is_checked(e) then
      entries[#entries + 1] = e
      paths[#paths + 1] = e.path
      if e.orig then paths[#paths + 1] = e.orig end
    end
  end
  return entries, paths
end

local push

local function commit(and_push)
  if not S.is_repo then return end
  if S.diff then close_diff() end
  local msg = vim.trim(table.concat(api.nvim_buf_get_lines(B.msg, 0, -1, false), "\n"))
  local entries, paths = selected()
  if #entries == 0 then return toast("No files selected - Space includes a file", "warn") end
  if msg == "" then
    api.nvim_set_current_win(W.msg)
    vim.cmd("startinsert")
    return toast("Write a commit message first", "warn")
  end
  for _, e in ipairs(entries) do
    if e.kind == "conflict" then return toast("Resolve the merge conflict in " .. e.path .. " first", "error") end
  end
  vim.cmd("silent! wall")
  toast("Committing " .. plural(#entries, "file") .. "…")
  -- stage what exists; drop what is gone (deleted files, the old name of a
  -- rename) from the index - git add refuses a path that is nowhere on disk
  local present, gone = {}, {}
  for _, p in ipairs(paths) do
    if vim.uv.fs_lstat(ROOT .. "/" .. p) then present[#present + 1] = p else gone[#gone + 1] = p end
  end
  local ok, out, err = true, "", ""
  if #present > 0 then
    ok, out, err = git(vim.list_extend({ "add", "-A", "--" }, present))
    if not ok then return show_output("git add failed", out .. err) end
  end
  if #gone > 0 then
    ok, out, err = git(vim.list_extend({ "rm", "--cached", "-q", "--ignore-unmatch", "--" }, gone))
    if not ok then return show_output("git rm failed", out .. err) end
  end
  local args = { "commit", "-m", msg, "--" }
  vim.list_extend(args, paths)
  ok, out, err = git(args)
  if not ok then return show_output("Commit failed", out .. err) end
  vim.cmd("stopinsert")
  api.nvim_buf_set_lines(B.msg, 0, -1, false, {})
  placeholder()
  for _, e in ipairs(entries) do S.checked[e.path] = nil end
  refresh(true)
  api.nvim_set_current_win(W.list)
  cursor_style()
  toast("Committed " .. plural(#entries, "file") .. "\n" .. (split_lines(out)[1] or ""))
  if and_push then push() end
end

push = function()
  if not S.is_repo then return end
  local has_up = git({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" })
  local cmd = has_up and { "git", "push" } or { "git", "push", "-u", "origin", "HEAD" }
  local w = math.min(vim.o.columns - 8, 100)
  local h = math.min(vim.o.lines - 8, 14)
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, {
    relative = "editor", row = math.floor((vim.o.lines - h) / 2) - 1, col = math.floor((vim.o.columns - w) / 2),
    width = w, height = h, border = "rounded", zindex = 200,
    title = " " .. table.concat(cmd, " ") .. " ", title_pos = "center",
  })
  vim.wo[win].winhl = "Normal:PcEditor,FloatBorder:PcBorder,FloatTitle:PcTitleNew"
  vim.cmd("redrawstatus")
  fn.jobstart(cmd, {
    cwd = ROOT, term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if api.nvim_win_is_valid(win) then
          api.nvim_win_set_config(win, {
            footer = code == 0 and " Pushed - press any key " or " Push failed (exit " .. code .. ") - press any key ",
            footer_pos = "center",
          })
        end
        refresh(true)
      end)
    end,
  })
  vim.cmd("startinsert")
end

----------------------------------------------------------------------------
-- List actions
----------------------------------------------------------------------------
local function current_row()
  if api.nvim_get_current_win() ~= W.list then return nil end
  return S.rows[api.nvim_win_get_cursor(W.list)[1]]
end

local function toggle(row)
  row = row or current_row()
  if not row then return end
  if row.type == "file" then
    S.checked[row.entry.path] = not is_checked(row.entry)
  else
    local all = true
    for _, e in ipairs(row.items) do if not is_checked(e) then all = false end end
    for _, e in ipairs(row.items) do S.checked[e.path] = not all end
  end
  render()
end

local function activate(row)
  row = row or current_row()
  if not row then return end
  if row.type == "group" then
    S.collapsed[row.id] = not S.collapsed[row.id]
    render()
  else
    open_diff(row.entry)
  end
end

local function quit()
  if S.diff then close_diff(true) end
  vim.cmd("silent! wall")
  vim.o.guicursor = DEFAULT_CURSOR
  vim.cmd("qa!")
end

----------------------------------------------------------------------------
-- Build the screen
----------------------------------------------------------------------------
B.list = scratch("Changes")
B.msg = scratch("Commit Message")
B.btn = scratch("Commit buttons")
vim.bo[B.list].modifiable = false
vim.bo[B.msg].filetype = "gitcommit"
vim.bo[B.msg].textwidth = 0

W.list = api.nvim_get_current_win()
api.nvim_win_set_buf(W.list, B.list)
vim.cmd("belowright split")
W.msg = api.nvim_get_current_win()
api.nvim_win_set_buf(W.msg, B.msg)
vim.cmd("belowright split")
W.btn = api.nvim_get_current_win()
api.nvim_win_set_buf(W.btn, B.btn)

for _, w in ipairs({ W.list, W.msg, W.btn }) do
  local wo = vim.wo[w]
  wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn, wo.wrap, wo.list = false, false, "no", "0", false, false
  wo.winfixheight = w ~= W.list
  wo.cursorline = w == W.list
  wo.spell = false
end
vim.wo[W.list].winbar = "%!v:lua.GitChangesWinbar()"
vim.wo[W.msg].wrap = true
vim.wo[W.msg].winhl = "Normal:PcEditor,NormalNC:PcEditor,CursorLine:PcCaret"
vim.wo[W.msg].cursorline = false
api.nvim_set_current_win(W.list)
layout()
render_buttons()
placeholder()
refresh(true)
cursor_style()

----------------------------------------------------------------------------
-- Keys
----------------------------------------------------------------------------
local function map(modes, lhs, rhs, buf)
  vim.keymap.set(modes, lhs, rhs, { buffer = buf, nowait = true, silent = true })
end

-- file list
map("n", "<CR>", function() activate() end, B.list)
map("n", "<C-d>", function() activate() end, B.list)   -- PyCharm: Show Diff
map("n", "<2-LeftMouse>", function() activate() end, B.list)
map("n", "<Space>", function() toggle() end, B.list)
local function tree_right()
  local r = current_row()
  if r and r.type == "group" and S.collapsed[r.id] then activate(r) else vim.cmd("normal! j") end
end
map("n", "<Right>", tree_right, B.list)
map("n", "l", tree_right, B.list)
local function tree_left()
  local r = current_row()
  if not r then return end
  if r.type == "group" then
    if not S.collapsed[r.id] then activate(r) end
    return
  end
  local l = api.nvim_win_get_cursor(W.list)[1]
  for i = l - 1, 1, -1 do
    if S.rows[i] and S.rows[i].type == "group" then api.nvim_win_set_cursor(W.list, { i, 0 }) return end
  end
end
map("n", "<Left>", tree_left, B.list)
map("n", "h", tree_left, B.list)
map("n", "<LeftRelease>", function()
  local pos = fn.getmousepos()
  if pos.winid ~= W.list then return end
  local r = S.rows[pos.line]
  if not r then return end
  local col = pos.wincol
  if r.type == "file" and col >= 7 and col <= 8 then toggle(r)
  elseif r.type == "group" and col >= 5 and col <= 6 then toggle(r)
  elseif r.type == "group" and col >= 3 and col <= 4 then activate(r) end
end, B.list)
for _, k in ipairs({ "<Esc>", "q" }) do map("n", k, quit, B.list) end
for _, k in ipairs({ "<F5>", "R", "<C-r>" }) do map("n", k, function() refresh(true) toast("Refreshed") end, B.list) end
map("n", "P", function() push() end, B.list)
map("n", "<Tab>", function() api.nvim_set_current_win(W.msg) cursor_style() vim.cmd("startinsert!") end, B.list)
for _, k in ipairs({ "i", "a", "o", "c", "x", "d", "u", "p" }) do map("n", k, "<Nop>", B.list) end

-- commit message
map({ "n", "i" }, "<C-k>", function() commit(false) end, B.msg)
map({ "n", "i" }, "<C-CR>", function() commit(false) end, B.msg)
map({ "n", "i" }, "<M-C-k>", function() commit(true) end, B.msg)
map("n", "<Esc>", function() api.nvim_set_current_win(W.list) cursor_style() end, B.msg)
map("n", "<Tab>", function() api.nvim_set_current_win(W.list) cursor_style() end, B.msg)
map("i", "<Tab>", function() vim.cmd("stopinsert") api.nvim_set_current_win(W.list) cursor_style() end, B.msg)

-- commit from the list too (PyCharm: Ctrl+K anywhere in the Commit window)
map("n", "<C-k>", function() commit(false) end, B.list)
map("n", "<M-C-k>", function() commit(true) end, B.list)

-- buttons
local function press_button(col)
  for _, r in ipairs(btn_ranges) do
    if col >= r[1] and col <= r[2] then
      if r[3] == "commit" then commit(false) else commit(true) end
      return true
    end
  end
end
map("n", "<LeftRelease>", function()
  local pos = fn.getmousepos()
  if pos.winid == W.btn then press_button(pos.wincol) end
  if api.nvim_get_current_win() == W.btn then api.nvim_set_current_win(W.list) cursor_style() end
end, B.btn)
map("n", "<CR>", function()
  press_button(api.nvim_win_get_cursor(W.btn)[2] + 1)
end, B.btn)

-- diff (global: the diff buffers include the real file)
local function in_diff() return S.diff ~= nil end
local function dmap(lhs, f)
  vim.keymap.set("n", lhs, function()
    if in_diff() then f() else
      api.nvim_feedkeys(api.nvim_replace_termcodes(lhs, true, false, true), "n", false)
    end
  end, { nowait = true, silent = true })
end
dmap("<Esc>", function() close_diff() end)
dmap("q", function() close_diff() end)
dmap("<F7>", function() step_change(1) end)
dmap("<S-F7>", function() step_change(-1) end)
dmap("<F19>", function() step_change(-1) end)        -- Shift+F7 in some terminals
dmap("<M-Right>", function() step_file(1) end)
dmap("<M-Left>", function() step_file(-1) end)
dmap("<M-Down>", function() step_change(1) end)
dmap("<M-Up>", function() step_change(-1) end)
vim.keymap.set({ "n", "i" }, "<C-s>", function() save_right() end, { silent = true })
-- Tab switches between the two sides
-- revert the change under the cursor (PyCharm: Rollback Lines, Ctrl+Alt+Z)
dmap("<M-C-z>", function()
  local w = api.nvim_get_current_win()
  revert_hunk(api.nvim_win_get_cursor(w)[1], w == S.diff.lw and "left" or "right")
end)
-- or click the « in the right pane's sign column
dmap("<LeftRelease>", function()
  local pos = fn.getmousepos()
  if S.diff and pos.winid == S.diff.rw and pos.wincol <= 2 and pos.line > 0 then
    revert_hunk(pos.line, "right")
  end
end)
dmap("<Tab>", function()
  local w = api.nvim_get_current_win()
  api.nvim_set_current_win(w == S.diff.lw and S.diff.rw or S.diff.lw)
end)

----------------------------------------------------------------------------
-- Autocommands
----------------------------------------------------------------------------
local aug = api.nvim_create_augroup("git-changes", { clear = true })
api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, { group = aug, callback = function() cursor_style() vim.cmd("redrawstatus") end })
api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, { group = aug, buffer = B.msg, callback = placeholder })
api.nvim_create_autocmd("VimResized", {
  group = aug,
  callback = function()
    layout()
    if S.diff then
      local g = diff_geometry()
      api.nvim_win_set_config(S.diff.lw, g.left)
      api.nvim_win_set_config(S.diff.rw, g.right)
    end
  end,
})
-- a diff float closed some other way (e.g. :q): tidy up the other one
api.nvim_create_autocmd("WinClosed", {
  group = aug,
  callback = function(a)
    local d = S.diff
    if d and (tonumber(a.match) == d.lw or tonumber(a.match) == d.rw) then
      vim.schedule(function() if S.diff == d then close_diff() end end)
    end
  end,
})
api.nvim_create_autocmd("ColorScheme", { group = aug, callback = colours })

-- Follow the agent: reread the file being diffed when it changes on disk, and
-- re-run git status while the list is showing.
local timer = vim.uv.new_timer()
timer:start(1500, 1500, vim.schedule_wrap(function()
  if S.diff then
    if S.diff.real and api.nvim_buf_is_valid(S.diff.rb) then
      pcall(vim.cmd, "silent! checktime " .. S.diff.rb)
    end
  elseif fn.mode() == "n" then
    refresh(false)
  end
end))
api.nvim_create_autocmd("FileChangedShellPost", { group = aug, callback = function() pcall(vim.cmd, "diffupdate") end })
