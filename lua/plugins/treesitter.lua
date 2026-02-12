return {
  {
    "nvim-treesitter/nvim-treesitter",
    version = false, 
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    cmd = { "TSUpdateSync", "TSUpdate", "TSInstall" },
    opts = {
      highlight = { enable = true },
      indent = { enable = true },
      ensure_installed = {
        "lua",
        "vim",
        "vimdoc",
        "query",
        "markdown",
        "markdown_inline",
        "rust",
        "go",
        "typescript",
        "python",
        "c",
        "asm",
        "java",
        "yaml",
        "json",
        "toml",
      },
    },
    config = function(_, opts)
      local ok, configs = pcall(require, "nvim-treesitter.configs")
      if not ok then
        configs = require("nvim-treesitter.config")
      end
      configs.setup(opts)
    end,
  },
}