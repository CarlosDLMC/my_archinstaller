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
hi("Normal",       { fg = c.fg, bg = "NONE" })  -- let the terminal background (foot, alpha 0.85) show through
hi("NormalFloat",  { fg = c.fg, bg = c.bg_alt })
hi("FloatBorder",  { fg = c.sep, bg = c.bg_alt })
hi("CursorLine",   { bg = c.caret_row })
hi("CursorLineNr", { fg = "#a1a3ab" })
hi("LineNr",       { fg = c.line_nr })
hi("Visual",       { bg = c.sel })
hi("Search",       { fg = c.bg, bg = c.keyword })
hi("IncSearch",    { fg = c.bg, bg = c.func })
hi("ColorColumn",  { bg = c.bg_alt })
hi("SignColumn",   { bg = "NONE" })
hi("NormalNC",     { fg = c.fg, bg = "NONE" })
hi("EndOfBuffer",  { fg = c.bg_alt, bg = "NONE" })
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

-- Rust, as RustRover draws it. Colours from RustRover 2026.2
-- (plugins/intellij-rust/lib/intellij.rustrover.common.jar!/org/rust/ide/colors/RustDark.xml,
-- falling back to RustDarcula.xml and the Dark scheme like the IDE does).
-- Everything is scoped to .rust so the Python colours above are untouched.
local r = {
  func     = "#6aa2d7",  -- functions, methods, calls
  macro    = "#d5a563",
  struct   = "#a6bb77",  -- struct, enum, union, type alias
  variant  = "#8cc8d4",  -- enum variants (italic)
  trait    = "#8d91dc",  -- traits and crates
  tparam   = "#3cacac",  -- generic type parameters
  lifetime = "#20999d",  -- italic
  self     = "#e59eae",
  attr     = "#b3ae60",  -- #[derive(...)], #[cfg(...)]
  question = "#d8a460",  -- the ? operator, bold
  doc      = "#5f826b",  -- /// doc comments
  unsafe   = "#4e2c28",  -- background of unsafe operations
}

-- legacy vim syntax (used while there is no treesitter rust parser)
hi("rustFuncName",        { fg = r.func })
hi("rustFuncCall",        { fg = r.func })
hi("rustMacro",           { fg = r.macro })
hi("rustAssert",          { fg = r.macro })
hi("rustPanic",           { fg = r.macro })
hi("rustLifetime",        { fg = r.lifetime, italic = true })
hi("rustSelf",            { fg = r.self })
hi("rustAttribute",       { fg = r.attr })
hi("rustDerive",          { fg = r.attr })
hi("rustDeriveTrait",     { fg = r.trait })
hi("rustTrait",           { fg = r.trait })
hi("rustEnumVariant",     { fg = r.variant, italic = true })
hi("rustType",            { fg = c.keyword })  -- i32, str, bool... RustRover colours primitives as keywords
hi("rustQuestionMark",    { fg = r.question, bold = true })
hi("rustCommentLineDoc",  { fg = r.doc, italic = true })
hi("rustCommentBlockDoc", { fg = r.doc, italic = true })
hi("rustEscape",          { fg = c.keyword })
hi("rustConstant",        { fg = c.const, italic = true })

-- treesitter
hi("@function.rust",              { fg = r.func })
hi("@function.call.rust",         { fg = r.func })
hi("@function.method.rust",       { fg = r.func })
hi("@function.method.call.rust",  { fg = r.func })
hi("@function.macro.rust",        { fg = r.macro })
hi("@type.rust",                  { fg = r.struct })
hi("@type.builtin.rust",          { fg = c.keyword })
hi("@constructor.rust",           { fg = r.variant, italic = true })
hi("@variable.builtin.rust",      { fg = r.self })
hi("@attribute.rust",             { fg = r.attr })
hi("@label.rust",                 { fg = r.lifetime, italic = true })  -- 'a lifetimes
hi("@constant.rust",              { fg = c.const, italic = true })
hi("@comment.documentation.rust", { fg = r.doc, italic = true })
hi("@string.escape.rust",         { fg = c.keyword })

-- rust-analyzer semantic tokens (these win over treesitter when the LSP is running)
hi("@lsp.type.function.rust",        { fg = r.func })
hi("@lsp.type.method.rust",          { fg = r.func })
hi("@lsp.typemod.method.trait.rust", { fg = r.func, italic = true })
hi("@lsp.type.macro.rust",           { fg = r.macro })
hi("@lsp.type.struct.rust",          { fg = r.struct })
hi("@lsp.type.union.rust",           { fg = r.struct })
hi("@lsp.type.typeAlias.rust",       { fg = r.struct })
hi("@lsp.type.enum.rust",            { fg = r.struct, italic = true })
hi("@lsp.type.enumMember.rust",      { fg = r.variant, italic = true })
hi("@lsp.type.interface.rust",       { fg = r.trait })  -- traits
hi("@lsp.typemod.namespace.crateRoot.rust", { fg = r.trait })
hi("@lsp.type.typeParameter.rust",   { fg = r.tparam })
hi("@lsp.type.lifetime.rust",        { fg = r.lifetime, italic = true })
hi("@lsp.type.selfKeyword.rust",     { fg = r.self })
hi("@lsp.type.builtinType.rust",     { fg = c.keyword })
hi("@lsp.type.property.rust",        { fg = c.const })
hi("@lsp.type.static.rust",          { fg = c.const })
hi("@lsp.type.const.rust",           { fg = c.const, italic = true })
hi("@lsp.type.attribute.rust",       { fg = r.attr })
hi("@lsp.type.attributeBracket.rust",{ fg = r.attr })
hi("@lsp.type.builtinAttribute.rust",{ fg = r.attr })
hi("@lsp.type.derive.rust",          { fg = r.trait })
hi("@lsp.type.escapeSequence.rust",  { fg = c.keyword })
hi("@lsp.type.formatSpecifier.rust", { fg = c.keyword })
hi("@lsp.typemod.operator.controlFlow.rust", { fg = r.question, bold = true })  -- ?
hi("@lsp.typemod.comment.documentation.rust", { fg = r.doc, italic = true })
hi("@lsp.mod.mutable.rust",          { underline = true })  -- let mut x: underlined like RustRover
hi("@lsp.typemod.selfKeyword.mutable.rust", { fg = r.self, underline = true })
hi("@lsp.mod.unsafe.rust",           { bg = r.unsafe })
