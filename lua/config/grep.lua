-- Native Live Grep with Preview (Async & Non-blocking)
-- Architecture: Async Spawn (libuv) + Dual Window UI

local M = {}
local uv = vim.loop
local ui = require("config.ui") -- Load UI for icons

-- Configuration
local CONFIG = {
  width_pct = 0.7,
  height_pct = 0.8,
  preview_width_pct = 0.7,
  batch_size = 50,
}

-- État global
local state = {
  buf_list = nil,
  win_list = nil,
  buf_preview = nil,
  win_preview = nil,
  job_handle = nil,
  results = {}, -- Raw results from grep
  line_map = {}, -- Maps buffer line to result index
  timer_debounce = nil,
  timer_preview = nil,
  last_query = "",
  last_preview_key = nil,
}

-- Ignore patterns
local function get_ignore_args()
  local common_ignores = {
    "node_modules", ".git", ".venv", "__pycache__", "target", "build", "dist",
    ".next", ".nuxt", ".output", "out", "coverage", ".npm", ".yarn",
    ".idea", ".vscode", ".DS_Store", "thumbs.db", "tmp", "temp", "vendor", "logs"
  }
  local args = {}
  for _, ignore in ipairs(common_ignores) do
    table.insert(args, "--glob")
    table.insert(args, "!" .. ignore)
  end
  local ext_ignores = { "*.lock", "*.log", "*.min.js", "*.map", "*.jpg", "*.png", "*.gif", "*.svg", "*.mp4", "*.zip", "*.tar.gz", "*.pdf" }
  for _, ext in ipairs(ext_ignores) do
    table.insert(args, "--glob")
    table.insert(args, "!" .. ext)
  end
  return args
end

