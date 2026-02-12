-- Native Async Picker Engine
-- Abstracting the complexity of Dual Pane UI, Async Jobs, and Input handling

local M = {}
local uv = vim.uv
local api = vim.api
local utils = require("utils")
local icons = require("utils.icons")

local Picker = {}
Picker.__index = Picker

function M.new(opts)
  local self = setmetatable({}, Picker)
  self.opts = opts or {}

  -- Configuration
  self.title = opts.title or "Picker"
  self.batch_size = opts.batch_size or 100

  -- State
  self.state = {
    query = "",
    items = {},        -- Raw items (strings or objects)
    filtered = {},     -- Displayed items
    highlights = {},   -- Highlight definitions
    selection_idx = 1, -- Current selection index

    -- Handles
    buf_list = nil,
    win_list = nil,
    buf_preview = nil,
    win_preview = nil,
    job_handle = nil,

    -- Timers
    timer_debounce = uv.new_timer(),
    timer_preview = uv.new_timer(),
  }

  return self
end

function Picker:start()
  local layout = utils.create_picker_layout({
    title = " " .. self.title .. " ",
    width_pct = self.opts.width_pct or 0.8,
    height_pct = self.opts.height_pct or 0.8,
    preview_pct = self.opts.preview_pct or 0.5,
  })

  self.state.buf_list = layout.list.buf
  self.state.win_list = layout.list.win
  self.state.buf_preview = layout.preview.buf
  self.state.win_preview = layout.preview.win

  -- Setup Interactions
  self:setup_keymaps()
  self:setup_autocmds()

  -- Initial Render
  self:render("")
  vim.cmd("startinsert")

  -- Kickoff Data Source
  if self.opts.on_start then
    self.opts.on_start(self)
  end
end

function Picker:close()
  -- Cleanup Timers
  if self.state.timer_debounce then
    self.state.timer_debounce:stop()
    self.state.timer_debounce:close()
  end
  if self.state.timer_preview then
    self.state.timer_preview:stop()
    self.state.timer_preview:close()
  end

  -- Cleanup Job
  if self.state.job_handle and not self.state.job_handle:is_closing() then
    self.state.job_handle:close()
  end

  -- Cleanup Windows
  if self.state.win_list and api.nvim_win_is_valid(self.state.win_list) then
    api.nvim_win_close(self.state.win_list, true)
  end

  -- Callback
  if self.opts.on_close then self.opts.on_close() end
end

-- =============================================================================
-- RENDERING & DISPLAY
-- =============================================================================

