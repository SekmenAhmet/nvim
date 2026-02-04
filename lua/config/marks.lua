-- Smart Marks - Gestion avancée des marques
-- Interface flottante pour voir et naviguer vers les marques

local M = {}
local api = vim.api
local window = require('config.window')

-- State
local state = {
  buf = nil,
  win = nil,
}

-- Marques locales à gérer (a-z)
local local_marks = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j' }

-- Récupérer toutes les marques locales
local function get_marks()
  local marks = {}
  local current_buf = api.nvim_get_current_buf()
  
  for _, mark in ipairs(local_marks) do
    -- Pour les marques locales (a-z), utiliser getpos
    local pos = vim.fn.getpos("'" .. mark)
    if pos[1] ~= 0 and pos[1] == current_buf then  -- Marque existe dans le buffer courant
      local line = pos[2]
      local col = pos[3]
      local bufname = vim.fn.bufname(current_buf)
      local display_name = bufname ~= "" and vim.fn.fnamemodify(bufname, ":t") or "[No Name]"
      
      -- Récupérer le contenu de la ligne
      local content = ""
      if vim.api.nvim_buf_is_valid(current_buf) then
        local lines = api.nvim_buf_get_lines(current_buf, line - 1, line, false)
        if lines[1] then
          content = lines[1]:sub(1, 50)
        end
      end
      
      table.insert(marks, {
        mark = mark,
        line = line,
        col = col,
        bufname = bufname,
        display_name = display_name,
        content = content,
      })
    end
  end
  
  return marks
end

-- Afficher la liste des marques
function M.show_marks()
  local marks = get_marks()
  
  if #marks == 0 then
    vim.notify("Aucune marque définie (utilise ma, mb, mc...)", vim.log.levels.INFO)
    return
  end
  
  -- Créer fenêtre centrée
  local win = window.create_centered({
    width_pct = 0.4,
    height = math.min(#marks + 4, 15),
    title = "Marks",
    row_offset = 5,
  })
  
  state.buf = win.buf
  state.win = win.win
  
  -- Construire les lignes
  local lines = {}
  for _, mark in ipairs(marks) do
    local line = string.format(" '%s  %s:%-4d %s", 
      mark.mark, mark.display_name, mark.line, mark.content)
    table.insert(lines, line)
  end
  
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  
  -- Highlights
  api.nvim_buf_clear_namespace(state.buf, -1, 0, -1)
  for i = 1, #marks do
    -- Colorer le 'a, 'b, etc en jaune
    api.nvim_buf_add_highlight(state.buf, -1, "MarkSign", i - 1, 0, 3)
  end
  
  -- Keymaps
  local opts = { buffer = state.buf }
  
  -- Enter: jumper à la marque
  vim.keymap.set("n", "<CR>", function()
    local cursor = api.nvim_win_get_cursor(state.win)
    local idx = cursor[1]
    local mark = marks[idx]
    if mark then
      api.nvim_win_close(state.win, true)
      -- Jumper à la marque
      if mark.bufname ~= "" then
        vim.cmd("edit " .. mark.bufname)
      end
      vim.cmd("normal! '" .. mark.mark)
      vim.cmd("normal! zz")
    end
  end, opts)
  
  -- d: supprimer la marque
  vim.keymap.set("n", "d", function()
    local cursor = api.nvim_win_get_cursor(state.win)
    local idx = cursor[1]
    local mark = marks[idx]
    if mark then
      vim.cmd("delmarks " .. mark.mark)
      -- Rafraichir
      api.nvim_win_close(state.win, true)
      vim.schedule(function()
        M.show_marks()
      end)
    end
  end, opts)
  
  -- Esc: fermer
  vim.keymap.set("n", "<Esc>", function()
    api.nvim_win_close(state.win, true)
  end, opts)
  
  vim.cmd("normal! gg")
end

-- Toggle marque rapide
function M.toggle_mark()
  local line = api.nvim_win_get_cursor(0)[1]
  local bufnr = api.nvim_get_current_buf()
  
  -- Vérifier si une marque existe déjà sur cette ligne
  for _, mark_char in ipairs(local_marks) do
    local pos = vim.fn.getpos("'" .. mark_char)
    -- pos[1] = buffer, pos[2] = ligne, pos[3] = colonne
    if pos[1] == bufnr and pos[2] == line then
      -- Marque existe sur cette ligne, la supprimer
      vim.cmd("delmarks " .. mark_char)
      vim.notify("Marque '" .. mark_char .. "' supprimée", vim.log.levels.INFO)
      return
    end
  end
  
  -- Trouver la première marque libre
  for _, mark_char in ipairs(local_marks) do
    local pos = vim.api.nvim_get_mark(mark_char, {})
    if pos[1] == 0 then  -- Marque libre
      vim.cmd("mark " .. mark_char)
      vim.notify("Marque '" .. mark_char .. " ajoutée", vim.log.levels.INFO)
      return
    end
  end
  
  vim.notify("Plus de marques disponibles", vim.log.levels.WARN)
end

-- Setup highlight
vim.api.nvim_set_hl(0, "MarkSign", { fg = "#e0af68", bold = true })

-- Keymaps
vim.keymap.set("n", "<leader>'", M.show_marks, { desc = "Show marks" })
vim.keymap.set("n", "<leader>m", M.toggle_mark, { desc = "Toggle mark" })

return M
