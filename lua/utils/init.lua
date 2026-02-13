local M = {}

-- Export sub-modules for easy access via require("utils").module
M.ui = require("utils.ui")
M.process = require("utils.process")
M.icons = require("utils.icons")
M.state = require("core.state")

-- Bridge common UI functions to the top level for backward compatibility
M.create_centered_win = M.ui.create_centered_win
M.create_float = M.ui.create_float
M.create_dual_pane = M.ui.create_dual_pane
M.create_picker_layout = M.ui.create_picker_layout
M.layout_manager = M.ui.layout_manager
M.notify = M.ui.notify
M.async_preview = M.ui.async_preview
M.open_in_normal_win = M.ui.open_in_normal_win
M.setup_scroll_preview = M.ui.setup_scroll_preview
M.setup_auto_close = M.ui.setup_auto_close
M.setup_list_navigation = M.ui.setup_list_navigation
M.setup_redirect_input = M.ui.setup_redirect_input
M.cleanup_timers = M.ui.cleanup_timers
M.close_windows = M.ui.close_windows
M.lazy_require = M.ui.lazy_require
M.get_diagnostic_level = M.ui.get_diagnostic_level
M.setup_lsp_handlers = M.ui.setup_lsp_handlers

-- Setup global notify
vim.notify = M.ui.notify

return M
