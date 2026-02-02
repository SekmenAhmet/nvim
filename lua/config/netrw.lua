local colors = require("config.colors")

local M = {}
M.buf = nil
M.win = nil
M.root = vim.loop.cwd()
M.expanded = {}
M.items = {}

local function get_items(path)
  local handle = vim.loop.fs_scandir(path)
  if not handle then return {} end
  
  local entries = {}
  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
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

local function draw()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
  
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  
  local lines = {}
  M.items = {}
  
  -- Header
  table.insert(lines, "   " .. vim.fn.fnamemodify(M.root, ":~"))
  table.insert(M.items, { path = M.root, type = "directory" })

  local function traverse(path, depth)
    local entries = get_items(path)
    for _, item in ipairs(entries) do
      local prefix = "   " .. string.rep("  ", depth)
      local icon = (item.type == "directory") and "> " or "  "
      
      -- Open/Close indicators
      if item.type == "directory" and M.expanded[item.path] then
        icon = "v "
      end
      
      table.insert(lines, prefix .. icon .. item.name)
      table.insert(M.items, { path = item.path, type = item.type })
      
      if item.type == "directory" and M.expanded[item.path] then
        traverse(item.path, depth + 1)
      end
    end
  end
  
  traverse(M.root, 0)
  
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  
  -- Apply highlights
  vim.api.nvim_buf_add_highlight(M.buf, -1, "TreeRoot", 0, 0, -1)
  for i, item in ipairs(M.items) do
    if i > 1 then
      local group = (item.type == "directory") and "TreeDir" or "TreeFile"
      vim.api.nvim_buf_add_highlight(M.buf, -1, group, i-1, 0, -1)
    end
  end
  
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

local function toggle()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
    return
  end
  
  M.root = vim.loop.cwd() -- Update root on open
  
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(M.buf, "filetype", "netrw")
    vim.api.nvim_buf_set_option(M.buf, "buftype", "nofile")
  end
  
  vim.cmd("topleft vsplit")
  M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)
  
  vim.api.nvim_win_set_width(M.win, 30)
  vim.api.nvim_win_set_option(M.win, "number", false)
  vim.api.nvim_win_set_option(M.win, "relativenumber", false)
  vim.api.nvim_win_set_option(M.win, "cursorline", true)
  vim.api.nvim_win_set_option(M.win, "wrap", false)
  vim.api.nvim_win_set_option(M.win, "signcolumn", "no")
  
  draw()
  
  local function map(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = M.buf, silent = true })
  end
  
  map("<CR>", function()
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.items[line]
    if not item then return end
    
    if item.type == "directory" then
      if M.expanded[item.path] then
        M.expanded[item.path] = nil
      else
        M.expanded[item.path] = true
      end
      draw()
    else
      vim.cmd("wincmd p")
      vim.cmd("edit " .. vim.fn.fnameescape(item.path))
    end
  end)
  
  map("a", function()
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.items[line]
    local dir = M.root
    
    if item then
       if item.type == "directory" then dir = item.path 
       else dir = vim.fn.fnamemodify(item.path, ":h") end
    end
    
    local name = vim.fn.input("New file/dir (ends with / for dir): ")
    if name == "" then return end
    local target = dir .. "/" .. name
    
    if name:match("/$") then
      vim.fn.mkdir(target, "p")
    else
      local f = io.open(target, "w")
      if f then f:close() end
    end
    draw()
  end)
  
  map("d", function()
     local line = vim.api.nvim_win_get_cursor(M.win)[1]
     local item = M.items[line]
     if not item or item.path == M.root then return end
     
     local choice = vim.fn.input("Delete " .. vim.fn.fnamemodify(item.path, ":t") .. "? (y/n): ")
     if choice:lower() == "y" then
       vim.fn.delete(item.path, "rf")
       draw()
     end
  end)
  
  map("r", function()
      local line = vim.api.nvim_win_get_cursor(M.win)[1]
      local item = M.items[line]
      if not item or item.path == M.root then return end
      
      local new_name = vim.fn.input("Rename: ", item.path)
      if new_name ~= "" and new_name ~= item.path then
        vim.fn.rename(item.path, new_name)
        draw()
      end
  end)

  -- Ensure global window navigation works
  map("<C-l>", "<C-w>l")
  map("<C-h>", "<C-w>h")

  map("-", function()
    -- Go up logic? Or just collapse?
    -- For now, just collapse parent
  end)
end

vim.keymap.set("n", "<C-b>", toggle, { silent = true })
vim.keymap.set("i", "<C-b>", toggle, { silent = true })
vim.keymap.set("v", "<C-b>", toggle, { silent = true })

-- Auto refresh on file save
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*",
  callback = function()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
      draw()
    end
  end
})