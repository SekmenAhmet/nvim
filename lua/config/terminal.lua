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

  -- Calculate dimensions (80% of screen)
  local width = math.floor(vim.o.columns * 0.8)
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
    title_pos = "left",
  })

  -- Setup terminal if buffer is empty (using jobstart with 'term' option - modern API)
  if vim.bo[terminal_buf].buftype ~= "terminal" then
    local shell = vim.fn.executable("fish") == 1 and "fish" or vim.o.shell
    vim.fn.jobstart({ shell }, {
      term = true,
      cwd = vim.fn.getcwd(),
      on_exit = function()
        if terminal_win and vim.api.nvim_win_is_valid(terminal_win) then
          vim.api.nvim_win_close(terminal_win, true)
          terminal_win = nil
        end
        terminal_buf = nil
      end,
    })
  end

  -- Window options
  vim.wo[terminal_win].number = false
  vim.wo[terminal_win].relativenumber = false

  -- Enter insert mode immediately
  vim.cmd("startinsert")

  -- Mappings sécurisés
  local opts = { buffer = terminal_buf, silent = true }
  -- <C-t> pour fermer (Toggle symétrique)
  vim.keymap.set("t", "<C-t>", M.toggle, opts)
  -- <Leader><Esc> pour forcer la fermeture si besoin
  vim.keymap.set("t", "<leader><Esc>", M.toggle, opts)

  -- Permettre la navigation standard entre fenêtres depuis le terminal
  vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], opts)
  vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], opts)
  vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], opts)
  vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], opts)
end

return M