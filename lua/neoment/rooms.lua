local M = {}

local api = vim.api
local sync = require("neoment.sync")
local matrix = require("neoment.matrix")
local util = require("neoment.util")
local error = require("neoment.error")

local room_list_buffer_name = "neoment://rooms"
local buffer_id = nil
--- @alias neoment.rooms.Section "invited" | "buffers" | "favorites" | "people" | "rooms" | "low_priority"

--- @type table<neoment.rooms.Section, boolean>
local room_list_fold_state = {
	invited = false,
	buffers = false,
	favorites = false,
	people = false,
	rooms = false,
	low_priority = false,
}

--- @type table<neoment.rooms.Section, string>
local sections = {
	invited = "Invited",
	buffers = "Buffers",
	favorites = "Favorites",
	people = "People",
	rooms = "Rooms",
	low_priority = "Low priority",
}
local window_width = 50

--- Format the last synchronization time
--- @return string Formatted last synchronization time
local function format_last_sync_time()
	local sync_status = sync.get_status()
	if sync_status.kind == "never" then
		return "No sync yet"
	end
	return tostring(os.date("%H:%M:%S", sync_status.last_sync))
end

--- Join a room by its ID
local function open_room(room_id)
	-- If the current buffer is the room list buffer
	local current_buf = api.nvim_get_current_buf()
	if current_buf == buffer_id then
		-- If this is the only window, create a new one
		if #vim.api.nvim_list_wins() == 1 then
			vim.cmd("vsplit")
		end
		vim.api.nvim_win_set_width(0, window_width)

		-- Move the cursor to the right window
		vim.cmd("wincmd l")
	end

	require("neoment.room").open_room(room_id)
end

--- Handle invited rooms
--- @param room_id string The ID of the room
local function handle_invited_room(room_id)
	local room_name = matrix.get_room_display_name(room_id)

	local answer = vim.fn.confirm(
		"You have been invited to join the room: " .. room_name,
		"&Join\n&Reject\n&Cancel",
		1,
		"Question"
	)

	if answer == 0 or answer == 3 then
		return
	end

	if answer == 1 then
		matrix.join_room(room_id, function(response)
			error.match(response, function()
				vim.schedule(function()
					open_room(room_id)
				end)
				return nil
			end, function(err)
				vim.notify("Error joining room: " .. err.error, vim.log.levels.ERROR)
			end)
		end)
		return
	end
	matrix.leave_room(room_id, function(response)
		error.match(response, function()
			vim.notify("Left room: " .. room_name, vim.log.levels.INFO)
			return nil
		end, function(err)
			vim.notify("Error leaving room: " .. err.error, vim.log.levels.ERROR)
		end)
	end)
end

--- Join the selected room
M.open_selected_room = function()
	local cursor = api.nvim_win_get_cursor(0)
	local current_line = cursor[1] -- 1-based, current line where the cursor is

	-- Check if the current line corresponds to a room
	if M.room_list_extmarks then
		for _, mark in ipairs(M.room_list_extmarks) do
			if mark.line == current_line then
				if mark.is_invited then
					handle_invited_room(mark.room_id)
					return
				end
				open_room(mark.room_id)
				return
			end
		end
	end

	vim.notify("No room found on this line. Position the cursor directly over the room name.", vim.log.levels.INFO)
end

--- Toggle the section fold at the cursor position
M.toggle_fold_at_cursor = function()
	local cursor = api.nvim_win_get_cursor(0)
	local current_line = cursor[1] -- 1-based, linha atual onde o cursor está

	local section = nil
	if M.room_section_lines then
		for section_name, _ in pairs(M.room_section_lines) do
			if current_line == M.room_section_lines[section_name] then
				section = section_name
				break
			end
		end
	end

	if section then
		room_list_fold_state[section] = not room_list_fold_state[section]

		-- Atualizar o símbolo de expansão no próprio buffer
		local current_line_text = api.nvim_buf_get_lines(0, current_line - 1, current_line, false)[1]
		local new_symbol = room_list_fold_state[section] and "" or ""
		local new_line = new_symbol .. current_line_text:sub(2)
		util.buffer_write(0, { new_line }, current_line - 1, current_line)

		M.update_room_list()
	else
		vim.notify("No section found on this line. Position the cursor over a section title.", vim.log.levels.INFO)
	end
