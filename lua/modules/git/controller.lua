local api = vim.api
local State = require("core.state")
local Model = require("modules.git.model")
local View = require("modules.git.view")

local M = {}

function M.refresh()
  Model.refresh_all()
end

function M.toggle()
  local is_active = not State.get("git.is_active")
  State.set("git.is_active", is_active)
  
  if is_active then
    -- Detect repo root
    local git_dir = vim.fn.finddir(".git", vim.fn.getcwd() .. ";")
    local root = git_dir ~= "" and vim.fn.fnamemodify(git_dir, ":p:h:h") or vim.fn.getcwd()
    State.set("git.repo_root", root)
    
    View.layout()
    M.setup_autocmds()
    M.setup_keymaps()
    M.refresh()
  else
    View.close()
  end
end

function M.setup_autocmds()
  local augroup = api.nvim_create_augroup("GitDashboardMVC", { clear = true })
  
  local panes = { "commit", "files", "branches", "stashes", "preview" }
  for _, pane in ipairs(panes) do
    local component = View.components[pane]
    local buf = component and component.buf
    if buf and api.nvim_buf_is_valid(buf) then
      api.nvim_create_autocmd("CursorMoved", {
        buffer = buf,
        group = augroup,
        callback = function()
          local idx = api.nvim_win_get_cursor(0)[1]
          if pane ~= "preview" then
            State.set("git.active_pane", pane)
            State.set("git.selected_indices." .. pane, idx)
          end
        end
      })
    end
  end
  
  -- Handle WinClosed to cleanup state if a main window is closed manually
  local main_win = View.wins.commit
  if main_win and api.nvim_win_is_valid(main_win) then
    api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(main_win),
      group = augroup,
      callback = function()
        if State.get("git.is_active") then
          State.set("git.is_active", false)
          View.close()
        end
      end
    })
  end
end

function M.switch_pane(target)
  if not target then
    local current = State.get("git.active_pane")
    if current == "commit" then target = "files"
    elseif current == "files" then target = "branches"
    elseif current == "branches" then target = "stashes"
    else target = "commit" end
  end
  
  local win = View.wins[target]
  if win and api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
    State.set("git.active_pane", target)
  end
end

