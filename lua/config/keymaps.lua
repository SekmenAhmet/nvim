local utils = require("utils")

-- Navigation entre fenêtres : Ctrl+HJKL
for _, dir in ipairs({"h", "j", "k", "l"}) do
  local desc = ({ h = "left", j = "below", k = "above", l = "right" })[dir]
  vim.keymap.set("n", "<C-" .. dir .. ">", "<C-w>" .. dir, { silent = true, desc = "Go to " .. desc .. " window" })
end

-- Resize du tree avec Ctrl+Alt+flèches (Inversé)
vim.keymap.set("n", "<C-M-Left>", "<cmd>vertical resize +2<CR>", { silent = true, desc = "Increase window width" })
vim.keymap.set("n", "<C-M-Right>", "<cmd>vertical resize -2<CR>", { silent = true, desc = "Decrease window width" })

-- Sauvegarde rapide avec Ctrl+S
vim.keymap.set({"n", "i", "v"}, "<C-s>", "<cmd>w<CR>", { silent = true, desc = "Save file" })

-- Navigation entre les buffers (Onglets)
vim.keymap.set("n", "<Tab>", ":bnext<CR>", { silent = true, desc = "Next Buffer" })
vim.keymap.set("n", "<S-Tab>", ":bprev<CR>", { silent = true, desc = "Previous Buffer" })

-- Smart Buffer Delete avec gestion des cas edge
local function smart_buffer_delete()
  local buf = vim.api.nvim_get_current_buf()
  
  -- 1. Terminal : Force delete
  if vim.bo[buf].buftype == "terminal" then
    vim.cmd("bdelete! " .. buf)
    return
  end
  
  -- 2. Modified : Confirm
  if vim.bo[buf].modified then
    local choice = vim.fn.confirm("Buffer modifié. Sauvegarder?", "&Oui\n&Non (perdre)\n&Annuler", 3)
    if choice == 1 then
      vim.cmd("write")
    elseif choice == 3 then
      return
    end
  end
  
  -- 3. Navigation : Try Alt (#) -> Next -> New
  local alt = vim.fn.bufnr("#")
  if alt ~= -1 and alt ~= buf and vim.fn.buflisted(alt) == 1 then
    vim.api.nvim_set_current_buf(alt)
  else
    vim.cmd("bnext")
    if vim.api.nvim_get_current_buf() == buf then
      vim.cmd("enew") -- Dernier buffer
    end
  end
  
  -- 4. Delete
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.cmd, "bdelete! " .. buf)
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
vim.keymap.set("n", "<leader>x", smart_buffer_delete, { silent = true, desc = "Close current buffer (smart)" })
vim.keymap.set("n", "<leader>X", close_all_buffers, { silent = true, desc = "Close all buffers" })

-- Supprimer le mot précédent en mode insert (Ctrl+Backspace)
vim.keymap.set("i", "<C-BS>", "<C-W>", { desc = "Delete previous word" })
vim.keymap.set("i", "<C-h>", "<C-W>", { desc = "Delete previous word" })

-- Lazy Loading Triggers (using utils.lazy_require)
vim.keymap.set("n", "<leader>ff", utils.lazy_require("config.finder", "open"), { desc = "Find Files (Native)" })
vim.keymap.set("n", "<leader>fg", utils.lazy_require("config.grep", "open"), { desc = "Live Grep (Native)" })
vim.keymap.set("n", "/", utils.lazy_require("config.search", "open"), { desc = "Search in file (Native)" })
vim.keymap.set({"n", "v"}, ":", utils.lazy_require("config.cmdline", "open"), { desc = "Command Line (Native)" })
vim.keymap.set({"n", "i"}, "<C-p>", utils.lazy_require("config.rest", "open"), { desc = "Open REST Client" })
vim.keymap.set({"n", "i", "t"}, "<C-t>", utils.lazy_require("config.terminal", "toggle"), { desc = "Toggle terminal" })
vim.keymap.set({"n", "i", "v"}, "<C-b>", utils.lazy_require("config.netrw", "toggle"), { silent = true, desc = "Toggle file tree" })
vim.keymap.set({"n", "i", "t"}, "<C-g>", utils.lazy_require("config.git", "toggle"), { desc = "Toggle Git Dashboard" })
