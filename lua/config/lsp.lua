local M = {}

-- Single augroup for all LSP formatting (optimization) - DEFINED FIRST
local lsp_format_augroup = vim.api.nvim_create_augroup("LspFormatting", { clear = true })
local ui_icons = require("utils.icons").ui

function M.on_attach(client, bufnr)
  -- Keymaps
  local opts = { buffer = bufnr, silent = true }
  
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
  vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
  
  -- Use custom picker for code actions
  vim.keymap.set("n", "<leader>ca", function()
    require("modules.lsp.actions").open()
  end, opts)
  
  -- Document Symbols Picker
  vim.keymap.set("n", "<leader>ss", function()
    require("modules.lsp.symbols").open()
  end, opts)

  -- Native Completion
  if client.server_capabilities.completionProvider then
    vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
  end

  -- Auto-format on save (using global augroup for efficiency)
  if client.server_capabilities.documentFormattingProvider then
    vim.api.nvim_clear_autocmds({ group = lsp_format_augroup, buffer = bufnr })
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
      [vim.diagnostic.severity.ERROR] = ui_icons.error,
      [vim.diagnostic.severity.WARN] = ui_icons.warn,
      [vim.diagnostic.severity.INFO] = ui_icons.info,
      [vim.diagnostic.severity.HINT] = ui_icons.hint,
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
M.capabilities.textDocument.completion.completionItem.preselectSupport = true
M.capabilities.textDocument.completion.completionItem.insertReplaceSupport = true
M.capabilities.textDocument.completion.completionItem.labelDetailsSupport = true
M.capabilities.textDocument.completion.completionItem.deprecatedSupport = true
M.capabilities.textDocument.completion.completionItem.commitCharactersSupport = true
M.capabilities.textDocument.completion.completionItem.tagSupport = { valueSet = { 1 } }
M.capabilities.textDocument.completion.completionItem.resolveSupport = {
  properties = { "documentation", "detail", "additionalTextEdits" },
}

-- Configuration par serveur
M.server_settings = {
  lua_ls = {
    settings = {
      Lua = {
        runtime = {
          version = "LuaJIT",
          path = vim.split(package.path, ";"),
        },
        diagnostics = {
          globals = { "vim", "require" },
          disable = { "lowercase-global" },
        },
        workspace = {
          checkThirdParty = false,
          library = {
            vim.env.VIMRUNTIME,
            vim.fn.stdpath("config") .. "/lua",
          },
          maxPreload = 10000,
          preloadFileSize = 10000,
        },
        telemetry = { enable = false },
        hint = { enable = true }, -- Enable inlay hints
      },
    },
  },
  rust_analyzer = {
    settings = {
      ["rust-analyzer"] = {
        checkOnSave = {
          command = "clippy",
        },
        procMacro = {
          enable = true,
        },
        cargo = {
          loadOutDirsFromCheck = true,
        },
      },
    },
  },
  gopls = {
    settings = {
      gopls = {
        analyses = {
          unusedparams = true,
          shadow = true,
        },
        staticcheck = true,
        completeUnimported = true,
        usePlaceholders = true,
        directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
      },
    },
  },
  clangd = {
    capabilities = {
      offsetEncoding = { "utf-16" },
    },
    cmd = {
      "clangd",
      "--background-index",
      "--clang-tidy",
      "--header-insertion=iwyu",
      "--completion-style=detailed",
      "--function-arg-placeholders",
      "--fallback-style=llvm",
    },
  },
  yamlls = {
    settings = {
      yaml = {
        schemaStore = {
          enable = true,
          url = "https://www.schemastore.org/api/json/catalog.json",
        },
        schemas = {
          ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
          ["https://json.schemastore.org/github-action.json"] = "/.github/actions/*",
        },
      },
    },
  },
  jsonls = {
    settings = {
      json = {
        validate = { enable = true },
      },
    },
  },
  -- jdtls: Pour une expérience complète, nvim-jdtls est recommandé.
  -- En natif, lspconfig utilise les root_markers standards (pom.xml, gradlew, .git).
  jdtls = {},
  asm_lsp = {},
  taplo = {},
}

return M
