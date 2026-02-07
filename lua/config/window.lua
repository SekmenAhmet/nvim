-- UI Window Component Library (Standardized)
-- Provides reusable window management utilities
-- Uses utils module for core functionality
-- Used by: finder.lua, grep.lua, search.lua, cmdline.lua, terminal.lua

local M = {}
local api = vim.api
local utils = require("utils")

-- Create a centered dual-pane window (list + preview)
-- Returns: { buf_list, win_list, buf_preview, win_preview }
function M.create_dual_pane(opts)
  return utils.create_dual_pane(opts)
end

-- Apply standard styling to list window
function M.apply_list_styling(win, buf)
  vim.wo[win].cursorline = true
  vim.wo[win].winhl = "NormalFloat:Normal,CursorLine:Visual"
  vim.bo[buf].buftype = "nofile"
  vim.wo[win].cursorcolumn = false
  vim.wo[win].list = false
  vim.wo[win].wrap = false
end

-- Apply standard styling to preview window
function M.apply_preview_styling(win, buf)
  vim.wo[win].winhl = "NormalFloat:Normal"
  vim.bo[buf].buftype = "nofile"
  vim.wo[win].wrap = false
end

-- Setup scroll preview keymaps (C-d / C-u)
function M.setup_scroll_preview(state, buf_list)
  buf_list = buf_list or state.buf_list
  
  local function scroll_preview(direction)
    if state.win_preview and api.nvim_win_is_valid(state.win_preview) then
      api.nvim_win_call(state.win_preview, function()
        local key = direction > 0 and "<C-d>" or "<C-u>"
        vim.cmd("normal! " .. api.nvim_replace_termcodes(key, true, false, true))
      end)
    end
  end
  
  vim.keymap.set({"i", "n"}, "<C-d>", function() scroll_preview(1) end, { buffer = buf_list })
  vim.keymap.set({"i", "n"}, "<C-u>", function() scroll_preview(-1) end, { buffer = buf_list })
end

-- Setup auto-close: when list closes, close preview and cleanup
function M.setup_auto_close(state, opts)
  opts = opts or {}
  local on_close = opts.on_close

  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win_list),
    once = true,
    callback = function()
      -- Close preview window
      if state.win_preview and api.nvim_win_is_valid(state.win_preview) then
        api.nvim_win_close(state.win_preview, true)
      end
      
      -- Cleanup job handle if present
      if state.job_handle and not state.job_handle:is_closing() then
        state.job_handle:close()
      end
      
      -- Call custom cleanup if provided
      if on_close then
        on_close()
      end
    end,
  })
end

-- Close windows gracefully
function M.close_windows(state)
  if state.win_list and api.nvim_win_is_valid(state.win_list) then
    api.nvim_win_close(state.win_list, true)
  end
end

-- Create a simple centered floating window
function M.create_centered(opts)
  return utils.create_centered_win(opts)
end

return M
