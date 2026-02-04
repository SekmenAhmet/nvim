local colors = require("config.colors")
local ui = require("config.ui")

local M = {}
M.buf = nil
M.win = nil
M.root = vim.uv.cwd()
M.expanded = {}
M.items = {}

-- Git cache pour éviter les appels répétés
local git_cache = {
  status = {},        -- { [relative_path] = status_code }
  timestamp = 0,
  root = nil,
  ttl = 2             -- 2 secondes de cache
}

-- Forward declaration de M.draw pour éviter les erreurs de scope
local draw_impl

-- Rafraîchir le git status de manière async
local function refresh_git_status(callback)
  local cwd = vim.uv.cwd()
  local git_dir = vim.fn.finddir(".git", cwd .. ";")
  
  if git_dir == "" then
    git_cache.status = {}
    git_cache.root = nil
    if callback then callback() end
    return
  end
  
  local repo_root = vim.fn.fnamemodify(git_dir, ":p:h:h")
  local now = vim.uv.now() / 1000
  
  -- Utiliser le cache si valide
  if git_cache.root == repo_root and (now - git_cache.timestamp) <= git_cache.ttl then
    if callback then callback() end
    return
  end
  
  git_cache.root = repo_root
  git_cache.timestamp = now
  
  -- Lancer git status en async
  local stdout = vim.uv.new_pipe(false)
  local stderr = vim.uv.new_pipe(false)
  
  local handle
  handle = vim.uv.spawn("git", {
    args = { "status", "--porcelain" },
    cwd = cwd,
    stdio = { nil, stdout, stderr }
  }, function(code, signal)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if handle and not handle:is_closing() then
      handle:close()
    end
    -- Appeler le callback après fermeture
    if callback then
      vim.schedule(callback)
    end
  end)
  
  local buffer = ""
  stdout:read_start(function(err, data)
    if err then return end
    if data then
      buffer = buffer .. data
    else
      -- Parse le résultat
      local new_status = {}
      for line in buffer:gmatch("[^\r\n]+") do
        if #line >= 3 then
          local status_code = line:sub(1, 2):gsub("%s", "")  -- XY -> X ou Y si pas espace
          if status_code == "" then status_code = line:sub(3, 3) end
          local file_path = line:sub(4)
          
          -- Normaliser le code
          if status_code:match("M") then
            new_status[file_path] = "M"  -- Modified
          elseif status_code:match("A") then
            new_status[file_path] = "A"  -- Added
          elseif status_code:match("D") then
            new_status[file_path] = "D"  -- Deleted
          elseif status_code == "??" then
            new_status[file_path] = "?"  -- Untracked
          end
        end
      end
      git_cache.status = new_status
    end
  end)
end

-- Obtenir le statut git d'un fichier
local function get_git_status_for_file(filepath)
  if not git_cache.root then return nil end
  -- Calculer le chemin relatif
  local rel_path = vim.fn.fnamemodify(filepath, ":.")
  return git_cache.status[rel_path]
end

-- Obtenir le niveau de diagnostic d'un fichier
local function get_diagnostic_level(filepath)
  -- Récupérer le buffer ID associé au fichier
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr == -1 then return nil end  -- Buffer pas chargé
  
  local diagnostics = vim.diagnostic.get(bufnr)
  local has_error = false
  local has_warn = false
  
  for _, d in ipairs(diagnostics) do
    if d.severity == vim.diagnostic.severity.ERROR then
      has_error = true
      break  -- Erreur prioritaire
    elseif d.severity == vim.diagnostic.severity.WARN then
      has_warn = true
    end
  end
  
  if has_error then return "error" end
  if has_warn then return "warn" end
  return nil
end

local function get_items(path)
  local handle = vim.uv.fs_scandir(path)
  if not handle then return {} end
  
  local entries = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if not name:match("^%.") then -- Hide dotfiles
      table.insert(entries, { name = name, type = type, path = path .. "/" .. name })
    end
  end
  
  table.sort(entries, function(a, b)
    if a.type == "directory" and b.type ~= "directory" then return true end
    if a.type ~= "directory" and b.type == "directory" then return false end
    return a.name < b.name
  end)
  return entries
