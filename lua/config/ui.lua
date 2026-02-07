-- Native UI Overrides & Icon Provider
local M = {}

-- apply overrides
vim.ui.select = M.select -- Defined below (placeholder, referenced from previous logic)

-- Icon Configuration (Icon + Hex Color)
local icons_config = {
  lua  = { icon = "", color = "#51a0cf" },
  py   = { icon = "", color = "#ffbc03" },
  js   = { icon = "", color = "#cbcb41" },
  ts   = { icon = "", color = "#3178c6" },
  jsx  = { icon = "", color = "#61dbfb" },
  tsx  = { icon = "", color = "#3178c6" },
  html = { icon = "", color = "#e34c26" },
  css  = { icon = "", color = "#563d7c" },
  scss = { icon = "", color = "#c6538c" },
  json = { icon = "", color = "#cbcb41" },
  xml  = { icon = "", color = "#e34c26" },
  c    = { icon = "", color = "#599eff" },
  cpp  = { icon = "", color = "#599eff" },
  h    = { icon = "", color = "#a074c4" },
  rs   = { icon = "", color = "#dea584" },
  go   = { icon = "", color = "#00add8" },
  java = { icon = "", color = "#cc3e44" },
  php  = { icon = "", color = "#a074c4" },
  rb   = { icon = "", color = "#701516" },
  sh   = { icon = "", color = "#4d5a5e" },
  bash = { icon = "", color = "#4d5a5e" },
  zsh  = { icon = "", color = "#89e051" },
  md   = { icon = "", color = "#ffffff" },
  txt  = { icon = "", color = "#89e051" },
  yml  = { icon = "", color = "#6d8086" },
  yaml = { icon = "", color = "#6d8086" },
  toml = { icon = "", color = "#6d8086" },
  make = { icon = "", color = "#6d8086" },
  conf = { icon = "", color = "#6d8086" },
  git  = { icon = "", color = "#f14e32" },
  Dockerfile = { icon = "", color = "#384d54" },
}

-- Setup function to define highlight groups
function M.setup()
  for ext, data in pairs(icons_config) do
    vim.api.nvim_set_hl(0, "Icon" .. ext, { fg = data.color })
  end
  vim.api.nvim_set_hl(0, "IconDefault", { fg = "#89e051" })
  vim.api.nvim_set_hl(0, "IconDir", { fg = "#7aa2f7" }) -- Folder color (Blue)
end

-- Return { icon = "...", hl = "Icon..." }
function M.get_icon_data(filename)
  local name = vim.fn.fnamemodify(filename, ":t")
  local ext = filename:match("^.+%.(.+)$") or name
  
  -- Exact match first
  if icons_config[name] then
    return { icon = icons_config[name].icon, hl = "Icon" .. name }
  end
  
  -- Extension match
  if ext and icons_config[ext:lower()] then
    return { icon = icons_config[ext:lower()].icon, hl = "Icon" .. ext:lower() }
  end
  
  return { icon = "", hl = "IconDefault" }
end

-- UI Helpers (Select/Input) - kept from previous version
-- Helper to create a floating window centered
local function create_win(width, height, title)
  local cols = vim.o.columns
  local lines = vim.o.lines
  local row = math.floor((lines - height) / 2)
  local col = math.floor((cols - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title and (" " .. title .. " ") or nil,
    title_pos = "center",
  })

  vim.wo[win].winhl = "NormalFloat:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual"
  vim.wo[win].cursorline = true
  
  return buf, win
end

function M.select(items, opts, on_choice)
  opts = opts or {}
  local choices = {}
  local format_item = opts.format_item or tostring

  for i, item in ipairs(items) do
    table.insert(choices, string.format(" %d. %s ", i, format_item(item)))
  end

  if #choices == 0 then return end

  local width = 0
  for _, line in ipairs(choices) do
    width = math.max(width, #line)
  end
  width = math.min(width + 4, math.floor(vim.o.columns * 0.8))
  local height = math.min(#choices, math.floor(vim.o.lines * 0.8))

  local buf, win = create_win(width, height, opts.prompt or "Select")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, choices)
  
  local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  local function confirm()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local idx = cursor[1]
    close()
    if on_choice then on_choice(items[idx], idx) end
  end

  vim.keymap.set("n", "<CR>", confirm, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
end

function M.input(opts, on_confirm)
  opts = opts or {}
  local prompt = opts.prompt or "Input: "
  local default = opts.default or ""
  local width = math.floor(vim.o.columns * 0.4)
  local height = 1

  local buf, win = create_win(width, height, prompt:gsub(":$", ""))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })
  vim.bo[buf].buftype = "nofile"
  
  vim.cmd("startinsert")
  if default ~= "" then vim.api.nvim_win_set_cursor(win, {1, #default}) end

  local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  local function confirm()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
    close()
    if on_confirm then on_confirm(lines[1] or "") end
  end

  vim.keymap.set({"i", "n"}, "<CR>", confirm, { buffer = buf, silent = true })
  vim.keymap.set({"i", "n"}, "<Esc>", function() close(); if on_confirm then on_confirm(nil) end end, { buffer = buf, silent = true })
end
-- Re-apply overrides in case of reload
vim.ui.select = M.select
vim.ui.input = M.input

-- Open in normal win
function M.open_in_normal_win(file, lnum)
  -- Logic identical to previous, just re-declaring for completeness
  local curr_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[cur_buf].filetype
  local cfg = vim.api.nvim_win_get_config(curr_win)
  
  -- Si on est dans le tree ou une fenêtre flottante
  if ft == "tree" or ft == "netrw" or cfg.relative ~= "" then
    vim.cmd("wincmd p") -- Aller à la fenêtre précédente
    curr_win = vim.api.nvim_get_current_win()
    cur_buf = vim.api.nvim_get_current_buf()
    ft = vim.bo[cur_buf].filetype
    cfg = vim.api.nvim_win_get_config(curr_win)
    
    -- Si la fenêtre précédente est aussi invalide (ex: on vient de lancer nvim)
    if ft == "tree" or ft == "netrw" or cfg.relative ~= "" then
      local found = false
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local w_buf = vim.api.nvim_win_get_buf(w)
        local w_ft = vim.bo[w_buf].filetype
        if vim.api.nvim_win_get_config(w).relative == "" and w_ft ~= "tree" and w_ft ~= "netrw" then
          vim.api.nvim_set_current_win(w)
          found = true
          break
        end
      end
      if not found then 
        vim.cmd("vsplit") -- Créer une nouvelle fenêtre
        vim.cmd("wincmd l") -- Aller à droite
      end
    end
  end
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  if lnum then
    vim.api.nvim_win_set_cursor(0, { tonumber(lnum), 0 })
    vim.cmd("normal! zz")
  end
end

return M