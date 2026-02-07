-- Options générales
vim.g.mapleader = " "

-- Detect OS and set Shell (cached for performance)
vim.g._shell_cache = vim.g._shell_cache or (
  vim.uv.os_uname().sysname == "Windows_NT" and "powershell" or "fish"
)
vim.opt.shell = vim.g._shell_cache

-- Editor options
local opts = {
  number         = true,
  relativenumber = true,
  tabstop        = 2,
  shiftwidth     = 2,
  expandtab      = true,
  smartindent    = true,
  wrap           = false,
  cursorline     = true,
  clipboard      = "unnamedplus",
  ignorecase     = true,
  smartcase      = true,
  mouse          = "a",
  splitbelow     = true,
  splitright     = true,
  scrolloff      = 8,
  signcolumn     = "yes",
  undofile       = true,
  list           = true,
  updatetime     = 500,
}

for k, v in pairs(opts) do
  vim.opt[k] = v
end

vim.opt.listchars = { trail = "·", nbsp = "␣", tab = "  ", lead = " " }

-- UI optimizations
vim.opt.shortmess:append("I")
vim.opt.fillchars = {
  eob = " ",
  fold = " ",
  diff = "╱",
  vert = "│",
}
