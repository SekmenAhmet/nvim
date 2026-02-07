-- Tabline (Bufferline) Native

local M = {}

-- Les couleurs sont définies dans config.colors

-- Obtenir le niveau de diagnostic d'un buffer
local function get_buffer_diagnostic_level(bufnr)
  local diagnostics = vim.diagnostic.get(bufnr)
  local has_error = false
  local has_warn = false
  
  for _, d in ipairs(diagnostics) do
    if d.severity == vim.diagnostic.severity.ERROR then
      has_error = true
      break
    elseif d.severity == vim.diagnostic.severity.WARN then
      has_warn = true
    end
  end
  
  if has_error then return "error" end
  if has_warn then return "warn" end
  return nil
end

function M.render()
  local line = ""
  
  -- 1. Dynamic Sidebar Padding
  local sidebar_width = 0
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    if ft == "netrw" or ft == "tree" then
       -- Vérifier que c'est bien la sidebar à gauche (col 0)
       if vim.api.nvim_win_get_position(win)[2] == 0 then
         sidebar_width = vim.api.nvim_win_get_width(win) + 1
         break
       end
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

      -- Vérifier les diagnostics
      local diag_level = get_buffer_diagnostic_level(buf)
      
      -- Clickable (Natif Neovim) - utilise le vrai buffer ID
      line = line .. "%" .. buf .. "T"

      -- Choisir le highlight selon l'état et les diagnostics
      local hl_group
      if is_current then
        if diag_level == "error" then
          hl_group = "TabLineSelError"
        elseif diag_level == "warn" then
          hl_group = "TabLineSelWarn"
        else
          hl_group = "TabLineSel"
        end
      else
        if diag_level == "error" then
          hl_group = "TabLineError"
        elseif diag_level == "warn" then
          hl_group = "TabLineWarn"
        else
          hl_group = "TabLine"
        end
      end

      line = line .. "%#" .. hl_group .. "# " .. name .. modified .. " "
      
      -- Fin de la zone cliquable
      line = line .. "%T"
      
      -- Séparateur
      line = line .. "%#TabLineFill#│"
      
      ::continue::
    end
  end

  -- Remplissage du reste de la ligne
  line = line .. "%#TabLineFill#%="
  
  -- Indicateur à droite - compteur de buffers
  local buf_count = 0
  for _, buf in ipairs(buffers) do
    if vim.bo[buf].buflisted then
      buf_count = buf_count + 1
    end
  end
  line = line .. "%#TabLine#%999X  " .. buf_count .. " "

  return line
end

-- Activer la tabline
vim.opt.showtabline = 2 -- Toujours afficher
vim.opt.tabline = "%!luaeval('require(\"config.tabline\").render()')"

-- Rafraîchir la tabline quand on ferme ou change de buffer
vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufEnter" }, {
  callback = function()
    vim.cmd("redrawtabline")
  end,
})

return M