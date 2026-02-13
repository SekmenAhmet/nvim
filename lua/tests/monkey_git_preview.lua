local runner = require("tests.runner")
local State = require("core.state")
local GitController = require("modules.git.controller")
local GitView = require("modules.git.view")

runner.run("Git Preview Monkey Test", {
  ["Rapid Selection Burst"] = function(done)
    vim.schedule(function()
      if not State.get("git.is_active") then
        GitController.toggle()
      end
      
      vim.defer_fn(function()
        GitController.switch_pane("files")
        local win = GitView.wins.files
        
        local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
        print("Starting burst moves on " .. line_count .. " lines")
        
        local iterations = 10
        
        local function burst(count)
          if count <= 0 then
            vim.defer_fn(function()
                local preview_comp = GitView.components.preview
                local pane = State.get("git.active_pane")
                local idx = State.get("git.selected_indices." .. pane)
                local entities = State.get("git.entities." .. pane)
                local entity = entities[idx]
                local lines = vim.api.nvim_buf_get_lines(preview_comp.buf, 0, -1, false)
                
                print(string.format("Final Selection: [%d] %s", idx, entity and entity.path or "unknown"))
                print("Final preview lines: " .. #lines)
                if #lines > 1 then
                    print("First line: " .. lines[1])
                end
                
                done(true)
            end, 1000)
            return
          end
          
          local new_line = (count % 2 == 0) and 1 or 2
          if line_count < 2 then new_line = 1 end
          
          vim.api.nvim_win_set_cursor(win, {new_line, 0})
          -- Manually trigger the state update since CursorMoved might be flaky in headless
          State.set("git.selected_indices.files", new_line)
          
          vim.defer_fn(function()
            burst(count - 1)
          end, 50)
        end
        
        burst(iterations)
      end, 500)
    end)
  end
})
