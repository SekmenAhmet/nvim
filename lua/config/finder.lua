-- Native Async Finder with Preview
-- Architecture: Async Spawn (libuv) + Dual Window UI

local M = {}
local uv = vim.uv
local ui = require("config.ui") -- Load UI module
local window = require("config.window") -- Window utilities

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
  last_results = {}, -- Objects {file, score} for incremental filtering
  last_query = "",
  preview_timer = vim.uv.new_timer(), -- Timer réutilisable unique
  last_preview_file = nil,
}

-- Smart Fuzzy Scoring Algorithm
-- "uc" matches "user_controller", "conf" matches "my_config"
local function score_file(file, query_lower)
  if query_lower == "" then return 1 end
  
  local file_lower = file:lower()
  local filename = file_lower:match("^.+/(.+)$") or file_lower
  
  -- Vérifier match exact d'abord
  if filename == query_lower then return 1000 end
  if vim.startswith(filename, query_lower) then return 800 end
  
  -- Fuzzy matching
  local query_idx = 1
  local score = 0
  local last_match = 0
  local consecutive = 0
  
  for i = 1, #filename do
    if filename:sub(i, i) == query_lower:sub(query_idx, query_idx) then
      -- Bonus début de fichier
      if i == 1 then score = score + 15 end
      
      -- Bonus début de mot (après _ - . /)
      if i > 1 and filename:sub(i-1, i-1):match("[%-_%.]") then
        score = score + 12
      end
      
      -- Bonus caractères consécutifs
      if last_match == i - 1 then
        consecutive = consecutive + 1
        score = score + 8 + consecutive * 2
      else
        consecutive = 0
        score = score + 5
      end
      
      -- Malus distance entre matches
      if last_match > 0 and i - last_match > 1 then
        score = score - (i - last_match - 1) * 2
      end
      
      query_idx = query_idx + 1
      last_match = i
      
      if query_idx > #query_lower then
        -- Match complet ! Bonus selon la position
        local remaining_chars = #filename - i
        return score + 100 + math.max(0, 50 - remaining_chars)
      end
    end
  end
  
  -- Fallback : substring si fuzzy échoue
  if filename:find(query_lower, 1, true) then
    return 100
  end
  
  -- Path match (dernier recours)
  if file_lower:find(query_lower, 1, true) then
    return 50
  end
  
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

  state.preview_timer:stop()
  state.preview_timer:start(5, 0, vim.schedule_wrap(function()
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
      if err then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(state.buf_preview) then
            vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, { " [Cannot read file: " .. tostring(err) .. "] " })
          end
        end)
        return
      end
      uv.fs_read(fd, 4096, 0, function(err_read, data)
        uv.fs_close(fd)
        if err_read then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(state.buf_preview) then
              vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, { " [Read error: " .. tostring(err_read) .. "] " })
            end
          end)
          return
        end

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
  local wins = window.create_dual_pane({
    width_pct = CONFIG.width_pct,
    height_pct = CONFIG.height_pct,
    preview_width_pct = CONFIG.preview_width_pct,
    list_title = "Find Files",
    preview_title = "Preview",
    list_filetype = "fzf_list",
    preview_filetype = "fzf_preview",
  })

  state.buf_list = wins.buf_list
  state.win_list = wins.win_list
  state.buf_preview = wins.buf_preview
  state.win_preview = wins.win_preview

  -- Setup scroll preview mappings
  window.setup_scroll_preview(state, state.buf_list)

  -- Setup auto-close
  window.setup_auto_close(state)
end

-- 3. Filter & Render
local function filter_and_render(query)
  if not vim.api.nvim_buf_is_valid(state.buf_list) then return end

  local padding = "  "
  local results = {}
  local highlights = {} -- Store highlight instructions

  local query_lower = query:lower()
  
  -- INCREMENTAL FILTERING LOGIC
  local source_list = state.files
  if #query > #state.last_query and query:sub(1, #state.last_query) == state.last_query and #state.last_results > 0 then
    source_list = {}
    for _, item in ipairs(state.last_results) do table.insert(source_list, item.file) end
  end

  -- FILTER & SCORE
  local scored_files = {}

  for _, file in ipairs(source_list) do
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

  -- Update state for next incremental search
  state.last_query = query
  state.last_results = scored_files

  -- SORT by Score DESC
  if query ~= "" then
    table.sort(scored_files, function(a, b) return a.score > b.score end)
  end

  -- DISPLAY
  state.filtered_files = {}
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
  }, function(code, signal)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if state.job_handle and not state.job_handle:is_closing() then
      state.job_handle:close()
    end
    state.job_handle = nil
  end)

  local buffer = ""
  stdout:read_start(function(err, data)
    if err then
      vim.schedule(function()
        vim.notify("Finder error: " .. tostring(err), vim.log.levels.ERROR)
      end)
      return
    end
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
    -- Stop preview timer
    if state.preview_timer then
      state.preview_timer:stop()
    end
    window.close_windows(state)
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
