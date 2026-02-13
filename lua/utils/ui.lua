local M = {}
local api = vim.api

-- =============================================================================
-- CONFIGURATION & STYLES
-- =============================================================================

M.config = {
  border = "rounded",
  zindex = 50,
  hl = {
    normal = "NormalFloat",
    border = "FloatBorder",
    cursorline = "Visual",
  }
}

-- =============================================================================
-- CORE WINDOW CREATION
-- =============================================================================

--- Creates a standard floating window
---@param opts table
---@return number buf, number win
function M.create_float(opts)
  local buf = opts.buf or api.nvim_create_buf(false, true)
  
  local win_opts = {
    relative = "editor",
    width = math.max(1, opts.width),
    height = math.max(1, opts.height),
    row = opts.row or 0,
    col = opts.col or 0,
    style = "minimal",
    border = opts.border or M.config.border,
    zindex = opts.zindex or M.config.zindex,
  }

  if opts.title then
    win_opts.title = " " .. opts.title .. " "
    win_opts.title_pos = opts.title_pos or "left"
  end

  local win = api.nvim_open_win(buf, opts.enter or false, win_opts)

  -- Styling
  vim.wo[win].winhl = string.format("Normal:%s,FloatBorder:%s,CursorLine:%s", 
    M.config.hl.normal, M.config.hl.border, M.config.hl.cursorline)
  
  if opts.cursorline then vim.wo[win].cursorline = true end
  if opts.wrap ~= nil then vim.wo[win].wrap = opts.wrap end
  if opts.filetype then vim.bo[buf].filetype = opts.filetype end
  
  vim.bo[buf].buftype = "nofile"

  return buf, win
end

-- =============================================================================
-- LAYOUT MANAGER (Declarative UI)
-- =============================================================================

---@class WinDef
---@field width_pct number?
---@field height_pct number?
---@field width number?
---@field height number?
---@field row number?
---@field col number?
---@field title string?
---@field filetype string?
---@field enter boolean?
---@field cursorline boolean?

--- Manages complex layouts declaratively. Reuses existing windows/buffers if provided.
---@param layout table<string, WinDef>
---@param existing table<string, {buf: number, win: number}>?
---@return table<string, {buf: number, win: number}>
function M.layout_manager(layout, existing)
  local results = existing or {}
  local W, H = vim.o.columns, vim.o.lines
  
  for key, def in pairs(layout) do
    local w = def.width or math.floor(W * (def.width_pct or 0.5))
    local h = def.height or math.floor(H * (def.height_pct or 0.5))
    local r = def.row or math.floor((H - h) / 2)
    local c = def.col or math.floor((W - w) / 2)
    
    local config = {
      buf = results[key] and results[key].buf or def.buf,
      width = math.max(1, w - 2),
      height = math.max(1, h - 2),
      row = r,
      col = c,
      title = def.title,
      enter = def.enter,
      filetype = def.filetype,
      cursorline = def.cursorline,
    }

    if results[key] and api.nvim_win_is_valid(results[key].win) then
      -- Update existing window
      api.nvim_win_set_config(results[key].win, {
        relative = "editor",
        width = config.width,
        height = config.height,
        row = config.row,
        col = config.col,
        title = config.title and (" " .. config.title .. " ") or nil,
      })
      if config.buf and api.nvim_buf_is_valid(config.buf) then
        api.nvim_win_set_buf(results[key].win, config.buf)
      end
    else
      -- Create new window
      local buf, win = M.create_float(config)
      results[key] = { buf = buf, win = win }
    end
    
    -- Ensure filetype is set
    if def.filetype then
      vim.bo[results[key].buf].filetype = def.filetype
    end
  end
  
  return results
end

-- =============================================================================
-- PRESETS & HELPERS
-- =============================================================================

function M.create_centered_win(opts)
  opts = opts or {}
  local w = math.floor(vim.o.columns * (opts.width_pct or 0.5))
  local h = opts.height or math.floor(vim.o.lines * (opts.height_pct or 0.5))
  
  return M.create_float({
    width = w,
    height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    title = opts.title,
    enter = opts.enter,
    filetype = opts.filetype
  })
end

