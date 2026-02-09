local M = {}

-- Apparence du menu
vim.opt.completeopt = "menu,menuone,noinsert,noselect"
vim.opt.pumblend = 10
vim.opt.pumheight = 10

-- Auto-Trigger Logic (Intelligent Native Autocomplete)
local function check_trigger()
  if vim.bo.buftype ~= "" or vim.fn.pumvisible() ~= 0 then return end
  
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local col = cursor[2]
  local before = line:sub(1, col)
  
  -- 1. Trigger sur les membres (obj.prop, obj->prop, class:meth)
  local char_before = before:sub(-1)
  local is_member = char_before:match("[%.:%-]") -- Déclenche sur . : - (pour ->)
  
  -- 2. Trigger sur les mots (min 2 chars)
  local word_before = before:match("[%w_]+$") or ""
  local is_word = #word_before >= 2

  if is_member or is_word then
    -- Priorité à l'Omnifunc (LSP) si disponible
    local key = (vim.bo.omnifunc ~= "") and "<C-x><C-o>" or "<C-n>"
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "n", false)
  end
end

-- Timer Singleton (Optimisation GC)
-- On réutilise le même timer pour éviter les allocations répétées à chaque frappe
local completion_timer = nil
-- Protection Hot-Reload
local _reg_name = "_completion_timer_singleton"
if rawget(_G, _reg_name) then
  local old = rawget(_G, _reg_name)
  if not old:is_closing() then old:stop(); old:close() end
end

completion_timer = vim.uv.new_timer()
rawset(_G, _reg_name, completion_timer)

local completion_augroup = vim.api.nvim_create_augroup("NativeCompletion", { clear = true })

vim.api.nvim_create_autocmd("TextChangedI", {
  group = completion_augroup,
  callback = function()
    -- Debounce de 150ms
    completion_timer:stop()
    completion_timer:start(150, 0, vim.schedule_wrap(check_trigger))
  end
})

-- Cleanup timer on VimLeave
vim.api.nvim_create_autocmd("VimLeave", {
  group = completion_augroup,
  callback = function()
    if completion_timer and not completion_timer:is_closing() then
      completion_timer:stop()
      completion_timer:close()
    end
  end,
})

-- Mappings de navigation (Optimisés pour Neovim 0.10+)
vim.keymap.set("i", "<Tab>", function()
  return vim.fn.pumvisible() == 1 and "<C-n>" or "<Tab>"
end, { expr = true })

vim.keymap.set("i", "<S-Tab>", function()
  return vim.fn.pumvisible() == 1 and "<C-p>" or "<S-Tab>"
end, { expr = true })

vim.keymap.set("i", "<CR>", function()
  return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
end, { expr = true })

-- Snippets Natifs (Neovim 0.10+) : Navigation dans les placeholders
vim.keymap.set({ "i", "s" }, "<C-l>", function()
  if vim.snippet.active({ direction = 1 }) then
    vim.snippet.jump(1)
  end
end, { silent = true })

vim.keymap.set({ "i", "s" }, "<C-h>", function()
  if vim.snippet.active({ direction = -1 }) then
    vim.snippet.jump(-1)
  end
end, { silent = true })

return M