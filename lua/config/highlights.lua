local colors = require("config.colors")

vim.opt.termguicolors = true

-- =============================================================================
--  THEME SETUP (Tokyo Night Refined)
-- =============================================================================

-- Editor UI
vim.api.nvim_set_hl(0, "Normal", { fg = colors.fg, bg = colors.bg })
vim.api.nvim_set_hl(0, "NormalFloat", { fg = colors.fg, bg = colors.bg_light })
vim.api.nvim_set_hl(0, "FloatBorder", { fg = colors.blue, bg = colors.bg_light })
vim.api.nvim_set_hl(0, "Cursor", { bg = colors.fg, fg = colors.bg })
vim.api.nvim_set_hl(0, "CursorLine", { bg = colors.bg_highlight })
vim.api.nvim_set_hl(0, "LineNr", { fg = colors.gray })
vim.api.nvim_set_hl(0, "CursorLineNr", { fg = colors.cyan, bold = true })
vim.api.nvim_set_hl(0, "Visual", { bg = colors.gray_dark })
vim.api.nvim_set_hl(0, "Search", { fg = colors.bg, bg = colors.yellow })
vim.api.nvim_set_hl(0, "IncSearch", { fg = colors.bg, bg = colors.red })

-- Syntax Groups
vim.api.nvim_set_hl(0, "Comment", { fg = colors.gray, italic = true })
vim.api.nvim_set_hl(0, "String", { fg = colors.green })
vim.api.nvim_set_hl(0, "Character", { fg = colors.green })
vim.api.nvim_set_hl(0, "Number", { fg = colors.yellow })
vim.api.nvim_set_hl(0, "Boolean", { fg = colors.yellow, bold = true })
vim.api.nvim_set_hl(0, "Float", { fg = colors.yellow })

-- Identifiers & Variables
vim.api.nvim_set_hl(0, "Identifier", { fg = colors.purple }) 
vim.api.nvim_set_hl(0, "Variable", { fg = colors.purple })
vim.api.nvim_set_hl(0, "Parameter", { fg = colors.yellow })

-- Functions
vim.api.nvim_set_hl(0, "Function", { fg = colors.blue, bold = true })

-- Keywords & Statements
vim.api.nvim_set_hl(0, "Statement", { fg = colors.purple }) 
vim.api.nvim_set_hl(0, "Conditional", { fg = colors.purple })
vim.api.nvim_set_hl(0, "Repeat", { fg = colors.purple })
vim.api.nvim_set_hl(0, "Keyword", { fg = colors.purple, italic = true })
vim.api.nvim_set_hl(0, "Operator", { fg = colors.cyan })

-- Types & Objects
vim.api.nvim_set_hl(0, "Type", { fg = colors.cyan })
vim.api.nvim_set_hl(0, "Structure", { fg = colors.cyan })
vim.api.nvim_set_hl(0, "StorageClass", { fg = colors.cyan })

vim.api.nvim_set_hl(0, "PreProc", { fg = colors.red })
vim.api.nvim_set_hl(0, "Include", { fg = colors.blue })

vim.api.nvim_set_hl(0, "Special", { fg = colors.blue })
vim.api.nvim_set_hl(0, "Delimiter", { fg = colors.fg })

-- Tree specific
vim.api.nvim_set_hl(0, "TreeDir", { fg = colors.blue, bold = true })
vim.api.nvim_set_hl(0, "TreeFile", { fg = colors.fg })
vim.api.nvim_set_hl(0, "TreeRoot", { fg = colors.red, bold = true })

-- =============================================================================
--  AUTO HIGHLIGHT WORD UNDER CURSOR
-- =============================================================================

vim.opt.updatetime = 300
local function set_highlight()
  local current_word = vim.fn.expand('<cword>')
  if current_word == "" then return end
  local escaped_word = vim.fn.escape(current_word, [[/\]])
  vim.b.current_word_match = vim.fn.matchadd('Visual', [[\<]] .. escaped_word .. [[\>]], -1)
end

local function clear_highlight()
  if vim.b.current_word_match then
    pcall(vim.fn.matchdelete, vim.b.current_word_match)
    vim.b.current_word_match = nil
  end
end

local grp = vim.api.nvim_create_augroup("AutoHighlight", { clear = true })
vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
  group = grp,
  callback = set_highlight,
})
vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
  group = grp,
  callback = clear_highlight,
})