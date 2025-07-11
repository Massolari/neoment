local buffer_id = vim.api.nvim_get_current_buf()
local room_id = vim.b.room_id

vim.bo.buftype = "nofile"
vim.bo.swapfile = false
vim.bo.modified = false
vim.wo.conceallevel = 2
vim.wo.wrap = true
vim.wo.foldmethod = "manual"
vim.wo.signcolumn = "no"

local neoment_room_ns = vim.api.nvim_get_namespaces()
for name, id in pairs(neoment_room_ns) do
	if name == "neoment_room" then
		vim.api.nvim_set_hl_ns(id)
		break
	end
end

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
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
	buffer = buffer_id,
	callback = function()
		vim.wo.number = false
		vim.wo.relativenumber = false
		vim.wo.conceallevel = 2
		vim.wo.cursorline = true
		vim.wo.breakindent = true
		vim.wo.breakindentopt = "shift:31,sbr"
		vim.wo.showbreak = string.rep(" ", 29) .. "│ "
		local winbar = require("neoment.matrix").get_room_name(room_id)
		local topic = require("neoment.matrix").get_room_topic(room_id)
		if topic ~= "" then
			winbar = winbar .. " - " .. topic
		end
		vim.api.nvim_set_option_value("winbar", winbar, { win = vim.api.nvim_get_current_win() })

		require("neoment.room").mark_read(buffer_id)
	end,
})
vim.wo.number = false
vim.wo.relativenumber = false

-- Destroy completely the buffer when closing
vim.api.nvim_create_autocmd("BufDelete", {
	buffer = buffer_id,
	callback = function()
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
vim.keymap.set("n", "<CR>", function()
	require("neoment.room").prompt_message()
end, opts)
vim.keymap.set("n", "<localleader>a", function()
	require("neoment.room").react_message()
end, vim.tbl_extend("error", opts, { desc = "Re[a]ct message" }))
vim.keymap.set("n", "<localleader>d", function()
	require("neoment.room").redact_message()
end, vim.tbl_extend("error", opts, { desc = "Re[d]act message" }))
vim.keymap.set("n", "<localleader>e", function()
	require("neoment.room").edit_message()
end, vim.tbl_extend("error", opts, { desc = "[E]dit message" }))
vim.keymap.set("n", "<localleader>f", function()
	require("neoment.rooms").pick()
end, vim.tbl_extend("error", opts, { desc = "[F]ind room" }))
vim.keymap.set("n", "<localleader>q", "<cmd>bdelete<CR>", vim.tbl_extend("error", opts, { desc = "[Q]uit room" }))
vim.keymap.set("n", "<localleader>l", function()
	require("neoment.rooms").toggle_room_list()
end, vim.tbl_extend("error", opts, { desc = "Toggle room [l]ist" }))
vim.keymap.set("n", "<localleader>o", function()
	require("neoment.room").open_attachment()
end, vim.tbl_extend("error", opts, { desc = "[O]pen attachment" }))
vim.keymap.set("n", "<localleader>p", function()
	require("neoment.room").load_more_messages()
end, vim.tbl_extend("error", opts, { desc = "Load [p]revious messages" }))
vim.keymap.set("n", "<localleader>r", function()
	require("neoment.room").reply_message()
end, vim.tbl_extend("error", opts, { desc = "[R]eply message" }))
vim.keymap.set("n", "<localleader>R", function()
	require("neoment.room").go_to_replied_message()
end, vim.tbl_extend("error", opts, { desc = "Go to [R]eplied message" }))
vim.keymap.set("n", "<localleader>s", function()
	require("neoment.room").save_attachment()
end, vim.tbl_extend("error", opts, { desc = "[S]ave attachment" }))
vim.keymap.set("n", "<localleader>u", function()
	require("neoment.room").upload_attachment()
end, vim.tbl_extend("error", opts, { desc = "[U]pload attachment" }))
vim.keymap.set("n", "<localleader>U", function()
	require("neoment.room").upload_image_from_clipboard()
end, vim.tbl_extend("error", opts, { desc = "[U]pload image from clipboard" }))
vim.keymap.set("n", "<localleader>w", function()
	require("neoment.room").forward_message()
end, vim.tbl_extend("error", opts, { desc = "For[w]ard message" }))
vim.keymap.set("n", "<localleader>z", function()
	require("neoment.room").toggle_image_zoom()
end, vim.tbl_extend("error", opts, { desc = "Toggle [z]oom image" }))
