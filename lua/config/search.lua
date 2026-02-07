-- Native Floating Search (Replace /)
-- Architecture: Floating Window + Realtime Search with Counter

local M = {}
local api = vim.api
local window = require("utils")

-- State
local state = {
  buf = nil,
  win = nil,
  target_win = nil,
  target_buf = nil,
  ns_id = api.nvim_create_namespace("live_search"),
  count_ns = api.nvim_create_namespace("search_count"),
  cursor_ns = api.nvim_create_namespace("search_cursor"),
  original_view = nil,
  match_ids = {},
  query = "",
  autocmds = {},
  count_extmark_id = nil,  -- Pour tracker l'extmark du compteur
}

-- Nettoyer tous les highlights
local function clear_highlights()
  -- Supprimer les matchadd
  if state.target_win and api.nvim_win_is_valid(state.target_win) then
    api.nvim_win_call(state.target_win, function()
      vim.fn.clearmatches()
    end)
  end
  state.match_ids = {}
  
  -- Nettoyer le counter dans la fenêtre de search
  if state.buf and api.nvim_buf_is_valid(state.buf) then
    api.nvim_buf_clear_namespace(state.buf, state.count_ns, 0, -1)
  end
  state.count_extmark_id = nil
end

-- Mettre à jour le compteur d'occurrences
local function update_counter()
  if not state.buf or not api.nvim_buf_is_valid(state.buf) then return end
  if not state.target_win or not api.nvim_win_is_valid(state.target_win) then return end
  
  -- Supprimer l'ancien extmark du compteur
  if state.count_extmark_id then
    pcall(api.nvim_buf_del_extmark, state.buf, state.count_ns, state.count_extmark_id)
    state.count_extmark_id = nil
  end
  
  if state.query == "" then
    return
  end
  
  api.nvim_win_call(state.target_win, function()
    local count = vim.fn.searchcount({
      pattern = state.query,
      maxcount = 999,
      timeout = 100,
    })
    
    if count.total > 0 then
      local count_str = string.format("[%d/%d]", count.current, count.total)
      -- Calculer la position : largeur - texte - 2 colonnes de marge
      local win_width = api.nvim_win_get_width(state.win)
      local col_pos = math.max(0, win_width - #count_str - 2)
      -- Utiliser overlay pour position précise
      local ok, id = pcall(api.nvim_buf_set_extmark, state.buf, state.count_ns, 0, 0, {
        virt_text = {{count_str, "Comment"}},
        virt_text_pos = "overlay",
        virt_text_win_col = col_pos,
        hl_mode = "combine",
      })
      if ok then
        state.count_extmark_id = id
      end
    end
  end)
end

-- Déplacer le curseur vers une occurrence
local function move_to_match(direction)
  if not state.target_win or not api.nvim_win_is_valid(state.target_win) then return end
  if state.query == "" then return end
  
  api.nvim_win_call(state.target_win, function()
    local flags = direction > 0 and "" or "b"  -- b = backward
    
    -- Rechercher avec wrap
    local found = vim.fn.search(state.query, flags .. "w")
    if found > 0 then
      vim.cmd("normal! zz")  -- Centrer la vue
    end
  end)
  
  -- Mettre à jour le compteur après le déplacement
  update_counter()
end

-- Mettre à jour la recherche (highlights + compteur)
local function update_search(query)
  state.query = query
  
  -- Nettoyer anciens highlights
  clear_highlights()
  
  if query == "" then
    update_counter()
    return
  end
  
  -- Ajouter highlight dans la fenêtre cible
  if state.target_win and api.nvim_win_is_valid(state.target_win) then
    api.nvim_win_call(state.target_win, function()
      local ok, id = pcall(vim.fn.matchadd, "Search", query)
      if ok then
        table.insert(state.match_ids, id)
      end
    end)
  end
  
  -- Mettre à jour le compteur
  update_counter()
end

-- Fermer proprement la recherche
local function close_search()
  -- Nettoyer les autocmds
  for _, au in ipairs(state.autocmds) do
    api.nvim_del_autocmd(au)
  end
  state.autocmds = {}
  
  -- Nettoyer les highlights
  clear_highlights()
  
  -- Fermer la fenêtre
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  
  state.win = nil
  state.buf = nil
  state.count_extmark_id = nil
end

function M.open()
  -- Récupérer la fenêtre et le buffer cibles
  state.target_win = api.nvim_get_current_win()
  state.target_buf = api.nvim_win_get_buf(state.target_win)
  state.original_view = vim.fn.winsaveview()
  state.query = ""
  state.match_ids = {}
  
  -- Créer la fenêtre de recherche
  local win = window.create_centered_win({
    width_pct = 0.25,
    height = 1,
    title = "Search",
    row_offset = 2
  })
  
  state.buf = win.buf
  state.win = win.win
  
  -- Initialiser avec padding
  api.nvim_buf_set_lines(state.buf, 0, -1, false, {"  "})
  
  vim.cmd("startinsert")
  api.nvim_win_set_cursor(state.win, {1, 2})
  
  -- Autocmd: Typing
  local au_typing = api.nvim_create_autocmd("TextChangedI", {
    buffer = state.buf,
    callback = function()
      local line = api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] or ""
      
      -- Enforce padding
      if not line:match("^  ") then
        local fixed = "  " .. line:gsub("^%s*", "")
        api.nvim_buf_set_lines(state.buf, 0, 1, false, {fixed})
        vim.api.nvim_win_set_cursor(state.win, {1, #fixed})
        line = fixed
      end
      
      local query = line:sub(3)
      update_search(query)
    end
  })
  table.insert(state.autocmds, au_typing)
  
  -- Autocmd: Suivi du curseur dans le buffer cible (throttled)
  local last_line = nil
  local au_cursor = api.nvim_create_autocmd("CursorMoved", {
    buffer = state.target_buf,
    callback = function()
      if state.query == "" then return end
      local current_line = api.nvim_win_get_cursor(state.target_win)[1]
      if current_line ~= last_line then
        last_line = current_line
        update_counter()
      end
    end
  })
  table.insert(state.autocmds, au_cursor)
  
  -- Autocmd: Fermer si on quitte la fenêtre cible
  local au_leave = api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.target_win),
    once = true,
    callback = function()
      close_search()
    end
  })
  table.insert(state.autocmds, au_leave)
  
  -- Keymap: Enter = occurrence suivante
  vim.keymap.set("i", "<CR>", function()
    move_to_match(1)  -- 1 = forward
  end, { buffer = state.buf })
  
  -- Keymap: Shift+Enter = occurrence précédente
  vim.keymap.set("i", "<S-CR>", function()
    move_to_match(-1)  -- -1 = backward
  end, { buffer = state.buf })
  
  -- Keymap: Esc = fermer (conserve position, retire highlights)
  vim.keymap.set({"i", "n"}, "<Esc>", function()
    close_search()
  end, { buffer = state.buf })
  
  -- Keymap: Ctrl+C = annuler (restaure position originale)
  vim.keymap.set({"i", "n"}, "<C-c>", function()
    -- Restaurer la position originale
    if state.target_win and api.nvim_win_is_valid(state.target_win) then
      api.nvim_win_call(state.target_win, function()
        vim.fn.winrestview(state.original_view)
      end)
    end
    close_search()
  end, { buffer = state.buf })
end

return M
