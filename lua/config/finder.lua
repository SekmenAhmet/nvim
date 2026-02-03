-- Native Async Finder with Preview
-- Architecture: Async Spawn (libuv) + Dual Window UI

local M = {}
local uv = vim.loop
local ui = require("config.ui") -- Load UI module

-- Configuration
local CONFIG = {
  width_pct = 0.7,
  height_pct = 0.8,
  preview_width_pct = 0.6,
  batch_size = 200,
}

-- État global
local state = {
  buf_list = nil,
  win_list = nil,
  buf_preview = nil,
  win_preview = nil,
  job_handle = nil,
  files = {}, -- Raw list of all files
  filtered_files = {}, -- Displayed files
  preview_timer = nil,
  last_preview_file = nil,
}

-- Ignore list for 'find' fallback
local ignore_list = {
  "-not -path '*/.*'",
  "-not -path '*/node_modules/*'",
  "-not -path '*/target/*'",
  "-not -path '*/build/*'",
  "-not -path '*/dist/*'",
  "-not -path '*/__pycache__/*'",
  "-not -path '*/venv/*'",
}

-- Smart Scoring Algorithm
local function score_file(file, query_lower)
  local file_lower = file:lower()
  -- Extract filename from path
  local filename = file_lower:match("^.+/(.+)$") or file_lower

  -- 1. Exact filename match (Best)
  if filename == query_lower then return 100 end

  -- 2. Filename starts with query
  if vim.startswith(filename, query_lower) then return 80 end

  -- 3. Filename contains query
  if filename:find(query_lower, 1, true) then return 60 end

  -- 4. Path contains query
  if file_lower:find(query_lower, 1, true) then return 40 end

  -- 5. Fuzzy / Acronym (Optional, simple implementation)
  -- If query is "mc", matches "main_controller"
  -- Skipped for now to keep it fast, unless requested.

  return 0
end

-- 1. Preview Logic
local function update_preview(filepath)
  if not filepath or filepath == "" then
    if vim.api.nvim_buf_is_valid(state.buf_preview) then
       vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, {})
    end
    return
  end

  if state.last_preview_file == filepath then return end
  state.last_preview_file = filepath

  if state.preview_timer then state.preview_timer:stop() end
  state.preview_timer = uv.new_timer()

  state.preview_timer:start(10, 0, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(state.buf_preview) then return end

    local stat = uv.fs_stat(filepath)
    if not stat or stat.type ~= "file" then
      vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, { " [Directory or Not Found] " })
      return
    end

    if stat.size > 200 * 1024 then
      vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, { " [File too large] " })
      return
    end

    uv.fs_open(filepath, "r", 438, function(err, fd)
      if err then return end
      uv.fs_read(fd, 4096, 0, function(err_read, data)
        uv.fs_close(fd)
        if err_read then return end

        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(state.buf_preview) then return end
          local lines = vim.split(data or "", "\n")
          if #lines > 100 then lines = { unpack(lines, 1, 100) } end

          vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, lines)

          -- Enhanced Filetype Detection
          local ft = vim.filetype.match({ filename = filepath })
          if ft then
            vim.bo[state.buf_preview].filetype = ft
          end
        end)
      end)
    end)
  end))
end