end

--- Create a new buffer for the room list
local function create_room_list()
	buffer_id = api.nvim_create_buf(false, false) -- listed=false, scratch=false
	api.nvim_buf_set_name(buffer_id, room_list_buffer_name)
	api.nvim_set_option_value("filetype", "neoment_rooms", { buf = buffer_id })
	api.nvim_set_option_value("buftype", "nofile", { buf = buffer_id })
	api.nvim_set_current_buf(buffer_id)

	M.update_room_list()
end

--- Show the room list buffer
--- If the buffer is already open, update the room list
--- If not, create a new buffer
M.toggle_room_list = function()
	-- Close the room list if it's already open
	for _, win in ipairs(api.nvim_list_wins()) do
		if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buffer_id then
			api.nvim_win_close(win, false)
			return
		end
	end

	vim.cmd("topleft vsplit")
	local new_win = api.nvim_get_current_win()
	api.nvim_win_set_width(new_win, window_width)

	if buffer_id and api.nvim_buf_is_loaded(buffer_id) then
		api.nvim_set_current_buf(buffer_id)
		M.update_room_list()
		return
	end

	create_room_list()
end

--- Get the icon for the section
--- @param section neoment.rooms.Section The section name
local function get_section_icon(section)
	return room_list_fold_state[section] and "" or ""
end

--- Get the line for a room
--- @param room neoment.matrix.client.Room|neoment.matrix.client.InvitedRoom The room object
--- @return string The formatted line for the room
local function get_room_line(room)
	local last_activity = matrix.get_room_last_activity(room.id)
	local display = matrix.get_room_display_name(room.id)

	if last_activity and last_activity > 0 then
		local time = os.date("%H:%M", math.floor(last_activity / 1000))
		display = display .. " [" .. time .. "]"
		if room.unread_highlights and room.unread_highlights > 0 then
			display = display .. " 🔔"
		elseif room.unread_notifications and room.unread_notifications > 0 then
			display = display .. " ⏺"
		end
	end

	return display
end

