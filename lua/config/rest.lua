-- Refactored REST Client
-- This file is now a thin wrapper around the rest module.

local controller = require("modules.rest.controller")

local M = {}

M.toggle = function()
  controller.toggle()
end

M.open = M.toggle

-- Compatibility with existing winbar calls
M.get_resp_winbar = function()
  return require("modules.rest.view").get_resp_winbar()
end

return M