function M.setup_keymaps()
  local panes = { "commit", "files", "branches", "stashes", "preview", "log" }
  for _, pane in ipairs(panes) do
    local component = View.components[pane]
    local buf = component and component.buf
    if buf and api.nvim_buf_is_valid(buf) then
      local opts = { buffer = buf, silent = true }
      
      -- Global Git Actions (Toggles)
      vim.keymap.set({"n", "i", "v", "t"}, "<C-g>", M.toggle, opts)
      vim.keymap.set({"n", "i", "v", "t"}, "<Esc>", M.toggle, opts)
      vim.keymap.set("n", "q", M.toggle, opts)
      
      -- Secondary Toggles
      vim.keymap.set({"n", "i", "v", "t"}, "<C-b>", View.toggle_log, opts)
      
      vim.keymap.set("n", "<Tab>", function() M.switch_pane() end, opts)
      vim.keymap.set("n", "r", M.refresh, opts)
      vim.keymap.set("n", "P", function() Model.push(M.refresh) end, opts)
      vim.keymap.set("n", "p", function() Model.pull(M.refresh) end, opts)
      
      -- Navigation
      vim.keymap.set("n", "<C-l>", function() M.switch_pane("preview") end, opts)
      
      if pane == "commit" then
        vim.keymap.set("n", "<C-j>", function() M.switch_pane("files") end, opts)
        vim.keymap.set("n", "<C-CR>", function()
          local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
          local msg = table.concat(lines, "\n"):gsub("^%s*", ""):gsub("%s*$", "")
          if msg ~= "" then
            Model.commit(msg, function(success)
              if success then
                api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
                M.refresh()
              end
            end)
          else
            vim.notify("Empty commit message", vim.log.levels.WARN)
          end
        end, opts)
        vim.keymap.set("n", "<Leader>g", function()
          Model.generate_commit_msg(function(msg)
            if msg then
              api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(msg, "\n"))
            end
          end)
        end, opts)
        
      elseif pane == "files" then
        vim.keymap.set("n", "<C-k>", function() M.switch_pane("commit") end, opts)
        vim.keymap.set("n", "<C-j>", function() M.switch_pane("branches") end, opts)
        vim.keymap.set("n", "<CR>", function()
          local idx = State.get("git.selected_indices.files")
          local file = State.get("git.entities.files")[idx]
          if file then Model.stage(file.path, file.staged, M.refresh) end
        end, opts)
        vim.keymap.set("n", "S", function() Model.stage_all(M.refresh) end, opts)
        vim.keymap.set("n", "U", function() Model.unstage_all(M.refresh) end, opts)
        vim.keymap.set("n", "D", function()
          local idx = State.get("git.selected_indices.files")
          local file = State.get("git.entities.files")[idx]
          if file and vim.fn.confirm("Discard changes in " .. file.path .. "?", "&Yes\n&No") == 1 then
            Model.discard(file.path, M.refresh)
          end
        end, opts)
        
      elseif pane == "branches" then
        vim.keymap.set("n", "<C-k>", function() M.switch_pane("files") end, opts)
        vim.keymap.set("n", "<C-j>", function() M.switch_pane("stashes") end, opts)
        vim.keymap.set("n", "<CR>", function()
          local idx = State.get("git.selected_indices.branches")
          local branch = State.get("git.entities.branches")[idx]
          if branch then Model.checkout(branch.name, M.refresh) end
        end, opts)

      elseif pane == "stashes" then
        vim.keymap.set("n", "<C-k>", function() M.switch_pane("branches") end, opts)
        vim.keymap.set("n", "<CR>", function()
          local idx = State.get("git.selected_indices.stashes")
          local stash = State.get("git.entities.stashes")[idx]
          if stash then
            local action = vim.fn.confirm("Stash action for " .. stash.id .. "?", "&Apply\n&Pop\n&Drop\n&Cancel")
            local actions = { "apply", "pop", "drop" }
            if actions[action] then
              Model.stash_apply(stash.id, actions[action], M.refresh)
            end
          end
        end, opts)
        
      elseif pane == "preview" then
        vim.keymap.set("n", "<C-h>", function() M.switch_pane("files") end, opts)
        vim.keymap.set("n", "s", function() M.handle_hunk(false) end, opts)
        vim.keymap.set("n", "u", function() M.handle_hunk(true) end, opts)
      end
    end
  end
end

function M.handle_hunk(reverse)
  local buf = View.components.preview.buf
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor_line = api.nvim_win_get_cursor(0)[1]
  
  local header = {}
  local first_hunk_idx = -1
  for i, line in ipairs(lines) do
    if line:match("^@@") then first_hunk_idx = i break end
    table.insert(header, line)
  end
  if first_hunk_idx == -1 then return end
  
  local hunk_start = -1
  for i = cursor_line, 1, -1 do
    if lines[i]:match("^@@") then hunk_start = i break end
  end
  if hunk_start == -1 then return end
  
  local hunk_end = -1
  for i = hunk_start + 1, #lines do
    if lines[i]:match("^@@") or lines[i]:match("^diff %-%-git") then
      hunk_end = i - 1
      break
    end
  end
  if hunk_end == -1 then hunk_end = #lines end
  
  local patch_lines = {}
  for _, l in ipairs(header) do table.insert(patch_lines, l) end
  for i = hunk_start, hunk_end do table.insert(patch_lines, lines[i]) end
  local patch = table.concat(patch_lines, "\n") .. "\n"
  
  Model.apply_hunk(patch, reverse, M.refresh)
end

return M
