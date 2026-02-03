-- Native Floating Search (Replace /)
-- Architecture: Floating Window + Realtime 'matchadd' & 'search'

local M = {}
local api = vim.api

-- State
local state = {
  buf = nil,
  win = nil,
  target_win = nil,
  ns_id = api.nvim_create_namespace("live_search"),
  original_cursor = nil,
  original_view = nil,
  match_id = nil,
  query = "",
}

local function clear_highlights()
  if state.target_win and api.nvim_win_is_valid(state.target_win) then
    api.nvim_win_call(state.target_win, function()
      if state.match_id then
        pcall(vim.fn.matchdelete, state.match_id)
        state.match_id = nil
      end
    end)
  end
end

local function highlight_and_search(query, direction)
  if not api.nvim_win_is_valid(state.target_win) then return end
  
  api.nvim_win_call(state.target_win, function()
    -- 1. Clear previous
    if state.match_id then pcall(vim.fn.matchdelete, state.match_id) state.match_id = nil end
    
    if query == "" then 
      -- Restore view if empty
      vim.fn.winrestview(state.original_view)
      return 
    end
    
    -- 2. Highlight all matches (Gray/Dim) using search pattern
    -- Note: We use 'Search' hl group.
    -- We use pcall because regex might be invalid while typing
    local ok, id = pcall(vim.fn.matchadd, "Search", query)
    if ok then state.match_id = id end

    -- 3. Move Cursor
    -- 'c' = accept match at cursor position
    -- 's' = do not move cursor (we handled this manually? no, let's let vim search)
    -- 'w' = wrap around
    local flags = "c"
    if direction == 1 then flags = "nw" end -- Just checking existence first? No, we want to jump.
    
    -- We always start search from ORIGINAL position for the first type-ahead
    -- BUT if we are pressing ENTER (Next), we search forward.
    
    if direction == 0 then
      -- Typing: Reset to start and search forward
      vim.fn.setpos(".", state.original_cursor)
      
      -- Smart Loop: Skip Comments
      local found = 0
      local attempt = 0
      while attempt < 50 do -- Safety limit
        found = vim.fn.search(query, "cW")
        if found == 0 then break end
        
        -- Check if match is inside a comment
        local syntax_group = vim.fn.synIDattr(vim.fn.synID(vim.fn.line("."), vim.fn.col("."), 1), "name")
        if not syntax_group:lower():match("comment") then
          break -- Valid match found
        end
        -- If comment, move cursor slightly and continue searching (remove 'c' flag to move forward)
        vim.fn.search(query, "W") 
        attempt = attempt + 1
      end
      
      if found > 0 then vim.cmd("normal! zz") end
      
    elseif direction == 1 then
      -- Enter: Search Next (with wrap and skip comments)
      local found = 0
      local attempt = 0
      while attempt < 50 do
        found = vim.fn.search(query, "w")
        if found == 0 then break end
        
        local syntax_group = vim.fn.synIDattr(vim.fn.synID(vim.fn.line("."), vim.fn.col("."), 1), "name")
        if not syntax_group:lower():match("comment") then
          break
        end
        attempt = attempt + 1
      end
      
      if found > 0 then vim.cmd("normal! zz") end
    end
  end)
end

function M.open()
  state.target_win = api.nvim_get_current_win()
  state.original_cursor = vim.fn.getpos(".")
  state.original_view = vim.fn.winsaveview()
  state.query = ""
  
  -- Create Floating Window (Top Center)
  local width = math.floor(vim.o.columns * 0.25)
  local col = math.floor((vim.o.columns - width) / 2)
  
  state.buf = api.nvim_create_buf(false, true)
  state.win = api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = 1,
    row = 2, -- Top, just below tabline
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Search ",
    title_pos = "center",
  })
  
  -- Styling
  vim.wo[state.win].winhl = "NormalFloat:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual"
  vim.bo[state.buf].buftype = "nofile"
  
  vim.cmd("startinsert")

  -- Event: Typing
  api.nvim_create_autocmd("TextChangedI", {
    buffer = state.buf,
    callback = function()
      local line = api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] or ""
      state.query = line
      highlight_and_search(line, 0)
    end
  })

  -- Action: Enter (Next Match)
  vim.keymap.set("i", "<CR>", function()
    highlight_and_search(state.query, 1)
  end, { buffer = state.buf })
  
  -- Action: Esc (Confirm & Close)
  vim.keymap.set({"i", "n"}, "<Esc>", function()
    -- Set the vim search register so 'n' works afterwards
    if state.query ~= "" then
      vim.fn.setreg("/", state.query)
      -- Also add to history
      vim.fn.histadd("search", state.query)
    end
    
    api.nvim_win_close(state.win, true)
    clear_highlights() -- Vim's native 'hlsearch' will take over if enabled
    vim.o.hlsearch = true
  end, { buffer = state.buf })

  -- Action: Ctrl+c (Cancel & Restore)
  vim.keymap.set({"i", "n"}, "<C-c>", function()
    api.nvim_win_close(state.win, true)
    clear_highlights()
    if state.target_win and api.nvim_win_is_valid(state.target_win) then
      api.nvim_win_call(state.target_win, function()
        vim.fn.winrestview(state.original_view)
      end)
    end
  end, { buffer = state.buf })
end

return M
