-- Native Git Dashboard v2 (MVC Bridge)
local M = {}
local api = vim.api

-- Logic is now handled in modules/git/
function M.toggle()
  require("modules.git.controller").toggle()
end

function M.open()
  require("modules.git.controller").toggle()
end

-- =============================================================================
-- NATIVE GIT GUTTER (Signs) - Keep this here for global operation
-- =============================================================================

local ns_gutter = api.nvim_create_namespace("GitGutter")
local CONFIG = {
  signs = {
    added    = { text = "▎", hl = "GitSignsAdd" },
    changed  = { text = "▎", hl = "GitSignsChange" },
    removed  = { text = "", hl = "GitSignsDelete" },
  },
}

function M.update_gutter(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= "" then return end
  
  local file = api.nvim_buf_get_name(bufnr)
  if file == "" then return end

  vim.system({ "git", "diff", "--unified=0", "--no-color", "--", file }, { text = true }, function(obj)
    if obj.code ~= 0 then return end
    
    vim.schedule(function()
      if not api.nvim_buf_is_valid(bufnr) then return end
      api.nvim_buf_clear_namespace(bufnr, ns_gutter, 0, -1)
      
      local diff = obj.stdout
      if not diff or diff == "" then return end
      
      local hunks = {}
      for line in diff:gmatch("@@ %-%d+,?%d* %+(%d+),?(%d*) @@") do
        local start = tonumber(line:match("(%d+)"))
        local count = tonumber(line:match(",(%d+)") or 1)
        table.insert(hunks, { start = start, count = count })
      end

      for _, hunk in ipairs(hunks) do
        for i = 0, math.max(0, hunk.count - 1) do
          local lnum = hunk.start + i - 1
          api.nvim_buf_set_extmark(bufnr, ns_gutter, lnum, 0, {
            sign_text = CONFIG.signs.changed.text,
            sign_hl_group = CONFIG.signs.changed.hl,
            priority = 10,
          })
        end
      end
    end)
  end)
end

-- Setup autocmds for gutter
api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
  group = api.nvim_create_augroup("GitGutter", { clear = true }),
  callback = function(args) M.update_gutter(args.buf) end
})

return M
