local M = {}

function M.on_attach(client, bufnr)
  -- Keymaps
  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
  
  -- Native Completion
  if client.server_capabilities.completionProvider then
    vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
  end
  
  -- LSP Signs configuration
  vim.diagnostic.config({
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = "E",
        [vim.diagnostic.severity.WARN] = "W",
        [vim.diagnostic.severity.INFO] = "I",
        [vim.diagnostic.severity.HINT] = "H",
      },
      linehl = {
        [vim.diagnostic.severity.ERROR] = "DiagnosticLineError",
      },
      numhl = {
        [vim.diagnostic.severity.ERROR] = "DiagnosticError",
        [vim.diagnostic.severity.WARN] = "DiagnosticWarn",
        [vim.diagnostic.severity.INFO] = "DiagnosticInfo",
        [vim.diagnostic.severity.HINT] = "DiagnosticHint",
      },
    },
    underline = true,        -- Souligner les erreurs
    virtual_text = false,    -- Pas de texte à droite (propre)
    severity_sort = true,    -- Erreurs d'abord
    float = {
      focusable = false,
      border = "rounded",
      source = "if_many",
      prefix = "",
      scope = "cursor",
    },
  }, bufnr)
end

-- Configuration globale des diagnostics
vim.diagnostic.config({
  signs = true,
  underline = true,
  virtual_text = false,
  severity_sort = true,
  float = {
    focusable = false,
    style = "minimal",
    border = "rounded",
    source = "if_many",
    header = "",
    prefix = "",
  },
})

-- Hover diagnostics automatique après 500ms
vim.opt.updatetime = 500

vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    -- Ne pas afficher si on est en mode insert
    if vim.api.nvim_get_mode().mode:match("^i") then
      return
    end
    
    -- Vérifier s'il y a des diagnostics à la position actuelle
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line = cursor_pos[1] - 1
    local col = cursor_pos[2]
    
    local diagnostics = vim.diagnostic.get(0, { lnum = line })
    if #diagnostics > 0 then
      -- Vérifier si le curseur est sur un diagnostic
      for _, d in ipairs(diagnostics) do
        if col >= d.col and col <= d.end_col then
          vim.diagnostic.open_float(nil, {
            focusable = false,
            close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
            border = "rounded",
            source = "if_many",
            prefix = "",
            scope = "cursor",
          })
          break
        end
      end
    end
  end,
})

-- Rafraîchir la tabline quand les diagnostics changent
vim.api.nvim_create_autocmd("DiagnosticChanged", {
  callback = function()
    vim.cmd("redrawtabline")
  end,
})

M.capabilities = vim.lsp.protocol.make_client_capabilities()
M.capabilities.textDocument.completion.completionItem.snippetSupport = true

return M