end

-- Implémentation de draw (définie ici pour éviter les problèmes de scope)
draw_impl = function()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
  
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  
  local lines = {}
  M.items = {}
  
  -- Header
  table.insert(lines, "  " .. vim.fn.fnamemodify(M.root, ":~"))
  table.insert(M.items, { path = M.root, type = "directory" })

  local function traverse(path, depth)
    local entries = get_items(path)
    for _, item in ipairs(entries) do
      local prefix = "  " .. string.rep("  ", depth)
      
      -- Git status symbol
      local git_symbol = ""
      local git_status = get_git_status_for_file(item.path)
      if git_status then
        local symbols = {
          M = "✗ ",
          A = "+ ",
          ["?"] = "? ",
          D = "- "
        }
        git_symbol = symbols[git_status] or ""
      end
      
      local icon = ""
      
      if item.type == "directory" then
        icon = M.expanded[item.path] and " " or " "
      else
        icon = ui.get_icon(item.name) .. " "
      end
      
      -- Ajouter le symbole git avant l'icône
      table.insert(lines, prefix .. git_symbol .. icon .. item.name)
      table.insert(M.items, { 
        path = item.path, 
        type = item.type,
        git_status = git_status,
        depth = depth
      })
      
      if item.type == "directory" and M.expanded[item.path] then
        traverse(item.path, depth + 1)
      end
    end
  end
  
  traverse(M.root, 0)
  
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  
  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(M.buf, -1, 0, -1)
  
  for i, item in ipairs(M.items) do
    local line_idx = i - 1
    local line_text = lines[i]
    
    if i == 1 then
      vim.api.nvim_buf_add_highlight(M.buf, -1, "TreeRoot", line_idx, 0, -1)
    else
      -- Trouver les positions
      local content_start = line_text:find("[^ ]")
      if content_start then
        -- Calculer la position après le préfixe d'indentation
        local prefix_len = content_start - 1
        
        -- Position du symbole git (s'il existe)
        local git_end = content_start
        if item.git_status then
          git_end = content_start + 2  -- "✗ " fait 2 caractères
        end
        
        -- Position de l'icône
        local icon_start = git_end
        local icon_end = line_text:find(" ", icon_start)
        if not icon_end then icon_end = #line_text end
        
        -- Position du nom
        local name_start = icon_end + 1
        
        -- Colorer le symbole git
        if item.git_status then
          local git_hl = {
            M = "GitStatusModified",
            A = "GitStatusAdded", 
            ["?"] = "GitStatusUntracked",
            D = "GitStatusDeleted"
          }
          vim.api.nvim_buf_add_highlight(M.buf, -1, git_hl[item.git_status], line_idx, content_start - 1, git_end)
        end
        
        -- Colorer l'icône
        if item.type == "directory" then
          vim.api.nvim_buf_add_highlight(M.buf, -1, "IconDir", line_idx, icon_start - 1, icon_end)
        else
          local icon_data = ui.get_icon_data(item.path)
          vim.api.nvim_buf_add_highlight(M.buf, -1, icon_data.hl, line_idx, icon_start - 1, icon_end)
        end
        
        -- Colorer le nom selon git ET diagnostics
        local name_hl = nil
        
        -- Vérifier les diagnostics pour les fichiers
        if item.type ~= "directory" then
          local diag_level = get_diagnostic_level(item.path)
          if diag_level == "error" then
            name_hl = "TreeFileError"
          elseif diag_level == "warn" then
            name_hl = "TreeFileWarn"
          end
        end
        
        -- Si pas de diagnostic, utiliser la couleur normale
        if not name_hl then
          name_hl = item.type == "directory" and "TreeDir" or "TreeFile"
        end
        
        vim.api.nvim_buf_add_highlight(M.buf, -1, name_hl, line_idx, name_start - 1, -1)
      end
    end
  end
  
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

-- Exposer draw publiquement
M.draw = draw_impl

function M.toggle()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
    vim.cmd("redrawtabline")
    return
  end
  
  M.root = vim.uv.cwd()
  
  -- Reset git cache on toggle
  git_cache.status = {}
  git_cache.timestamp = 0
  
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(M.buf, "filetype", "netrw")
    vim.api.nvim_buf_set_option(M.buf, "buftype", "nofile")
  end
  
  vim.cmd("topleft vsplit")
  M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)
  
  local width = 30
  vim.api.nvim_win_set_width(M.win, width)
  vim.cmd("redrawtabline")
  
  vim.api.nvim_win_set_option(M.win, "number", false)
  vim.api.nvim_win_set_option(M.win, "relativenumber", false)
  vim.api.nvim_win_set_option(M.win, "cursorline", true)
  vim.api.nvim_win_set_option(M.win, "wrap", false)
  vim.api.nvim_win_set_option(M.win, "signcolumn", "no")
  
  -- Rafraîchir git puis dessiner
  refresh_git_status(function()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      draw_impl()
    end
  end)
  
  local function map(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = M.buf, silent = true })
  end
  
  map("<CR>", function()
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.items[line]
    if not item then return end
    if item.type == "directory" then
      if M.expanded[item.path] then M.expanded[item.path] = nil else M.expanded[item.path] = true end
      draw_impl()
    else
      ui.open_in_normal_win(item.path)
    end
  end)
  
  map("a", function()
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.items[line]
    local dir = M.root
    if item then if item.type == "directory" then dir = item.path else dir = vim.fn.fnamemodify(item.path, ":h") end end
    local name = vim.fn.input("New file/dir (ends with / for dir): ")
    if name == "" then return end
    local target = dir .. "/" .. name
    if name:match("/$") then vim.fn.mkdir(target, "p") else
      local f = io.open(target, "w"); if f then f:close() end
    end
    draw_impl()
  end)
  
  map("d", function()
     local line = vim.api.nvim_win_get_cursor(M.win)[1]
     local item = M.items[line]
     if not item or item.path == M.root then return end
     local choice = vim.fn.input("Delete " .. vim.fn.fnamemodify(item.path, ":t") .. "? (y/n): ")
     if choice:lower() == "y" then vim.fn.delete(item.path, "rf"); draw_impl() end
  end)
  
  map("r", function()
      local line = vim.api.nvim_win_get_cursor(M.win)[1]
      local item = M.items[line]
      if not item or item.path == M.root then return end
      local new_name = vim.fn.input("Rename: ", item.path)
      if new_name ~= "" and new_name ~= item.path then vim.fn.rename(item.path, new_name); draw_impl() end
  end)
  map("<C-l>", "<C-w>l")
  map("<C-h>", "<C-w>h")
end

-- Rafraîchir sur sauvegarde (pour git status)
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*",
  callback = function()
    -- Invalider le cache git
    git_cache.timestamp = 0
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      refresh_git_status(function()
        if M.win and vim.api.nvim_win_is_valid(M.win) then
          draw_impl()
        end
      end)
    end
  end
})

-- Rafraîchir sur retour de focus (changement de fenêtre)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  callback = function()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      -- Invalider partiellement le cache
      if (vim.uv.now() / 1000 - git_cache.timestamp) > 1 then
        refresh_git_status(function()
          if M.win and vim.api.nvim_win_is_valid(M.win) then
            draw_impl()
          end
        end)
      end
    end
  end
})

-- Rafraîchir quand les diagnostics changent
vim.api.nvim_create_autocmd("DiagnosticChanged", {
  callback = function()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      draw_impl()
    end
    -- Rafraîchir aussi la tabline
    vim.cmd("redrawtabline")
  end
})

-- Force minimal UI on any netrw buffer (even opened via :e .)
vim.api.nvim_create_autocmd("FileType", {
  pattern = "netrw",
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.cursorline = true
    vim.opt_local.signcolumn = "no"
  end
})

return M
