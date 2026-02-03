-- Setup lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
  -- Disable Luarocks handling (we use system packages or don't need rocks)
  rocks = {
    enabled = false,
    hererocks = false, 
  },
})
