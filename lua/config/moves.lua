-- Native Line Moving and Duplication (VSCode style)
-- No external plugins used

-- Move Lines (Shift + Alt + Arrow)
-- Normal Mode
vim.keymap.set("n", "<M-S-Down>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
vim.keymap.set("n", "<M-S-Up>", "<cmd>m .-2<cr>==", { desc = "Move line up" })

-- Insert Mode
vim.keymap.set("i", "<M-S-Down>", "<Esc><cmd>m .+1<cr>==gi", { desc = "Move line down" })
vim.keymap.set("i", "<M-S-Up>", "<Esc><cmd>m .-2<cr>==gi", { desc = "Move line up" })

-- Visual Mode
vim.keymap.set("v", "<M-S-Down>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "<M-S-Up>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })


-- Duplicate Lines (Ctrl + Shift + Alt + Arrow)
-- Normal Mode
vim.keymap.set("n", "<C-M-S-Down>", "<cmd>t .<cr>", { desc = "Duplicate line down" })
vim.keymap.set("n", "<C-M-S-Up>", "<cmd>t -1<cr>", { desc = "Duplicate line up" })

-- Insert Mode
vim.keymap.set("i", "<C-M-S-Down>", "<Esc><cmd>t .<cr>gi", { desc = "Duplicate line down" })
vim.keymap.set("i", "<C-M-S-Up>", "<Esc><cmd>t -1<cr>gi", { desc = "Duplicate line up" })

-- Visual Mode
-- Note: Duplicating a selection in visual mode and keeping the selection is tricky in pure Vim script/Lua without side effects.
-- These commands duplicate the selection below/above and attempt to re-select the *new* block or the original one.
vim.keymap.set("v", "<C-M-S-Down>", ":t '><cr>gv=gv", { desc = "Duplicate selection down" })
vim.keymap.set("v", "<C-M-S-Up>", ":t '<-1<cr>gv=gv", { desc = "Duplicate selection up" })
