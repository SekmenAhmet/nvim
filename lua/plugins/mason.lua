return {
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    build = ":MasonUpdate",
    opts = {
      ui = {
        icons = {
          package_installed = "✓",
          package_pending = "➜",
          package_uninstalled = "✗",
        },
      },
    },
  },
  {
    "williamboman/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    config = function()
      local lsp_config = require("config.lsp")
      require("mason-lspconfig").setup({
        handlers = {
          -- Explicitly disable asm_lsp
          ["asm_lsp"] = function() end,
          
          -- The default handler for all servers
          function(server_name)
            require("lspconfig")[server_name].setup({
              on_attach = lsp_config.on_attach,
              capabilities = lsp_config.capabilities,
              flags = {
                debounce_text_changes = 150,
              }
            })
          end,
        },
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    lazy = true, -- Now loaded by mason-lspconfig
  },
}