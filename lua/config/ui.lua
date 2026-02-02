-- Native UI Overrides (Floating Input/Select)
local M = {}

local colors = require("config.colors")

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

-- Override vim.ui.select (Used by Code Actions, etc.)
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
  
  -- Keymaps
  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local function confirm()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local idx = cursor[1]
    close()
    if on_choice then on_choice(items[idx], idx) end
  end

  vim.keymap.set("n", "<CR>", confirm, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
  
  -- Auto-select first item if needed, but usually just wait
end

-- Override vim.ui.input (Used by Rename, etc.)
function M.input(opts, on_confirm)
  opts = opts or {}
  local prompt = opts.prompt or "Input: "
  local default = opts.default or ""

  -- Calculate width based on prompt + reasonable input space
  local width = math.floor(vim.o.columns * 0.4)
  local height = 1

  local buf, win = create_win(width, height, prompt:gsub(":$", ""))
  
  -- Insert default text
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })
  
  -- Setup buffer for input
  vim.bo[buf].buftype = "prompt" -- Actually, normal buffer is easier for simple input
  vim.bo[buf].buftype = "nofile"
  
  vim.cmd("startinsert")
  if default ~= "" then
    vim.api.nvim_win_set_cursor(win, {1, #default})
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local function confirm()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
    local text = lines[1] or ""
    close()
    if on_confirm then on_confirm(text) end
  end

  vim.keymap.set({"i", "n"}, "<CR>", confirm, { buffer = buf, silent = true })
  vim.keymap.set({"i", "n"}, "<Esc>", function() 
    close()
    if on_confirm then on_confirm(nil) end 
  end, { buffer = buf, silent = true })
end

-- Apply overrides
vim.ui.select = M.select
vim.ui.input = M.input

return M
