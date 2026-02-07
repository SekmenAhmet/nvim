return {
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false, -- On force le chargement immédiat pour debug
    config = function()
      -- Tentative de chargement sécurisée
      local ok, configs = pcall(require, "nvim-treesitter.configs")
      
      if not ok then
        -- Si ça échoue, on tente de voir si on peut charger 'nvim-treesitter' tout court
        local ok_main, ts = pcall(require, "nvim-treesitter")
        if ok_main then
          vim.notify("Treesitter chargé partiellement. Lancez :TSUpdate", vim.log.levels.INFO)
          -- On essaie de configurer via setup() du main si possible (rare)
        else
          vim.notify("Erreur critique: Fichiers Treesitter manquants sur le disque.", vim.log.levels.ERROR)
        end
        return
      end

      -- Si on arrive ici, configs existe (miracle ?)
      configs.setup({
        -- On laisse l'utilisateur ou le système gérer l'installation des parseurs
        -- car tree-sitter-cli n'est pas forcément présent.
        ensure_installed = { "lua", "vim", "vimdoc", "query", "markdown", "markdown_inline" }, 
        auto_install = true, 
        sync_install = false,
        highlight = { enable = true },
        indent = { enable = true },
      })
    end
  },
}