-- 1. Preview Logic
local function update_preview(filename, lnum)
  if not filename or filename == "" then 
     if vim.api.nvim_buf_is_valid(state.buf_preview) then
       vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, {})
     end
     return 
  end
  lnum = tonumber(lnum) or 1
  local key = filename .. ":" .. lnum
  if state.last_preview_key == key then return end
  state.last_preview_key = key
  
  if state.timer_preview then state.timer_preview:stop() end
  state.timer_preview = uv.new_timer()
  
  state.timer_preview:start(20, 0, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(state.buf_preview) then return end
    local stat = uv.fs_stat(filename)
    if not stat or stat.type ~= "file" then return end

    uv.fs_open(filename, "r", 438, function(err, fd) 
      if err then return end
      uv.fs_read(fd, stat.size, 0, function(err_read, data) 
        uv.fs_close(fd)
        if err_read then return end
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(state.buf_preview) then return end
          local lines = vim.split(data or "", "\n")
          vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, lines)
          
          local ft = vim.filetype.match({ filename = filename })
          if ft then vim.bo[state.buf_preview].filetype = ft end
          
          pcall(vim.api.nvim_win_set_cursor, state.win_preview, {lnum, 0})
          vim.api.nvim_win_call(state.win_preview, function() vim.cmd("normal! zz") end)
          
          local ns = vim.api.nvim_create_namespace("grep_preview")
          vim.api.nvim_buf_clear_namespace(state.buf_preview, ns, 0, -1)
          vim.api.nvim_buf_add_highlight(state.buf_preview, ns, "Search", lnum - 1, 0, -1)
        end)
      end)
    end)
  end))
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
  
  table.insert(display_lines, "  " .. query)
  table.insert(display_lines, "  " .. string.rep("─", vim.api.nvim_win_get_width(state.win_list) - 4))
  
  if #state.results == 0 then
    table.insert(display_lines, "  " .. (query == "" and "-- Type to search --" or "-- No results --"))
  else
    local current_file = nil
    for i, res in ipairs(state.results) do
      if #display_lines > 500 then break end
      if res.filename ~= current_file then
        current_file = res.filename
        local clean_name = res.filename:gsub("^%./", "")
        local icon_data = ui.get_icon_data(clean_name)
        table.insert(display_lines, " " .. icon_data.icon .. " " .. clean_name)
        local row = #display_lines - 1
        local col_end = 1 + #icon_data.icon
        table.insert(highlights, { row = row, col_start = 1, col_end = col_end, hl = icon_data.hl })
      end
      
      local line_str = string.format("   %s: %s", res.lnum, res.text)
      table.insert(display_lines, line_str)
      state.line_map[#display_lines] = i
    end
  end
  
  vim.api.nvim_buf_set_lines(state.buf_list, 0, -1, false, display_lines)
  vim.api.nvim_buf_clear_namespace(state.buf_list, -1, 0, -1)
  
  for i, line in ipairs(display_lines) do
    if line:match("^   %d+:") then
      local lnum_end = line:find(":")
      vim.api.nvim_buf_add_highlight(state.buf_list, -1, "LineNr", i - 1, 3, lnum_end)
    elseif i > 2 and not line:match("^   ") then
       local icon_end = line:find(" ", 2)
       if icon_end then
          vim.api.nvim_buf_add_highlight(state.buf_list, -1, "Directory", i - 1, icon_end, -1)
       end
    end
  end
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf_list, -1, hl.hl, hl.row, hl.col_start, hl.col_end)
  end

  if vim.api.nvim_get_mode().mode == 'i' then
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
  
  local cmd = "rg"
  local args = { "--vimgrep", "--no-heading", "--smart-case" }
  local ignore_args = get_ignore_args()
  for _, v in ipairs(ignore_args) do table.insert(args, v) end
  table.insert(args, query)
  table.insert(args, ".")
  
  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false) -- Capture stderr for safety
  
  state.job_handle = uv.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function() 
    stdout:read_stop()
    stderr:read_stop() -- Stop stderr reading
    stdout:close()
    stderr:close() -- Close stderr pipe
    if state.job_handle then state.job_handle:close() end
  end)
  
  -- Dummy read for stderr to prevent buffer blocking
  stderr:read_start(function(err, data) end) 
  
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
          table.insert(state.results, { filename = parts[1], lnum = parts[2], text = table.concat(parts, ":", 4) })
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
  local total_width = math.floor(vim.o.columns * CONFIG.width_pct)
  local total_height = math.floor(vim.o.lines * CONFIG.height_pct)
  local row = math.floor((vim.o.lines - total_height) / 2)
  local col = math.floor((vim.o.columns - total_width) / 2)
  local preview_width = math.floor(total_width * CONFIG.preview_width_pct)
  local list_width = total_width - preview_width - 2

  state.buf_list = vim.api.nvim_create_buf(false, true)
  state.win_list = vim.api.nvim_open_win(state.buf_list, true, {
    relative = "editor", width = list_width, height = total_height, row = row, col = col,
    style = "minimal", border = "rounded", title = " Live Grep ",
  })
  vim.bo[state.buf_list].filetype = "grep_list"

  state.buf_preview = vim.api.nvim_create_buf(false, true)
  state.win_preview = vim.api.nvim_open_win(state.buf_preview, false, {
    relative = "editor", width = preview_width, height = total_height, row = row, col = col + list_width + 2,
    style = "minimal", border = "rounded", title = " Preview ",
  })

  vim.wo[state.win_list].cursorline = true
  vim.wo[state.win_list].winhl = "NormalFloat:Normal,CursorLine:Visual"
  vim.bo[state.buf_list].buftype = "nofile"
  vim.wo[state.win_list].cursorcolumn = false
  vim.wo[state.win_list].wrap = false
  vim.wo[state.win_preview].winhl = "NormalFloat:Normal"
  vim.bo[state.buf_preview].buftype = "nofile"
  vim.wo[state.win_preview].number = true

  local function scroll_preview(direction)
    if vim.api.nvim_win_is_valid(state.win_preview) then
      vim.api.nvim_win_call(state.win_preview, function()
        local key = direction > 0 and "<C-d>" or "<C-u>"
        vim.cmd("normal! " .. vim.api.nvim_replace_termcodes(key, true, false, true))
      end)
    end
  end
  vim.keymap.set({"i", "n"}, "<C-d>", function() scroll_preview(1) end, { buffer = state.buf_list })
  vim.keymap.set({"i", "n"}, "<C-u>", function() scroll_preview(-1) end, { buffer = state.buf_list })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win_list), once = true,
    callback = function()
      if state.win_preview and vim.api.nvim_win_is_valid(state.win_preview) then vim.api.nvim_win_close(state.win_preview, true) end
      if state.job_handle and not state.job_handle:is_closing() then state.job_handle:close() end
    end
  })
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
        local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1]
        local query = line:sub(3)
        if state.timer_debounce then state.timer_debounce:stop() end
        state.timer_debounce = uv.new_timer()
        state.timer_debounce:start(100, 0, vim.schedule_wrap(function() start_grep(query) end))
      end
    end
  })
  
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    buffer = state.buf_list,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list)
      local row = cursor[1]
      local res_idx = state.line_map[row]
      if res_idx then
        local res = state.results[res_idx]
        if res then update_preview(res.filename, res.lnum) end
      elseif row == 1 and #state.results > 0 then
        local res = state.results[1]
        if res then update_preview(res.filename, res.lnum) end
      end
    end
  })

  local function close()
    if vim.api.nvim_win_is_valid(state.win_list) then vim.api.nvim_win_close(state.win_list, true) end
  end
  
  local function open_result()
    local cursor = vim.api.nvim_win_get_cursor(state.win_list)
    local row = cursor[1]
    local res_idx = state.line_map[row] or (row == 1 and 1 or nil)
    local res = res_idx and state.results[res_idx]
    if res then close(); require("config.ui").open_in_normal_win(res.filename, res.lnum) end
  end

  local opts = { buffer = state.buf_list }
  vim.keymap.set({"i", "n"}, "<Esc>", close, opts)
  vim.keymap.set({"i", "n"}, "<CR>", open_result, opts)
  
  local function navigate(dir)
    vim.cmd("stopinsert")
    -- Safety: If list is empty or map not ready, do nothing
    if vim.tbl_isempty(state.line_map) then return end
    
    local current_row = vim.api.nvim_win_get_cursor(state.win_list)[1]
    local line_count = vim.api.nvim_buf_line_count(state.buf_list)
    
    local target_row
    if current_row == 1 and dir > 0 then
      target_row = 3 
    else
      target_row = current_row + dir
    end
    
    if target_row < 3 then target_row = 3 end
    if target_row > line_count then target_row = line_count end
    
    local steps = 0
    while not state.line_map[target_row] and target_row < line_count and target_row >= 3 and steps < 100 do
      target_row = target_row + dir
      steps = steps + 1
    end
    
    if state.line_map[target_row] then
       vim.api.nvim_win_set_cursor(state.win_list, {target_row, 0})
    end
  end

  vim.keymap.set("i", "<Down>", function() navigate(1) end, opts)
  vim.keymap.set("n", "<Down>", function() navigate(1) end, opts)
  vim.keymap.set("n", "<Up>", function() navigate(-1) end, opts)
  vim.keymap.set("i", "<Up>", function() 
    local row = vim.api.nvim_win_get_cursor(state.win_list)[1]
    if row <= 3 then 
      vim.api.nvim_win_set_cursor(state.win_list, {1, 0})
      vim.cmd("startinsert")
      local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1]
      vim.api.nvim_win_set_cursor(state.win_list, {1, #line})
    else
      navigate(-1)
    end
  end, opts)

  local function redirect_to_input(key)
    local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1]
    vim.api.nvim_win_set_cursor(state.win_list, {1, #line})
    vim.cmd("startinsert")
    if key then
      local k = vim.api.nvim_replace_termcodes(key, true, false, true)
      vim.api.nvim_feedkeys(k, "n", true)
    end
  end

  for i = 32, 126 do 
    local char = string.char(i)
    vim.keymap.set("n", char, function() redirect_to_input(char) end, opts)
  end
  vim.keymap.set("n", "<BS>", function() redirect_to_input("<BS>") end, opts)
end

return M