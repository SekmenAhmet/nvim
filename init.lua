-- Measure startup time
local start_time = vim.loop.hrtime()

-- 1. Disable Useless Providers (Optimization)
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0

-- 2. Disable Built-in Plugins (Optimization)
local builtins = {
  "netrw", "netrwPlugin", "netrwSettings", "netrwFileHandlers",
  "gzip", "zip", "zipPlugin", "tar", "tarPlugin",
  "getscript", "getscriptPlugin", "vimball", "vimballPlugin",
  "2html_plugin", "logipat", "rrhelper", "spellfileplugin", "matchit"
}

for _, plugin in ipairs(builtins) do
  vim.g["loaded_" .. plugin] = 1
end

-- Optimize Lua module loading
if vim.loader then vim.loader.enable() end

-- Entry point
require("config.options")
require("config.colors").setup() -- Load Theme immediately
require("config.lazy")
require("config.keymaps") -- Keymaps now handle lazy loading triggers
require("config.moves")
require("config.statusline")
require("config.tabline")
-- require("config.highlights") -- Remplacé par Treesitter

-- Defer non-critical modules to unblock UI painting
vim.schedule(function()
  -- These are now loaded lazily via keymaps in config.keymaps
  -- require("config.netrw") 
  -- require("config.finder")
  -- require("config.grep")
  -- require("config.terminal")
  
  -- Still load these as they might have autocommands or setup
  require("config.ui")
  require("config.autocmds")
  
  -- Startup time report
  local end_time = vim.loop.hrtime()
  local startup_ms = (end_time - start_time) / 1e6
  vim.g.startup_time = startup_ms -- Global variable for statusline
  
  vim.api.nvim_create_user_command("StartupTime", function()
    print(string.format("⚡ Neovim chargé en %.2f ms", startup_ms))
  end, {})
end)

-- Lazy load interaction heavy modules on InsertEnter
vim.api.nvim_create_autocmd("InsertEnter", {
  once = true,
  callback = function()
    require("config.autopairs")
    require("config.completion")
  end
})