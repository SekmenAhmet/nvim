local icons = require("utils.icons")
local utils = require("utils")

local M = {}
M.buf = nil
M.win = nil
M.root = vim.uv.cwd()
M.expanded = {}
M.items = {}

-- Git cache pour éviter les appels répétés
local git_cache = {
  status = {},
  timestamp = 0,
  root = nil,
  ttl = 2
}

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
  
  if git_cache.root == repo_root and (now - git_cache.timestamp) <= git_cache.ttl then
    if callback then callback() end
    return
  end
  
  git_cache.root = repo_root
  git_cache.timestamp = now
  
  local stdout = vim.uv.new_pipe(false)
  local stderr = vim.uv.new_pipe(false)
  
  local handle
  handle = vim.uv.spawn("git", {
    args = { "status", "--porcelain" },
    cwd = cwd,
    stdio = { nil, stdout, stderr }
  }, function()
    stdout:read_stop(); stderr:read_stop(); stdout:close(); stderr:close()
    if handle and not handle:is_closing() then handle:close() end
    if callback then vim.schedule(callback) end
  end)
  
  local buffer = ""
  stdout:read_start(function(err, data)
    if data then
      buffer = buffer .. data
    else
      local new_status = {}
      for line in buffer:gmatch("[^\r\n]+") do
        if #line >= 3 then
          local status_code = line:sub(1, 2):gsub("%s", "")
          if status_code == "" then status_code = line:sub(3, 3) end
          local file_path = line:sub(4)
          if status_code:match("M") then new_status[file_path] = "M"
          elseif status_code:match("A") then new_status[file_path] = "A"
          elseif status_code:match("D") then new_status[file_path] = "D"
          elseif status_code == "??" then new_status[file_path] = "?" end
        end
      end
      git_cache.status = new_status
    end
  end)
end

local function get_git_status_for_file(filepath)
  if not git_cache.root then return nil end
  local rel_path = vim.fn.fnamemodify(filepath, ":.")
  return git_cache.status[rel_path]
end

local function get_items(path)
  local handle = vim.uv.fs_scandir(path)
  if not handle then return {} end
  
  local entries = {}
  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if name ~= ".git" then
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

