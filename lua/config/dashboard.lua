local M = {}
local api = vim.api

local logo = {
  "                                  ",
  "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ",
  "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ",
  "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ",
  "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ",
  "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ",
  "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ",
  "                                  ",
  "            NATIVE LUA IDE v2.0   ",
  "                                  ",
}

local options = {
  { icon = " ", text = "Find Files", key = "f", cmd = "require('config.finder').open()", type = "lua" },
  { icon = " ", text = "Live Grep",  key = "g", cmd = "require('config.grep').open()", type = "lua" },
  { icon = " ", text = "New File",   key = "n", cmd = "enew", type = "cmd" },
  { icon = "󰚰 ", text = "Git Status", key = "s", cmd = "require('config.git').toggle()", type = "lua" },
  { icon = " ", text = "Docker",     key = "d", cmd = "require('config.docker').toggle()", type = "lua" },
  { icon = "󰒲 ", text = "Lazy",       key = "l", cmd = "Lazy", type = "cmd" },
  { icon = "󰈆 ", text = "Quit",       key = "q", cmd = "qa", type = "cmd" },
}

local function draw(buf, win)
  if not api.nvim_buf_is_valid(buf) or not api.nvim_win_is_valid(win) then return end

  local lines = {}
  for _, l in ipairs(logo) do table.insert(lines, l) end
  table.insert(lines, "")
  
  local start_row = #lines
  -- Build option lines
  for _, opt in ipairs(options) do
    table.insert(lines, string.format("       %s  %s  [%s]", opt.icon, opt.text, opt.key))
  end

  -- Center lines horizontally
  local win_width = api.nvim_win_get_width(win)
  local centered_lines = {}
  local paddings = {}

  for _, l in ipairs(lines) do
    local line_width = vim.fn.strdisplaywidth(l)
    local padding_len = math.max(0, math.floor((win_width - line_width) / 2))
    local padding = string.rep(" ", padding_len)
    table.insert(centered_lines, padding .. l)
    table.insert(paddings, padding_len)
  end

  -- Center vertically
  local win_height = api.nvim_win_get_height(win)
  local content_height = #centered_lines
  local row_offset = math.max(0, math.floor((win_height - content_height) / 2) - 2)
  
  local final_lines = {}
  for _=1, row_offset do table.insert(final_lines, "") end
  for _, l in ipairs(centered_lines) do table.insert(final_lines, l) end

  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, final_lines)
  vim.bo[buf].modifiable = false

  -- Highlights
  local ns = api.nvim_create_namespace("dashboard")
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  
  -- Logo Highlights
  for i = 0, #logo - 1 do
    local real_row = row_offset + i
    if real_row >= 0 then
        api.nvim_buf_add_highlight(buf, ns, "Function", real_row, 0, -1)
    end
  end
  -- Subtitle/Version Highlight
  if row_offset + #logo - 2 >= 0 then
      api.nvim_buf_add_highlight(buf, ns, "Comment", row_offset + #logo - 2, 0, -1)
  end

  -- Options Highlights
  for i = 0, #options - 1 do
    local opt_row_idx = start_row + i + 1
    local real_row = row_offset + start_row + i
    
    local line_content = centered_lines[opt_row_idx]
    local padding_len = paddings[opt_row_idx]
    local opt = options[i + 1]

    if line_content then
      local icon_start = padding_len + 7
      local icon_end = icon_start + #opt.icon
      api.nvim_buf_add_highlight(buf, ns, "Directory", real_row, icon_start, icon_end) 
      
      local key_start = line_content:find("%[", icon_end)
      if key_start then
         api.nvim_buf_add_highlight(buf, ns, "String", real_row, key_start - 1, -1)
      end
    end
  end
end

function M.open()
  if vim.fn.argc() > 0 or vim.api.nvim_buf_get_name(0) ~= "" or vim.bo.buftype ~= "" then
    return
  end

  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)

  -- UI Configuration
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "dashboard"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].foldcolumn = "0"
  
  -- Hide Cursor Logic
  local guicursor_saved = vim.opt.guicursor:get()
  vim.opt.guicursor:append("a:hor1-Cursor/lCursor")
  
  api.nvim_create_autocmd({"BufLeave", "WinLeave"}, {
    buffer = buf,
    callback = function()
      vim.opt.guicursor = guicursor_saved
    end
  })
  
  api.nvim_create_autocmd({"BufEnter", "WinEnter"}, {
    buffer = buf,
    callback = function()
       vim.opt.guicursor:append("a:hor1-Cursor/lCursor")
    end
  })

  -- Redraw on resize
  api.nvim_create_autocmd({"VimResized", "WinResized"}, {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        draw(buf, win)
      end)
    end
  })

  draw(buf, win)

  -- Keymaps & Action Handling
  local map_opts = { buffer = buf, silent = true, nowait = true }
  for _, opt in ipairs(options) do
    vim.keymap.set("n", opt.key, function()
      if opt.type == "cmd" then
        vim.cmd(opt.cmd)
      else
        local f = loadstring(opt.cmd)
        if f then f() end
      end
    end, map_opts)
  end
end

return M
