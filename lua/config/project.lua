local M = {}

function M.toggle()
  require("modules.project.controller").toggle()
end

function M.add()
  require("modules.project.controller").add_current()
end

-- Commands
vim.api.nvim_create_user_command("Project", M.toggle, {})
vim.api.nvim_create_user_command("ProjectAdd", M.add, {})

-- Auto-save session on exit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    local cwd = vim.fn.getcwd()
    require("utils.session").save(cwd)
  end
})

-- Keymaps
vim.keymap.set("n", "<leader>pp", M.toggle, { desc = "Project Picker" })
vim.keymap.set("n", "<leader>pa", M.add, { desc = "Add Project" })

return M
