local M = {}

-- Single augroup for all LSP formatting (optimization) - DEFINED FIRST
local lsp_format_augroup = vim.api.nvim_create_augroup("LspFormatting", { clear = true })

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

  -- Auto-format on save (using global augroup for efficiency)
  if client.server_capabilities.documentFormattingProvider then
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = lsp_format_augroup,
      buffer = bufnr,
      callback = function()
        vim.lsp.buf.format({ bufnr = bufnr, async = false })
      end,
    })
  end
end

-- Configuration globale des diagnostics
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
    scope = "cursor",
  },
})

-- Augroup pour tous les autocmds LSP globaux
local lsp_global_augroup = vim.api.nvim_create_augroup("LspGlobal", { clear = true })

-- Hover diagnostics automatique après updatetime (configuré dans diagnostic.config.float ci-dessus)
vim.api.nvim_create_autocmd("CursorHold", {
  group = lsp_global_augroup,
  callback = function()
    -- Skip if in insert mode
    if vim.api.nvim_get_mode().mode:match("^i") then
      return
    end
    vim.diagnostic.open_float(nil, { scope = "cursor" })
  end,
})

M.capabilities = vim.lsp.protocol.make_client_capabilities()
M.capabilities.textDocument.completion.completionItem.snippetSupport = true

return M
