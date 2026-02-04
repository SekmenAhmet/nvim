-- Native Live Grep with Preview (Async & Non-blocking)
-- Architecture: Async Spawn (libuv) + Dual Window UI

local M = {}
local uv = vim.uv
local ui = require("config.ui") -- Load UI for icons
local window = require("config.window") -- Window utilities

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
  results = {}, -- Raw results from grep
  line_map = {}, -- Maps buffer line to result index
  timer_debounce = vim.uv.new_timer(), -- Timer réutilisable unique
  timer_preview = vim.uv.new_timer(),  -- Timer réutilisable unique
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

  state.timer_preview:stop()
  state.timer_preview:start(5, 0, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(state.buf_preview) then return end
    local stat = uv.fs_stat(filename)
    if not stat or stat.type ~= "file" then
      vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, { " [File not found] " })
      return
    end

    -- OPTIMISATION : Limiter la lecture aux lignes contextuelles
    local context_lines = 50  -- 50 avant + 50 après = 100 lignes max
    local line_length_estimate = 100
    local max_read_size = context_lines * 2 * line_length_estimate  -- ~10KB
    
    local read_size = stat.size
    local offset = 0
    local is_truncated = false
    
    -- Si fichier gros, lire seulement le contexte
    if stat.size > max_read_size then
      is_truncated = true
      -- Estimation grossière : lnum * taille_moyenne_ligne
      offset = math.max(0, (lnum - context_lines) * line_length_estimate)
      read_size = math.min(max_read_size, stat.size - offset)
      
      -- Aligner sur le début d'une ligne
      if offset > 0 then
        offset = math.max(0, offset - line_length_estimate)
        read_size = math.min(max_read_size + line_length_estimate, stat.size - offset)
      end
    end

    uv.fs_open(filename, "r", 438, function(err, fd)
      if err then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(state.buf_preview) then
            vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, { " [Cannot open file: " .. tostring(err) .. "] " })
          end
        end)
        return
      end
      uv.fs_read(fd, read_size, offset, function(err_read, data)
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
          vim.api.nvim_buf_set_lines(state.buf_preview, 0, -1, false, lines)

          local ft = vim.filetype.match({ filename = filename })
          if ft then vim.bo[state.buf_preview].filetype = ft end

          -- Calculer la ligne relative dans le contexte lu
          local relative_lnum = lnum
          if is_truncated then
            -- Si on a lu un offset, trouver où est la ligne cible
            relative_lnum = math.min(context_lines + 1, #lines)
            -- Chercher la ligne contenant le numéro (approximatif)
            for i, line in ipairs(lines) do
              if i > 1 and i < #lines then
                -- Heuristique : si on trouve un pattern similaire
                if i >= context_lines - 5 and i <= context_lines + 5 then
                  relative_lnum = i
                  break
                end
              end
            end
          end
          
          relative_lnum = math.max(1, math.min(relative_lnum, #lines))
          
          pcall(vim.api.nvim_win_set_cursor, state.win_preview, {relative_lnum, 0})
          vim.api.nvim_win_call(state.win_preview, function() vim.cmd("normal! zz") end)

          local ns = vim.api.nvim_create_namespace("grep_preview")
          vim.api.nvim_buf_clear_namespace(state.buf_preview, ns, 0, -1)
          vim.api.nvim_buf_add_highlight(state.buf_preview, ns, "Search", relative_lnum - 1, 0, -1)
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

  -- Separator (Line 2 in buffer)
  table.insert(display_lines, "  " .. string.rep("─", vim.api.nvim_win_get_width(state.win_list) - 4))

  if #state.results == 0 then
    table.insert(display_lines, "  " .. (query == "" and "-- Type to search --" or "-- No results --"))
  else
    local current_file = nil
    for i, res in ipairs(state.results) do
      if #display_lines > 500 then break end
      -- New file group
      if res.filename ~= current_file then
        current_file = res.filename
        -- Strip ./ and trim spaces
        local clean_name = res.filename:gsub("^%./", ""):gsub("^%s*(.-)%s*$", "%1")
        local icon_data = ui.get_icon_data(clean_name)
        
        table.insert(display_lines, " " .. icon_data.icon .. " " .. clean_name)
        
        local row = 1 + (#display_lines - 1) 
        local col_end = 1 + #icon_data.icon
        table.insert(highlights, { row = row, col_start = 1, col_end = col_end, hl = icon_data.hl })
      end
      
      -- Trim result text to avoid messy indentation in the list
      local clean_text = res.text:gsub("^%s*(.-)%s*$", "%1")
      local line_str = string.format("   %s: %s", res.lnum, clean_text)
      table.insert(display_lines, line_str)
      -- Map absolute buffer line index (1 for sep + index in list)
      state.line_map[1 + #display_lines] = i
    end
  end

  -- Initial Init of Line 1 if empty (just in case)
  if vim.api.nvim_buf_line_count(state.buf_list) == 0 then
     vim.api.nvim_buf_set_lines(state.buf_list, 0, -1, false, {"  "})
  end

  -- Update ONLY lines 2+ (Results)
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

  -- IMPORTANT: DO NOT TOUCH CURSOR IF INSERT MODE
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
  }, function(code, signal)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if state.job_handle and not state.job_handle:is_closing() then
      state.job_handle:close()
    end
  end)

  stderr:read_start(function(err, data)
    if err then
      vim.schedule(function()
        vim.notify("Grep stderr error: " .. tostring(err), vim.log.levels.WARN)
      end)
    end
  end)

  local buffer = ""
  stdout:read_start(function(err, data)
    if err then
      vim.schedule(function()
        vim.notify("Grep error: " .. tostring(err), vim.log.levels.ERROR)
      end)
      return
    end
    if data then
      buffer = buffer .. data
      local lines = vim.split(buffer, "\n")
      buffer = lines[#lines]
      lines[#lines] = nil
      for _, line in ipairs(lines) do
        local parts = vim.split(line, ":")
        if #parts >= 4 then
          local filename = parts[1]
          local lnum = parts[2]
          local text = table.concat(parts, ":", 4)
          local is_comment = text:match("^%s*//") or text:match("^%s*#") or text:match("^%s*%-%-") or text:match("^%s*%%") or text:match("^%s*/%*") or text:match("^%s*%*")
          if not is_comment then
             table.insert(state.results, { filename = filename, lnum = lnum, text = text })
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
  local wins = window.create_dual_pane({
    width_pct = CONFIG.width_pct,
    height_pct = CONFIG.height_pct,
    preview_width_pct = CONFIG.preview_width_pct,
    list_title = "Live Grep",
    preview_title = "Preview",
    list_filetype = "grep_list",
  })

  state.buf_list = wins.buf_list
  state.win_list = wins.win_list
  state.buf_preview = wins.buf_preview
  state.win_preview = wins.win_preview

  -- Enable line numbers for preview (grep specific)
  vim.wo[state.win_preview].number = true

  -- Setup scroll preview mappings
  window.setup_scroll_preview(state, state.buf_list)

  -- Setup auto-close avec nettoyage des highlights
  window.setup_auto_close(state, {
    on_close = function()
      -- Nettoyer les highlights du preview
      local ns = vim.api.nvim_create_namespace("grep_preview")
      if state.buf_preview and vim.api.nvim_buf_is_valid(state.buf_preview) then
        vim.api.nvim_buf_clear_namespace(state.buf_preview, ns, 0, -1)
      end
      -- Nettoyer tous les buffers de highlights grep
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        end
      end
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
        -- Enforce Padding Synchronously Here
        local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1] or ""
        if not line:match("^  ") then
           local fixed = "  " .. line:gsub("^%s*", "")
           vim.api.nvim_buf_set_lines(state.buf_list, 0, 1, false, {fixed})
           vim.api.nvim_win_set_cursor(state.win_list, {1, #fixed})
           line = fixed
        end

        local query = line:sub(3)
        state.timer_debounce:stop()
        state.timer_debounce:start(20, 0, vim.schedule_wrap(function() start_grep(query) end))
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
    window.close_windows(state)
  end

  local function open_result()
    local cursor = vim.api.nvim_win_get_cursor(state.win_list)
    local row = cursor[1]
    local res_idx = state.line_map[row] or (row == 1 and 1 or nil)
    local res = res_idx and state.results[res_idx]
    if res then 
      close()
      -- Nettoyer les highlights avant d'ouvrir
      local ns = vim.api.nvim_create_namespace("grep_preview")
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        end
      end
      require("config.ui").open_in_normal_win(res.filename, res.lnum) 
    end
  end

  local opts = { buffer = state.buf_list }
  vim.keymap.set({"i", "n"}, "<Esc>", close, opts)
  vim.keymap.set({"i", "n"}, "<CR>", open_result, opts)

  local function navigate(dir)
    vim.cmd("stopinsert")
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
