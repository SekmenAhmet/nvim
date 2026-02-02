-- Native Live Grep (Leader fg)
-- Zero plugins, pure Lua + 'grep'/'rg' command

local M = {}

-- Configuration de la fenêtre flottante (Identique au Finder)
local function create_window()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor(vim.o.lines * 0.1) -- Position higher
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Live Grep ",
    title_pos = "center",
  })

  vim.wo[win].cursorline = true
  vim.wo[win].winhl = "NormalFloat:Normal,CursorLine:Visual"

  vim.bo[buf].filetype = "custom_grep"
  vim.bo[buf].buftype = "nofile"
  
  return buf, win
end

function M.open()
  local buf, win = create_window()
  local padding = "  "
  local timer = vim.loop.new_timer()
  
  -- Table pour stocker les résultats bruts (filename, lnum, text)
  -- Indexé par numéro de ligne dans le buffer (à partir de 3)
  local grep_results = {}

  -- Détecter l'outil disponible
  local cmd_base = nil
  if vim.fn.executable("rg") == 1 then
    cmd_base = "rg --vimgrep --no-heading -g '!*.md' -g '!*.json' -g '!*.lock' -g '!*.log'"
  elseif vim.fn.executable("git") == 1 then
    cmd_base = "git grep -n -- ':(exclude)*.md' ':(exclude)*.json' ':(exclude)*.lock' ':(exclude)*.log'"
  elseif vim.fn.executable("grep") == 1 then
    cmd_base = "grep -rnH --exclude-dir=.git --exclude=*.md --exclude=*.json --exclude=*.lock --exclude=*.log" 
  end

  -- Highlight syntaxique
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      vim.fn.matchadd("Comment", "^  ─.*$")
      vim.fn.matchadd("Function", "^  .*$")
      -- Highlight du nom de fichier dans les résultats (ex: "  src/main.lua:10: code")
      -- Pattern: après le padding, jusqu'au premier ':'
      vim.fn.matchadd("Directory", "^  [^:]\\+") 
      -- Highlight du numéro de ligne
      vim.fn.matchadd("Number", ":\\d\\+:") 
    end,
    once = true
  })

  -- Fonction d'affichage
  local function update_view(query, output_lines)
    local display_lines = {}
    
    -- Ligne 1 : Input
    table.insert(display_lines, padding .. query)
    -- Ligne 2 : Séparateur
    table.insert(display_lines, padding .. string.rep("─", vim.api.nvim_win_get_width(win) - 6))
    
    -- Reset des résultats
    grep_results = {}

    if not cmd_base then
       table.insert(display_lines, padding .. "Error: No grep tool found (install ripgrep or git)")
    elseif query == "" then
      table.insert(display_lines, padding .. "-- Type to search --")
    else
      if #output_lines == 0 then
        table.insert(display_lines, padding .. "-- No results --")
      else
        for i, line in ipairs(output_lines) do
          if i > 200 then break end -- Limite d'affichage
          -- Parsing basique: file:line:text
          -- On stocke le résultat pour pouvoir l'ouvrir plus tard
          -- line format: "path/to/file:123:match text"
          local parts = vim.split(line, ":")
          if #parts >= 3 then
             local filename = parts[1]
             local lnum = parts[2]
             -- Reconstruire le texte (au cas où il y a des : dedans)
             local text = table.concat(parts, ":", 3)
             
             table.insert(grep_results, { filename = filename, lnum = lnum })
             table.insert(display_lines, padding .. line)
          end
        end
      end
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

    -- Remettre le curseur en haut
    if vim.api.nvim_get_mode().mode == 'i' then
        vim.api.nvim_win_set_cursor(win, {1, #padding + #query})
    end
  end

  -- Exécution différée (Debounce)
  local function trigger_grep(query)
    timer:stop()
    timer:start(300, 0, vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      
      if not cmd_base then
        update_view(query, {})
        return
      end

      if query == "" then
        update_view("", {})
        return
      end
      
      -- Nettoyer la query pour le shell (très basique)
      local safe_query = query:gsub('"', '\\"')
      
      -- Exécuter la commande (limité à 200 résultats pour la perf)
      -- On utilise shell pipe head si dispo, sinon on coupe en Lua
      local cmd = cmd_base .. ' "' .. safe_query .. '" .'
      if vim.fn.executable("head") == 1 then
         cmd = cmd .. " | head -n 200"
      end

      local output = vim.fn.systemlist(cmd)
      
      -- Fallback limit if head not available
      if #output > 200 then
         local limited = {}
         for i=1, 200 do limited[i] = output[i] end
         output = limited
      end
      
      update_view(query, output)
    end))
  end

  -- Initialisation
  update_view("", {})
  vim.cmd("startinsert")

  -- Event: Changement de texte
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(win)
      if cursor[1] == 1 then
          local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
          local query = line:sub(#padding + 1)
          trigger_grep(query)
      end
    end
  })

  -- Navigation
  vim.keymap.set("i", "<Down>", function()
    vim.cmd("stopinsert")
    if vim.api.nvim_buf_line_count(buf) >= 3 then
      vim.api.nvim_win_set_cursor(win, {3, 0})
    end
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

  -- Action: Ouvrir
  local function open_result()
    local cursor_row = vim.api.nvim_win_get_cursor(win)[1]
    -- Les résultats commencent à la ligne 3
    -- L'index dans grep_results est : cursor_row - 2
    local result_index = cursor_row - 2
    local result = grep_results[result_index]

    if result then
      vim.api.nvim_win_close(win, true)
      vim.cmd("e " .. result.filename)
      -- Aller à la ligne
      vim.api.nvim_win_set_cursor(0, { tonumber(result.lnum), 0 })
      -- Centrer
      vim.cmd("normal! zz")
    end
  end

  -- Quitter
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("i", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })

  -- Valider
  vim.keymap.set("n", "<CR>", open_result, { buffer = buf })
  vim.keymap.set("i", "<CR>", open_result, { buffer = buf })
end

-- Mapping global
vim.keymap.set("n", "<leader>fg", M.open, { desc = "Live Grep (Native)" })

return M