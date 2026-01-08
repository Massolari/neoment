local M = {}
local is_focused = true

M.setup = function()
	local focus_group = vim.api.nvim_create_augroup("NeomentFocus", { clear = true })

	vim.api.nvim_create_autocmd("FocusGained", {
		group = focus_group,
		callback = function()
			is_focused = true
		end,
	})

	vim.api.nvim_create_autocmd("FocusLost", {
		group = focus_group,
		callback = function()
			is_focused = false
		end,
	})
end

M.is_focused = function()
	return is_focused
end

return M