-- Notification System
local notifications = {}
function M.notify(msg, level, opts)
  opts = opts or {}
  local icons = require("utils.icons").ui
  local level_map = {
    [vim.log.levels.ERROR] = { icon = icons.error, hl = "DiagnosticError" },
    [vim.log.levels.WARN]  = { icon = icons.warn,  hl = "DiagnosticWarn" },
    [vim.log.levels.INFO]  = { icon = icons.info,  hl = "DiagnosticInfo" },
  }
  
  local config = level_map[level or vim.log.levels.INFO]
  local lines = vim.split(tostring(msg), "\n")
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, #l) end
  width = width + 4
  
  local row = 1
  for _, n in ipairs(notifications) do
    if api.nvim_win_is_valid(n.win) then
      row = row + api.nvim_win_get_height(n.win) + 2
    end
  end

  local buf, win = M.create_float({
    width = width,
    height = #lines,
    row = row,
    col = vim.o.columns - width - 2,
    title = config.icon .. " Notification",
    zindex = 100,
  })
  
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.wo[win].winhl = "NormalFloat:Normal,FloatBorder:" .. config.hl
  
  table.insert(notifications, { win = win, buf = buf })
  local current_notification = notifications[#notifications]

  vim.defer_fn(function()
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    -- Remove from notifications table
    for i, n in ipairs(notifications) do
      if n == current_notification then
        table.remove(notifications, i)
        break
      end
    end
  end, opts.timeout or 3000)
end

-- Override global notify
vim.notify = M.notify

-- =============================================================================
-- ASYNC PREVIEW & IO
-- =============================================================================

function M.async_preview(filepath, buf, win, opts)
  opts = opts or {}
  if not filepath or filepath == "" or not api.nvim_buf_is_valid(buf) then return end

  local uv = vim.uv
  uv.fs_open(filepath, "r", 438, function(err, fd)
    if err then return end
    uv.fs_fstat(fd, function(err2, stat)
      if err2 then uv.fs_close(fd); return end
      uv.fs_read(fd, stat.size, 0, function(err3, data)
        uv.fs_close(fd)
        if err3 then return end
        vim.schedule(function()
          if not api.nvim_buf_is_valid(buf) then return end
          local lines = vim.split(data or "", "\n")
          vim.bo[buf].modifiable = true
          api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          vim.bo[buf].modifiable = false
          
          local ft = vim.filetype.match({ filename = filepath })
          if ft then vim.bo[buf].filetype = ft end
          
          if win and api.nvim_win_is_valid(win) then
             api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
          end
        end)
      end)
    end)
  end)
end

-- =============================================================================
-- FINDER / PICKER UTILITIES
-- =============================================================================

function M.create_dual_pane(opts)
  opts = opts or {}
  local W, H = vim.o.columns, vim.o.lines
  local w_pct = opts.width_pct or 0.7
  local h_pct = opts.height_pct or 0.8
  local p_pct = opts.preview_width_pct or 0.6
  
  local tw = math.floor(W * w_pct)
  local th = math.floor(H * h_pct)
  local r = math.floor((H - th) / 2)
  local c = math.floor((W - tw) / 2)
  
  local pw = math.floor(tw * p_pct)
  local lw = tw - pw - 2

  local list_buf, list_win = M.create_float({
    width = lw, height = th, row = r, col = c,
    title = opts.list_title or "List", enter = true, cursorline = true,
    filetype = opts.list_filetype
  })

  local prev_buf, prev_win = M.create_float({
    width = pw, height = th, row = r, col = c + lw + 2,
    title = opts.preview_title or "Preview", enter = false,
    filetype = opts.preview_filetype
  })

  return {
    buf_list = list_buf, win_list = list_win,
    buf_preview = prev_buf, win_preview = prev_win
  }
end

function M.create_picker_layout(opts)
  local res = M.create_dual_pane(opts)
  return {
    list = { buf = res.buf_list, win = res.win_list },
    preview = { buf = res.buf_preview, win = res.win_preview }
  }
end

function M.setup_scroll_preview(state, buf)
  local function scroll(dir)
    if state.win_preview and api.nvim_win_is_valid(state.win_preview) then
      local key = dir > 0 and "<C-d>" or "<C-u>"
      api.nvim_win_call(state.win_preview, function()
        vim.cmd("normal! " .. api.nvim_replace_termcodes(key, true, false, true))
      end)
    end
  end
  vim.keymap.set({"i", "n"}, "<C-d>", function() scroll(1) end, { buffer = buf })
  vim.keymap.set({"i", "n"}, "<C-u>", function() scroll(-1) end, { buffer = buf })
end

function M.setup_auto_close(state)
  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win_list),
    once = true,
    callback = function()
      if state.win_preview and api.nvim_win_is_valid(state.win_preview) then
        api.nvim_win_close(state.win_preview, true)
      end
      if state.job_handle and not state.job_handle:is_closing() then
        state.job_handle:close()
      end
    end
  })
end

function M.setup_list_navigation(buf, win, list_start)
  local function nav(dir)
    local curr = api.nvim_win_get_cursor(win)[1]
    local count = api.nvim_buf_line_count(buf)
    local next = curr + dir
    if curr == 1 and dir > 0 then next = list_start end
    if curr <= list_start and dir < 0 then
      api.nvim_win_set_cursor(win, {1, 0})
      vim.cmd("startinsert")
      return
    end
    if next < list_start then next = list_start end
    if next > count then next = count end
    api.nvim_win_set_cursor(win, {next, 0})
  end
  local opts = { buffer = buf, silent = true }
  vim.keymap.set({"n", "i"}, "<C-j>", function() nav(1) end, opts)
  vim.keymap.set({"n", "i"}, "<C-k>", function() nav(-1) end, opts)
  vim.keymap.set("n", "j", function() nav(1) end, opts)
  vim.keymap.set("n", "k", function() nav(-1) end, opts)
end

