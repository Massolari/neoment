local M = {}

local config = require("neoment.config")

--- Show a notification with Neoment prefix
--- @param msg string The message to display
--- @param level vim.log.levels The log level
local function notify(msg, level)
	vim.schedule(function()
		config.get().notifier("[Neoment] " .. msg, level)
	end)
end

--- Show a info notification
--- @param msg string The message to display
M.info = function(msg)
	notify(msg, vim.log.levels.INFO)
end

--- Show a warning notification
--- @param msg string The message to display
M.warning = function(msg)
	notify(msg, vim.log.levels.WARN)
end

--- Show an error notification
--- @param msg string The message to display
M.error = function(msg)
	notify(msg, vim.log.levels.ERROR)
end

--- Show a notification with options
--- Note: This function is run outside of vim.schedule, so be careful when using it in async contexts.
--- @param msg string The message to display
--- @param level vim.log.levels The log level
--- @param opts table Additional options for vim.notify
M.with_opts = function(msg, level, opts)
	return config.get().notifier("[Neoment] " .. msg, level, opts)
end

return M
