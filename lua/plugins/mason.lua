return {
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    build = ":MasonUpdate",
    config = function()
      require("mason").setup()
    end
  },
  {
    "williamboman/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    config = function()
      local lsp = require("config.lsp")
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "pyright",
          "ts_ls",
          "html",
          "cssls",
          "rust_analyzer",
          "gopls",
          "clangd",
          "asm_lsp",
          "jdtls",
          "yamlls",
          "jsonls",
          "taplo",
        },
        handlers = {
          function(server_name)
            -- Special case for jdtls: often handled by nvim-jdtls plugin.
            -- If we want to stay native with lspconfig, we can setup here,
            -- but many prefer skipping it to use a dedicated ftplugin.
            if server_name == "jdtls" then
              -- You might want to skip this if using nvim-jdtls:
              -- return
            end

            local opts = {
              on_attach = lsp.on_attach,
              capabilities = vim.deepcopy(lsp.capabilities),
            }

            -- Merge server-specific settings if they exist
            if lsp.server_settings[server_name] then
              opts = vim.tbl_deep_extend("force", opts, lsp.server_settings[server_name])
            end

            require("lspconfig")[server_name].setup(opts)
          end,
        }
      })
    end
  },
  { "neovim/nvim-lspconfig" }
}
