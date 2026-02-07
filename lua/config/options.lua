-- Options générales
vim.g.mapleader = " "

-- Detect OS and set Shell
if vim.uv.os_uname().sysname == "Windows_NT" then
  vim.opt.shell = "powershell"
else
  -- Linux/Mac
  vim.opt.shell = "fish"
end

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.mouse = "a"
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.completeopt = "menu,menuone,noinsert,noselect"
vim.opt.undofile = true
vim.opt.list = true
-- Ensure no dots for leading spaces ("lead" defaults to Space if not set, but let's be explicit)
vim.opt.listchars = { trail = "·", nbsp = "␣", tab = "  ", lead = " " }

-- LSP hover diagnostics delay
vim.opt.updatetime = 500

-- UI optimizations
vim.opt.shortmess:append("I") -- Disable intro screen
vim.opt.fillchars = {
  eob = " ",     -- Hide end-of-buffer tildes
  fold = " ",    -- Fold character
  diff = "╱",    -- Diff separator
  vert = "│",    -- Vertical split
}
