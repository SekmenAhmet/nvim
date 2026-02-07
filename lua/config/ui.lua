-- Native UI Overrides & Icon Provider
local M = {}

-- Icon Configuration (Icon + Hex Color)
local icons_config = {
  -- Languages & Extensions
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
  dockerignore = { icon = "", color = "#384d54" },
  sql  = { icon = "", color = "#dadada" },
  rake = { icon = "", color = "#701516" },
  swift = { icon = "", color = "#e37933" },
  lock = { icon = "", color = "#bbbbbb" },
  vue = { icon = "", color = "#42b883" },
  svelte = { icon = "", color = "#ff3e00" },
  jsonc = { icon = "", color = "#cbcb41" },
  json5 = { icon = "", color = "#cbcb41" },
  graphql = { icon = "", color = "#e10098" },
  gql = { icon = "", color = "#e10098" },
  
  -- Common Files (Exact matches)
  [".gitignore"] = { icon = "", color = "#f14e32" },
  [".gitconfig"] = { icon = "", color = "#f14e32" },
  ["Makefile"]   = { icon = "", color = "#6d8086" },
  ["package.json"] = { icon = "", color = "#689f63" },
  ["package-lock.json"] = { icon = "", color = "#7bb077" },
  ["node_modules"] = { icon = "", color = "#E8274B" },
  ["LICENSE"] = { icon = "", color = "#d0bf41" },
  ["README.md"] = { icon = "", color = "#42a5f5" },
  [".env"] = { icon = "", color = "#faf743" },

  -- Media
  png = { icon = "", color = "#a074c4" },
  jpg = { icon = "", color = "#a074c4" },
  jpeg = { icon = "", color = "#a074c4" },
  gif = { icon = "", color = "#a074c4" },
  svg = { icon = "", color = "#ffb13b" },
  pdf = { icon = "", color = "#ff3333" },
  
  -- Archives
  zip = { icon = "", color = "#dcb239" },
  tar = { icon = "", color = "#dcb239" },
  gz = { icon = "", color = "#dcb239" },
  ["7z"] = { icon = "", color = "#dcb239" },
}

-- Setup function to define highlight groups
function M.setup()
  for name, data in pairs(icons_config) do
    -- Clean name for HL group (no dots)
    local hl_name = name:gsub("%.", "")
    vim.api.nvim_set_hl(0, "Icon" .. hl_name, { fg = data.color })
  end
  vim.api.nvim_set_hl(0, "IconDefault", { fg = "#89e051" })
  vim.api.nvim_set_hl(0, "IconDir", { fg = "#7aa2f7" }) -- Folder color (Blue)
  vim.api.nvim_set_hl(0, "IconDirOpen", { fg = "#9ece6a" }) -- Open Folder color (Greenish)
end

-- Simple LRU cache for icon lookups
local icon_cache = {}
local cache_size = 0
local max_cache_size = 100

-- Return { icon = "...", hl = "Icon..." }
function M.get_icon_data(filename)
  -- Check cache first
  if icon_cache[filename] then
    return icon_cache[filename]
  end
  
  local name = vim.fn.fnamemodify(filename, ":t")
  local ext = name:match("^.+%.(.+)$")
  local result
  
  -- Exact match first
  if icons_config[name] then
    result = { icon = icons_config[name].icon, hl = "Icon" .. name:gsub("%.", "") }
  -- Extension match
  elseif ext and icons_config[ext:lower()] then
    result = { icon = icons_config[ext:lower()].icon, hl = "Icon" .. ext:lower():gsub("%.", "") }
  else
    result = { icon = "", hl = "IconDefault" }
  end
  
  -- Simple cache eviction (FIFO)
  if cache_size >= max_cache_size then
    icon_cache = {}
    cache_size = 0
  end
  
  icon_cache[filename] = result
  cache_size = cache_size + 1
  
  return result
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
    title_pos = "left",
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

-- Apply UI overrides
vim.ui.select = M.select
vim.ui.input = M.input

return M