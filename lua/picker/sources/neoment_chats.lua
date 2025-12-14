-- Neoment chatting buffer picker.
-- require picker.nvim

local M = {}

M.get = function()
	local chatbufs = vim.tbl_filter(function(buf)
		return vim.startswith(vim.api.nvim_buf_get_name(buf), "neoment://room/!")
	end, vim.api.nvim_list_bufs())

    local icons = require('neoment.icon')

	local items = {}

	for _, buf in ipairs(chatbufs) do
		local room_name = require("neoment.matrix").get_room_name(vim.b[buf].room_id)
		table.insert(items, {
			str = icons.room .. ' ' .. room_name,
		})
	end

	return items
end

return M
