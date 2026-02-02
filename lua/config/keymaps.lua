-- Navigation entre fenêtres : Ctrl+H (gauche), Ctrl+L (droite)
vim.keymap.set("n", "<C-h>", "<C-w>h", { silent = true, desc = "Go to left window" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { silent = true, desc = "Go to right window" })

-- Resize du tree avec Ctrl+Alt+flèches
vim.keymap.set("n", "<C-M-Left>", "<cmd>vertical resize -2<CR>", { silent = true, desc = "Decrease window width" })
vim.keymap.set("n", "<C-M-Right>", "<cmd>vertical resize +2<CR>", { silent = true, desc = "Increase window width" })

-- Sauvegarde rapide avec Ctrl+S
vim.keymap.set("n", "<C-s>", ":w<CR>", { silent = true, desc = "Save file" })
vim.keymap.set("i", "<C-s>", "<Esc>:w<CR>a", { silent = true, desc = "Save file" })
vim.keymap.set("v", "<C-s>", "<Esc>:w<CR>", { silent = true, desc = "Save file" })

-- Navigation entre les buffers (Onglets)
vim.keymap.set("n", "<Tab>", ":bnext<CR>", { silent = true, desc = "Next Buffer" })
vim.keymap.set("n", "<S-Tab>", ":bprev<CR>", { silent = true, desc = "Previous Buffer" })

-- Fermer le buffer actuel sans fermer la fenêtre
vim.keymap.set("n", "<leader>x", ":bp|bd #<CR>", { silent = true, desc = "Close current buffer" })

-- Supprimer le mot précédent en mode insert (Ctrl+Backspace)
vim.keymap.set("i", "<C-BS>", "<C-W>", { desc = "Delete previous word" })
vim.keymap.set("i", "<C-h>", "<C-W>", { desc = "Delete previous word" })
