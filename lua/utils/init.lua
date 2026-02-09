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

-- =============================================================================
-- UI MODE UTILITIES (Strict Mode)
-- =============================================================================

-- Configure a buffer for strict UI mode (read-only list behavior)
-- @param buf number: buffer to configure
-- @param opts table: { win = number, enter_fn = function }
function M.set_ui_mode(buf, opts)
  opts = opts or {}
  
  -- Visuals
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false
  if opts.win and api.nvim_win_is_valid(opts.win) then
    vim.wo[opts.win].cursorline = true
    vim.wo[opts.win].number = false
    vim.wo[opts.win].relativenumber = false
  end

  local map_opts = { buffer = buf, silent = true, nowait = true }

  -- Block Editing Keys
  local banned = { "i", "I", "a", "A", "o", "O", "c", "C", "d", "D", "x", "X", "p", "P", "s", "S", "r", "R" }
  for _, k in ipairs(banned) do
    vim.keymap.set({"n", "v"}, k, "<Nop>", map_opts)
  end

  -- Navigation
  vim.keymap.set("n", "j", "j", map_opts)
  vim.keymap.set("n", "k", "k", map_opts)
  vim.keymap.set("n", "<Down>", "j", map_opts)
  vim.keymap.set("n", "<Up>", "k", map_opts)
  vim.keymap.set("n", "<Left>", "h", map_opts)
  vim.keymap.set("n", "<Right>", "l", map_opts)
  
  -- Actions
  if opts.enter_fn then
    vim.keymap.set("n", "<CR>", opts.enter_fn, map_opts)
  end
end

-- Setup list navigation for Finder/Grep (Mixed Input + List)
-- Handles seamless transition between Input (Line 1) and List (Line 2+)
-- @param buf number
-- @param win number
-- @param list_start_line number: 1-based index where list starts (usually 2 or 3)
function M.setup_list_navigation(buf, win, list_start_line)
  local map_opts = { buffer = buf, silent = true }
  list_start_line = list_start_line or 2

  local function nav(dir)
    if vim.api.nvim_get_mode().mode == 'i' then vim.cmd("stopinsert") end
    
    local current_row = api.nvim_win_get_cursor(win)[1]
    local line_count = api.nvim_buf_line_count(buf)
    local target = current_row + dir

    -- If currently in input (row 1) and going down, jump to list start
    if current_row == 1 and dir > 0 then
      target = list_start_line
    end

    -- If in list start and going up, jump to input
    if current_row <= list_start_line and dir < 0 then
      api.nvim_win_set_cursor(win, {1, 0})
      vim.cmd("startinsert")
      -- Move cursor to end of input line
      local line = api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      api.nvim_win_set_cursor(win, {1, #line})
      return
    end

    -- Boundary checks
    if target < list_start_line then target = list_start_line end
    if target > line_count then target = line_count end

    -- Only move if valid
    if target >= list_start_line and target <= line_count then
      api.nvim_win_set_cursor(win, {target, 0})
    end
  end

  -- Mappings for both Normal and Insert modes
  vim.keymap.set({"n", "i"}, "<Down>", function() nav(1) end, map_opts)
  vim.keymap.set({"n", "i"}, "<Up>", function() nav(-1) end, map_opts)
  vim.keymap.set({"n", "i"}, "<C-j>", function() nav(1) end, map_opts)
  vim.keymap.set({"n", "i"}, "<C-k>", function() nav(-1) end, map_opts)
  
  -- Pure Normal mode j/k (if user escapes input)
  vim.keymap.set("n", "j", function() nav(1) end, map_opts)
  vim.keymap.set("n", "k", function() nav(-1) end, map_opts)
end

-- Async Preview Generator
-- Uses libuv to read file content without blocking the UI
-- @param filepath string
-- @param buf_preview number
-- @param win_preview number
-- @param opts table: { lnum = number, timer = uv_timer, cache = table, on_loaded = function }
function M.async_preview(filepath, buf_preview, win_preview, opts)
  opts = opts or {}
  if not filepath or filepath == "" or not api.nvim_buf_is_valid(buf_preview) then
    if api.nvim_buf_is_valid(buf_preview) then
      api.nvim_buf_set_lines(buf_preview, 0, -1, false, {})
    end
    return
  end

  local lnum = tonumber(opts.lnum) or 1
  local key = filepath .. ":" .. lnum
  
  -- Cache Check
  if opts.cache and opts.cache[key] then
    local c = opts.cache[key]
    vim.schedule(function()
      if not api.nvim_buf_is_valid(buf_preview) then return end
      api.nvim_buf_set_lines(buf_preview, 0, -1, false, c.lines)
      if c.ft then vim.bo[buf_preview].filetype = c.ft end
      if win_preview and api.nvim_win_is_valid(win_preview) then
        pcall(api.nvim_win_set_cursor, win_preview, {c.relative_lnum or 1, 0})
        api.nvim_win_call(win_preview, function() vim.cmd("normal! zz") end)
      end
      if opts.on_loaded then opts.on_loaded(c.relative_lnum) end
    end)
    return
  end

  -- Debounce Timer
  if opts.timer then
    opts.timer:stop()
    opts.timer:start(5, 0, vim.schedule_wrap(function()
      M._do_preview_read(filepath, buf_preview, win_preview, lnum, key, opts)
    end))
  else
    M._do_preview_read(filepath, buf_preview, win_preview, lnum, key, opts)
  end
end

-- Internal reader logic
function M._do_preview_read(filepath, buf, win, lnum, key, opts)
  if not api.nvim_buf_is_valid(buf) then return end
  
  local uv = vim.uv
  local stat = uv.fs_stat(filepath)
  if not stat or stat.type ~= "file" then
    api.nvim_buf_set_lines(buf, 0, -1, false, { " [File not found or Directory] " })
    return
  end

  -- Optimization: Context reading
  local context = 50
  local avg_line = 100
  local max_read = context * 2 * avg_line
  
  local size = stat.size
  local offset = 0
  local truncated = false
  
  if size > max_read then
    truncated = true
    offset = math.max(0, (lnum - context) * avg_line)
    -- Align offset (heuristic)
    if offset > 0 then offset = math.max(0, offset - avg_line) end
    size = math.min(max_read, stat.size - offset)
  end

  uv.fs_open(filepath, "r", 438, function(err, fd)
    if err then return end
    uv.fs_read(fd, size, offset, function(read_err, data)
      uv.fs_close(fd)
      if read_err then return end
      
      vim.schedule(function()
        if not api.nvim_buf_is_valid(buf) then return end
        local lines = vim.split(data or "", "\n")
        
        -- Calculate relative line number
        local rel_lnum = lnum
        if truncated then
          -- Simple heuristic: middle of the chunk is roughly our target
          rel_lnum = math.floor(#lines / 2)
          -- Ensure it's valid
          if rel_lnum < 1 then rel_lnum = 1 end
          if rel_lnum > #lines then rel_lnum = #lines end
        else
          if rel_lnum > #lines then rel_lnum = #lines end
        end
        if rel_lnum < 1 then rel_lnum = 1 end

        local ft = vim.filetype.match({ filename = filepath })
        
        -- Cache result
        if opts.cache then
          opts.cache[key] = { lines = lines, ft = ft, relative_lnum = rel_lnum }
        end

        api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        if ft then vim.bo[buf].filetype = ft end
        
        if win and api.nvim_win_is_valid(win) then
          pcall(api.nvim_win_set_cursor, win, {rel_lnum, 0})
          api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
        end
        
        if opts.on_loaded then opts.on_loaded(rel_lnum) end
      end)
    end)
  end)
end

return M
