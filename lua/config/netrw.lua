local ui = require("config.ui")
local diag_utils = require("utils")

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
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr == -1 then return nil end
  return diag_utils.get_diagnostic_level(bufnr)
end

local function get_items(path)
  local handle = vim.uv.fs_scandir(path)
  if not handle then return {} end
  
  local entries = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then break end
    -- Show .env files specifically, hide other dotfiles
    if name == ".env" or not name:match("^%.") then
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
  
  vim.bo[M.buf].modifiable = true
  
  local lines = {}
  M.items = {}
  
  -- Header simple
  table.insert(lines, "  " .. vim.fn.fnamemodify(M.root, ":~"))
  table.insert(M.items, { path = M.root, type = "directory" })

  local function traverse(path, depth)
    local entries = get_items(path)
    for _, item in ipairs(entries) do
      local indent = string.rep("  ", depth)
      if depth > 0 then indent = "│ " .. string.rep("  ", depth - 1) end
      
      local git_status = get_git_status_for_file(item.path)
      local icon = ""
      
      if item.type == "directory" then
        icon = M.expanded[item.path] and " " or " "
      else
        icon = ui.get_icon_data(item.name).icon .. " "
      end
      
      table.insert(lines, " " .. indent .. icon .. item.name)
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
  
  -- Application des highlights
  vim.api.nvim_buf_clear_namespace(M.buf, -1, 0, -1)
  
  for i, item in ipairs(M.items) do
    local idx = i - 1
    local line = lines[i]
    
    if i == 1 then
      vim.api.nvim_buf_add_highlight(M.buf, -1, "Directory", idx, 0, -1)
    else
      -- 1. Colorer les guides d'indentation
      local guide_pos = line:find("│")
      if guide_pos then
        vim.api.nvim_buf_add_highlight(M.buf, -1, "Comment", idx, guide_pos - 1, guide_pos + 2)
      end

      -- 2. Colorer l'icône
      -- La structure de la ligne est : "  [indent]icon name"
      -- On cherche le premier caractère non-espace après l'éventuel guide d'indentation (│ fait 3 octets)
      local search_start = (guide_pos and (guide_pos + 3) or 0) + 1
      local icon_start_idx = line:find("[^ ]", search_start)
      
      if icon_start_idx then
        -- L'icône se termine au premier espace qui suit
        local icon_end_idx = line:find(" ", icon_start_idx)
        
        if icon_end_idx then
          if item.type == "directory" then
            vim.api.nvim_buf_add_highlight(M.buf, -1, "IconDir", idx, icon_start_idx - 1, icon_end_idx - 1)
          else
            local icon_data = ui.get_icon_data(item.path)
            vim.api.nvim_buf_add_highlight(M.buf, -1, icon_data.hl, idx, icon_start_idx - 1, icon_end_idx - 1)
          end

          -- 3. Colorer le nom selon Git / Diagnostics (On commence après l'icône + espace)
          local name_pos = line:find("[^ ]", icon_end_idx)
          if name_pos then
            local name_hl = item.type == "directory" and "Directory" or "Normal"
            local diag = get_diagnostic_level(item.path)
            if diag == "error" then name_hl = "DiagnosticError"
            elseif diag == "warn" then name_hl = "DiagnosticWarn"
            elseif item.git_status == "M" then name_hl = "DiffChange"
            elseif item.git_status == "A" or item.git_status == "?" then name_hl = "DiffAdd"
            elseif item.git_status == "D" then name_hl = "DiffDelete"
            end
            vim.api.nvim_buf_add_highlight(M.buf, -1, name_hl, idx, name_pos - 1, -1)
          end
        end
      end
    end
  end
  
  vim.bo[M.buf].modifiable = false
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
    vim.bo[M.buf].filetype = "tree"
    vim.bo[M.buf].buftype = "nofile"
  end
  
  vim.cmd("topleft vsplit")
  M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)
  
  local width = 30
  vim.api.nvim_win_set_width(M.win, width)
  vim.cmd("redrawtabline")
  
  vim.wo[M.win].number = false
  vim.wo[M.win].relativenumber = false
  vim.wo[M.win].cursorline = true
  vim.wo[M.win].wrap = false
  vim.wo[M.win].signcolumn = "no"
  
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

-- Augroup for tree autocommands
local tree_augroup = vim.api.nvim_create_augroup("NativeTree", { clear = true })

-- Rafraîchir sur sauvegarde (pour git status)
vim.api.nvim_create_autocmd("BufWritePost", {
  group = tree_augroup,
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
  group = tree_augroup,
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
  group = tree_augroup,
  callback = function()
    vim.schedule(function()
      if M.win and vim.api.nvim_win_is_valid(M.win) then
        draw_impl()
      end
    end)
  end
})

return M