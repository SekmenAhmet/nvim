-- Tabline (Bufferline) Native avec Icônes Colorées et Cache
local ui = require("config.ui")
local diag_utils = require("utils")
local M = {}

-- Cache pour les diagnostics (performance)
local diag_cache = {}

-- Mettre à jour le cache pour un buffer ou tous
local function update_diag_cache(bufnr)
  if bufnr then
    diag_cache[bufnr] = diag_utils.get_diagnostic_level(bufnr)
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) then diag_cache[b] = diag_utils.get_diagnostic_level(b) end
    end
  end
end

function M.render()
  local line = ""
  
  -- 1. Dynamic Sidebar Padding
  local sidebar_width = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "tree" and vim.api.nvim_win_get_position(win)[2] == 0 then
      sidebar_width = vim.api.nvim_win_get_width(win) + 1
      break
    end
  end

  if sidebar_width > 0 then
    line = line .. "%#TabLineFill#" .. string.rep(" ", sidebar_width)
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local buffers = vim.api.nvim_list_bufs()

  -- Rendu des buffers (skip unnamed buffers)
  local listed_buffers = {}
  for _, b in ipairs(buffers) do
    if vim.bo[b].buflisted then
      local name = vim.api.nvim_buf_get_name(b)
      -- Skip unnamed buffers (Untitled) entirely
      if name ~= "" then
        table.insert(listed_buffers, b)
      end
    end
  end

  for i, buf in ipairs(listed_buffers) do
    local is_current = (buf == current_buf)
    local name = vim.api.nvim_buf_get_name(buf)
    local modified = vim.bo[buf].modified and " ●" or ""
    
    name = (name == "") and "Untitled" or vim.fn.fnamemodify(name, ":t")
    local diag_level = diag_cache[buf]
    local icon_data = ui.get_icon_data(name)

    -- Clickable
    line = line .. "%" .. buf .. "T"

    -- Highlight Group selection (Fond de l'onglet)
    local hl_tab_bg = is_current and "TabLineSel" or "TabLine"
    if diag_level == "error" then hl_tab_bg = is_current and "TabLineSelError" or "TabLineError"
    elseif diag_level == "warn" then hl_tab_bg = is_current and "TabLineSelWarn" or "TabLineWarn"
    end

    -- Début de l'onglet
    line = line .. "%#" .. hl_tab_bg .. "# "
    
    -- ICONE COLORÉE : On passe au highlight de l'icône, puis on revient au fond de l'onglet
    line = line .. "%#" .. icon_data.hl .. "#" .. icon_data.icon .. "%#" .. hl_tab_bg .. "# "
    
    -- Nom du fichier + Modifié
    line = line .. name .. modified .. " "
    
    line = line .. "%T"
    
    -- Separator (if not last)
    if i < #listed_buffers then
      line = line .. "%#TabLineSeparator#|%#TabLineFill#"
    else
      line = line .. "%#TabLineFill# "
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
vim.opt.tabline = "%!luaeval('require(\"config.tabline\").render()')"

return M