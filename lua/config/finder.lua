-- Native Fuzzy Finder (Leader ff)
-- Zero plugins, pure Lua + 'find' command

local M = {}

-- Configuration de la fenêtre flottante
local function create_window()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Création du buffer "scratch" (non enregistré)
  local buf = vim.api.nvim_create_buf(false, true)

  -- Création de la fenêtre
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Find File ",
    title_pos = "center",
  })

  -- Options locales à la fenêtre (Style)
  vim.wo[win].cursorline = true
  vim.wo[win].winhl = "NormalFloat:Normal,CursorLine:Visual"

  -- Options locales au buffer
  vim.bo[buf].filetype = "custom_finder"
  vim.bo[buf].buftype = "nofile"
  
  return buf, win
end

-- Fonction principale
function M.open()
  -- 1. Récupérer tous les fichiers (ignore les fichiers cachés et .git)
  local files = vim.fn.systemlist("find . -type f -not -path '*/.*' | sed 's|^\\./||'")
  
  if #files > 10000 then
    table.insert(files, 1, "-- Too many files, showing top 10000 --")
  end

  local buf, win = create_window()
  local padding = "  " -- Padding à gauche

  -- Highlight syntaxique manuel
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      vim.fn.matchadd("Comment", "^  ─.*$")
      vim.fn.matchadd("Function", "^  .*$")
    end,
    once = true
  })

  -- Fonction pour rafraîchir l'affichage
  local function redraw(query)
    local results = {}
    -- Ligne 1 : Le pattern de recherche avec padding
    table.insert(results, padding .. query)
    
    -- Ligne 2 : Séparateur visuel avec padding
    table.insert(results, padding .. string.rep("─", vim.api.nvim_win_get_width(win) - 6))

    -- Filtrage basique
    local match_count = 0
    for _, file in ipairs(files) do
      if match_count > 500 then break end
      if query == "" or file:lower():find(query:lower(), 1, true) then
        table.insert(results, padding .. file)
        match_count = match_count + 1
      end
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, results)
    
    -- Placer le curseur après le padding et le texte en insert mode
    if vim.api.nvim_get_mode().mode == 'i' then
        vim.api.nvim_win_set_cursor(win, {1, #padding + #query})
    end
  end

  -- Initialisation
  redraw("")
  vim.cmd("startinsert")

  -- EVENT : Quand on tape du texte
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(win)
      if cursor[1] == 1 then
          local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
          local query = line:sub(#padding + 1)
          redraw(query)
      end
    end
  })

  -- NAVIGATION INTELLIGENTE
  vim.keymap.set("i", "<Down>", function()
    vim.cmd("stopinsert")
    vim.api.nvim_win_set_cursor(win, {3, 0})
  end, { buffer = buf })

  vim.keymap.set("n", "<Up>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    if cursor[1] <= 3 then
      vim.api.nvim_win_set_cursor(win, {1, 0})
      vim.cmd("startinsert")
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      vim.api.nvim_win_set_cursor(win, {1, #line})
    else
      vim.cmd("normal! k")
    end
  end, { buffer = buf })

  -- ACTION : Ouvrir le fichier
  local function open_file()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    if cursor_line <= 2 then return end

    local line_content = vim.api.nvim_get_current_line()
    local clean_path = line_content:sub(#padding + 1)
    
    vim.api.nvim_win_close(win, true)
    
    if clean_path and clean_path ~= "" then
      vim.cmd("e " .. clean_path)
    end
  end

  -- Quitter proprement avec Echap dans les deux modes
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("i", "<Esc>", "<cmd>close<CR>", { buffer = buf })

  -- Sélectionner
  vim.keymap.set("n", "<CR>", open_file, { buffer = buf })
  vim.keymap.set("i", "<CR>", open_file, { buffer = buf })
end

-- Mapping global
vim.keymap.set("n", "<leader>ff", M.open, { desc = "Find Files (Native)" })

return M
