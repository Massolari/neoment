-- Neoment chatting buffer picker.
-- require picker.nvim

local M = {}
M.get = function()
	local chatbufs = vim.tbl_filter(function(buf)
		return vim.startswith(vim.api.nvim_buf_get_name(buf), "neoment://room/!")
			or vim.startswith(vim.api.nvim_buf_get_name(buf), "neoment://thread/")
	end, vim.api.nvim_list_bufs())

	local icons = require("neoment.icon")

	local items = {}

	for _, buf in ipairs(chatbufs) do
		local room_name = require("neoment.matrix").get_room_name(vim.b[buf].room_id)
		local display
		if vim.b[buf].thread_root_id then
			display = string.format("%s %s > Thread", icons.thread, room_name)
		else
			display = string.format("%s %s", icons.room, room_name)
		end
		table.insert(items, {
			str = display,
			value = {
				buf = buf,
			},
		})
	end

	return items
end

M.default_action = function(item)
	vim.api.nvim_win_set_buf(0, item.value.buf)
end

return M
