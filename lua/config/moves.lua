-- Native Line Moving and Duplication (VSCode style)
-- No external plugins used

local moves = {
  -- Move Lines (Shift + Alt + Arrow)
  { "n", "<M-S-Down>",     "<cmd>m .+1<cr>==",       "Move line down" },
  { "n", "<M-S-Up>",       "<cmd>m .-2<cr>==",       "Move line up" },
  { "i", "<M-S-Down>",     "<Esc><cmd>m .+1<cr>==gi", "Move line down" },
  { "i", "<M-S-Up>",       "<Esc><cmd>m .-2<cr>==gi", "Move line up" },
  { "v", "<M-S-Down>",     ":m '>+1<cr>gv=gv",       "Move selection down" },
  { "v", "<M-S-Up>",       ":m '<-2<cr>gv=gv",       "Move selection up" },
  -- Duplicate Lines (Ctrl + Shift + Alt + Arrow)
  { "n", "<C-M-S-Down>",   "<cmd>t .<cr>",           "Duplicate line down" },
  { "n", "<C-M-S-Up>",     "<cmd>t -1<cr>",          "Duplicate line up" },
  { "i", "<C-M-S-Down>",   "<Esc><cmd>t .<cr>gi",    "Duplicate line down" },
  { "i", "<C-M-S-Up>",     "<Esc><cmd>t -1<cr>gi",   "Duplicate line up" },
  { "v", "<C-M-S-Down>",   ":t '><cr>gv=gv",         "Duplicate selection down" },
  { "v", "<C-M-S-Up>",     ":t '<-1<cr>gv=gv",       "Duplicate selection up" },
}

for _, m in ipairs(moves) do
  vim.keymap.set(m[1], m[2], m[3], { desc = m[4] })
end
