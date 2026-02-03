local M = {}

-- Apparence du menu
vim.opt.completeopt = "menu,menuone,noinsert,noselect"
vim.opt.pumblend = 10
vim.opt.pumheight = 10

-- Couleurs (Native, utilise le colorscheme actuel)
-- Pas besoin de redéfinir si le thème est bon, mais on assure la lisibilité
vim.api.nvim_set_hl(0, "Pmenu", { link = "NormalFloat" })
vim.api.nvim_set_hl(0, "PmenuSel", { link = "Visual" })

-- Auto-Trigger Logic (The "Native Autocomplete" trick)
-- Lance la complétion automatiquement après 2 caractères
local function check_trigger()
  -- Désactiver pour les buffers spéciaux (Finder, Grep, etc.)
  if vim.bo.buftype == "nofile" or vim.bo.buftype == "prompt" then return end
  local ft = vim.bo.filetype
  if ft == "fzf_list" or ft == "grep_list" or ft == "TelescopePrompt" then return end

  local col = vim.fn.col('.') - 1
  if col < 2 then return end
  
  local line = vim.api.nvim_get_current_line()
  local char_before = line:sub(col, col)
  
  -- Ne pas déclencher si on vient de taper un espace ou un symbole
  if char_before:match("%W") then return end
  
  -- Si le menu n'est pas visible, on lance <C-n>
  if vim.fn.pumvisible() == 0 then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-n>", true, false, true), "n", false)
  end
end

-- Debounce timer pour ne pas spammer <C-n> à chaque frappe
local timer = nil
vim.api.nvim_create_autocmd("TextChangedI", {
  callback = function()
    if timer then timer:stop() end
    timer = vim.loop.new_timer()
    timer:start(100, 0, vim.schedule_wrap(check_trigger))
  end
})

-- Mappings de navigation confortables
local function map(lhs, rhs)
  vim.keymap.set("i", lhs, rhs, { expr = true, silent = true })
end

-- <Tab> pour descendre ou valider
map("<Tab>", 'pumvisible() ? "<C-n>" : "<Tab>"')
map("<S-Tab>", 'pumvisible() ? "<C-p>" : "<S-Tab>"')
map("<CR>", 'pumvisible() ? "<C-y>" : "<CR>"')

-- Setup Lsp Attach
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client.server_capabilities.completionProvider then
      vim.bo[event.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
    end
  end,
})

return M