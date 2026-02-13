local picker = require("utils.picker")
local ui = require("utils.ui")
local icons = require("utils.icons")

local M = {}

function M.open()
  local params = { textDocument = vim.lsp.util.make_text_document_params() }
  
  vim.lsp.buf_request(0, "textDocument/documentSymbol", params, function(err, symbols, ctx)
    if err then return end
    if not symbols or #symbols == 0 then return end

    -- Flatten symbols (handle nested symbols)
    local flat_symbols = {}
    local function flatten(syms, parent_name)
      for _, s in ipairs(syms) do
        local name = parent_name and (parent_name .. "." .. s.name) or s.name
        table.insert(flat_symbols, {
          name = name,
          kind = s.kind,
          range = s.range or s.selectionRange,
          uri = ctx.params.textDocument.uri
        })
        if s.children then
          flatten(s.children, name)
        end
      end
    end
    flatten(symbols)

    local kind_map = {
      [1] = "File", [2] = "Module", [3] = "Namespace", [4] = "Package",
      [5] = "Class", [6] = "Method", [7] = "Property", [8] = "Field",
      [9] = "Constructor", [10] = "Enum", [11] = "Interface", [12] = "Function",
      [13] = "Variable", [14] = "Constant", [15] = "String", [16] = "Number",
      [17] = "Boolean", [18] = "Array", [19] = "Object", [20] = "Key",
      [21] = "Null", [22] = "EnumMember", [23] = "Struct", [24] = "Event",
      [25] = "Operator", [26] = "TypeParameter"
    }

    local p = picker.new({
      title = "Document Symbols",
      width_pct = 0.7,
      height_pct = 0.7,
      preview_pct = 0.6,
      on_start = function(self)
        self.state.items = flat_symbols
        self.state.filtered = flat_symbols
        self:render("")
      end,
      format_item = function(sym)
        local kind_name = kind_map[sym.kind] or "Unknown"
        local icon = icons.kind[kind_name] or "󰅩"
        return sym.name, icon, "Function"
      end,
      static_filter = function(items, query)
        if query == "" then return items end
        local filtered = {}
        for _, it in ipairs(items) do
          if it.name:lower():match(query:lower()) then
            table.insert(filtered, it)
          end
        end
        return filtered
      end,
      preview_item = function(sym, buf, win)
        local filepath = vim.uri_to_fname(sym.uri)
        ui.async_preview(filepath, buf, win, {
          lnum = sym.range.start.line + 1
        })
      end,
      on_select = function(sym)
        local row = sym.range.start.line + 1
        local col = sym.range.start.character
        api.nvim_win_set_cursor(0, { row, col })
        vim.cmd("normal! zz")
      end
    })
    
    p:start()
  end)
end

return M
