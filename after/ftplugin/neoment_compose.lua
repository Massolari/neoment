local buf = vim.api.nvim_get_current_buf()

vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

vim.api.nvim_set_option_value("number", false, { win = 0 })
vim.api.nvim_set_option_value("relativenumber", false, { win = 0 })
vim.api.nvim_set_option_value("cursorline", true, { win = 0 })

-- Set up keybindings
local opts = { noremap = true, silent = true, buffer = buf }

-- Enter in normal mode to send
vim.keymap.set("n", "<CR>", function()
	require("neoment.room").send_and_close_compose(vim.api.nvim_get_current_buf())
end, opts)

-- Ctrl+S in insert mode to send
vim.keymap.set("i", "<C-s>", function()
	vim.cmd("stopinsert")
	require("neoment.room").send_and_close_compose(vim.api.nvim_get_current_buf())
end, opts)

-- Ctrl+C to cancel
vim.keymap.set({ "n", "i" }, "<C-c>", function()
	if vim.fn.mode() == "i" then
		vim.cmd("stopinsert")
	end

	local current_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(vim.b.room_win)
	vim.api.nvim_win_close(current_win, true)
end, opts)
