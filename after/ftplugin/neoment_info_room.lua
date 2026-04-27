local buffer_id = vim.api.nvim_get_current_buf()
local util = require("neoment.util")
local room_info = require("neoment.room_info")

local opts = { noremap = true, silent = true, buffer = buffer_id }
local function set_opts_desc(desc)
	return vim.tbl_extend("force", opts, { desc = desc })
end

util.set_common_mappings(buffer_id)
local set_mapping = util.get_plug_mapping_setter("NeomentInfoRoom")

set_mapping("n", "<localleader>q", "Quit", "<cmd>bdelete<CR>", set_opts_desc("[Q]uit (close) info"))

set_mapping("n", "<localleader>a", "ToggleFavorite", function()
	room_info.toggle_favorite(buffer_id)
end, set_opts_desc("Toggle f[a]vorite status"))

set_mapping("n", "<localleader>l", "ToggleLowPriority", function()
	room_info.toggle_low_priority(buffer_id)
end, set_opts_desc("Toggle [l]ow priority status"))

set_mapping("n", "<localleader>d", "ToggleDirect", function()
	room_info.toggle_direct(buffer_id)
end, set_opts_desc("Toggle [d]irect message status"))

set_mapping("n", "<Tab>", "ToggleMembers", function()
	room_info.toggle_members(buffer_id)
end, set_opts_desc("Toggle members list"))

set_mapping("n", "<localleader>z", "ToggleZoomAvatar", function()
	room_info.toggle_avatar_zoom(buffer_id)
end, set_opts_desc("Toggle [z]oom avatar"))

vim.api.nvim_create_autocmd("BufReadCmd", {
	buffer = buffer_id,
	callback = function(ev)
		-- update room buffer context
		room_info.update_buffer(ev.buf)
		-- `:e` command also will clear treesitter highlight.
		vim.treesitter.start(ev.buf, "markdown")
	end,
})

vim.api.nvim_create_autocmd("BufDelete", {
	buffer = buffer_id,
	callback = function()
		room_info.cleanup_avatar(buffer_id)
	end,
})
