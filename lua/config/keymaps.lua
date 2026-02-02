-- Navigation entre fenêtres : Ctrl+H (gauche), Ctrl+L (droite)
vim.keymap.set("n", "<C-h>", "<C-w>h", { silent = true, desc = "Go to left window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { silent = true, desc = "Go to right window" })

-- Resize du tree avec Ctrl+Alt+flèches (Inversé)
vim.keymap.set("n", "<C-M-Left>", "<cmd>vertical resize +2<CR>", { silent = true, desc = "Increase window width" })
vim.keymap.set("n", "<C-M-Right>", "<cmd>vertical resize -2<CR>", { silent = true, desc = "Decrease window width" })

-- Sauvegarde rapide avec Ctrl+S
vim.keymap.set("n", "<C-s>", ":w<CR>", { silent = true, desc = "Save file" })
vim.keymap.set("i", "<C-s>", "<Esc>:w<CR>a", { silent = true, desc = "Save file" })
vim.keymap.set("v", "<C-s>", "<Esc>:w<CR>", { silent = true, desc = "Save file" })

-- Navigation entre les buffers (Onglets)
vim.keymap.set("n", "<Tab>", ":bnext<CR>", { silent = true, desc = "Next Buffer" })
vim.keymap.set("n", "<S-Tab>", ":bprev<CR>", { silent = true, desc = "Previous Buffer" })

-- Helper to close current buffer
local function close_buffer()
  local current = vim.api.nvim_get_current_buf()
  local buffers = vim.fn.getbufinfo({buflisted=1})
  
  if #buffers > 1 then
    -- Try to switch to previous buffer first
    vim.cmd("bprevious")
  else
    -- If it's the last buffer, create a new one first
    vim.cmd("enew")
  end
  
  -- Delete the original buffer if it's valid
  if vim.api.nvim_buf_is_valid(current) then
    vim.cmd("bdelete " .. current)
  end
end

-- Helper to close all buffers
local function close_all_buffers()
  -- Create a new empty buffer
  vim.cmd("enew")
  -- Delete all other listed buffers
  local current = vim.api.nvim_get_current_buf()
  local buffers = vim.fn.getbufinfo({buflisted=1})
  for _, buf in ipairs(buffers) do
    if buf.bufnr ~= current then
      pcall(vim.cmd, "bdelete " .. buf.bufnr)
    end
  end
end

-- Fermer le buffer actuel sans fermer la fenêtre
vim.keymap.set("n", "<leader>x", close_buffer, { silent = true, desc = "Close current buffer" })
vim.keymap.set("n", "<leader>X", close_all_buffers, { silent = true, desc = "Close all buffers" })

-- Supprimer le mot précédent en mode insert (Ctrl+Backspace)
vim.keymap.set("i", "<C-BS>", "<C-W>", { desc = "Delete previous word" })
vim.keymap.set("i", "<C-h>", "<C-W>", { desc = "Delete previous word" })
