-- Navigation entre fenêtres : Ctrl+HJKL (Toutes directions)
vim.keymap.set("n", "<C-h>", "<C-w>h", { silent = true, desc = "Go to left window" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { silent = true, desc = "Go to window below" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { silent = true, desc = "Go to window above" })
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

-- Lazy Loading Triggers
-- These load the module only when the key is pressed

-- Finder (Leader ff)
vim.keymap.set("n", "<leader>ff", function() require("config.finder").open() end, { desc = "Find Files (Native)" })

-- Live Grep (Leader fg)
vim.keymap.set("n", "<leader>fg", function() require("config.grep").open() end, { desc = "Live Grep (Native)" })

-- Native Search (Replace /)
vim.keymap.set("n", "/", function() require("config.search").open() end, { desc = "Search in file (Native)" })

-- Native Cmdline (Replace :)
vim.keymap.set({"n", "v"}, ":", function() require("config.cmdline").open() end, { desc = "Command Line (Native)" })

-- Native REST Client (Postman-like)
vim.keymap.set({"n", "i"}, "<C-p>", function() require("config.rest").open() end, { desc = "Open REST Client" })

-- Terminal (Ctrl+t)
local function toggle_term() require("config.terminal").toggle() end
vim.keymap.set({"n", "i", "t"}, "<C-t>", toggle_term, { desc = "Toggle terminal" })

-- Netrw Tree (Ctrl+b)
local function toggle_netrw() require("config.netrw").toggle() end
vim.keymap.set({"n", "i", "v"}, "<C-b>", toggle_netrw, { silent = true, desc = "Toggle file tree" })

-- Git Dashboard (Ctrl+g)
vim.keymap.set({"n", "i", "t"}, "<C-g>", function() require("config.git").toggle() end, { desc = "Toggle Git Dashboard" })
