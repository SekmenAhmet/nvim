-- Autopairs natif

-- Liste des paires
local map_pairs = {
  ['('] = ')',
  ['['] = ']',
  ['{'] = '}',
  ['"'] = '"',
  ["'"] = "'",
  ['`'] = '`',
}

-- INSERT MODE : Fermeture automatique intelligente
for open, close in pairs(map_pairs) do
  vim.keymap.set("i", open, function()
    -- Récupérer la ligne et la position du curseur
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2] -- col est 0-indexé

    -- Récupérer le caractère juste après le curseur
    local next_char = line:sub(col + 1, col + 1)

    -- Si le caractère suivant est une lettre, un chiffre ou un underscore, on n'auto-ferme pas.
    if next_char:match("[%w_]") then
      return open
    end

    -- Sinon, on insère la paire et on revient au milieu
    return open .. close .. "<Left>"
  end, { expr = true, noremap = true, desc = "Auto close " .. open })
end

-- BACKSPACE : Supprimer la paire si on est au milieu
vim.keymap.set("i", "<BS>", function()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] -- 0-indexed column

  -- On regarde le caractère avant (col) et après (col + 1)
  local char_before = line:sub(col, col)
  local char_after = line:sub(col + 1, col + 1)

  -- Si on est entre deux symboles qui forment une paire, on supprime les deux
  if map_pairs[char_before] == char_after then
    return "<BS><Del>"
  end

  return "<BS>"
end, { expr = true, noremap = true, desc = "Smart backspace for autopairs" })

-- VISUAL MODE : Entourer la sélection
for open, close in pairs(map_pairs) do
  vim.keymap.set("v", open, function()
    -- 'c' coupe la sélection, on insère les symboles et on colle le contenu
    return "c" .. open .. "<C-r>\"" .. close .. "<Esc>"
  end, { expr = true, noremap = true, desc = "Surround selection with " .. open })
end