-- 2. Create UI
local function create_ui()
  local total_width = math.floor(vim.o.columns * CONFIG.width_pct)
  local total_height = math.floor(vim.o.lines * CONFIG.height_pct)
  local row = math.floor((vim.o.lines - total_height) / 2)
  local col = math.floor((vim.o.columns - total_width) / 2)

  local preview_width = math.floor(total_width * CONFIG.preview_width_pct)
  local list_width = total_width - preview_width - 2

  -- Buffers
  state.buf_list = vim.api.nvim_create_buf(false, true)
  state.buf_preview = vim.api.nvim_create_buf(false, true)

  -- Set filetype for completion exclusion
  vim.bo[state.buf_list].filetype = "fzf_list"
  vim.bo[state.buf_preview].filetype = "fzf_preview"

  -- Windows
  state.win_list = vim.api.nvim_open_win(state.buf_list, true, {
    relative = "editor",
    width = list_width,
    height = total_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Find Files ",
  })

  state.win_preview = vim.api.nvim_open_win(state.buf_preview, false, {
    relative = "editor",
    width = preview_width,
    height = total_height,
    row = row,
    col = col + list_width + 2,
    style = "minimal",
    border = "rounded",
    title = " Preview ",
  })

  -- Styling
  vim.wo[state.win_list].cursorline = true
  vim.wo[state.win_list].winhl = "NormalFloat:Normal,CursorLine:Visual"
  vim.bo[state.buf_list].buftype = "nofile"
  -- Menu-like behavior
  vim.wo[state.win_list].cursorcolumn = false
  vim.wo[state.win_list].list = false
  vim.wo[state.win_list].wrap = false

  vim.wo[state.win_preview].winhl = "NormalFloat:Normal"

  -- Scroll Preview Mappings (Power User Feature)
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

  -- AUTO-CLOSE Logic: If list window closes, close preview
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win_list),
    once = true,
    callback = function()
      if state.win_preview and vim.api.nvim_win_is_valid(state.win_preview) then
        vim.api.nvim_win_close(state.win_preview, true)
      end
      -- Cleanup job
      if state.job_handle and not state.job_handle:is_closing() then
         state.job_handle:close()
      end
    end
  })
end

