local M = {}

-- Visual mode mappings
vim.keymap.set("v", "<leader>ae", function()
  require("modules.ai.ui").explain_selection()
end, { desc = "AI Explain" })

vim.keymap.set("v", "<leader>ar", function()
  require("modules.ai.ui").refactor_selection()
end, { desc = "AI Refactor" })

-- Normal mode prompt
vim.keymap.set("n", "<leader>aa", function()
  local prompt = vim.fn.input("AI Prompt: ")
  if prompt ~= "" then
    vim.notify("🤖 AI is thinking...", vim.log.levels.INFO)
    require("utils.ai").generate(prompt, nil, function(response, err)
      if err then
        vim.notify("AI Error: " .. err, vim.log.levels.ERROR)
      else
        require("modules.ai.ui").show_response("AI Response", response)
      end
    end)
  end
end, { desc = "AI Prompt" })

return M
