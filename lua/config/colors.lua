local M = {}

-- Palette "Tokyo Night Refined" (Sombre, Moderne, Contrasté)
local c = {
  bg = "#1a1b26",
  bg_dark = "#16161e",
  bg_highlight = "#292e42",
  bg_visual = "#364a82",
  fg = "#c0caf5",
  fg_dark = "#a9b1d6",
  fg_gutter = "#3b4261",
  
  comment = "#565f89",
  
  red = "#f7768e",
  orange = "#ff9e64",
  yellow = "#e0af68",
  green = "#9ece6a",
  cyan = "#7dcfff",
  blue = "#7aa2f7",
  purple = "#bb9af7",
  magenta = "#bb9af7",
}

function M.setup()
  vim.cmd("hi clear")
  if vim.fn.exists("syntax_on") then vim.cmd("syntax reset") end
  vim.o.termguicolors = true
  vim.g.colors_name = "native_tokyo"

  local hl = vim.api.nvim_set_hl
  local function set(group, opts) hl(0, group, opts) end

  -- 1. BASE UI
  set("Normal", { fg = c.fg, bg = c.bg })
  set("NormalFloat", { fg = c.fg, bg = c.bg_dark })
  set("FloatBorder", { fg = c.blue, bg = c.bg_dark })
  set("Cursor", { bg = c.fg, fg = c.bg })
  set("CursorLine", { bg = c.bg_highlight })
  set("CursorLineNr", { fg = c.yellow, bold = true })
  set("LineNr", { fg = c.fg_gutter })
  set("VertSplit", { fg = c.bg_highlight, bg = c.bg })
  set("StatusLine", { fg = c.fg, bg = c.bg_highlight })
  set("StatusLineNC", { fg = c.comment, bg = c.bg_dark })
  set("Visual", { bg = c.bg_visual })
  set("Search", { bg = c.yellow, fg = c.bg_dark, bold = true })
  set("MatchParen", { fg = c.orange, bold = true })
  set("Directory", { fg = c.blue, bold = true })
  set("Title", { fg = c.blue, bold = true })
  set("ErrorMsg", { fg = c.red, bold = true })
  set("WarningMsg", { fg = c.yellow })
  
  -- 2. SYNTAX (Standard)
  set("Comment", { fg = c.comment, italic = true })
  set("Constant", { fg = c.orange })
  set("String", { fg = c.green })
  set("Character", { fg = c.green })
  set("Number", { fg = c.orange })
  set("Boolean", { fg = c.orange })
  set("Float", { fg = c.orange })
  set("Identifier", { fg = c.magenta })
  set("Function", { fg = c.blue })
  set("Statement", { fg = c.purple })
  set("Conditional", { fg = c.purple })
  set("Repeat", { fg = c.purple })
  set("Label", { fg = c.purple })
  set("Operator", { fg = c.cyan })
  set("Keyword", { fg = c.purple, italic = true })
  set("PreProc", { fg = c.cyan })
  set("Include", { fg = c.cyan })
  set("Define", { fg = c.cyan })
  set("Macro", { fg = c.cyan })
  set("Type", { fg = c.blue })
  set("Structure", { fg = c.blue })
  set("Special", { fg = c.blue })
  set("Delimiter", { fg = c.fg_dark })
  set("Underlined", { underline = true })
  set("Error", { fg = c.red })
  set("Todo", { fg = c.yellow, bold = true })

  -- 3. TREESITTER (The real power)
  set("@comment", { link = "Comment" })
  set("@keyword", { fg = c.purple, italic = true })
  set("@keyword.function", { fg = c.magenta, italic = true })
  set("@keyword.return", { fg = c.red, italic = true })
  set("@function", { fg = c.blue })
  set("@function.call", { fg = c.blue })
  set("@function.builtin", { fg = c.cyan })
  set("@method", { fg = c.blue })
  set("@variable", { fg = c.fg })
  set("@variable.builtin", { fg = c.red })
  set("@parameter", { fg = c.yellow })
  set("@property", { fg = c.green })
  set("@field", { fg = c.green })
  set("@constructor", { fg = c.orange })
  set("@type", { fg = c.blue })
  set("@type.builtin", { fg = c.cyan })
  set("@string", { fg = c.green })
  set("@number", { fg = c.orange })
  set("@boolean", { fg = c.orange })
  set("@tag", { fg = c.red })
  set("@tag.attribute", { fg = c.yellow })
  set("@tag.delimiter", { fg = c.fg_dark })
  
  -- 4. PLUGIN SPECIFIC
  -- Finder / Grep (Highlights custom que j'ai utilisés dans ton finder.lua)
  set("TreeDir", { fg = c.blue, bold = true })
  set("TreeFile", { fg = c.fg })
  set("TreeRoot", { fg = c.purple, bold = true, underline = true })
  
  -- Pmenu (Autocompletion)
  set("Pmenu", { bg = c.bg_dark, fg = c.fg })
  set("PmenuSel", { bg = c.bg_visual, fg = "NONE", bold = true })
  set("PmenuThumb", { bg = c.fg_gutter })

  -- LSP
  set("DiagnosticError", { fg = c.red })
  set("DiagnosticWarn", { fg = c.yellow })
  set("DiagnosticInfo", { fg = c.cyan })
  set("DiagnosticHint", { fg = c.comment })
  
  -- Register Icon Highlights
  require("config.ui").setup()
end

return M