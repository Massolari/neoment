local buffer_id = vim.api.nvim_get_current_buf()
local util = require("neoment.util")

local opts = { noremap = true, silent = true, buffer = buffer_id }
local function set_opts_desc(desc)
	return vim.tbl_extend("force", opts, { desc = desc })
end

local set_mapping = util.get_plug_mapping_setter("NeomentInfoRoom")

set_mapping("n", "<localleader>f", "Find", function()
	require("neoment.rooms").pick()
end, set_opts_desc("[F]ind room"))
set_mapping("n", "<localleader>F", "FindOpen", function()
	require("neoment.rooms").pick_open()
end, set_opts_desc("[F]ind open room"))
set_mapping("n", "<localleader>l", "ToggleRoomList", function()
	require("neoment.rooms").toggle_room_list()
end, set_opts_desc("Toggle room [l]ist"))

vim.api.nvim_create_autocmd("BufReadCmd", {
	buffer = buffer_id,
	callback = function(ev)
		-- update room buffer context
		require("neoment.room_info").update_buffer(ev.buf)
		-- `:e` command also will clear treesitter highlight.
		vim.treesitter.start(ev.buf, "markdown")
	end,
})
