-- Tabline (Bufferline) Native avec Icônes Colorées et Cache
local icons = require("utils.icons")
local utils = require("utils")
local M = {}

-- Cache pour les diagnostics (performance)
local diag_cache = {}

-- Mettre à jour le cache pour un buffer ou tous
local function update_diag_cache(bufnr)
  if bufnr then
    diag_cache[bufnr] = utils.get_diagnostic_level(bufnr)
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) then diag_cache[b] = utils.get_diagnostic_level(b) end
    end
  end
end

function M.render()
  local line = ""
  
  -- 1. Dynamic Sidebar Padding (Netrw / Tree)
  local sidebar_width = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    if (ft == "tree" or ft == "netrw") and vim.api.nvim_win_get_position(win)[2] == 0 then
      sidebar_width = vim.api.nvim_win_get_width(win) + 1
      break
    end
  end

  if sidebar_width > 0 then
    line = line .. "%#TabLineFill#" .. string.rep(" ", sidebar_width)
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local buffers = vim.api.nvim_list_bufs()

  -- Rendu des buffers (skip unnamed buffers unless they are the only ones)
  local listed_buffers = {}
  for _, b in ipairs(buffers) do
    if vim.bo[b].buflisted then
      table.insert(listed_buffers, b)
    end
  end

  for i, buf in ipairs(listed_buffers) do
    local is_current = (buf == current_buf)
    local path = vim.api.nvim_buf_get_name(buf)
    local name = (path == "") and "[Untitled]" or vim.fn.fnamemodify(path, ":t")
    local modified = vim.bo[buf].modified and " ●" or ""
    
    local diag_level = diag_cache[buf]
    local icon_data = icons.get(name)

    -- Clickable
    line = line .. "%" .. buf .. "T"

    -- Highlight Group selection
    local hl_tab_bg = is_current and "TabLineSel" or "TabLine"
    if diag_level == "error" then 
      hl_tab_bg = is_current and "TabLineSelError" or "TabLineError"
    elseif diag_level == "warn" then 
      hl_tab_bg = is_current and "TabLineSelWarn" or "TabLineWarn"
    end

    -- Rendering the tab
    line = line .. "%#" .. hl_tab_bg .. "# "
    line = line .. "%#" .. icon_data.hl .. "#" .. icon_data.icon .. "%#" .. hl_tab_bg .. "# "
    line = line .. name .. modified .. " "
    line = line .. "%T"
    
    -- Separator
    if i < #listed_buffers then
      line = line .. "%#TabLineSeparator#|%#TabLineFill#"
    end
  end

  line = line .. "%=%#TabLine#  " .. #listed_buffers .. " "
  return line
end

-- Autocommandes pour le cache et le refresh
local tabline_augroup = vim.api.nvim_create_augroup("NativeTabline", { clear = true })

vim.api.nvim_create_autocmd("DiagnosticChanged", {
  group = tabline_augroup,
  callback = function(args)
    update_diag_cache(args.buf)
    vim.cmd("redrawtabline")
  end,
})

vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufEnter" }, {
  group = tabline_augroup,
  callback = function(args)
    update_diag_cache(args.buf)
    vim.cmd("redrawtabline")
  end,
})

-- Activer la tabline
vim.opt.showtabline = 2
vim.opt.tabline = "%!v:lua.require'config.tabline'.render()"

return M
