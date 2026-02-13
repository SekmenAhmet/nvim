local runner = require("tests.runner")
local utils = require("utils")

local M = {}

function M.run_monkey_test()
  local iterations = 100
  local actions = {
    -- Navigation
    { name = "Next Buffer", fn = function() vim.cmd("bnext") end },
    { name = "Prev Buffer", fn = function() vim.cmd("bprev") end },
    
    -- Modules
    { name = "Toggle Git", fn = function() require("config.git").toggle() end },
    { name = "Toggle Project", fn = function() require("config.project").toggle() end },
    { name = "Toggle Docker", fn = function() require("config.docker").toggle() end },
    { name = "Toggle Terminal", fn = function() require("config.terminal").toggle() end },
    { name = "Toggle Netrw", fn = function() require("config.netrw").toggle() end },
    { name = "Toggle REST", fn = function() require("config.rest").toggle() end },
    
    -- Finder & Grep (these usually open pickers)
    { name = "Open Finder", fn = function() require("config.finder").open() end },
    { name = "Open Grep", fn = function() require("config.grep").open() end },
    
    -- UI
    { name = "Resize Up", fn = function() vim.cmd("resize +2") end },
    { name = "Resize Down", fn = function() vim.cmd("resize -2") end },
    { name = "Close Window", fn = function() pcall(vim.cmd, "close") end },
    
    -- Buffer operations
    { name = "Smart Delete", fn = function() 
      -- Mock confirm for monkey test
      local old_confirm = vim.fn.confirm
      vim.fn.confirm = function() return 2 end -- "Non (perdre)"
      vim.api.nvim_input("\\x") -- Assuming leader is \
      vim.fn.confirm = old_confirm
    end },
    
    -- AI (Mocking input)
    { name = "AI Prompt Mock", fn = function()
        local old_input = vim.fn.input
        vim.fn.input = function() return "Explain this code" end
        require("utils.ai").generate("Explain this code", nil, function(response, err)
           -- Callback handled
        end)
        vim.fn.input = old_input
    end },

    -- UI Specific
    { name = "Dashboard", fn = function() require("config.dashboard").open() end },
  }

  local function check_ui_stability()
    -- Check statusline
    local ok_st, st = pcall(vim.api.nvim_get_option_value, "statusline", {})
    if not ok_st then error("Statusline option is invalid") end
    
    -- Try to evaluate statusline if it's a lua expression (common in this config)
    if st:match("%%!") then
      local expr = st:gsub("%%!", "")
      local ok_eval = pcall(vim.api.nvim_eval, expr)
      if not ok_eval then error("Statusline evaluation failed: " .. expr) end
    end

    -- Check tabline
    local ok_tb, tb = pcall(vim.api.nvim_get_option_value, "tabline", {})
    if ok_tb and tb:match("%%!") then
      local expr = tb:gsub("%%!", "")
      local ok_eval = pcall(vim.api.nvim_eval, expr)
      if not ok_eval then error("Tabline evaluation failed: " .. expr) end
    end
  end

  print("Starting Monkey Test with " .. iterations .. " iterations...")

  for i = 1, iterations do
    local action = actions[math.random(#actions)]
    
    local ok, err = pcall(action.fn)
    if not ok then
      error(string.format("Monkey test failed at iteration %d during '%s': %s", i, action.name, err))
    end
    
    -- Post-action UI check
    local ok_ui, ui_err = pcall(check_ui_stability)
    if not ok_ui then
      error(string.format("UI instability detected after '%s' at iteration %d: %s", action.name, i, ui_err))
    end
    
    -- Slight delay
    vim.wait(20) 
  end
  
  print("Monkey Test completed successfully.")
end

runner.run("Monkey Test Suite", {
  ["Chaos Run"] = function(done)
    local ok, err = pcall(M.run_monkey_test)
    done(ok, err)
  end
})