function M.draw()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
  
  vim.bo[M.buf].modifiable = true
  local lines, items = {}, {}
  
  table.insert(lines, "  " .. vim.fn.fnamemodify(M.root, ":~"))
  table.insert(items, { path = M.root, type = "directory" })

  local function traverse(path, depth)
    local entries = get_items(path)
    for _, item in ipairs(entries) do
      local indent = depth > 0 and ("│ " .. string.rep("  ", depth - 1)) or ""
      local icon_data = (item.type == "directory") 
        and { icon = M.expanded[item.path] and "" or "", hl = "IconDir" }
        or icons.get(item.name)
      
      table.insert(lines, string.format(" %s%s %s", indent, icon_data.icon, item.name))
      table.insert(items, { 
        path = item.path, type = item.type, name = item.name,
        depth = depth, icon_hl = icon_data.hl, icon = icon_data.icon
      })
      
      if item.type == "directory" and M.expanded[item.path] then
        traverse(item.path, depth + 1)
      end
    end
  end
  
  traverse(M.root, 0)
  M.items = items
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  
  vim.api.nvim_buf_clear_namespace(M.buf, -1, 0, -1)
  for i, item in ipairs(M.items) do
    local idx = i - 1
    local line = lines[i]
    if i == 1 then
      vim.api.nvim_buf_add_highlight(M.buf, -1, "Directory", idx, 0, -1)
    else
      local guide_pos = line:find("│")
      if guide_pos then
        vim.api.nvim_buf_add_highlight(M.buf, -1, "Comment", idx, guide_pos - 1, guide_pos + 2)
      end

      local icon_start = line:find(item.icon, 1, true)
      if icon_start then
        vim.api.nvim_buf_add_highlight(M.buf, -1, item.icon_hl, idx, icon_start - 1, icon_start + #item.icon - 1)
        
        local name_pos = line:find(item.name, icon_start + #item.icon, true)
        if name_pos then
          local hl = item.type == "directory" and "Directory" or "Normal"
          local git_status = get_git_status_for_file(item.path)
          local diag = utils.get_diagnostic_level(item.path)
          
          if diag == "error" then hl = "DiagnosticError"
          elseif diag == "warn" then hl = "DiagnosticWarn"
          elseif git_status == "M" then hl = "DiffChange"
          elseif git_status == "A" or git_status == "?" then hl = "DiffAdd"
          elseif git_status == "D" then hl = "DiffDelete" end
          
          vim.api.nvim_buf_add_highlight(M.buf, -1, hl, idx, name_pos - 1, -1)
        end
      end
    end
  end
  vim.bo[M.buf].modifiable = false
end

function M.close()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
  vim.cmd("redrawtabline")
end

function M.toggle()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    M.close()
    return
  end
  
  M.root = vim.uv.cwd()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].filetype = "tree"; vim.bo[M.buf].buftype = "nofile"
  end
  
  vim.cmd("topleft vsplit"); M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)
  vim.api.nvim_win_set_width(M.win, 30); vim.cmd("redrawtabline")
  
  vim.wo[M.win].number = false; vim.wo[M.win].relativenumber = false
  vim.wo[M.win].cursorline = true; vim.wo[M.win].wrap = false; vim.wo[M.win].signcolumn = "no"
  
  refresh_git_status(function() if M.win and vim.api.nvim_win_is_valid(M.win) then M.draw() end end)
  
  local function map(lhs, rhs) vim.keymap.set("n", lhs, rhs, { buffer = M.buf, silent = true }) end
  map("<CR>", function()
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.items[line]
    if not item then return end
    if item.type == "directory" then
      M.expanded[item.path] = not M.expanded[item.path]; M.draw()
    else
      require("utils.ui").open_in_normal_win(item.path)
    end
  end)
  
  map("a", function()
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.items[line]
    local dir = (item and item.type == "directory") and item.path or (item and vim.fn.fnamemodify(item.path, ":h") or M.root)
    local name = vim.fn.input("New file/dir (ends with / for dir): ")
    if name == "" then return end
    local target = dir .. "/" .. name
    if name:match("/$") then 
      vim.fn.mkdir(target, "p") 
      M.draw()
    else
      vim.uv.fs_open(target, "w", 438, function(err, fd) 
        if not err and fd then 
          vim.uv.fs_close(fd) 
        end 
        vim.schedule(M.draw)
      end)
    end
  end)
  
  map("d", function()
     local line = vim.api.nvim_win_get_cursor(M.win)[1]
     local item = M.items[line]
     if not item or item.path == M.root then return end
     if vim.fn.confirm("Delete " .. vim.fn.fnamemodify(item.path, ":t") .. "?", "&Yes\n&No") == 1 then
       vim.fn.delete(item.path, "rf"); M.draw()
     end
  end)
end

local tree_augroup = vim.api.nvim_create_augroup("NativeTree", { clear = true })
vim.api.nvim_create_autocmd({ "BufWritePost", "FocusGained", "BufEnter", "DiagnosticChanged" }, {
  group = tree_augroup,
  callback = function()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      git_cache.timestamp = 0
      refresh_git_status(function() if M.win and vim.api.nvim_win_is_valid(M.win) then M.draw() end end)
    end
  end
})

-- Ensure diagnostics are reflected even when switching back to the tree
vim.api.nvim_create_autocmd("WinEnter", {
  group = tree_augroup,
  callback = function()
    if M.win and vim.api.nvim_win_is_valid(M.win) and vim.api.nvim_get_current_win() == M.win then
      M.draw()
    end
  end
})

return M
