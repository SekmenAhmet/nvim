-- Autocommandes
-- Central augroup for all config autocommands
local config_augroup = vim.api.nvim_create_augroup("ConfigAutocmds", { clear = true })

-- 1. Trim trailing whitespace on save (Optimized native API)
vim.api.nvim_create_autocmd("BufWritePre", {
  group = config_augroup,
  pattern = "*",
  callback = function(args)
    -- Use native vim command for ~10x better performance than Lua loop
    vim.api.nvim_buf_call(args.buf, function()
      vim.cmd([[keeppatterns %s/\s\+$//e]])
    end)
  end,
  desc = "Remove trailing whitespace on save",
})

-- 2. Highlight on Yank (Flasher le texte copié)
vim.api.nvim_create_autocmd("TextYankPost", {
  group = config_augroup,
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
  group = config_augroup,
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
  group = config_augroup,
  pattern = "*",
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
    vim.cmd("startinsert")
  end,
  desc = "Terminal UI settings",
})
  