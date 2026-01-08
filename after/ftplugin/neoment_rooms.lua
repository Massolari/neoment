if vim.b.did_ftplugin then
	return
end
vim.b.did_ftplugin = true
local buffer_id = vim.api.nvim_get_current_buf()
local util = require("neoment.util")

vim.bo.buftype = "nofile"
vim.bo.swapfile = false

-- update rooms list buffer after :e command
vim.api.nvim_create_autocmd("BufReadCmd", {
	buffer = buffer_id,
	callback = function()
		require("neoment.rooms").update_room_list()
		vim.api.nvim_set_option_value("buflisted", false, { buf = buffer_id })
	end,
})

-- Window options

vim.api.nvim_create_autocmd("BufUnload", {
	group = vim.api.nvim_create_augroup("neoment_room_list", {}),
	buffer = buffer_id,
	callback = function(ev)
		for _, id in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(id) == ev.buf then
				vim.wo[id].winfixbuf = false
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
set_mapping("n", "<localleader>F", "PickOpen", function()
	require("neoment.rooms").pick_open()
end, set_opts_desc("[F]ind open room"))
set_mapping("n", "<localleader>l", "ToggleLowPriority", function()
	require("neoment.rooms").toggle_low_priority()
end, set_opts_desc("Toggle [L]ow priority"))
set_mapping("n", "<localleader>r", "ToggleRead", function()
	require("neoment.rooms").toggle_read()
end, set_opts_desc("Toggle [R]ead"))
