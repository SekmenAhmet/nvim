-- UI Window Component Library (Standardized)
-- Provides reusable window management utilities
-- Used by: finder.lua, grep.lua, search.lua, cmdline.lua, terminal.lua

local M = {}
local api = vim.api

-- Create a centered dual-pane window (list + preview)
-- Returns: { buf_list, win_list, buf_preview, win_preview }
function M.create_dual_pane(opts)
  opts = opts or {}
  local width_pct = opts.width_pct or 0.7
  local height_pct = opts.height_pct or 0.8
  local preview_width_pct = opts.preview_width_pct or 0.6
  local list_title = opts.list_title or " List "
  local preview_title = opts.preview_title or " Preview "
  local list_filetype = opts.list_filetype
  local preview_filetype = opts.preview_filetype

  local total_width = math.floor(vim.o.columns * width_pct)
  local total_height = math.floor(vim.o.lines * height_pct)
  local row = math.floor((vim.o.lines - total_height) / 2)
  local col = math.floor((vim.o.columns - total_width) / 2)
  local preview_width = math.floor(total_width * preview_width_pct)
  local list_width = total_width - preview_width - 2

  -- Create buffers
  local buf_list = api.nvim_create_buf(false, true)
  local buf_preview = api.nvim_create_buf(false, true)

  -- Set filetypes if provided
  if list_filetype then
    vim.bo[buf_list].filetype = list_filetype
  end
  if preview_filetype then
    vim.bo[buf_preview].filetype = preview_filetype
  end

  -- Create windows
  local win_list = api.nvim_open_win(buf_list, true, {
    relative = "editor",
    width = list_width,
    height = total_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. list_title .. " ",
  })

  local win_preview = api.nvim_open_win(buf_preview, false, {
    relative = "editor",
    width = preview_width,
    height = total_height,
    row = row,
    col = col + list_width + 2,
    style = "minimal",
    border = "rounded",
    title = " " .. preview_title .. " ",
  })

  -- Apply common styling
  M.apply_list_styling(win_list, buf_list)
  M.apply_preview_styling(win_preview, buf_preview)

  return {
    buf_list = buf_list,
    win_list = win_list,
    buf_preview = buf_preview,
    win_preview = win_preview,
  }
end

-- Apply standard styling to list window
function M.apply_list_styling(win, buf)
  vim.wo[win].cursorline = true
  vim.wo[win].winhl = "NormalFloat:Normal,CursorLine:Visual"
  vim.bo[buf].buftype = "nofile"
  vim.wo[win].cursorcolumn = false
  vim.wo[win].list = false
  vim.wo[win].wrap = false
end

-- Apply standard styling to preview window
function M.apply_preview_styling(win, buf)
  vim.wo[win].winhl = "NormalFloat:Normal"
  vim.bo[buf].buftype = "nofile"
  vim.wo[win].wrap = false
end

-- Setup scroll preview keymaps (C-d / C-u)
function M.setup_scroll_preview(state, buf_list)
  buf_list = buf_list or state.buf_list
  
  local function scroll_preview(direction)
    if state.win_preview and api.nvim_win_is_valid(state.win_preview) then
      api.nvim_win_call(state.win_preview, function()
        local key = direction > 0 and "<C-d>" or "<C-u>"
        vim.cmd("normal! " .. api.nvim_replace_termcodes(key, true, false, true))
      end)
    end
  end
  
  vim.keymap.set({"i", "n"}, "<C-d>", function() scroll_preview(1) end, { buffer = buf_list })
  vim.keymap.set({"i", "n"}, "<C-u>", function() scroll_preview(-1) end, { buffer = buf_list })
end

-- Setup auto-close: when list closes, close preview and cleanup
function M.setup_auto_close(state, opts)
  opts = opts or {}
  local on_close = opts.on_close

  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win_list),
    once = true,
    callback = function()
      -- Close preview window
      if state.win_preview and api.nvim_win_is_valid(state.win_preview) then
        api.nvim_win_close(state.win_preview, true)
      end
      
      -- Cleanup job handle if present
      if state.job_handle and not state.job_handle:is_closing() then
        state.job_handle:close()
      end
      
      -- Call custom cleanup if provided
      if on_close then
        on_close()
      end
    end,
  })
end

-- Close windows gracefully
function M.close_windows(state)
  if state.win_list and api.nvim_win_is_valid(state.win_list) then
    api.nvim_win_close(state.win_list, true)
  end
end

-- Create a simple centered floating window
function M.create_centered(opts)
  opts = opts or {}
  local width_pct = opts.width_pct or 0.25
  local height = opts.height
  local height_pct = opts.height_pct
  local title = opts.title or ""
  local row_offset = opts.row_offset or 2

  -- Calculate height
  if not height and height_pct then
    height = math.floor(vim.o.lines * height_pct)
  elseif not height then
    height = 1
  end

  local width = math.floor(vim.o.columns * width_pct)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = row_offset

  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title ~= "" and (" " .. title .. " ") or nil,
    title_pos = "center",
  })

  vim.wo[win].winhl = "NormalFloat:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual"
  vim.bo[buf].buftype = "nofile"

  return { buf = buf, win = win }
end

return M
