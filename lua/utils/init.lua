-- Utils: Common utilities for Neovim config
-- Centralizes duplicated patterns across modules

local M = {}
local api = vim.api

-- =============================================================================
-- WINDOW UTILITIES
-- =============================================================================

-- Create a centered floating window
-- @param opts table: { width_pct, height, height_pct, title, row_offset }
-- @return table: { buf = number, win = number }
function M.create_centered_win(opts)
  opts = opts or {}
  local width_pct = opts.width_pct or 0.25
  local height = opts.height
  local height_pct = opts.height_pct
  local title = opts.title or ""
  local row_offset = opts.row_offset or 2

  -- Calculate height
  if not height and height_pct then
    height = math.floor(vim.o.lines * height_pct)
  elseif not height then
    height = 1
  end

  local width = math.floor(vim.o.columns * width_pct)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = row_offset

  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title ~= "" and (" " .. title .. " ") or nil,
    title_pos = "left",
  })

  vim.wo[win].winhl = "NormalFloat:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual"
  vim.bo[buf].buftype = "nofile"

  return { buf = buf, win = win }
end

-- Create a dual-pane window (list + preview)
-- @param opts table: { width_pct, height_pct, preview_width_pct, list_title, preview_title, list_filetype, preview_filetype }
-- @return table: { buf_list, win_list, buf_preview, win_preview }
function M.create_dual_pane(opts)
  opts = opts or {}
  local width_pct = opts.width_pct or 0.7
  local height_pct = opts.height_pct or 0.8
  local preview_width_pct = opts.preview_width_pct or 0.6
  local list_title = opts.list_title or " List "
  local preview_title = opts.preview_title or " Preview "
  local list_filetype = opts.list_filetype
  local preview_filetype = opts.preview_filetype

  local total_width = math.floor(vim.o.columns * width_pct)
  local total_height = math.floor(vim.o.lines * height_pct)
  local row = math.floor((vim.o.lines - total_height) / 2)
  local col = math.floor((vim.o.columns - total_width) / 2)
  local preview_width = math.floor(total_width * preview_width_pct)
  local list_width = total_width - preview_width - 2

  -- Create buffers
  local buf_list = api.nvim_create_buf(false, true)
  local buf_preview = api.nvim_create_buf(false, true)

  -- Set filetypes if provided
  if list_filetype then
    vim.bo[buf_list].filetype = list_filetype
  end
  if preview_filetype then
    vim.bo[buf_preview].filetype = preview_filetype
  end

  -- Create windows
  local win_list = api.nvim_open_win(buf_list, true, {
    relative = "editor",
    width = list_width,
    height = total_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. list_title .. " ",
  })

  local win_preview = api.nvim_open_win(buf_preview, false, {
    relative = "editor",
    width = preview_width,
    height = total_height,
    row = row,
    col = col + list_width + 2,
    style = "minimal",
    border = "rounded",
    title = " " .. preview_title .. " ",
  })

  -- Apply common styling
  vim.wo[win_list].cursorline = true
  vim.wo[win_list].winhl = "NormalFloat:Normal,CursorLine:Visual"
  vim.bo[buf_list].buftype = "nofile"
  vim.wo[win_list].cursorcolumn = false
  vim.wo[win_list].list = false
  vim.wo[win_list].wrap = false
  
  vim.wo[win_preview].winhl = "NormalFloat:Normal"
  vim.bo[buf_preview].buftype = "nofile"
  vim.wo[win_preview].wrap = false

  return {
    buf_list = buf_list,
    win_list = win_list,
    buf_preview = buf_preview,
    win_preview = win_preview,
  }
end

-- =============================================================================
-- TIMER UTILITIES
-- =============================================================================

-- Create a debounced function
-- @param ms number: debounce delay in milliseconds
-- @param fn function: function to debounce
-- @return function: debounced function
function M.debounce(ms, fn)
  local timer = vim.uv.new_timer()
  return function(...)
    local args = {...}
    timer:stop()
    timer:start(ms, 0, vim.schedule_wrap(function()
      fn(unpack(args))
    end))
  end
end

-- =============================================================================
-- STATE UTILITIES
-- =============================================================================

-- Create a standardized state template for UI modules
-- @return table: state object with cleanup method
function M.create_state()
  return {
    buf = nil,
    win = nil,
    autocmds = {},
    timers = {},
    
    -- Add autocmd to state for automatic cleanup
    add_autocmd = function(self, event, opts)
      local id = api.nvim_create_autocmd(event, opts)
      table.insert(self.autocmds, id)
      return id
    end,
    
    -- Add timer to state for automatic cleanup
    add_timer = function(self, timer)
      table.insert(self.timers, timer)
      return timer
    end,
    
    -- Cleanup all resources
    cleanup = function(self)
      -- Close window if valid
      if self.win and api.nvim_win_is_valid(self.win) then
        api.nvim_win_close(self.win, true)
      end
      
      -- Delete autocmds
      for _, id in ipairs(self.autocmds) do
        pcall(api.nvim_del_autocmd, id)
      end
      self.autocmds = {}
      
      -- Stop timers
      for _, timer in ipairs(self.timers) do
        if timer and not timer:is_closing() then
          timer:stop()
        end
      end
      self.timers = {}
    end
  }
end

-- =============================================================================
-- STRING UTILITIES
-- =============================================================================

-- Trim trailing whitespace from buffer
-- Uses native vim command for performance
-- @param bufnr number: buffer number (default: current buffer)
function M.trim_trailing_whitespace(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  api.nvim_buf_call(bufnr, function()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
  end)
end

return M
