local M = {}

local constants = require("neoment.constants")
local util = require("neoment.util")
local matrix = require("neoment.matrix")

--- Opens the room info window for the given room ID.
--- @param room_id string The ID of the room to open info for.
--- @return number The buffer number of the room info window.
M.open_info = function(room_id)
	-- Check if the buffer already exists
	local existing_buffer = util.get_existing_buffer(function(buf)
		return vim.b[buf].room_id == room_id and vim.bo[buf].filetype == constants.INFO_ROOM_FILETYPE
	end)
	if existing_buffer then
		vim.api.nvim_set_current_buf(existing_buffer)
		M.update_buffer(existing_buffer)
		return existing_buffer
	end

	-- Create a new buffer for the room
	local buffer_name =
		string.format("neoment://room/info/%s/%s", room_id, matrix.get_room_display_name_with_space(room_id))
	local buffer_id = vim.api.nvim_create_buf(true, false) -- listed=true, scratch=false
	vim.api.nvim_buf_set_name(buffer_id, buffer_name)
	vim.b[buffer_id].room_id = room_id
	vim.bo[buffer_id].filetype = constants.INFO_ROOM_FILETYPE
	vim.api.nvim_set_current_buf(buffer_id)
	local win = vim.api.nvim_get_current_win()

	vim.wo[win][0].conceallevel = 2
	vim.wo[win][0].concealcursor = "n"
	vim.wo[win][0].wrap = true
	vim.wo[win][0].foldmethod = "manual"
	vim.wo[win][0].signcolumn = "no"
	vim.wo[win][0].number = false
	vim.wo[win][0].relativenumber = false

	vim.treesitter.start(buffer_id, "markdown")

	M.update_buffer(buffer_id)
	return buffer_id
end

--- Updates the content of the room info buffer.
--- @param buffer_id number The buffer number to update.
M.update_buffer = function(buffer_id)
	if not vim.api.nvim_buf_is_loaded(buffer_id) then
		return
	end
	local room_id = vim.b[buffer_id].room_id

	if not room_id then
		return
	end

	-- Get room information
	local room = matrix.has_room(room_id) and matrix.get_room(room_id) or matrix.get_invited_room(room_id)
	local lines = {}

	-- Header
	table.insert(lines, "# Room Information")
	table.insert(lines, "")

	-- Room name
	table.insert(lines, "**Name:** " .. matrix.get_room_display_name(room_id))
	table.insert(lines, "")

	-- Room ID
	table.insert(lines, "**Room ID:** " .. room_id)
	local room_link = "https://matrix.to/#/" .. vim.uri_encode(room_id)
	table.insert(lines, "**Room link:** " .. room_link)
	table.insert(lines, "")

	-- Topic/Description
	if room.topic and room.topic ~= "" then
		table.insert(lines, "**Topic:**")
		for _, line in ipairs(vim.split(room.topic, "\n")) do
			if line:match("%S") then
				table.insert(lines, line)
			end
		end
		table.insert(lines, "")
	end

	-- Space
	local space_name = matrix.get_space_name(room_id)
	if space_name then
		table.insert(lines, "**Space:** " .. space_name)
		table.insert(lines, "")
	end

	-- Room type
	local room_type = "Room"
	if matrix.is_space(room_id) then
		room_type = "Space"
	elseif room.is_direct then
		room_type = "Direct Message"
	end
	table.insert(lines, "**Type:** " .. room_type)
	table.insert(lines, "")

	table.insert(lines, string.format(" - [%s] Favorite", room.is_favorite and "x" or " "))
	table.insert(lines, string.format(" - [%s] Low Priority", room.is_lowpriority and "x" or " "))
	table.insert(lines, "")

	-- Members
	local members = matrix.get_room_members(room_id)
	local member_count = vim.tbl_count(members)
	table.insert(lines, string.format("**Members:** %d", member_count))
	table.insert(lines, "")

	-- List members
	if member_count > 0 then
		local member_list = {}
		for user_id, member_name in pairs(members) do
			table.insert(member_list, { user_id = user_id, display_name = member_name })
		end
		table.sort(member_list, function(a, b)
			return a.display_name:lower() < b.display_name:lower()
		end)

		for _, member in ipairs(member_list) do
			if member.display_name and member.display_name ~= member.user_id then
				table.insert(lines, string.format(" - %s (%s)", member.display_name, member.user_id))
			else
				table.insert(lines, string.format(" - %s", member.user_id))
			end
		end
		table.insert(lines, "")
	end

	-- Set buffer contents
	util.buffer_write(buffer_id, lines, 0, -1)
end

return M