-- 3. Filter & Render
local function filter_and_render(query)
  if not vim.api.nvim_buf_is_valid(state.buf_list) then return end

  local padding = "  "
  local results = {}
  local highlights = {} -- Store highlight instructions

  local query_lower = query:lower()
  state.filtered_files = {}

  -- FILTER & SCORE
  local scored_files = {}

  for _, file in ipairs(state.files) do
    if query == "" then
       table.insert(scored_files, { file = file, score = 1 })
       if #scored_files > 500 then break end
    else
       local score = score_file(file, query_lower)
       if score > 0 then
         table.insert(scored_files, { file = file, score = score })
       end
    end
  end

  -- SORT by Score DESC
  if query ~= "" then
    table.sort(scored_files, function(a, b) return a.score > b.score end)
  end

  -- DISPLAY
  -- Header
  table.insert(results, padding .. query)
  table.insert(results, padding .. string.rep("─", vim.api.nvim_win_get_width(state.win_list) - 4))

  for i, item in ipairs(scored_files) do
    if i > 500 then break end
    local clean_file = item.file:gsub("^%./", "")

    -- Get Icon Data (icon + color group)
    local icon_data = ui.get_icon_data(clean_file)

    -- Format line: "   config.lua"
    local line_str = padding .. icon_data.icon .. " " .. clean_file
    table.insert(results, line_str)
    table.insert(state.filtered_files, clean_file)

    -- Store highlight info: (line_index, col_start, col_end, hl_group)
    -- Header takes 2 lines, so index is i + 1 (lua 0-based for highlight) + 2
    local row = i + 1
    -- Padding (2) + Icon length (byte length)
    local icon_len = #icon_data.icon
    table.insert(highlights, { row = row, col_start = 2, col_end = 2 + icon_len, hl = icon_data.hl })
  end

  vim.api.nvim_buf_set_lines(state.buf_list, 0, -1, false, results)

  -- APPLY HIGHLIGHTS
  vim.api.nvim_buf_clear_namespace(state.buf_list, -1, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf_list, -1, hl.hl, hl.row, hl.col_start, hl.col_end)
  end

  -- Restore cursor
  if vim.api.nvim_get_mode().mode == 'i' then
      vim.api.nvim_win_set_cursor(state.win_list, {1, #padding + #query})
  end

  -- AUTO PREVIEW FIRST RESULT
  if #state.filtered_files > 0 then
    update_preview(state.filtered_files[1])
  else
    update_preview(nil)
  end
end

-- 4. Start Scan
local function start_scan(on_update)
  state.files = {}

  local cmd, args
  if vim.fn.executable("rg") == 1 then
    cmd = "rg"
    args = { "--files", "--hidden", "--glob", "!.git/*", "--glob", "!node_modules/*", "--glob", "!__pycache__/*", "--glob", "!target/*", "--glob", "!.venv/*" }
  else
    cmd = "find"
    args = { ".", "-type", "f" }
  end

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  state.job_handle = uv.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function()
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if state.job_handle then state.job_handle:close() end
    state.job_handle = nil
  end)

  local buffer = ""
  stdout:read_start(function(err, data)
    assert(not err, err)
    if data then
      buffer = buffer .. data
      local lines = vim.split(buffer, "\n")
      buffer = lines[#lines]
      lines[#lines] = nil

      for _, line in ipairs(lines) do
        if line ~= "" then table.insert(state.files, line) end
      end

      if #state.files % CONFIG.batch_size == 0 then
        vim.schedule(on_update)
      end
    else
      vim.schedule(on_update)
    end
  end)
end

-- 5. Main
function M.open()
  create_ui()
  filter_and_render("")
  vim.cmd("startinsert")

  start_scan(function()
    local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1]
    local query = line and line:gsub("^  ", "") or ""
    filter_and_render(query)
  end)

  -- Input Change
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = state.buf_list,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list)
      if cursor[1] == 1 then
          local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1]
          local query = line:sub(3)
          filter_and_render(query)
      end
    end
  })

  -- Cursor Move (Preview Update)
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    buffer = state.buf_list,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list)
      local row = cursor[1]

      if row >= 3 then
        local idx = row - 2
        local file = state.filtered_files[idx]
        update_preview(file)
      elseif row == 1 and #state.filtered_files > 0 then
        update_preview(state.filtered_files[1])
      end
    end
  })

  -- Actions
  local function close()
    if vim.api.nvim_win_is_valid(state.win_list) then
      vim.api.nvim_win_close(state.win_list, true)
    end
    -- WinClosed autocommand handles the rest
  end

  local function open_file()
    local cursor = vim.api.nvim_win_get_cursor(state.win_list)
    local idx
    if cursor[1] == 1 then idx = 1 else idx = cursor[1] - 2 end

    local file = state.filtered_files[idx]
    if file then
      close()
      require("config.ui").open_in_normal_win(file)
    end
  end

  local opts = { buffer = state.buf_list }
  vim.keymap.set({"i", "n"}, "<Esc>", close, opts)
  vim.keymap.set({"i", "n"}, "<CR>", open_file, opts)

  -- Navigation
  vim.keymap.set("i", "<Down>", function()
    vim.cmd("stopinsert")
    vim.api.nvim_win_set_cursor(state.win_list, {3, 0})
  end, opts)

  vim.keymap.set("n", "<Up>", function()
    local cursor = vim.api.nvim_win_get_cursor(state.win_list)
    if cursor[1] <= 3 then
      vim.api.nvim_win_set_cursor(state.win_list, {1, 0})
      vim.cmd("startinsert")
      local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1]
      vim.api.nvim_win_set_cursor(state.win_list, {1, #line})
    else
      vim.cmd("normal! k")
    end
  end, opts)

  -- AUTO-REDIRECT INPUT: Type anywhere to search
  local function redirect_to_input(key)
    -- 1. Move cursor to input line (end)
    local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1]
    vim.api.nvim_win_set_cursor(state.win_list, {1, #line})
    -- 2. Enter Insert Mode
    vim.cmd("startinsert")
    -- 3. Feed the key
    if key then
      local k = vim.api.nvim_replace_termcodes(key, true, false, true)
      vim.api.nvim_feedkeys(k, "n", true)
    end
  end

  -- Map all printable chars + Backspace
  for i = 32, 126 do -- ASCII space to ~
    local char = string.char(i)
    vim.keymap.set("n", char, function() redirect_to_input(char) end, opts)
  end
  vim.keymap.set("n", "<BS>", function() redirect_to_input("<BS>") end, opts)
end

return M
