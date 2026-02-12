local M = {}
local api = vim.api
local icons = require("utils.icons")

-- =============================================================================
-- WINDOW MANAGEMENT
-- =============================================================================

function M.create_float(config)
  local buf = config.buf or api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, config.enter or false, {
    relative = "editor",
    width = config.width,
    height = config.height,
    row = config.row,
    col = config.col,
    style = "minimal",
    border = "rounded",
    title = config.title,
    title_pos = config.title_pos or "center",
    zindex = config.zindex or 50,
  })

  vim.wo[win].winhl = "NormalFloat:Normal,FloatBorder:FloatBorder,CursorLine:Visual"
  if config.cursorline then vim.wo[win].cursorline = true end
  
  return buf, win
end

-- Centralized Centered Window
function M.create_centered_win(opts)
  local width = math.floor(vim.o.columns * (opts.width_pct or 0.5))
  local height = opts.height or math.floor(vim.o.lines * (opts.height_pct or 0.5))
  local row = opts.row_offset or math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  return M.create_float({
    width = width,
    height = height,
    row = row,
    col = col,
    title = opts.title,
    enter = opts.enter
  })
end

function M.create_picker_layout(opts)
  local width = math.floor(vim.o.columns * (opts.width_pct or 0.8))
  local height = math.floor(vim.o.lines * (opts.height_pct or 0.8))
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local preview_pct = opts.preview_pct or 0.55
  local preview_width = math.floor(width * preview_pct)
  local list_width = width - preview_width - 2

  local buf_list, win_list = M.create_float({
    width = list_width, height = height, row = row, col = col,
    title = opts.title, enter = true, cursorline = true
  })

  local buf_preview, win_preview = M.create_float({
    width = preview_width, height = height, row = row, col = col + list_width + 2,
    title = " Preview ", enter = false, cursorline = false
  })
  
  vim.bo[buf_list].filetype = opts.ft_list or "picker_list"
  vim.bo[buf_preview].filetype = opts.ft_preview or "picker_preview"
  vim.wo[win_preview].number = true

  return {
    list = { buf = buf_list, win = win_list },
    preview = { buf = buf_preview, win = win_preview }
  }
end

-- =============================================================================
-- ASYNC NOTIFICATIONS (Native Float)
-- =============================================================================

local notifications = {}

function M.notify(msg, level, opts)
  opts = opts or {}
  local level_map = {
    [vim.log.levels.ERROR] = { icon = " ", hl = "DiagnosticError" },
    [vim.log.levels.WARN]  = { icon = " ", hl = "DiagnosticWarn" },
    [vim.log.levels.INFO]  = { icon = " ", hl = "DiagnosticInfo" },
  }
  
  local config = level_map[level or vim.log.levels.INFO]
  local lines = vim.split(tostring(msg), "\n")
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, #l) end
  width = width + 4
  
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  local row = 1
  for _, n in ipairs(notifications) do
    if api.nvim_win_is_valid(n.win) then
      row = row + api.nvim_win_get_height(n.win) + 2
    end
  end

  local win = api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = #lines,
    row = row,
    col = vim.o.columns - width - 2,
    style = "minimal",
    border = "rounded",
    title = " " .. (config.icon or "") .. "Notification ",
    zindex = 100,
  })

  vim.wo[win].winhl = "NormalFloat:Normal,FloatBorder:" .. config.hl
  
  local entry = { win = win, buf = buf }
  table.insert(notifications, entry)

  vim.defer_fn(function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
    for i, n in ipairs(notifications) do
      if n.win == win then table.remove(notifications, i) break end
    end
  end, opts.timeout or 3000)
end

vim.notify = M.notify

-- =============================================================================
-- LSP HANDLERS (Material Style)
-- =============================================================================

function M.setup_lsp_handlers()
  local border = "rounded"
  vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = border })
  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = border })
end

-- =============================================================================
-- NAVIGATION HELPERS
-- =============================================================================

function M.open_in_normal_win(file, lnum)
  local curr_win = api.nvim_get_current_win()
  local cur_buf = api.nvim_win_get_buf(curr_win)
  local ft = vim.bo[cur_buf].filetype
  local cfg = api.nvim_win_get_config(curr_win)
  
  if ft == "tree" or ft == "netrw" or cfg.relative ~= "" then
    vim.cmd("wincmd p")
    curr_win = api.nvim_get_current_win()
    cur_buf = api.nvim_win_get_buf(curr_win)
    ft = vim.bo[cur_buf].filetype
    cfg = api.nvim_win_get_config(curr_win)
    
    if ft == "tree" or ft == "netrw" or cfg.relative ~= "" then
      for _, w in ipairs(api.nvim_list_wins()) do
        local w_buf = api.nvim_win_get_buf(w)
        if api.nvim_win_get_config(w).relative == "" and vim.bo[w_buf].filetype ~= "tree" then
          api.nvim_set_current_win(w)
          goto found
        end
      end
      vim.cmd("vsplit")
    end
  end
  ::found::
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  if lnum then
    api.nvim_win_set_cursor(0, { tonumber(lnum), 0 })
    vim.cmd("normal! zz")
  end
end

return M
