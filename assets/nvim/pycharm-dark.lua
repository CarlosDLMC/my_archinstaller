-- JetBrains "Dark" (PyCharm 2025.3, new UI).
-- Colours extracted from /opt/pycharm-2025.3.1/lib/app.jar!/themes/expUI/expUI_darkScheme.xml
-- so this matches the editor rather than approximating it.
vim.cmd("highlight clear")
vim.g.colors_name = "pycharm-dark"
vim.o.termguicolors = true
vim.o.background = "dark"

local c = {
  bg        = "#1e1f22",  -- editor background
  bg_alt    = "#2b2d30",  -- tool windows / statusline
  caret_row = "#26282e",
  sel       = "#2e436e",
  fg        = "#bcbec4",  -- default text
  fg_dim    = "#9da0a8",
  comment   = "#7a7e85",
  line_nr   = "#4b5059",
  indent    = "#313438",
  sep       = "#43454a",
  keyword   = "#cf8e6d",  -- orange
  string    = "#6aab73",  -- green
  number    = "#2aacb8",  -- teal
  func      = "#56a8f5",  -- blue
  const     = "#c77dbb",  -- magenta
  red       = "#f75464",
  added     = "#549159",
  modified  = "#375fad",
  caret     = "#ced0d6",
}

local function hi(g, o) vim.api.nvim_set_hl(0, g, o) end

-- editor chrome
hi("Normal",       { fg = c.fg, bg = c.bg })
hi("NormalFloat",  { fg = c.fg, bg = c.bg_alt })
hi("FloatBorder",  { fg = c.sep, bg = c.bg_alt })
hi("CursorLine",   { bg = c.caret_row })
hi("CursorLineNr", { fg = "#a1a3ab" })
hi("LineNr",       { fg = c.line_nr })
hi("Visual",       { bg = c.sel })
hi("Search",       { fg = c.bg, bg = c.keyword })
hi("IncSearch",    { fg = c.bg, bg = c.func })
hi("ColorColumn",  { bg = c.bg_alt })
hi("SignColumn",   { bg = c.bg })
hi("VertSplit",    { fg = c.sep })
hi("WinSeparator", { fg = c.sep })
hi("StatusLine",   { fg = c.fg, bg = c.bg_alt })
hi("Pmenu",        { fg = c.fg, bg = c.bg_alt })
hi("PmenuSel",     { fg = c.fg, bg = c.sel })
hi("IndentBlanklineChar", { fg = c.indent })
hi("Whitespace",   { fg = c.indent })
hi("MatchParen",   { fg = c.keyword, bold = true })
hi("Cursor",       { fg = c.bg, bg = c.caret })

-- syntax
hi("Comment",    { fg = c.comment, italic = true })
hi("Constant",   { fg = c.const })
hi("String",     { fg = c.string })
hi("Character",  { fg = c.string })
hi("Number",     { fg = c.number })
hi("Boolean",    { fg = c.keyword })
hi("Float",      { fg = c.number })
hi("Identifier", { fg = c.fg })
hi("Function",   { fg = c.func })
hi("Statement",  { fg = c.keyword })
hi("Keyword",    { fg = c.keyword })
hi("Conditional",{ fg = c.keyword })
hi("Repeat",     { fg = c.keyword })
hi("Operator",   { fg = c.fg })
hi("PreProc",    { fg = c.keyword })
hi("Type",       { fg = c.fg })
hi("Special",    { fg = c.const })
hi("Todo",       { fg = c.bg, bg = c.keyword, bold = true })
hi("Error",      { fg = c.red })

-- treesitter (LazyVim leans on these)
hi("@comment",            { link = "Comment" })
hi("@keyword",            { fg = c.keyword })
hi("@keyword.function",   { fg = c.keyword })
hi("@keyword.return",     { fg = c.keyword })
hi("@string",             { fg = c.string })
hi("@number",             { fg = c.number })
hi("@boolean",            { fg = c.keyword })
hi("@function",           { fg = c.func })
hi("@function.call",      { fg = c.func })
hi("@function.method",    { fg = c.func })
hi("@constructor",        { fg = c.func })
hi("@variable",           { fg = c.fg })
hi("@variable.member",    { fg = c.const })
hi("@variable.builtin",   { fg = c.keyword })
hi("@property",           { fg = c.const })
hi("@constant",           { fg = c.const })
hi("@constant.builtin",   { fg = c.const })
hi("@type",               { fg = c.fg })
hi("@type.builtin",       { fg = c.keyword })
hi("@operator",           { fg = c.fg })
hi("@punctuation",        { fg = c.fg })
hi("@parameter",          { fg = c.fg })

-- diagnostics / git
hi("DiagnosticError", { fg = c.red })
hi("DiagnosticWarn",  { fg = c.keyword })
hi("DiagnosticInfo",  { fg = c.func })
hi("DiagnosticHint",  { fg = c.number })
hi("DiffAdd",    { fg = c.added })
hi("DiffChange", { fg = c.modified })
hi("DiffDelete", { fg = c.red })
hi("GitSignsAdd",    { fg = c.added })
hi("GitSignsChange", { fg = c.modified })
hi("GitSignsDelete", { fg = c.red })
