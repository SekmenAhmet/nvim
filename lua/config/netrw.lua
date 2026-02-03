local colors = require("config.colors")
local ui = require("config.ui")

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
  table.insert(lines, "  " .. vim.fn.fnamemodify(M.root, ":~"))
  table.insert(M.items, { path = M.root, type = "directory" })

  local function traverse(path, depth)
    local entries = get_items(path)
    for _, item in ipairs(entries) do
      local prefix = "  " .. string.rep("  ", depth)
      local icon = ""
      
      if item.type == "directory" then
        icon = M.expanded[item.path] and " " or " "
      else
        icon = ui.get_icon(item.name) .. " "
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
  vim.api.nvim_buf_clear_namespace(M.buf, -1, 0, -1)
  
  for i, item in ipairs(M.items) do
    local line_idx = i - 1
    local line_text = lines[i]
    
    if i == 1 then
      vim.api.nvim_buf_add_highlight(M.buf, -1, "TreeRoot", line_idx, 0, -1)
    else
      -- Find the first non-space character (the icon)
      local icon_start = line_text:find("[^ ]")
      if icon_start then
        -- Find the space after the icon to know its end column
        local icon_end = line_text:find(" ", icon_start)
        
        if item.type == "directory" then
          -- Color the folder icon
          vim.api.nvim_buf_add_highlight(M.buf, -1, "IconDir", line_idx, icon_start - 1, icon_end)
          -- Color the folder name
          vim.api.nvim_buf_add_highlight(M.buf, -1, "TreeDir", line_idx, icon_end, -1)
        else
          -- Color the file icon using our dynamic highlight groups
          local icon_data = ui.get_icon_data(item.path)
          vim.api.nvim_buf_add_highlight(M.buf, -1, icon_data.hl, line_idx, icon_start - 1, icon_end)
          -- Color the file name
          vim.api.nvim_buf_add_highlight(M.buf, -1, "TreeFile", line_idx, icon_end, -1)
        end
      end
    end
  end
  
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

function M.toggle()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
    vim.cmd("redrawtabline")
    return
  end
  
  M.root = vim.loop.cwd()
  
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
  
  draw()
  
  local function map(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = M.buf, silent = true })
  end
  
  map("<CR>", function()
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.items[line]
    if not item then return end
    if item.type == "directory" then
      if M.expanded[item.path] then M.expanded[item.path] = nil else M.expanded[item.path] = true end
      draw()
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
    draw()
  end)
  
  map("d", function()
     local line = vim.api.nvim_win_get_cursor(M.win)[1]
     local item = M.items[line]
     if not item or item.path == M.root then return end
     local choice = vim.fn.input("Delete " .. vim.fn.fnamemodify(item.path, ":t") .. "? (y/n): ")
     if choice:lower() == "y" then vim.fn.delete(item.path, "rf"); draw() end
  end)
  
  map("r", function()
      local line = vim.api.nvim_win_get_cursor(M.win)[1]
      local item = M.items[line]
      if not item or item.path == M.root then return end
      local new_name = vim.fn.input("Rename: ", item.path)
      if new_name ~= "" and new_name ~= item.path then vim.fn.rename(item.path, new_name); draw() end
  end)
  map("<C-l>", "<C-w>l")
  map("<C-h>", "<C-w>h")
end

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*",
  callback = function()
    if M.win and vim.api.nvim_win_is_valid(M.win) then draw() end
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
    -- Try to inject our drawer if possible, or at least clean UI
    -- M.buf = vim.api.nvim_get_current_buf() -- Potentially unsafe if hijacked logic differs
  end
})

return M