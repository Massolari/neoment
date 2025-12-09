if vim.b.did_ftplugin then
	return
end
vim.b.did_ftplugin = true
local buffer_id = vim.api.nvim_get_current_buf()
local util = require("neoment.util")

-- Destroy completely the buffer when closing
vim.api.nvim_create_autocmd("BufDelete", {
	buffer = buffer_id,
	callback = function()
		vim.schedule(function()
			require("neoment.space").close(buffer_id)
		end)
	end,
})
-- update rooms list buffer after :e command
vim.api.nvim_create_autocmd("BufReadCmd", {
	buffer = buffer_id,
	callback = function()
		util.buffer_write(buffer_id, { "Loading space..." }, 0, -1)
		require("neoment.space").open_space(vim.b.space_id)
	end,
})

local opts = { noremap = true, silent = true, buffer = buffer_id }
local function set_opts_desc(desc)
	return vim.tbl_extend("force", opts, { desc = desc })
end

local set_mapping = util.get_plug_mapping_setter("NeomentSpace")
set_mapping("n", "<CR>", "Enter", function()
	require("neoment.space").open_room_under_cursor()
end, opts)
set_mapping("n", "<localleader>f", "Find", function()
	require("neoment.rooms").pick()
end, set_opts_desc("[F]ind room"))
set_mapping("n", "<localleader>q", "Quit", "<cmd>bdelete<CR>", set_opts_desc("[Q]uit buffer"))
set_mapping("n", "<localleader>l", "ToggleRoomList", function()
	require("neoment.rooms").toggle_room_list()
end, set_opts_desc("Toggle room [l]ist"))
