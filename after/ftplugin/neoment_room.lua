if vim.b.did_ftplugin then
	return
end
vim.b.did_ftplugin = true
local buffer_id = vim.api.nvim_get_current_buf()
local room_id = vim.b.room_id
local util = require("neoment.util")

vim.bo.buftype = "nofile"
vim.bo.swapfile = false
vim.bo.modified = false

vim.treesitter.start(buffer_id, "markdown")

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
	buffer = buffer_id,
	callback = function()
		local winbar = require("neoment.matrix").get_room_name(room_id)
		local topic = require("neoment.matrix").get_room_topic(room_id)
		local thread_root_id = vim.b[buffer_id].thread_root_id
		if thread_root_id then
			winbar = "🧵 Thread in " .. winbar
		elseif topic ~= "" then
			winbar = winbar .. " - " .. topic
		end
		vim.api.nvim_set_option_value("winbar", winbar, { win = vim.api.nvim_get_current_win() })

		require("neoment.room").mark_read(buffer_id)
	end,
})
vim.wo.number = false
vim.wo.relativenumber = false

-- avoid `:e` command clear buffer context and syntax highlight.
-- BufReadPre, BufRead and BufReadPost will not be triggered as the file does not exist.
-- this callback function will not be called when first time open the room.
-- because it is registered after creating the buffer for a room.
vim.api.nvim_create_autocmd("BufReadCmd", {
	buffer = buffer_id,
	callback = function(ev)
		-- update room buffer context
		require("neoment.room").update_buffer(ev.buf)
		-- `:e` command also will clear treesitter highlight.
		vim.treesitter.start(ev.buf, "markdown")
	end,
})

-- Destroy completely the buffer when closing
vim.api.nvim_create_autocmd("BufDelete", {
	buffer = buffer_id,
	callback = function()
		if vim.b[buffer_id].thread_root_id then
			return
		end
		vim.schedule(function()
			require("neoment.room").close(buffer_id, room_id)
		end)
	end,
})

vim.api.nvim_create_autocmd("CursorHold", {
	buffer = buffer_id,
	callback = function()
		require("neoment.room").handle_cursor_hold(buffer_id)
	end,
})

-- Mappings

local opts = { noremap = true, silent = true, buffer = buffer_id }
local function set_opts_desc(desc)
	return vim.tbl_extend("force", opts, { desc = desc })
end

local set_mapping = util.get_plug_mapping_setter("NeomentRoom")

set_mapping("n", "<CR>", "Compose", function()
	require("neoment.room").prompt_message()
end, opts)
set_mapping("n", "<localleader>a", "React", function()
	require("neoment.room").react_message()
end, set_opts_desc("Re[a]ct message"))
set_mapping("n", "<localleader>d", "Redact", function()
	require("neoment.room").redact_message()
end, set_opts_desc("Re[d]act message"))
set_mapping("n", "<localleader>e", "Edit", function()
	require("neoment.room").edit_message()
end, set_opts_desc("[E]dit message"))
set_mapping("n", "<localleader>f", "Find", function()
	require("neoment.rooms").pick()
end, set_opts_desc("[F]ind room"))
set_mapping("n", "<localleader>q", "Quit", "<cmd>bdelete<CR>", set_opts_desc("[Q]uit room"))
set_mapping("n", "<localleader>l", "ToggleRoomList", function()
	require("neoment.rooms").toggle_room_list()
end, set_opts_desc("Toggle room [l]ist"))
set_mapping("n", "<localleader>L", "Leave", function()
	require("neoment.room").leave_room()
end, set_opts_desc("[L]eave room"))
set_mapping("n", "<localleader>m", "SetReadMarker", function()
	require("neoment.room").set_read_mark()
end, set_opts_desc("Set read [m]arker"))
set_mapping("n", "<localleader>o", "OpenAttachment", function()
	require("neoment.room").open_attachment()
end, set_opts_desc("[O]pen attachment"))
set_mapping("n", "<localleader>p", "LoadPreviousMessages", function()
	require("neoment.room").load_more_messages()
end, set_opts_desc("Load [p]revious messages"))
set_mapping("n", "<localleader>r", "Reply", function()
	require("neoment.room").reply_message()
end, set_opts_desc("[R]eply message"))
set_mapping("n", "<localleader>R", "GoToReplied", function()
	require("neoment.room").go_to_replied_message()
end, set_opts_desc("Go to [R]eplied message"))
set_mapping("n", "<localleader>t", "OpenThread", function()
	require("neoment.room").open_thread()
end, set_opts_desc("Open [t]hread"))
set_mapping("n", "<localleader>s", "SaveAttachment", function()
	require("neoment.room").save_attachment()
end, set_opts_desc("[S]ave attachment"))
set_mapping("n", "<localleader>u", "UploadAttachment", function()
	require("neoment.room").upload_attachment()
end, set_opts_desc("[U]pload attachment"))
set_mapping("n", "<localleader>U", "UploadImageFromClipboard", function()
	require("neoment.room").upload_image_from_clipboard()
end, set_opts_desc("[U]pload image from clipboard"))
set_mapping("n", "<localleader>w", "Forward", function()
	require("neoment.room").forward_message()
end, set_opts_desc("For[w]ard message"))
set_mapping("n", "<localleader>z", "ToggleZoomImage", function()
	require("neoment.room").toggle_image_zoom()
end, set_opts_desc("Toggle [z]oom image"))