--- Update the room list buffer
M.update_room_list = function()
	if not buffer_id or not api.nvim_buf_is_loaded(buffer_id) then
		return
	end

	local sync_status = sync.get_status()
	if sync_status.kind == "never" then
		util.buffer_write(buffer_id, { "No sync yet" }, 0, -1)
		return
	elseif sync_status.kind == "syncing" and sync_status.last_sync == nil then
		util.buffer_write(buffer_id, { "Syncing..." }, 0, -1)
		return
	end

	---@type table<neoment.rooms.Section, table<neoment.matrix.client.Room>>
	local section_rooms = {
		invited = {},
		buffers = {},
		favorites = {},
		people = {},
		rooms = {},
		low_priority = {},
	}

	local open_buffers = vim.tbl_filter(function(buf)
		return api.nvim_buf_is_loaded(buf)
	end, api.nvim_list_bufs())

	for _, room in pairs(matrix.get_invited_rooms()) do
		table.insert(section_rooms.invited, room)
	end

	-- Categorize rooms
	for id, room in pairs(matrix.get_rooms()) do
		-- Check if the room is open in a buffer
		for _, buf in ipairs(open_buffers) do
			if vim.b[buf].room_id == id then
				table.insert(section_rooms.buffers, room)
				goto continue
			end
		end

		if room.is_favorite then
			table.insert(section_rooms.favorites, room)
		elseif room.is_direct then
			table.insert(section_rooms.people, room)
		elseif room.is_lowpriority then
			table.insert(section_rooms.low_priority, room)
		else
			table.insert(section_rooms.rooms, room)
		end
		::continue::
	end

	--- Sort rooms by last activity
	--- @param a neoment.matrix.client.Room The first room
	--- @param b neoment.matrix.client.Room The second room
	--- @return boolean True if the first room is more recent than the second
	local sort_by_activity = function(a, b)
		return (a.last_activity or 0) > (b.last_activity or 0)
	end

	-- Sort by activity (most recent first)
	table.sort(section_rooms.buffers, sort_by_activity)
	table.sort(section_rooms.favorites, sort_by_activity)
	table.sort(section_rooms.people, sort_by_activity)
	table.sort(section_rooms.rooms, sort_by_activity)
	table.sort(section_rooms.low_priority, sort_by_activity)

	-- Montar a lista
	local lines = {
		"Rooms - Last sync: " .. format_last_sync_time(),
		"",
	}
	--- @class neoment.rooms.RoomMark
	--- @field line number
	--- @field room_id string
	--- @field is_buffer boolean
	--- @field is_invited boolean
	--- @field has_unread boolean

	--- @type table<neoment.rooms.RoomMark>
	local extmarks = {}
	local line_index = 3 -- Starting from the 3rd line

	--- @type table<neoment.rooms.Section, number>
	local section_lines = {}
	--- @type table<neoment.rooms.Section>
	local section_list = {
		"favorites",
		"people",
		"rooms",
		"low_priority",
	}

	if #section_rooms.buffers > 0 then
		table.insert(section_list, 1, "buffers")
	end

	if #section_rooms.invited > 0 then
		table.insert(section_list, 1, "invited")
	end

	for index, section in ipairs(section_list) do
		local icon = get_section_icon(section)
		table.insert(lines, string.format("%s %s (%d)", icon, sections[section], #section_rooms[section]))
		section_lines[section] = line_index
		line_index = line_index + 1

		if not room_list_fold_state[section] then
			for _, r in ipairs(section_rooms[section]) do
				--- @type neoment.matrix.client.Room
				local room = r

				local display = get_room_line(room)

				table.insert(lines, "  " .. display)
				--- @type neoment.rooms.RoomMark
				local extmark = {
					line = line_index,
					room_id = room.id,
					is_buffer = section == "buffers",
					is_invited = section == "invited",
					has_unread = (room.unread_notifications and room.unread_notifications > 0)
						or (room.unread_highlights and room.unread_highlights > 0),
				}
				table.insert(extmarks, extmark)
				line_index = line_index + 1
			end
		end

		if index < #section_list then
			table.insert(lines, "")
			line_index = line_index + 1
		end
	end

	util.buffer_write(buffer_id, lines, 0, -1)

	M.room_list_extmarks = extmarks
	M.room_section_lines = section_lines

	local ns_id = api.nvim_create_namespace("neoment_room_list")
	api.nvim_buf_clear_namespace(buffer_id, ns_id, 0, -1)

	vim.hl.range(buffer_id, ns_id, "Title", { 0, 0 }, { 0, -1 })

	-- Highlight the section titles
	for _, section in ipairs(section_list) do
		local line = section_lines[section]
		vim.hl.range(buffer_id, ns_id, "NeomentSectionTitle", { line - 1, 0 }, { line - 1, -1 })
	end

	-- Highlight the room lines
	for _, m in ipairs(extmarks) do
		--- @type neoment.rooms.RoomMark
		local mark = m
		if mark.is_buffer then
			api.nvim_buf_set_extmark(buffer_id, ns_id, mark.line - 1, 0, {
				line_hl_group = mark.has_unread and "NeomentBufferRoomUnread" or "NeomentBufferRoom",
			})
		elseif mark.has_unread then
			-- Apply bold highlight for unread rooms
			api.nvim_buf_set_extmark(buffer_id, ns_id, mark.line - 1, 0, {
				line_hl_group = "NeomentRoomUnread",
			})
		end
	end
end

--- Select a room from the list using a picker
M.pick = function()
	local room_names = {}
	local room_ids = {}

	for id, room in pairs(matrix.get_rooms()) do
		table.insert(room_names, room.name)
		table.insert(room_ids, id)
	end

	vim.ui.select(room_names, {
		prompt = "Rooms",
	}, function(choice, idx)
		if choice then
			open_room(room_ids[idx])
		end
	end)
end

--- Get the buffer ID of the room list
--- @return number|nil
M.get_buffer_id = function()
	return buffer_id
end

--- Get the name of the room list buffer
M.get_buffer_name = function()
	return room_list_buffer_name
end

return M
