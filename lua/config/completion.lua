local M = {}

vim.opt.pumblend = 10
vim.opt.pumheight = 15

vim.api.nvim_set_hl(0, "Pmenu", { bg = "#1e1e1e", fg = "#d4d4d4" })
vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#073655", fg = "#ffffff", bold = true })
vim.api.nvim_set_hl(0, "PmenuSbar", { bg = "#2d2d2d" })
vim.api.nvim_set_hl(0, "PmenuThumb", { bg = "#569cd6" })
vim.api.nvim_set_hl(0, "CmpItemAbbr", { fg = "#d4d4d4" })
vim.api.nvim_set_hl(0, "CmpItemAbbrDeprecated", { fg = "#808080", strikethrough = true })
vim.api.nvim_set_hl(0, "CmpItemAbbrMatch", { fg = "#569cd6", bold = true })
vim.api.nvim_set_hl(0, "CmpItemKind", { fg = "#4ec9b0" })
vim.api.nvim_set_hl(0, "CmpItemMenu", { fg = "#6a9955", italic = true })

local Mappings = {}

function Mappings.setup()
  local function map(mode, lhs, rhs, opts)
    opts = opts or {}
    vim.keymap.set(mode, lhs, rhs, opts)
  end

  map("i", "<Up>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-p>"
    end
    return "<Up>"
  end, { expr = true, desc = "Previous completion or up" })
  map("i", "<Down>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-n>"
    end
    return "<Down>"
  end, { expr = true, desc = "Next completion or down" })
  map("i", "<CR>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-y>"
    end
    return "<CR>"
  end, { expr = true, desc = "Confirm completion" })
  map("i", "<Tab>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-n>"
    end
    return "<Tab>"
  end, { expr = true, desc = "Next completion or tab" })
  map("i", "<S-Tab>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-p>"
    end
    return "<S-Tab>"
  end, { expr = true, desc = "Previous completion or shift-tab" })
end

Mappings.setup()

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client.server_capabilities.completionProvider then
      vim.bo[event.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
    end
  end,
})

function M.test_completion()
  local has_lsp = false
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.server_capabilities.completionProvider then
      has_lsp = true
      print("LSP client avec completion: " .. client.name)
    end
  end
  if not has_lsp then
    print("Aucun LSP avec complétion trouvé")
  end
end

vim.api.nvim_create_user_command("TestLSP", function()
  M.test_completion()
end, {})

vim.keymap.set("n", "<leader>tl", function()
  M.test_completion()
end, { desc = "Test LSP completion" })

return M
