-- Enhanced Quick Fix List
-- Interface flottante moderne pour la quickfix list

local M = {}
local api = vim.api
local window = require('config.window')

-- State
local state = {
  buf = nil,
  win = nil,
  items = {},
  current_idx = 1,
}

-- Récupérer et formater les items de la quickfix
local function get_qf_items()
  local qflist = vim.fn.getqflist({ items = 1, title = 1 })
  local items = {}
  
  for i, item in ipairs(qflist.items) do
    if item.valid == 1 then
      local filename = item.bufnr > 0 and vim.fn.bufname(item.bufnr) or ""
      local display_name = filename ~= "" and vim.fn.fnamemodify(filename, ":t") or "[No Name]"
      local text = item.text:gsub("^%s*", ""):sub(1, 50)
      
      table.insert(items, {
        idx = i,
        filename = filename,
        display_name = display_name,
        lnum = item.lnum,
        col = item.col,
        text = text,
        type = item.type or "",
      })
    end
  end
  
  return items, qflist.title
end

-- Obtenir l icône selon le type
local function get_type_icon(qf_type)
  local icons = {
    E = "E",
    W = "W",
    I = "I",
    H = "H",
  }
  return icons[qf_type] or " "
end

-- Afficher la quickfix list
function M.show()
  local items, title = get_qf_items()
  
  if #items == 0 then
    vim.notify("Quickfix list vide", vim.log.levels.INFO)
    return
  end
  
  state.items = items
  state.current_idx = 1
  
  -- Créer la fenêtre (style finder)
  local wins = window.create_dual_pane({
    width_pct = 0.7,
    height_pct = 0.8,
    preview_width_pct = 0.6,
    list_title = title ~= "" and title or "Quickfix",
    preview_title = "Preview",
    list_filetype = "qf_list",
  })
  
  state.buf = wins.buf_list
  state.win = wins.win_list
  
  -- Remplir la liste
  local lines = {}
  
  for i, item in ipairs(items) do
    local icon = get_type_icon(item.type)
    local line = string.format(" %s %s:%d %s", 
      icon, item.display_name, item.lnum, item.text)
    table.insert(lines, line)
  end
  
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  
  -- Keymaps
  local opts = { buffer = state.buf }
  
  -- Enter: ouvrir et fermer
  vim.keymap.set("n", "<CR>", function()
    local cursor = api.nvim_win_get_cursor(state.win)
    local idx = cursor[1]
    local item = state.items[idx]
    if item then
      -- Fermer puis ouvrir
      api.nvim_win_close(state.win, true)
      require("config.ui").open_in_normal_win(item.filename, item.lnum)
    end
  end, opts)
  
  -- o: ouvrir sans fermer
  vim.keymap.set("n", "o", function()
    local cursor = api.nvim_win_get_cursor(state.win)
    local idx = cursor[1]
    local item = state.items[idx]
    if item then
      require("config.ui").open_in_normal_win(item.filename, item.lnum)
    end
  end, opts)
  
  -- Esc: fermer
  vim.keymap.set("n", "<Esc>", function()
    api.nvim_win_close(state.win, true)
  end, opts)
  
  -- d: supprimer de la liste
  vim.keymap.set("n", "d", function()
    local cursor = api.nvim_win_get_cursor(state.win)
    local idx = cursor[1]
    -- Supprimer de la qf list
    vim.fn.setqflist({}, 'r', { idx = idx, items = {} })
    -- Rafraichir
    M.show()
  end, opts)
  
  vim.cmd("normal! gg")
end

-- Keymap pour ouvrir
vim.keymap.set('n', '<leader>q', M.show, { desc = 'Quickfix list' })

return M
