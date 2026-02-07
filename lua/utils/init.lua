-- Utils: Common utilities for Neovim config
-- Centralizes duplicated patterns across modules

local M = {}
local api = vim.api

-- =============================================================================
-- WINDOW UTILITIES
-- =============================================================================

-- Create a centered floating window
-- @param opts table: { width_pct, height_pct OR height (in lines), title, row_offset }
-- @return table: { buf = number, win = number }
function M.create_centered_win(opts)
  opts = opts or {}
  local width_pct = opts.width_pct or 0.25
  local title = opts.title or ""
  local row_offset = opts.row_offset or 2

  -- Support both height (absolute lines) and height_pct (ratio)
  local height
  if opts.height then
    height = opts.height
  elseif opts.height_pct then
    height = math.floor(vim.o.lines * opts.height_pct)
  else
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

-- Setup scroll preview keymaps (C-d / C-u)
-- @param state table: containing win_preview
-- @param buf_list number: buffer to map
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
-- @param state table: containing win_list, win_preview, job_handle
-- @param opts table: { on_close = function }
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
-- @param state table: containing win_list
function M.close_windows(state)
  if state.win_list and api.nvim_win_is_valid(state.win_list) then
    api.nvim_win_close(state.win_list, true)
  end
end

-- Cleanup timers safely
-- @param timers table: list of timers to cleanup
function M.cleanup_timers(timers)
  for _, timer in ipairs(timers or {}) do
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
end

-- =============================================================================
-- DIAGNOSTIC UTILITIES
-- =============================================================================

-- Get the diagnostic severity level for a buffer
-- @param bufnr number: buffer number
-- @return string|nil: "error", "warn", or nil
function M.get_diagnostic_level(bufnr)
  local errs = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })
  if errs > 0 then return "error" end
  local warns = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.WARN })
  if warns > 0 then return "warn" end
  return nil
end

-- =============================================================================
-- INPUT UTILITIES (Shared by finder/grep)
-- =============================================================================

-- Redirect normal mode keystrokes to input line (line 1)
-- @param buf number: buffer to map
-- @param win number|function: window handle or function returning it
function M.setup_redirect_input(buf, get_win)
  local function redirect_to_input(key)
    local win = type(get_win) == "function" and get_win() or get_win
    local line = api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    api.nvim_win_set_cursor(win, {1, #line})
    vim.cmd("startinsert")
    if key then
      local k = api.nvim_replace_termcodes(key, true, false, true)
      api.nvim_feedkeys(k, "n", true)
    end
  end

  local opts = { buffer = buf }
  for i = 32, 126 do
    local char = string.char(i)
    vim.keymap.set("n", char, function() redirect_to_input(char) end, opts)
  end
  vim.keymap.set("n", "<BS>", function() redirect_to_input("<BS>") end, opts)
end

-- =============================================================================
-- LAZY LOADING UTILITIES
-- =============================================================================

-- Create a lazy keymap that requires a module on first use
-- @param module string: module path to require
-- @param fn string|function: function to call (string for method name, function for custom)
-- @return function: keymap callback
function M.lazy_require(module, fn)
  return function()
    local mod = require(module)
    if type(fn) == "string" then
      mod[fn]()
    else
      fn(mod)
    end
  end
end

return M
