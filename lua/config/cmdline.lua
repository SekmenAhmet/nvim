-- Native Floating Cmdline (Replace :)
-- Architecture: Floating Window + vim.fn.getcompletion

local M = {}
local api = vim.api
local window = require("utils")

-- State
local state = {
  buf = nil,
  win = nil,
}

function M.open()
  state.original_guicursor = vim.o.guicursor
  
  -- Create Floating Window
  local buf, win = window.create_centered_win({
    width_pct = 0.3,
    height = 1,
    title = "Command",
    row_offset = 0,
    enter = true,
  })
  
  state.buf = buf
  state.win = win
  
  -- Configure Buffer
  vim.bo[buf].modifiable = true
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  
  api.nvim_buf_set_lines(buf, 0, -1, false, {"  : "})
  
  vim.cmd("startinsert!")
  api.nvim_win_set_cursor(win, {1, 4})
  
  -- Enforce Padding and prevent editing the prefix
  api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    callback = function()
      local line = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
      if not line:match("^  : ") then
         local content = line:gsub("^%s*:?%s*", "")
         local fixed = "  : " .. content
         api.nvim_buf_set_lines(buf, 0, 1, false, {fixed})
         local cursor = api.nvim_win_get_cursor(win)
         api.nvim_win_set_cursor(win, {1, math.max(4, cursor[2])})
      end
    end
  })

  -- Block cursor from going before the prefix
  api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    buffer = buf,
    callback = function()
      local cursor = api.nvim_win_get_cursor(win)
      if cursor[2] < 4 then
        api.nvim_win_set_cursor(win, {1, 4})
      end
    end
  })
  
  -- Auto-close on leave
  api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function() M.close() end
  })

  -- Keymaps
  local opts = { buffer = buf, silent = true }
  
  -- Execute
  vim.keymap.set("i", "<CR>", function()
    local line = api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    local cmd = line:gsub("^  : ", "")
    M.close()
    if cmd ~= "" then
      local ok, out = pcall(api.nvim_exec2, cmd, { output = true })
      if not ok then
        vim.notify(out, vim.log.levels.ERROR)
      elseif out and out.output ~= "" then
        vim.notify(out.output, vim.log.levels.INFO)
      end
    end
  end, opts)
  
  vim.keymap.set({"i", "n"}, "<Esc>", M.close, opts)
  vim.keymap.set({"i", "n"}, "<C-c>", M.close, opts)
  
  -- Completion
  vim.keymap.set("i", "<Tab>", function()
    local line = api.nvim_get_current_line()
    local cmd_part = line:gsub("^  : ", "")
    local items = vim.fn.getcompletion(cmd_part, "cmdline")
    if #items > 0 then
      api.nvim_set_current_line("  : " .. items[1])
      api.nvim_feedkeys(api.nvim_replace_termcodes("<End>", true, false, true), "n", false)
    end
  end, opts)
end

function M.close()
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  vim.cmd("stopinsert")
end

return M