function M.setup_redirect_input(buf, get_win)
  local function redirect(char)
    local win = type(get_win) == "function" and get_win() or get_win
    api.nvim_set_current_win(win)
    local line = api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    api.nvim_win_set_cursor(win, {1, #line})
    vim.cmd("startinsert")
    if char then api.nvim_feedkeys(char, "n", true) end
  end
  local opts = { buffer = buf }
  for i = 32, 126 do
    local c = string.char(i)
    vim.keymap.set("n", c, function() redirect(c) end, opts)
  end
  vim.keymap.set("n", "<BS>", function() redirect() api.nvim_feedkeys(api.nvim_replace_termcodes("<BS>", true, false, true), "n", true) end, opts)
end

function M.cleanup_timers(timers)
  for _, t in ipairs(timers or {}) do
    if t and not t:is_closing() then t:stop(); t:close() end
  end
end

function M.close_windows(state)
  if state.win_list and api.nvim_win_is_valid(state.win_list) then
    api.nvim_win_close(state.win_list, true)
  end
end

-- =============================================================================
-- DIAGNOSTIC UTILITIES
-- =============================================================================

--- Get the diagnostic severity level for a buffer or path
--- @param target number|string: buffer number or file path
--- @return string|nil: "error", "warn", or nil
function M.get_diagnostic_level(target)
  local bufnr = type(target) == "number" and target or vim.fn.bufnr(target)
  
  -- If we have a valid buffer, use it (faster)
  if bufnr > 0 and api.nvim_buf_is_valid(bufnr) then
    local errs = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR })
    if errs > 0 then return "error" end
    local warns = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.WARN })
    if warns > 0 then return "warn" end
  else
    -- Fallback: search all diagnostics by path (slower but works for closed files)
    if type(target) == "string" then
      local all = vim.diagnostic.get(nil)
      local has_warn = false
      for _, d in ipairs(all) do
        local d_path = api.nvim_buf_get_name(d.bufnr)
        if d_path == target or d_path:match(target .. "$") then
          if d.severity == vim.diagnostic.severity.ERROR then return "error" end
          if d.severity == vim.diagnostic.severity.WARN then has_warn = true end
        end
      end
      if has_warn then return "warn" end
    end
  end
  return nil
end

-- =============================================================================
-- LSP HANDLERS
-- =============================================================================

function M.setup_lsp_handlers()
  local border = M.config.border
  vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = border })
  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = border })
end

-- =============================================================================
-- LAZY LOADING UTILITIES
-- =============================================================================

--- Create a lazy keymap that requires a module on first use
---@param module string: module path to require
---@param fn string|function: function to call (string for method name, function for custom)
---@return function: keymap callback
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

--- Configure a buffer for strict UI mode (read-only list behavior)
--- @param buf number: buffer to configure
--- @param opts table: { win = number, enter_fn = function }
function M.set_ui_mode(buf, opts)
  opts = opts or {}
  
  -- Visuals
  vim.bo[buf].modifiable = false
  if opts.win and api.nvim_win_is_valid(opts.win) then
    vim.wo[opts.win].cursorline = true
    vim.wo[opts.win].number = false
    vim.wo[opts.win].relativenumber = false
  end

  local map_opts = { buffer = buf, silent = true, nowait = true }

  -- Block ALL Insert/Editing Keys
  local banned = { "i", "I", "a", "A", "o", "O", "c", "C", "d", "D", "x", "X", "p", "P", "s", "S", "r", "R" }
  for _, k in ipairs(banned) do
    vim.keymap.set({"n", "v"}, k, "<Nop>", map_opts)
  end

  -- Standard Navigation
  vim.keymap.set("n", "j", "j", map_opts)
  vim.keymap.set("n", "k", "k", map_opts)
  
  -- Custom Actions
  if opts.enter_fn then
    vim.keymap.set("n", "<CR>", opts.enter_fn, map_opts)
  end
end

-- =============================================================================
-- NAVIGATION
-- =============================================================================

function M.open_in_normal_win(file, lnum)
  local wins = api.nvim_list_wins()
  local sidebar_fts = { "tree", "netrw", "docker_tree", "rest_tree", "git_files" }
  
  -- Try to find a valid "editor" window
  for _, w in ipairs(wins) do
    local buf = api.nvim_win_get_buf(w)
    local ft = vim.bo[buf].filetype
    local bt = vim.bo[buf].buftype
    local cfg = api.nvim_win_get_config(w)
    
    -- Sidebar protection
    local is_sidebar = vim.tbl_contains(sidebar_fts, ft) or ft:match("tree")
    -- Dashboard is replaceable
    local is_dashboard = ft == "dashboard"
    
    local is_normal = cfg.relative == "" and (bt == "" or is_dashboard) and not is_sidebar
    
    if is_normal then
      api.nvim_set_current_win(w)
      vim.cmd("edit " .. vim.fn.fnameescape(file))
      if lnum then api.nvim_win_set_cursor(w, {tonumber(lnum), 0}) end
      return
    end
  end
  
  -- If no valid editor window is found, create a new vertical split
  vim.cmd("vsplit " .. vim.fn.fnameescape(file))
end

return M
