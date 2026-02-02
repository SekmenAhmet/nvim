-- Tabline (Bufferline) Native

local M = {}

-- Définition des couleurs personnalisées
-- On essaie de matcher le thème en utilisant des groupes existants
vim.api.nvim_set_hl(0, "TabLine", { link = "Comment" })      -- Onglets inactifs (gris)
vim.api.nvim_set_hl(0, "TabLineSel", { link = "Normal" })    -- Onglet actif (texte normal)
vim.api.nvim_set_hl(0, "TabLineFill", { link = "Normal" })   -- Fond de la barre (vide)

function M.render()
  local line = ""
  local current_buf = vim.api.nvim_get_current_buf()
  local buffers = vim.api.nvim_list_bufs()

  -- Fond de remplissage au début
  line = line .. "%#TabLineFill#"

  for i, buf in ipairs(buffers) do
    if vim.bo[buf].buflisted then
      local is_current = (buf == current_buf)
      local name = vim.api.nvim_buf_get_name(buf)
      local modified = vim.bo[buf].modified and " ●" or ""
      
      -- FILTRAGE : Ignorer les buffers vides (No Name) sauf s'ils sont actifs ou modifiés
      -- ou si c'est un terminal ou autre buftype special
      if name == "" and not is_current and not vim.bo[buf].modified then
         goto continue
      end
      
      -- Nettoyage du nom
      if name == "" then
        name = "[No Name]"
      else
        name = vim.fn.fnamemodify(name, ":t")
      end

      -- Clickable (Natif Neovim)
      -- %nT démarre la zone cliquable pour le buffer n
      line = line .. "%" .. i .. "T"

      if is_current then
        -- Onglet Actif : Style distinct
        line = line .. "%#TabLineSel# " .. name .. modified .. " "
      else
        -- Onglet Inactif
        line = line .. "%#TabLine# " .. name .. modified .. " "
      end
      
      -- Fin de la zone cliquable
      line = line .. "%T"
      
      -- Séparateur discret
      line = line .. "%#TabLineFill#│"
      
      ::continue::
    end
  end

  -- Remplissage du reste de la ligne + bouton de fermeture (X) tout à droite
  line = line .. "%#TabLineFill#%="
  
  -- Si on veut un petit indicateur 'Tabs' à droite
  line = line .. "%#TabLine#%999X   "

  return line
end

-- Activer la tabline
vim.opt.showtabline = 2 -- Toujours afficher
vim.opt.tabline = "%!luaeval('require(\"config.tabline\").render()')"

return M