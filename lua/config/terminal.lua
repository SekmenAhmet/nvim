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
  local col = math.floor((vim.o.columns - width) / 2) + 1  -- +1 padding x

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
    -- Determine shell based on OS
    local shell = vim.o.shell
    local is_windows = vim.uv.os_uname().version:find("Windows") or vim.fn.has("win32") == 1

    if is_windows then
      if vim.fn.executable("pwsh") == 1 then
        shell = "pwsh"
      elseif vim.fn.executable("powershell") == 1 then
        shell = "powershell"
      end
    else
      -- Linux/Unix: Prefer fish if available
      if vim.fn.executable("fish") == 1 then
        shell = "fish"
      end
    end

    vim.fn.termopen(shell, {
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
  -- Esc ferme directement depuis le mode terminal (plus pratique)
  vim.keymap.set("t", "<Esc>", function()
    vim.api.nvim_win_close(terminal_win, true)
    terminal_win = nil
  end, opts)
  vim.keymap.set("t", "<C-t>", M.toggle, opts) 
  vim.keymap.set("n", "<C-t>", M.toggle, opts)
  vim.keymap.set("n", "q", M.toggle, opts)
  vim.keymap.set("n", "<Esc>", M.toggle, opts) -- Allow closing with Esc in Normal mode
end

return M