local M = {}
local icons = require("utils.icons")
local ui_utils = require("utils.ui")

function M.setup()
  icons.setup()
  ui_utils.setup_lsp_handlers()
end

-- UI Helpers (Select/Input) Overrides
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

  local win_info = ui_utils.create_centered_win({
    width_pct = width / vim.o.columns,
    height = height,
    title = opts.prompt or "Select",
    enter = true
  })
  
  local buf, win = win_info.buf, win_info.win
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
  
  local win_info = ui_utils.create_centered_win({
    width_pct = width / vim.o.columns,
    height = 1,
    title = prompt:gsub(":$", ""),
    enter = true
  })
  
  local buf, win = win_info.buf, win_info.win
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

-- Global Overrides
vim.ui.select = M.select
vim.ui.input = M.input

return M
