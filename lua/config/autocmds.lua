-- Autocommandes

-- 1. Trim trailing whitespace on save (Native Lua API)
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  callback = function(args)
    local buf = args.buf
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local modified = false
    
    for i, line in ipairs(lines) do
      local trimmed = line:gsub("%s+$", "")
      if trimmed ~= line then
        lines[i] = trimmed
        modified = true
      end
    end
    
    if modified then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end
  end,
  desc = "Remove trailing whitespace on save",
})

-- 2. Highlight on Yank (Flasher le texte copié)
local highlight_yank_group = vim.api.nvim_create_augroup("HighlightYank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = highlight_yank_group,
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

-- 4. Terminal mode improvements
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
    vim.cmd("startinsert")
  end,
  desc = "Terminal UI settings",
})
  