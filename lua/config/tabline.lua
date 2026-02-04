-- Tabline (Bufferline) Native

local M = {}

-- Les couleurs sont définies dans config.colors

function M.render()
  local line = ""
  
  -- 1. Dynamic Sidebar Padding
  local sidebar_width = 0
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "netrw" then
       sidebar_width = vim.api.nvim_win_get_width(win)
       break
    end
  end

  if sidebar_width > 0 then
    line = line .. "%#TabLineFill#" .. string.rep(" ", sidebar_width)
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local buffers = vim.api.nvim_list_bufs()

  -- Check for single empty buffer to hide tabline
  local listed_count = 0
  local single_buf = nil
  for _, buf in ipairs(buffers) do
    if vim.bo[buf].buflisted then
      listed_count = listed_count + 1
      single_buf = buf
    end
  end
  if listed_count == 1 and single_buf then
    local name = vim.api.nvim_buf_get_name(single_buf)
    if name == "" and not vim.bo[single_buf].modified then
      return ""
    end
  end

  -- Fond de remplissage au début
  line = line .. "%#TabLineFill#"

  for i, buf in ipairs(buffers) do
    if vim.bo[buf].buflisted then
      local is_current = (buf == current_buf)
      local name = vim.api.nvim_buf_get_name(buf)
      local modified = vim.bo[buf].modified and " ●" or ""
      
      -- FILTRAGE : Ignorer les buffers vides (No Name) sauf s'ils sont actifs ou modifiés
      if name == "" and not is_current and not vim.bo[buf].modified then
         goto continue
      end
      
      -- Nettoyage du nom
      if name == "" then
        name = "Untitled"
      else
        name = vim.fn.fnamemodify(name, ":t")
      end

      -- Clickable (Natif Neovim)
      line = line .. "%" .. i .. "T"

      if is_current then
        -- Onglet Actif
        line = line .. "%#TabLineSel# " .. name .. modified .. " "
      else
        -- Onglet Inactif
        line = line .. "%#TabLine# " .. name .. modified .. " "
      end
      
      -- Fin de la zone cliquable
      line = line .. "%T"
      
      -- Séparateur
      line = line .. "%#TabLineFill#│"
      
      ::continue::
    end
  end

  -- Remplissage du reste de la ligne
  line = line .. "%#TabLineFill#%="
  
  -- Indicateur à droite
  line = line .. "%#TabLine#%999X   "

  return line
end

-- Activer la tabline
vim.opt.showtabline = 2 -- Toujours afficher
vim.opt.tabline = "%!luaeval('require(\"config.tabline\").render()')"

return M