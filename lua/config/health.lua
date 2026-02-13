local M = {}

function M.check()
  local health = vim.health
  health.start("Native IDE Configuration")
  
  -- 1. Check Dependencies
  health.info("Checking system dependencies...")
  local deps = {
    { cmd = "git", desc = "Git CLI" },
    { cmd = "docker", desc = "Docker CLI" },
    { cmd = "curl", desc = "Curl (for AI/REST)" },
    { cmd = "jq", desc = "JQ (for JSON formatting)" },
    { cmd = "rg", desc = "Ripgrep (for Finder)" },
    { cmd = "ollama", desc = "Ollama (for AI)" },
  }
  
  for _, dep in ipairs(deps) do
    if vim.fn.executable(dep.cmd) == 1 then
      health.ok(dep.desc .. " is installed")
    else
      health.warn(dep.desc .. " not found")
    end
  end
  
  -- 2. Check Lua Modules
  health.info("Checking core Lua modules...")
  local modules = {
    "core.state", "utils.ui", "utils.process", 
    "modules.git.controller", "modules.docker.controller", 
    "modules.rest.controller", "modules.project.controller"
  }
  
  for _, mod in ipairs(modules) do
    local ok, err = pcall(require, mod)
    if ok then
      health.ok("Module '" .. mod .. "' loaded successfully")
    else
      health.error("Module '" .. mod .. "' failed to load: " .. tostring(err))
    end
  end
  
  -- 3. Check AI State
  health.info("Checking AI state...")
  local ai = require("utils.ai")
  if ai.is_ready() then
    health.ok("AI Engine is ready")
  else
    health.warn("AI Engine is not initialized (will initialize on first use)")
  end
end

-- Register as health provider (for :checkhealth)
-- Neovim looks for `check` function in `lua/**/health.lua` or `lua/**/health/init.lua`
-- But we can also just register a command.

vim.api.nvim_create_user_command("IDEHealth", M.check, {})

return M
