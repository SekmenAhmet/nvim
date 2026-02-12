-- Native Async Finder with Preview
-- Architecture: Async Spawn (libuv) + Dual Window UI

local M = {}
local uv = vim.uv
local icons = require("utils.icons")
local utils = require("utils")
local fuzzy = require("utils.fuzzy")

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
  preview_timer = vim.uv.new_timer(),
  last_preview_file = nil,
}

-- 1. Preview Logic
local function update_preview(filepath)
  utils.async_preview(filepath, state.buf_preview, state.win_preview, {
    timer = state.preview_timer,
  })
end

-- 2. Create UI
local function create_ui()
  local wins = utils.create_dual_pane({
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

  utils.setup_scroll_preview(state, state.buf_list)
  utils.setup_auto_close(state)
end

-- 3. Filter & Render
local function filter_and_render(query)
  if not vim.api.nvim_buf_is_valid(state.buf_list) then return end

  local padding = "  "
  local results = {}
  local highlights = {}

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
       local score = fuzzy.score(file, query)
       if score > 0 then
         table.insert(scored_files, { file = file, score = score })
       end
    end
  end

  state.last_query = query
  state.last_results = scored_files

  if query ~= "" then
    table.sort(scored_files, function(a, b) return a.score > b.score end)
  end

  -- DISPLAY
  state.filtered_files = {}
  table.insert(results, padding .. query)
  table.insert(results, padding .. string.rep("─", vim.api.nvim_win_get_width(state.win_list) - 4))

  for i, item in ipairs(scored_files) do
    if i > 500 then break end
    local clean_file = item.file:gsub("^%./", "")
    local icon_data = icons.get(clean_file)

    local line_str = padding .. icon_data.icon .. " " .. clean_file
    table.insert(results, line_str)
    table.insert(state.filtered_files, clean_file)

    local row = i + 1
    local icon_len = #icon_data.icon
    table.insert(highlights, { row = row, col_start = 2, col_end = 2 + icon_len, hl = icon_data.hl })
  end

  vim.api.nvim_buf_set_lines(state.buf_list, 0, -1, false, results)
  vim.api.nvim_buf_clear_namespace(state.buf_list, -1, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf_list, -1, hl.hl, hl.row, hl.col_start, hl.col_end)
  end

  if vim.api.nvim_get_mode().mode == 'i' then
      vim.api.nvim_win_set_cursor(state.win_list, {1, #padding + #query})
  end

  if #state.filtered_files > 0 then
    update_preview(state.filtered_files[1])
  else
    update_preview(nil)
  end
end

-- 4. Start Scan
local function start_scan(on_update)
  state.files = {}
  local cmd = vim.fn.executable("rg") == 1 and "rg" or "find"
  local args = cmd == "rg" 
    and { "--files", "--hidden", "--glob", "!.git/*", "--glob", "!node_modules/*" }
    or { ".", "-type", "f" }

  local stdout = uv.new_pipe(false)
  local handle
  handle = uv.spawn(cmd, {
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
    if not vim.api.nvim_buf_is_valid(state.buf_list) then return end
    local line = vim.api.nvim_buf_get_lines(state.buf_list, 0, 1, false)[1]
    local query = line and line:gsub("^  ", "") or ""
    filter_and_render(query)
  end)

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

  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    buffer = state.buf_list,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(state.win_list)
      local row = cursor[1]
      if row >= 3 then
        local idx = row - 2
        update_preview(state.filtered_files[idx])
      elseif row == 1 and #state.filtered_files > 0 then
        update_preview(state.filtered_files[1])
      end
    end
  })

  local function close()
    utils.cleanup_timers({ state.preview_timer })
    utils.close_windows(state)
  end

  local function open_file()
    local cursor = vim.api.nvim_win_get_cursor(state.win_list)
    local idx = cursor[1] == 1 and 1 or cursor[1] - 2
    local file = state.filtered_files[idx]
    if file then
      close()
      require("utils.ui").open_in_normal_win(file)
    end
  end

  local opts = { buffer = state.buf_list }
  vim.keymap.set({"i", "n"}, "<Esc>", close, opts)
  vim.keymap.set({"i", "n"}, "<CR>", open_file, opts)
  utils.setup_list_navigation(state.buf_list, state.win_list, 3)
  utils.setup_redirect_input(state.buf_list, function() return state.win_list end)
end

return M
