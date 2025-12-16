local M = {}

function M.define_highlights()
	-- Definir grupos de highlight
	vim.api.nvim_set_hl(0, "NeomentRoomsTitle", { link = "@text.title.2.markdown" })
	vim.api.nvim_set_hl(0, "NeomentSectionTitle", { link = "Title" })
	vim.api.nvim_set_hl(0, "NeomentBufferRoom", { link = "@keyword" })
	vim.api.nvim_set_hl(0, "NeomentRoomUnread", { link = "Bold" })
	vim.api.nvim_set_hl(0, "NeomentBufferRoomUnread", { link = "@keyword" })
	vim.api.nvim_set_hl(0, "NeomentMention", { link = "ColorColumn" })
	vim.api.nvim_set_hl(0, "NeomentMentionUser", { link = "@comment.error" })
	vim.api.nvim_set_hl(0, "NeomentBubbleContent", { link = "ColorColumn" })
	vim.api.nvim_set_hl(0, "NeomentBubbleBorder", { link = "ColorColumn" })
	vim.api.nvim_set_hl(0, "NeomentBubbleActiveContent", { link = "IncSearch" })
	vim.api.nvim_set_hl(0, "NeomentBubbleActiveBorder", { link = "IncSearch" })

	local neoment_room_ns = vim.api.nvim_create_namespace("neoment_room")
	vim.api.nvim_set_hl(neoment_room_ns, "NonText", { link = "FloatBorder" })

	-- Apply bold to NeomentBufferRoom
	local hl_buffer_room_undead = vim.api.nvim_get_hl(0, { name = "NeomentBufferRoomUnread", link = false })
	if hl_buffer_room_undead then
		hl_buffer_room_undead.bold = true
		--- @diagnostic disable-next-line: param-type-mismatch
		vim.api.nvim_set_hl(0, "NeomentBufferRoomUnread", hl_buffer_room_undead)
	end

	-- Change the foreground with the background on NeomentBubbleBorder and NeomentBubbleActiveBorder
	for _, hl_name in ipairs({ "NeomentBubbleActiveBorder", "NeomentBubbleBorder" }) do
		local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
		if hl then
			local new_fg = hl.bg
			hl.bg = hl.fg
			hl.fg = new_fg
			--- @diagnostic disable-next-line: param-type-mismatch
			vim.api.nvim_set_hl(0, hl_name, hl)
		end
	end
end

return M
