local M = {}

local State = require("core.state")
local ui_utils = require("utils.ui")

---@class ViewComponent
---@field buf number
---@field win number
---@field name string
---@field options table
---@field _render_timer any

---Crée un nouveau composant de vue
function M.create_component(name, options)
  options = options or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  
  vim.api.nvim_buf_set_option(buf, "buftype", options.buftype or "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", options.bufhidden or "hide")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  
  if options.filetype then
    vim.api.nvim_buf_set_option(buf, "filetype", options.filetype)
  end

  return {
    buf = buf,
    win = -1,
    name = name,
    options = options,
    _render_timer = nil
  }
end

---Rendu avec debouncing optionnel
function M.render(component, lines, highlights, debounce_ms)
  if not vim.api.nvim_buf_is_valid(component.buf) then return end

  local function do_render()
    if not vim.api.nvim_buf_is_valid(component.buf) then return end
    
    vim.api.nvim_buf_set_option(component.buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(component.buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(component.buf, "modifiable", false)
    
    local ns = vim.api.nvim_create_namespace("view_factory_" .. component.name)
    vim.api.nvim_buf_clear_namespace(component.buf, ns, 0, -1)
    
    if highlights then
      for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(
          component.buf,
          ns,
          hl.group,
          hl.line,
          hl.col_start or 0,
          hl.col_end or -1
        )
      end
    end
  end

  if debounce_ms and debounce_ms > 0 then
    if component._render_timer then
      component._render_timer:stop()
      if not component._render_timer:is_closing() then component._render_timer:close() end
    end
    
    local timer = vim.uv.new_timer()
    component._render_timer = timer
    timer:start(debounce_ms, 0, vim.schedule_wrap(function()
      do_render()
      if component._render_timer == timer then
        component._render_timer = nil
      end
      if not timer:is_closing() then
        timer:close()
      end
    end))
  else
    do_render()
  end
end

---Applique les keymaps et le mode UI spécifique
function M.apply_ui_rules(component, rules)
  if not vim.api.nvim_buf_is_valid(component.buf) then return end
  
  -- Appliquer set_ui_mode si spécifié (contrainte de navigation/édition)
  if rules.mode then
    ui_utils.set_ui_mode(component.buf, { win = component.win, mode = rules.mode })
  end

  -- Appliquer les mappings personnalisés
  if rules.mappings then
    local opts = { noremap = true, silent = true, buffer = component.buf }
    for lhs, callback in pairs(rules.mappings) do
      vim.keymap.set("n", lhs, callback, opts)
    end
  end
end

function M.show_floating(component, layout_config)
  local width = math.floor(vim.o.columns * (layout_config.width or 0.8))
  local height = math.floor(vim.o.lines * (layout_config.height or 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = layout_config.title,
    title_pos = "center"
  }

  if not vim.api.nvim_win_is_valid(component.win) then
    component.win = vim.api.nvim_open_win(component.buf, true, win_opts)
  else
    vim.api.nvim_win_set_config(component.win, win_opts)
  end
  
  return component.win
end

return M
