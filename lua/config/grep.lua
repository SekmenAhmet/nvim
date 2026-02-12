-- Native Live Grep with Preview (Async & Non-blocking)
-- Architecture: Async Spawn (libuv) + Dual Window UI

local M = {}
local uv = vim.uv
local icons = require("utils.icons")
local utils = require("utils")

-- Configuration
local CONFIG = {
  width_pct = 0.7,
  height_pct = 0.8,
  preview_width_pct = 0.55,
  batch_size = 50,
}

-- État global
local state = {
  buf_list = nil,
  win_list = nil,
  buf_preview = nil,
  win_preview = nil,
  job_handle = nil,
  results = {},
  line_map = {},
  timer_debounce = vim.uv.new_timer(),
  timer_preview = vim.uv.new_timer(),
  last_query = "",
  preview_cache = {},
}

-- 1. Preview Logic
local function update_preview(filename, lnum)
  lnum = tonumber(lnum) or 1
  utils.async_preview(filename, state.buf_preview, state.win_preview, {
    lnum = lnum,
    timer = state.timer_preview,
    cache = state.preview_cache,
    on_loaded = function(rel_lnum)
      local ns = vim.api.nvim_create_namespace("grep_preview")
      vim.api.nvim_buf_clear_namespace(state.buf_preview, ns, 0, -1)
      vim.api.nvim_buf_add_highlight(state.buf_preview, ns, "Search", rel_lnum - 1, 0, -1)
    end
  })
end

-- 2. Render List (Grouped by File)
local function render_list(query)
  if not vim.api.nvim_buf_is_valid(state.buf_list) or not vim.api.nvim_win_is_valid(state.win_list) then return end

  table.sort(state.results, function(a, b)
    if a.filename == b.filename then
      return (tonumber(a.lnum) or 0) < (tonumber(b.lnum) or 0)
    else
      return a.filename < b.filename
    end
  end)

  local display_lines = {}
  local highlights = {}
  state.line_map = {}

  table.insert(display_lines, "  " .. string.rep("─", vim.api.nvim_win_get_width(state.win_list) - 4))

  if #state.results == 0 then
    table.insert(display_lines, "  " .. (query == "" and "-- Type to search --" or "-- No results --"))
  else
    local current_file = nil
    for i, res in ipairs(state.results) do
      if #display_lines > 500 then break end
      if res.filename ~= current_file then
        current_file = res.filename
        local clean_name = res.filename:gsub("^%./", ""):gsub("^%s*(.-)%s*$", "%1")
        local icon_data = icons.get(clean_name)
        
        table.insert(display_lines, " " .. icon_data.icon .. " " .. clean_name)
        local row = 1 + (#display_lines - 1) 
        table.insert(highlights, { row = row, col_start = 1, col_end = 1 + #icon_data.icon, hl = icon_data.hl })
      end
      
      local clean_text = res.text:gsub("^%s*(.-)%s*$", "%1")
      table.insert(display_lines, string.format("   %s: %s", res.lnum, clean_text))
      state.line_map[1 + #display_lines] = i
    end
  end

  vim.api.nvim_buf_set_lines(state.buf_list, 1, -1, false, display_lines)
  vim.api.nvim_buf_clear_namespace(state.buf_list, -1, 1, -1)

  for i, line in ipairs(display_lines) do
    local hl_row = i
    if line:match("^   %d+:") then
      local lnum_end = line:find(":")
      vim.api.nvim_buf_add_highlight(state.buf_list, -1, "LineNr", hl_row, 3, lnum_end)
    elseif i > 1 and not line:match("^   ") then
       local icon_end = line:find(" ", 2)
       if icon_end then
          vim.api.nvim_buf_add_highlight(state.buf_list, -1, "Directory", hl_row, icon_end, -1)
       end
    end
  end
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf_list, -1, hl.hl, hl.row, hl.col_start, hl.col_end)
  end

  if vim.api.nvim_get_mode().mode ~= 'i' then
      vim.api.nvim_win_set_cursor(state.win_list, {1, 2 + #query})
  end

  if #state.results > 0 then
      update_preview(state.results[1].filename, state.results[1].lnum)
  else
      update_preview(nil)
  end
end

-- 3. Async Search Engine
local function start_grep(query)
  if query == "" then
    state.results = {}
    render_list(query)
    return
  end
  if state.job_handle and not state.job_handle:is_closing() then state.job_handle:close() end
  state.results = {}

  local args = { "--vimgrep", "--no-heading", "--smart-case", "--glob", "!.git/*", "--glob", "!node_modules/*", query, "." }
  local stdout = uv.new_pipe(false)
  local handle
  handle = uv.spawn("rg", {
    args = args,
    stdio = { nil, stdout, nil },
  }, function()
    stdout:read_stop()
    stdout:close()
    if handle and not handle:is_closing() then handle:close() end
  end)
  state.job_handle = handle

  local buffer = ""
  stdout:read_start(function(err, data)
    if data then
      buffer = buffer .. data
      local lines = vim.split(buffer, "\n")
      buffer = lines[#lines]
      lines[#lines] = nil
      for _, line in ipairs(lines) do
        local parts = vim.split(line, ":")
        if #parts >= 4 then
          local text = table.concat(parts, ":", 4)
          if not text:match("^%s*[/#-]") then
             table.insert(state.results, { filename = parts[1], lnum = parts[2], text = text })
          end
        end
      end
      if #state.results % CONFIG.batch_size == 0 then
        vim.schedule(function() render_list(query) end)
      end
    else
      vim.schedule(function() render_list(query) end)
    end
  end)
end

-- 4. Create UI
local function create_ui()
  local wins = utils.create_dual_pane({
    width_pct = CONFIG.width_pct,
    height_pct = CONFIG.height_pct,
    preview_width_pct = CONFIG.preview_width_pct,
    list_title = "Live Grep",
    preview_title = "Preview",
    list_filetype = "grep_list",
  })
  state.buf_list, state.win_list, state.buf_preview, state.win_preview = wins.buf_list, wins.win_list, wins.buf_preview, wins.win_preview
  vim.wo[state.win_preview].number = true
  utils.setup_scroll_preview(state, state.buf_list)
  utils.setup_auto_close(state)
end

-- 5. Main
function M.open()
  create_ui()
  render_list("")
  vim.cmd("startinsert")

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = state.buf_list,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list)
      if cursor[1] == 1 then
        local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1] or ""
        local query = line:sub(3)
        state.timer_debounce:stop()
        state.timer_debounce:start(100, 0, vim.schedule_wrap(function() start_grep(query) end))
      end
    end
  })

  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    buffer = state.buf_list,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list)
      local res_idx = state.line_map[cursor[1]]
      if res_idx then
        update_preview(state.results[res_idx].filename, state.results[res_idx].lnum)
      end
    end
  })

  local function close()
    utils.cleanup_timers({ state.timer_debounce, state.timer_preview })
    utils.close_windows(state)
  end

  local function open_result()
    local cursor = vim.api.nvim_win_get_cursor(state.win_list)
    local res_idx = state.line_map[cursor[1]] or 1
    local res = state.results[res_idx]
    if res then 
      close()
      require("config.ui").open_in_normal_win(res.filename, res.lnum) 
    end
  end

  local opts = { buffer = state.buf_list }
  vim.keymap.set({"i", "n"}, "<Esc>", close, opts)
  vim.keymap.set({"i", "n"}, "<CR>", open_result, opts)
  utils.setup_list_navigation(state.buf_list, state.win_list, 3)
  utils.setup_redirect_input(state.buf_list, function() return state.win_list end)
end

return M
