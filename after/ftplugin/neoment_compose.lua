local buf = vim.api.nvim_get_current_buf()
local util = require("neoment.util")

vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

vim.api.nvim_set_option_value("number", false, { win = 0 })
vim.api.nvim_set_option_value("relativenumber", false, { win = 0 })
vim.api.nvim_set_option_value("cursorline", true, { win = 0 })

-- Set up keybindings
local opts = { noremap = true, silent = true, buffer = buf }
local set_mapping = util.get_plug_mapping_setter("NeomentCompose")

-- Enter in normal mode to send
set_mapping("n", "<CR>", "Send", function()
	require("neoment.room").send_and_close_compose(vim.api.nvim_get_current_buf())
end, opts)

-- Ctrl+S in insert mode to send
set_mapping("i", "<C-s>", "SendInsert", function()
	vim.cmd("stopinsert")
	require("neoment.room").send_and_close_compose(vim.api.nvim_get_current_buf())
end, opts)

local function abort()
	local current_win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(vim.b.room_win)
	vim.api.nvim_win_close(current_win, true)
end

-- Ctrl+C to cancel
set_mapping("n", "<C-c>", "Abort", abort, opts)
set_mapping("i", "<C-c>", "AbortInsert", function()
	vim.cmd("stopinsert")
	abort()
end, opts)