function Picker:render(query)
  if not api.nvim_buf_is_valid(self.state.buf_list) then return end

  local display_lines = {}
  local highlights = {}
  local padding = "  "

  -- 1. Input Line & Header
  table.insert(display_lines, padding .. query)
  table.insert(display_lines, padding .. string.rep("─", api.nvim_win_get_width(self.state.win_list) - 4))

  -- 2. Process Items
  -- If static mode, filter self.state.items
  -- If dynamic mode, items are already filtered/provided by job

  local items_to_show = self.state.filtered
  if self.opts.static_filter then
    items_to_show = self.opts.static_filter(self.state.items, query)
    self.state.filtered = items_to_show -- Update filtered state for selection
  end

  if #items_to_show == 0 then
    if #display_lines < 5 then table.insert(display_lines, padding .. "-- No results --") end
  else
    for i, item in ipairs(items_to_show) do
      if i > 500 then break end -- Hard limit for rendering speed

      -- Format Item
      local text, icon, hl_group
      if self.opts.format_item then
        text, icon, hl_group = self.opts.format_item(item)
      else
        text = tostring(item)
      end

      local line_str = padding .. (icon and (icon .. " ") or "") .. text
      table.insert(display_lines, line_str)

      -- Add Highlight
      if icon and hl_group then
        local row = i + 1 -- Header is 2 lines, + 0-based index offset?
        -- Header (2 lines) -> index 1,2. Item 1 is line 3.
        -- Lua lines 1-based. Item 1 is at line 3.
        -- nvim_buf_add_highlight row is 0-based. Item 1 is row 2.
        local h_row = i + 1
        local col_start = #padding
        local col_end = col_start + #icon
        table.insert(highlights, { row = h_row, col_start = col_start, col_end = col_end, hl = hl_group })
      end
    end
  end

  -- 3. Write Buffer
  api.nvim_buf_set_lines(self.state.buf_list, 0, -1, false, display_lines)

  -- 4. Apply Highlights
  local ns = api.nvim_create_namespace("PickerHL")
  api.nvim_buf_clear_namespace(self.state.buf_list, ns, 0, -1)
  for _, h in ipairs(highlights) do
    api.nvim_buf_add_highlight(self.state.buf_list, ns, h.hl, h.row, h.col_start, h.col_end)
  end

  -- 5. Restore Cursor (Input Mode)
  if api.nvim_get_mode().mode == 'i' then
    api.nvim_win_set_cursor(self.state.win_list, {1, #padding + #query})
  end

  -- 6. Trigger Preview
  self:update_preview()
end

-- =============================================================================
-- LOGIC & EVENTS
-- =============================================================================

function Picker:update_preview()
  local cursor = api.nvim_win_get_cursor(self.state.win_list)
  local row = cursor[1]
  local idx = row - 2 -- Header offset

  if idx < 1 then idx = 1 end
  local item = self.state.filtered[idx]

  if item and self.opts.preview_item then
    -- Debounce preview
    self.state.timer_preview:stop()
    self.state.timer_preview:start(10, 0, vim.schedule_wrap(function()
       self.opts.preview_item(item, self.state.buf_preview, self.state.win_preview)
    end))
  else
    api.nvim_buf_set_lines(self.state.buf_preview, 0, -1, false, {})
  end
end

function Picker:setup_keymaps()
  local opts = { buffer = self.state.buf_list }

  -- Close
  vim.keymap.set({"i", "n"}, "<Esc>", function() self:close() end, opts)

  -- Confirm
  vim.keymap.set({"i", "n"}, "<CR>", function()
    local cursor = api.nvim_win_get_cursor(self.state.win_list)
    local idx = math.max(1, cursor[1] - 2)
    local item = self.state.filtered[idx]
    if item and self.opts.on_select then
      self:close()
      self.opts.on_select(item)
    end
  end, opts)

  -- Navigation
  local move = function(dir)
    local cur = api.nvim_win_get_cursor(self.state.win_list)
    local target = cur[1] + dir
    local max = math.max(3, 2 + #self.state.filtered)
    if target < 3 then target = 3 end -- Skip header
    if target > max then target = max end

    if target <= max and target >= 3 then
      api.nvim_win_set_cursor(self.state.win_list, {target, 0})
      self:update_preview()
    end
  end

  vim.keymap.set({"i", "n"}, "<Down>", function() move(1) end, opts)
  vim.keymap.set({"i", "n"}, "<Up>", function()
    local cur = api.nvim_win_get_cursor(self.state.win_list)
    if cur[1] <= 3 then
      -- Go to input
      api.nvim_win_set_cursor(self.state.win_list, {1, 0})
      vim.cmd("startinsert")
      local line = api.nvim_buf_get_lines(self.state.buf_list, 0, 1, false)[1]
      api.nvim_win_set_cursor(self.state.win_list, {1, #line})
    else
      move(-1)
    end
  end, opts)

  -- Scroll Preview
  vim.keymap.set({"i", "n"}, "<C-d>", function()
    api.nvim_win_call(self.state.win_preview, function() vim.cmd("normal! 20j") end)
  end, opts)
  vim.keymap.set({"i", "n"}, "<C-u>", function()
    api.nvim_win_call(self.state.win_preview, function() vim.cmd("normal! 20k") end)
  end, opts)

  -- Input Redirect
  self:setup_input_redirect()
end

function Picker:setup_input_redirect()
   -- Similar to utils.setup_redirect_input but bound to instance
   local function redirect(key)
    local line = api.nvim_buf_get_lines(self.state.buf_list, 0, 1, false)[1]
    api.nvim_win_set_cursor(self.state.win_list, {1, #line})
    vim.cmd("startinsert")
    if key then
      local k = api.nvim_replace_termcodes(key, true, false, true)
      api.nvim_feedkeys(k, "n", true)
    end
   end

   local opts = { buffer = self.state.buf_list }
   for i = 32, 126 do
    local char = string.char(i)
    vim.keymap.set("n", char, function() redirect(char) end, opts)
   end
   vim.keymap.set("n", "<BS>", function() redirect("<BS>") end, opts)
end

function Picker:setup_autocmds()
  -- Input Change
  api.nvim_create_autocmd("TextChangedI", {
    buffer = self.state.buf_list,
    callback = function()
      local cursor = api.nvim_win_get_cursor(self.state.win_list)
      if cursor[1] == 1 then
        local line = api.nvim_buf_get_lines(self.state.buf_list, 0, 1, false)[1]
        local query = line:gsub("^%s+", "")
        self.state.query = query

        if self.opts.on_change then
          -- Dynamic Debounce
          self.state.timer_debounce:stop()
          self.state.timer_debounce:start(self.opts.debounce or 20, 0, vim.schedule_wrap(function()
             self.opts.on_change(query, self)
          end))
        else
          -- Static Rerender
          self:render(query)
        end
      end
    end
  })

  -- Auto Close on WinLeave/Closed
  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(self.state.win_list),
    once = true,
    callback = function() self:close() end
  })
end

-- =============================================================================
-- ASYNC HELPERS
-- =============================================================================

function Picker:spawn(cmd, args, on_data, on_exit)
  if self.state.job_handle and not self.state.job_handle:is_closing() then
    self.state.job_handle:close()
  end

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)

  self.state.job_handle = uv.spawn(cmd, {
    args = args,
    stdio = { nil, stdout, stderr },
  }, function(code, signal)
    stdout:read_stop()
    stderr:read_stop()
    stdout:close()
    stderr:close()
    if self.state.job_handle and not self.state.job_handle:is_closing() then
       self.state.job_handle:close()
    end
    if on_exit then on_exit(code) end
  end)

  local buffer = ""
  stdout:read_start(function(err, data)
    if err then return end
    if data then
      buffer = buffer .. data
      local lines = vim.split(buffer, "\n")
      buffer = lines[#lines]
      lines[#lines] = nil

      vim.schedule(function() on_data(lines) end)
    end
  end)
end

return M
