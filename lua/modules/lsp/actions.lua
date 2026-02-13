local picker = require("utils.picker")
local ui = require("utils.ui")

local M = {}

function M.open()
  local params = vim.lsp.util.make_range_params()
  params.context = { diagnostics = vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 }) }

  vim.lsp.buf_request(0, "textDocument/codeAction", params, function(err, actions, ctx)
    if err then 
      vim.notify("LSP Error: " .. tostring(err), vim.log.levels.ERROR)
      return 
    end
    
    if not actions or #actions == 0 then
      vim.notify("No code actions available", vim.log.levels.INFO)
      return
    end

    local p = picker.new({
      title = "Code Actions",
      width_pct = 0.5,
      height_pct = 0.4,
      preview_pct = 0, -- No preview needed for actions usually
      on_start = function(self)
        self.state.items = actions
        self.state.filtered = actions
        self:render("")
      end,
      format_item = function(action)
        local title = action.title or action.label or "Unknown action"
        return title, "󰌵", "DiagnosticInfo"
      end,
      static_filter = function(items, query)
        if query == "" then return items end
        local filtered = {}
        for _, it in ipairs(items) do
          local title = (it.title or it.label or ""):lower()
          if title:match(query:lower()) then
            table.insert(filtered, it)
          end
        end
        return filtered
      end,
      on_select = function(action)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        if not client then return end
        
        if action.edit or action.command then
          if action.edit then
            vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
          end
          if action.command then
            local command = type(action.command) == "table" and action.command or action
            client.exec_command(command)
          end
        else
          client.request("codeAction/resolve", action, function(err2, resolved_action)
            if err2 or not resolved_action then
              -- Fallback or error
              return
            end
            if resolved_action.edit then
              vim.lsp.util.apply_workspace_edit(resolved_action.edit, client.offset_encoding)
            end
            if resolved_action.command then
              client.exec_command(resolved_action.command)
            end
          end)
        end
      end
    })
    
    p:start()
  end)
end

return M
