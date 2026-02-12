-- Bridge for the refactored Docker module
-- Follows MVC + Async patterns
local M = {}

function M.toggle()
  require("modules.docker.controller").toggle()
end

return M
