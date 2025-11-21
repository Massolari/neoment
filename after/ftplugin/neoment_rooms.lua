local buffer_id = vim.api.nvim_get_current_buf()

vim.api.nvim_set_option_value("buftype", "nofile", { buf = 0 })
vim.api.nvim_set_option_value("swapfile", false, { buf = 0 })
vim.api.nvim_set_option_value("modified", false, { buf = 0 })

local old_number = vim.wo.number
local old_relativenumber = vim.wo.relativenumber
local old_cursorline = vim.wo.cursorline
vim.api.nvim_create_autocmd("BufLeave", {
	buffer = buffer_id,
	callback = function()
		vim.wo.number = old_number
		vim.wo.relativenumber = old_relativenumber
		vim.wo.cursorline = old_cursorline
	end,
})
vim.api.nvim_create_autocmd("BufEnter", {
	buffer = buffer_id,
	callback = function()
		vim.wo.number = false
		vim.wo.relativenumber = false
		vim.wo.cursorline = true
	end,
})
vim.wo.number = false
vim.wo.relativenumber = false
vim.wo.cursorline = true

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
vim.keymap.set("n", "<CR>", function()
	require("neoment.rooms").open_selected_room()
end, opts)
vim.keymap.set("n", "<Tab>", function()
	require("neoment.rooms").toggle_fold_at_cursor()
end, opts)
vim.keymap.set("n", "q", function()
	require("neoment.rooms").toggle_room_list()
end, opts)
vim.keymap.set("n", "<localleader>a", function()
	require("neoment.rooms").toggle_favorite()
end, set_opts_desc("Toggle F[a]vorite"))
vim.keymap.set("n", "<localleader>f", function()
	require("neoment.rooms").pick()
end, set_opts_desc("[F]ind room"))
vim.keymap.set("n", "<localleader>l", function()
	require("neoment.rooms").toggle_low_priority()
end, set_opts_desc("Toggle [L]ow priority"))
vim.keymap.set("n", "<localleader>r", function()
	require("neoment.rooms").toggle_read()
end, set_opts_desc("Toggle [R]ead"))
vim.keymap.set("n", "<localleader>s", function()
	require("neoment").sync_start()
end, set_opts_desc("[S]ync rooms"))
