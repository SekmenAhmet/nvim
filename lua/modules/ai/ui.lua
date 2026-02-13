local ui = require("utils.ui")
local ai = require("utils.ai")
local api = vim.api

local M = {}

M.win = nil
M.buf = nil

function M.show_response(title, content)
  if M.win and api.nvim_win_is_valid(M.win) then
    api.nvim_win_close(M.win, true)
  end

  local lines = vim.split(content, "
")
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))
  
  M.buf, M.win = ui.create_centered_win({
    title = title,
    width_pct = 0.6,
    height = height,
    enter = true,
    filetype = "markdown"
  })

  api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.bo[M.buf].modifiable = false
  
  -- Keymaps to close
  local opts = { buffer = M.buf, silent = true }
  vim.keymap.set("n", "q", function() api.nvim_win_close(M.win, true) end, opts)
  vim.keymap.set("n", "<Esc>", function() api.nvim_win_close(M.win, true) end, opts)
end

function M.explain_selection()
  local start_pos = api.nvim_buf_get_mark(0, "<")
  local end_pos = api.nvim_buf_get_mark(0, ">")
  local lines = api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)
  local code = table.concat(lines, "
")
  
  vim.notify("🤖 AI is thinking...", vim.log.levels.INFO)
  ai.explain(code, function(response, err)
    if err then
      vim.notify("AI Error: " .. err, vim.log.levels.ERROR)
    else
      M.show_response("AI Explanation", response)
    end
  end)
end

function M.refactor_selection()
  local start_pos = api.nvim_buf_get_mark(0, "<")
  local end_pos = api.nvim_buf_get_mark(0, ">")
  local lines = api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)
  local code = table.concat(lines, "
")
  
  vim.notify("🤖 AI is refactoring...", vim.log.levels.INFO)
  ai.refactor(code, function(response, err)
    if err then
      vim.notify("AI Error: " .. err, vim.log.levels.ERROR)
    else
      M.show_response("AI Refactoring Suggestion", response)
    end
  end)
end

return M
