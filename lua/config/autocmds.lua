-- Autocommandes

-- 1. Trim trailing whitespace on save
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  callback = function()
    local view = vim.fn.winsaveview()
    vim.cmd([[%s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
  desc = "Remove trailing whitespace on save",
})

-- 2. Highlight on Yank (Flasher le texte copié)
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("HighlightYank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({
      higroup = "IncSearch", -- Couleur du flash (souvent inversé)
      timeout = 200,         -- Durée en ms
    })
  end,
  desc = "Highlight copied text",
})

-- 3. Restore Cursor Position (Revenir à la dernière ligne connue)
vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = "*",
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local line_count = vim.api.nvim_buf_line_count(0)
    -- Si la marque est valide (entre ligne 1 et fin du fichier)
    if mark[1] > 0 and mark[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
  desc = "Restore cursor position on file open",
})
  