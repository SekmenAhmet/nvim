-- Measure startup time
local start_time = vim.loop.hrtime()

-- Optimize Lua module loading
if vim.loader then vim.loader.enable() end

-- Disable default Netrw (Must be done before startup finishes)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Entry point
require("config.options")
require("config.lazy")
require("config.keymaps")
require("config.moves")
require("config.statusline")
require("config.tabline")
require("config.highlights")

-- Defer non-critical modules to unblock UI painting
vim.schedule(function()
  require("config.netrw") -- Custom Tree
  require("config.ui")    -- Custom UI
  require("config.autopairs")
  require("config.finder")
  require("config.grep")
  require("config.terminal")
  require("config.completion")
  require("config.autocmds")
  
  -- Startup time report
  local end_time = vim.loop.hrtime()
  local startup_ms = (end_time - start_time) / 1e6
  
  vim.api.nvim_create_user_command("StartupTime", function()
    print(string.format("⚡ Neovim chargé en %.2f ms", startup_ms))
  end, {})

  print(string.format("⚡ Neovim chargé en %.2f ms", startup_ms))
end)
