-- Native Floating Cmdline (Replace :)
-- Architecture: Floating Window + vim.fn.getcompletion

local M = {}
local api = vim.api

-- State
local state = {
  buf = nil,
  win = nil,
  compl_win = nil,
  compl_buf = nil,
  original_guicursor = nil,
}

local function close_completion()
  if state.compl_win and api.nvim_win_is_valid(state.compl_win) then
    api.nvim_win_close(state.compl_win, true)
    state.compl_win = nil
  end
end

local function update_completion(cmd)
  -- Get native vim completion
  local items = vim.fn.getcompletion(cmd, "cmdline")
  
  if #items == 0 then
    close_completion()
    return
  end
  
  -- Limit items
  if #items > 10 then items = { unpack(items, 1, 10) } end
  
  if not state.compl_win or not api.nvim_win_is_valid(state.compl_win) then
    state.compl_buf = api.nvim_create_buf(false, true)
    local width = api.nvim_win_get_width(state.win)
    local row = 2 -- Below cmdline
    local col = api.nvim_win_get_config(state.win).col
    
    state.compl_win = api.nvim_open_win(state.compl_buf, false, {
      relative = "editor",
      width = width,
      height = #items,
      row = row + 1, -- +1 purely relative to editor? No, row is absolute from editor top
      -- Actually, easier to make it relative to the cmdline win if supported, but editor relative is safer for positioning
      row = 2 + 3, -- Cmdline is at row 2, height 1 + border 2 = 3 offset
      col = col[1], -- It returns an array sometimes? No, number.
      style = "minimal",
      border = "rounded",
    })
    vim.wo[state.compl_win].winhl = "NormalFloat:NormalFloat,FloatBorder:FloatBorder"
  else
    api.nvim_win_set_height(state.compl_win, #items)
  end
  
  api.nvim_buf_set_lines(state.compl_buf, 0, -1, false, items)
end

function M.open()
  state.original_guicursor = vim.o.guicursor
  
  -- Create Floating Window (Top Center)
  local width = math.floor(vim.o.columns * 0.25)
  local col = math.floor((vim.o.columns - width) / 2)
  
  state.buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(state.buf, 0, -1, false, {"  : "}) -- Padding with :
  
  state.win = api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = 1,
    row = 2,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Command ",
    title_pos = "center",
  })
  
  vim.wo[state.win].winhl = "NormalFloat:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual"
  vim.bo[state.buf].buftype = "nofile"
  
  vim.cmd("startinsert")
  vim.api.nvim_win_set_cursor(state.win, {1, 4}) -- Start after "  : "
  
  -- Enforce Padding and : on Type
  api.nvim_create_autocmd("TextChangedI", {
    buffer = state.buf,
    callback = function()
      local line = api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] or ""
      if not line:match("^  : ") then
         local content = line:gsub("^%s*:?%s*", "")
         local fixed = "  : " .. content
         api.nvim_buf_set_lines(state.buf, 0, 1, false, {fixed})
         vim.api.nvim_win_set_cursor(state.win, {1, #fixed})
      end
    end
  })
  
  -- Auto-close on leave
  api.nvim_create_autocmd("WinLeave", {
    buffer = state.buf,
    once = true,
    callback = function()
      M.close()
    end
  })

  -- Keymaps
  local opts = { buffer = state.buf }
  
  -- Execute
  vim.keymap.set("i", "<CR>", function()
    local line = api.nvim_buf_get_lines(state.buf, 0, 1, false)[1]
    local cmd = line:gsub("^  : ", "") -- Strip prefix
    M.close()
    if cmd and cmd ~= "" then
      -- Execute command and print output if any
      local ok, out = pcall(api.nvim_exec2, cmd, { output = true })
      if not ok then
        vim.notify(out, vim.log.levels.ERROR)
      elseif out and out.output ~= "" then
        vim.notify(out.output, vim.log.levels.INFO)
      end
    end
  end, opts)
  
  -- Close
  vim.keymap.set({"i", "n"}, "<Esc>", function() M.close() end, opts)
  vim.keymap.set({"i", "n"}, "<C-c>", function() M.close() end, opts)
  
  -- Simple Completion Trigger (Tab)
  -- This is a very basic "Show options" completion, not a full menu navigation
  -- For full native completion, it's complex. 
  -- Simplified: If tab, complete first match or show menu.
  vim.keymap.set("i", "<Tab>", function()
    local line = api.nvim_get_current_line()
    -- Native completion call
    local items = vim.fn.getcompletion(line, "cmdline")
    if #items > 0 then
      -- Very basic: just pick first one. 
      -- A full menu would require managing selection state.
      -- Let's try to be smart: if common prefix, complete it.
      local current = items[1]
      -- Replace current word? Or append?
      -- CMD line completion usually replaces the partial word.
      -- This is hard to get right 100% without 'wildmenu' logic.
      -- Alternative: Feed keys to real cmdline? No.
      
      -- Let's just complete the common prefix or the first item
      api.nvim_set_current_line(items[1])
      api.nvim_feedkeys(api.nvim_replace_termcodes("<End>", true, false, true), "n", false)
    end
  end, opts)
end

function M.close()
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  close_completion()
  vim.cmd("stopinsert")
end

return M
