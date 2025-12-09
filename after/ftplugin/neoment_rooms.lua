if vim.b.did_ftplugin then
	return
end
vim.b.did_ftplugin = true
local buffer_id = vim.api.nvim_get_current_buf()
local util = require("neoment.util")

vim.bo.buftype = "nofile"
vim.bo.swapfile = false

local old_number = vim.wo.number
local old_relativenumber = vim.wo.relativenumber
local old_cursorline = vim.wo.cursorline
vim.api.nvim_create_autocmd("BufWinLeave", {
	buffer = buffer_id,
	callback = function()
		vim.wo.number = old_number
		vim.wo.relativenumber = old_relativenumber
		vim.wo.cursorline = old_cursorline
	end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
	buffer = buffer_id,
	callback = function()
		vim.wo.number = false
		vim.wo.relativenumber = false
		vim.wo.cursorline = true
		vim.wo.winfixwidth = true
	end,
})

-- update rooms list buffer after :e command
vim.api.nvim_create_autocmd("BufReadCmd", {
	buffer = buffer_id,
	callback = function()
		require("neoment.rooms").update_room_list()
	end,
})

-- Window options

vim.api.nvim_create_autocmd("VimResized", {
	group = vim.api.nvim_create_augroup("neoment_room_list", {}),
	pattern = "*",
	callback = function()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buffer_id then
				-- Resize the window to the specified width
				vim.api.nvim_win_set_width(win, 50)
				break
			end
		end
	end,
})

-- Mappings
local opts = { noremap = true, silent = true, buffer = 0 }
local function set_opts_desc(desc)
	return vim.tbl_extend("force", opts, { desc = desc })
end

local set_mapping = util.get_plug_mapping_setter("NeomentRooms")
set_mapping("n", "<CR>", "Enter", function()
	require("neoment.rooms").open_selected_room()
end, opts)
set_mapping("n", "<Tab>", "ToggleFold", function()
	require("neoment.rooms").toggle_fold_at_cursor()
end, opts)
set_mapping("n", "q", "Close", function()
	require("neoment.rooms").toggle_room_list()
end, opts)
set_mapping("n", "<localleader>a", "ToggleFavorite", function()
	require("neoment.rooms").toggle_favorite()
end, set_opts_desc("Toggle F[a]vorite"))
set_mapping("n", "<localleader>f", "Pick", function()
	require("neoment.rooms").pick()
end, set_opts_desc("[F]ind room"))
set_mapping("n", "<localleader>l", "ToggleLowPriority", function()
	require("neoment.rooms").toggle_low_priority()
end, set_opts_desc("Toggle [L]ow priority"))
set_mapping("n", "<localleader>r", "ToggleRead", function()
	require("neoment.rooms").toggle_read()
end, set_opts_desc("Toggle [R]ead"))
