-- Native Fuzzy Finder (Leader ff)
-- Zero plugins, pure Lua (Cross-platform)

local M = {}

-- Ignore list
local ignored_dirs = {
  ["node_modules"] = true,
  [".git"] = true,
  [".venv"] = true,
  ["__pycache__"] = true,
  ["target"] = true,
  ["build"] = true,
  ["dist"] = true,
  ["vendor"] = true,
}

-- Pure Lua recursive file scanner (Replaces 'find'/'sed')
local function get_files(path)
  local files = {}
  local handle = vim.loop.fs_scandir(path)
  if not handle then return {} end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then break end
    
    -- Ignore dotfiles/dotdirs and specific ignored dirs
    if not name:match("^%.") and not ignored_dirs[name] then
      local rel_path = path == "." and name or (path .. "/" .. name)
      
      if type == "directory" then
        -- Recurse
        local sub_files = get_files(rel_path)
        for _, f in ipairs(sub_files) do
          table.insert(files, f)
        end
      elseif type == "file" then
        table.insert(files, rel_path)
      end
    end
  end
  return files
end

-- Configuration de la fenêtre flottante
local function create_window()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor(vim.o.lines * 0.1) -- 10% from top
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Find File ",
    title_pos = "center",
  })

  vim.wo[win].cursorline = true
  vim.wo[win].winhl = "NormalFloat:Normal,CursorLine:Visual"
  vim.bo[buf].filetype = "custom_finder"
  vim.bo[buf].buftype = "nofile"
  
  return buf, win
end

function M.open()
  local buf, win = create_window()
  local padding = "  "
  
  -- Scan files asynchronously or synchronously? 
  -- For reasonable project sizes, sync is fine and simpler.
  -- Adding a "Loading..." message could be good.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { padding .. "Scanning files..." })
  vim.cmd("redraw")
  
  -- Run scan
  local all_files = get_files(".")
  
  if #all_files > 20000 then
    -- Safety cap
    local capped = {}
    for i=1, 20000 do capped[i] = all_files[i] end
    all_files = capped
    table.insert(all_files, 1, "-- Max limit reached (20k) --")
  end

  local function redraw(query)
    local results = {}
    table.insert(results, padding .. query)
    table.insert(results, padding .. string.rep("─", vim.api.nvim_win_get_width(win) - 6))

    local match_count = 0
    local query_lower = query:lower()
    
    for _, file in ipairs(all_files) do
      if match_count > 500 then break end
      -- Fuzzy-ish search (smart case handled by lower)
      if query == "" or file:lower():find(query_lower, 1, true) then
        table.insert(results, padding .. file)
        match_count = match_count + 1
      end
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, results)
    
    if vim.api.nvim_get_mode().mode == 'i' then
        vim.api.nvim_win_set_cursor(win, {1, #padding + #query})
    end
  end

  -- Init
  redraw("")
  vim.cmd("startinsert")

  -- Handlers
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(win)
      if cursor[1] == 1 then
          local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
          local query = line:sub(#padding + 1)
          redraw(query)
      end
    end
  })

  vim.keymap.set("i", "<Down>", function()
    vim.cmd("stopinsert")
    vim.api.nvim_win_set_cursor(win, {3, 0})
  end, { buffer = buf })

  vim.keymap.set("n", "<Up>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    if cursor[1] <= 3 then
      vim.api.nvim_win_set_cursor(win, {1, 0})
      vim.cmd("startinsert")
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      vim.api.nvim_win_set_cursor(win, {1, #line})
    else
      vim.cmd("normal! k")
    end
  end, { buffer = buf })

  local function open_file()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    if cursor_line <= 2 then return end

    local line_content = vim.api.nvim_get_current_line()
    local clean_path = line_content:sub(#padding + 1)
    
    vim.api.nvim_win_close(win, true)
    
    if clean_path and clean_path ~= "" and vim.loop.fs_stat(clean_path) then
      require("config.ui").open_in_normal_win(clean_path)
    end
  end

  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("i", "<Esc>", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "<CR>", open_file, { buffer = buf })
  vim.keymap.set("i", "<CR>", open_file, { buffer = buf })
end

return M