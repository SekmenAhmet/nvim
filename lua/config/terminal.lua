local M = {}

local terminal_buf = nil
local terminal_win = nil

function M.toggle()
  -- If window is open, close it
  if terminal_win and vim.api.nvim_win_is_valid(terminal_win) then
    vim.api.nvim_win_close(terminal_win, true)
    terminal_win = nil
    return
  end

  -- Calculate dimensions
  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer if needed
  if terminal_buf == nil or not vim.api.nvim_buf_is_valid(terminal_buf) then
    terminal_buf = vim.api.nvim_create_buf(false, true)
  end

  -- Create window
  terminal_win = vim.api.nvim_open_win(terminal_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Terminal ",
    title_pos = "center",
  })

  -- Setup terminal if buffer is empty (newly created)
  if vim.bo[terminal_buf].channel == 0 then
    vim.fn.termopen(vim.o.shell, {
      cwd = vim.fn.getcwd(),
      on_exit = function()
        terminal_buf = nil
        terminal_win = nil
      end,
    })
  end

  -- Window options
  vim.wo[terminal_win].number = false
  vim.wo[terminal_win].relativenumber = false
  
  -- Enter insert mode immediately
  vim.cmd("startinsert")

  -- Keymaps for the terminal buffer
  local opts = { buffer = terminal_buf, silent = true }
  vim.keymap.set("t", "<Esc>", [[<C-\\><C-n>]], opts) -- Exit insert mode
  vim.keymap.set("t", "<C-t>", M.toggle, opts) 
  vim.keymap.set("n", "<C-t>", M.toggle, opts)
  vim.keymap.set("n", "q", M.toggle, opts)
  vim.keymap.set("n", "<Esc>", M.toggle, opts) -- Allow closing with Esc in Normal mode
end

-- Global Keymaps
-- Changed from <C-:> to <C-t> for better compatibility
vim.keymap.set("n", "<C-t>", M.toggle, { desc = "Toggle terminal" })
vim.keymap.set("i", "<C-t>", M.toggle, { desc = "Toggle terminal" })
vim.keymap.set("t", "<C-t>", M.toggle, { desc = "Toggle terminal" })

vim.api.nvim_create_user_command("ToggleTerm", M.toggle, {})

return M