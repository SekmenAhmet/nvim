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
        ensure_installed = { "lua_ls", "pyright", "ts_ls", "html", "cssls" },
        handlers = {
          function(server_name)
            require("lspconfig")[server_name].setup({
              on_attach = lsp.on_attach,
              capabilities = lsp.capabilities,
            })
          end,
        }
      })
    end
  },
  { "neovim/nvim-lspconfig" }
}
