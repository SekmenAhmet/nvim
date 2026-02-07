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
  set("Identifier", { fg = c.purple })
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
  set("@keyword.function", { fg = c.purple, italic = true })
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
  -- Finder / Grep / Tree
  set("TreeDir", { fg = c.blue, bold = true })
  set("TreeFile", { fg = c.fg })
  set("TreeRoot", { fg = c.purple, bold = true, underline = true })
  
  -- LSP diagnostics in Tree
  set("TreeFileError", { fg = c.red, bold = true })    -- Fichier avec erreurs
  set("TreeFileWarn", { fg = c.yellow, bold = true })  -- Fichier avec warnings
  
  -- Statusline
  set("StatusLineNormal", { fg = c.blue, bg = c.bg_highlight, bold = true })
  set("StatusLineInsert", { fg = c.green, bg = c.bg_highlight, bold = true })
  set("StatusLineVisual", { fg = c.magenta, bg = c.bg_highlight, bold = true })
  set("StatusLineReplace", { fg = c.red, bg = c.bg_highlight, bold = true })
  set("StatusLineCmd", { fg = c.yellow, bg = c.bg_highlight, bold = true })
  
  -- Tabline
  set("TabLine", { fg = c.comment, bg = c.bg_dark })
  set("TabLineSel", { fg = c.blue, bg = c.bg, bold = true })
  set("TabLineFill", { bg = c.bg_dark })
  set("TabLineSeparator", { fg = c.fg_gutter, bg = c.bg_dark })
  
  -- Tabline with diagnostics
  set("TabLineError", { fg = c.red, bg = c.bg_dark, bold = true })
  set("TabLineWarn", { fg = c.yellow, bg = c.bg_dark, bold = true })
  set("TabLineSelError", { fg = c.red, bg = c.bg, bold = true })
  set("TabLineSelWarn", { fg = c.yellow, bg = c.bg, bold = true })

  -- LSP Diagnostics (Native)
  set("DiagnosticError", { fg = c.red })
  set("DiagnosticWarn", { fg = c.yellow })
  set("DiagnosticInfo", { fg = c.blue })
  set("DiagnosticHint", { fg = c.cyan })
  
  -- LSP Signs (Gutter)
  set("DiagnosticSignError", { fg = c.red, bold = true })
  set("DiagnosticSignWarn", { fg = c.yellow, bold = true })
  set("DiagnosticSignInfo", { fg = c.blue })
  set("DiagnosticSignHint", { fg = c.cyan })
  
  -- LSP Underline
  set("DiagnosticUnderlineError", { underline = true, sp = c.red })
  set("DiagnosticUnderlineWarn", { underline = true, sp = c.yellow })
  set("DiagnosticUnderlineInfo", { underline = true, sp = c.blue })
  set("DiagnosticUnderlineHint", { underline = true, sp = c.cyan })
  
  -- LSP Floating Window
  set("DiagnosticFloatingError", { fg = c.red, bg = c.bg_dark })
  set("DiagnosticFloatingWarn", { fg = c.yellow, bg = c.bg_dark })
  set("DiagnosticFloatingInfo", { fg = c.blue, bg = c.bg_dark })
  set("DiagnosticFloatingHint", { fg = c.cyan, bg = c.bg_dark })
  
  -- Line highlight for errors (optional)
  set("DiagnosticLineError", { bg = "#3b2020" })  -- Rouge très subtil

  -- Pmenu
  set("Pmenu", { bg = c.bg_dark, fg = c.fg })
  set("PmenuSel", { bg = c.bg_visual, fg = "NONE", bold = true })
  set("PmenuThumb", { bg = c.fg_gutter })

  -- Illuminate (word highlight under cursor)
  set("IlluminatedWord", { bg = "#2f3346", fg = c.fg })

  -- Marks
  set("MarkSign", { fg = c.yellow, bold = true })

  -- Git Dashboard Syntax Highlighting
  set("GitStatusStaged", { fg = c.green, bold = true })
  set("GitStatusUnstaged", { fg = c.yellow })
  set("GitStatusUntracked", { fg = c.red })
  set("GitStatusModified", { fg = c.orange })
  set("GitStatusAdded", { fg = c.green })
  set("GitStatusDeleted", { fg = c.red })
  set("GitStatusRenamed", { fg = c.purple })
  set("GitBranchCurrent", { fg = c.green, bold = true })
  set("GitBranchLocal", { fg = c.blue })
  set("GitBranchRemote", { fg = c.purple })
  set("GitLogGraph", { fg = c.fg_gutter })
  set("GitLogHash", { fg = c.orange, bold = true })
  set("GitLogRef", { fg = c.blue })
  set("GitLogHead", { fg = c.green, bold = true })

end

return M
