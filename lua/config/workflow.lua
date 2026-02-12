-- Workflow Integrator: Cross-tool automation
-- Bridge between Docker, Git, and REST
local M = {}

local function setup_docker_git_bridge()
  -- If we are in a docker-compose.yml, provide context-aware commands
  vim.api.nvim_create_autocmd("BufEnter", {
    pattern = { "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml" },
    callback = function()
      -- Could add buffer-local keymaps here to trigger docker actions
      local opts = { buffer = 0, silent = true }
      vim.keymap.set("n", "<leader>du", function() 
        require("modules.docker.controller").toggle() 
        -- Optional: automatically trigger 'up'
      end, vim.tbl_extend("force", opts, { desc = "Open Docker Client for this project" }))
    end
  })
end

local function setup_rest_git_bridge()
  -- If a REST request is successful, maybe we want to log it or something
  -- Currently we use core/state to notify changes
  local State = require("core.state")
  State.subscribe("rest.last_status", function(status)
    if status:match("^HTTP/%d%.%d 2") then
      -- Success notification already handled by view, but we could do more here
    end
  end)
end

function M.setup()
  setup_docker_git_bridge()
  setup_rest_git_bridge()
end

return M
