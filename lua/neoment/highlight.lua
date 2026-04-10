local M = {}

function M.define_highlights()
	vim.api.nvim_set_hl(0, "NeomentRoomsTitle", { link = "Title" })
	vim.api.nvim_set_hl(0, "NeomentHeaderDecoration", { link = "NonText" })
	vim.api.nvim_set_hl(0, "NeomentSectionTitle", { link = "Title" })
	vim.api.nvim_set_hl(0, "NeomentBufferRoom", { link = "@keyword" })
	vim.api.nvim_set_hl(0, "NeomentRoomUnread", { link = "Bold" })
	vim.api.nvim_set_hl(0, "NeomentBufferRoomUnread", { link = "@keyword" })
	vim.api.nvim_set_hl(0, "NeomentMention", { link = "ColorColumn" })
	vim.api.nvim_set_hl(0, "NeomentMentionUser", { link = "@comment.error" })
	vim.api.nvim_set_hl(0, "NeomentEmoticon", { link = "@markup.link" })
	vim.api.nvim_set_hl(0, "NeomentBubbleContent", { link = "ColorColumn" })
	vim.api.nvim_set_hl(0, "NeomentBubbleBorder", { link = "ColorColumn" })
	vim.api.nvim_set_hl(0, "NeomentBubbleActiveContent", { link = "IncSearch" })
	vim.api.nvim_set_hl(0, "NeomentBubbleActiveBorder", { link = "IncSearch" })

	-- Room list highlights
	vim.api.nvim_set_hl(0, "NeomentRoomIcon", { link = "Comment" })
	vim.api.nvim_set_hl(0, "NeomentRoomIconBuffer", { link = "@keyword" })
	vim.api.nvim_set_hl(0, "NeomentRoomIconUnread", { link = "@constant" })
	vim.api.nvim_set_hl(0, "NeomentRoomTime", { link = "Comment" })
	vim.api.nvim_set_hl(0, "NeomentNotificationDot", { link = "DiagnosticInfo" })
	vim.api.nvim_set_hl(0, "NeomentNotificationCircle", { link = "DiagnosticWarn" })
	vim.api.nvim_set_hl(0, "NeomentNotificationBell", { link = "DiagnosticError" })

	-- Last message highlights
	vim.api.nvim_set_hl(0, "NeomentLastMessageTree", { link = "NonText" })
	vim.api.nvim_set_hl(0, "NeomentLastMessageSender", { link = "@variable" })
	vim.api.nvim_set_hl(0, "NeomentLastMessage", { link = "Comment" })

	-- Tombstone (upgraded room) highlights
	vim.api.nvim_set_hl(0, "NeomentTombstone", { link = "WarningMsg" })

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
			local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
			local new_fg = hl.bg
			hl.bg = normal_hl.bg
			hl.fg = new_fg
			--- @diagnostic disable-next-line: param-type-mismatch
			vim.api.nvim_set_hl(0, hl_name, hl)
		end
	end
end

return M
