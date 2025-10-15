local M = {}

local api = vim.api
local sync = require("neoment.sync")
local matrix = require("neoment.matrix")
local util = require("neoment.util")
local error = require("neoment.error")

local room_list_buffer_name = "neoment://rooms"
local rooms_buffer_id = nil
--- @alias neoment.rooms.Section "invited" | "buffers" | "favorites" | "people" | "spaces" | "rooms" | "low_priority"

--- @type table<neoment.rooms.Section, boolean>
local room_list_fold_state = {}

--- Get the fold state for a section
--- @param section neoment.rooms.Section The section name
--- @param default? boolean Optional default value if the section is not found
--- @return boolean The fold state of the section
local function get_fold_state(section, default)
	if room_list_fold_state[section] == nil then
		room_list_fold_state[section] = default or false
	end
	return room_list_fold_state[section]
end

--- @type table<neoment.rooms.Section, string>
local sections = {
	invited = "Invited",
	buffers = "Buffers",
	favorites = "Favorites",
	people = "People",
	spaces = "Spaces",
	rooms = "Rooms",
	low_priority = "Low priority",
}
local window_width = 50

--- Get the room mark under the cursor
--- @return neoment.rooms.RoomMark|nil The RoomMark if found, nil otherwise
local function get_room_mark_under_cursor()
	local cursor = api.nvim_win_get_cursor(0)
	local current_line = cursor[1] -- 1-based, current line where the cursor is

	if M.room_list_extmarks then
		for _, mark in ipairs(M.room_list_extmarks) do
			if mark.line == current_line then
				return mark
			end
		end
	end

	vim.notify("No room found on this line. Position the cursor directly over the room name.", vim.log.levels.INFO)
	return nil
end

--- Format the last synchronization time
--- @return string Formatted last synchronization time
local function format_last_sync_time()
	local sync_status = sync.get_status()
	if sync_status.kind == "never" then
		return "No sync yet"
	end
	return tostring(os.date("%H:%M:%S", sync_status.last_sync))
end

--- Get the logged user info
--- @return string, string The display name, and status text
local function get_logged_user_info()
	-- Get current user info
	local user_id = matrix.get_user_id()
	if not user_id then
		return "Unknown", "offline"
	end

	local display_name = matrix.get_display_name_or_fetch(user_id)
	local presence = matrix.get_current_user_presence()

	-- Default to offline if no presence info
	local status = presence and presence.presence or "offline"

	-- Get status icon
	local status_icon = ""
	if status == "online" then
		status_icon = "●"
	elseif status == "unavailable" then
		status_icon = "◐"
	else -- offline
		status_icon = "○"
	end

	local status_text = string.format("%s %s", status_icon, status)

	return display_name, status_text
end

--- Open a room in a new window
M.open_room = function(room_id)
	-- If the current buffer is the room list buffer
	local current_buf = api.nvim_get_current_buf()
	if current_buf == rooms_buffer_id then
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
					M.open_room(room_id)
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
	local mark = get_room_mark_under_cursor()

	if not mark then
		return
	end

	-- Check if the current line corresponds to a room
	if mark.is_invited then
		handle_invited_room(mark.room_id)
		return
	end
	M.open_room(mark.room_id)
end

--- Toggle the section fold at the cursor position
M.toggle_fold_at_cursor = function()
	local cursor = api.nvim_win_get_cursor(0)
	local current_line = cursor[1] -- 1-based, linha atual onde o cursor está

	local section = nil
	if M.section_lines then
		for section_name, _ in pairs(M.section_lines) do
			if current_line == M.section_lines[section_name] then
				section = section_name
				break
			end
		end
	end

	if section then
		room_list_fold_state[section] = not get_fold_state(section)

		-- Atualizar o símbolo de expansão no próprio buffer
		local current_line_text = api.nvim_buf_get_lines(0, current_line - 1, current_line, false)[1]
		local new_symbol = get_fold_state(section) and "" or ""
		local new_line = new_symbol .. current_line_text:sub(2)
		util.buffer_write(0, { new_line }, current_line - 1, current_line)

		M.update_room_list()
	else
		vim.notify("No section found on this line. Position the cursor over a section title.", vim.log.levels.INFO)
	end
end

--- Create a new buffer for the room list
local function create_room_list()
	rooms_buffer_id = api.nvim_create_buf(false, false) -- listed=false, scratch=false
	api.nvim_buf_set_name(rooms_buffer_id, room_list_buffer_name)
	api.nvim_set_option_value("filetype", "neoment_rooms", { buf = rooms_buffer_id })
	api.nvim_set_option_value("buftype", "nofile", { buf = rooms_buffer_id })
	api.nvim_set_current_buf(rooms_buffer_id)

	M.update_room_list()
end

--- Show the room list buffer
--- If the buffer is already open, update the room list
--- If not, create a new buffer
M.toggle_room_list = function()
	-- Close the room list if it's already open
	for _, win in ipairs(api.nvim_list_wins()) do
		if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == rooms_buffer_id then
			api.nvim_win_close(win, false)
			return
		end
	end

	vim.cmd("topleft vsplit")
	local new_win = api.nvim_get_current_win()
	api.nvim_win_set_width(new_win, window_width)

	if rooms_buffer_id and api.nvim_buf_is_loaded(rooms_buffer_id) then
		api.nvim_set_current_buf(rooms_buffer_id)
		M.update_room_list()
		return
	end

	create_room_list()
end

--- Get the fold arrow for the section
--- @param is_folded boolean Whether the section is folded
local function get_section_fold_arrow(is_folded)
	return is_folded and "" or ""
end

--- Get the icon for the section
--- @param section neoment.rooms.Section The section name
--- @return string The icon for the section
local function get_section_icon(section)
	if section == "invited" then
		return ""
	elseif section == "buffers" then
		return "󰮫"
	elseif section == "favorites" then
		return ""
	elseif section == "people" then
		return ""
	elseif section == "spaces" then
		return "󰴖"
	elseif section == "rooms" then
		return "󰮧"
	elseif section == "low_priority" then
		return "󰘄"
	else
		return ""
	end
end

--- Get the line for a room
--- @param room neoment.matrix.client.Room|neoment.matrix.client.InvitedRoom The room object
--- @param show_space boolean Whether to show the space name in the line
--- @return string The formatted line for the room
local function get_room_line(room, show_space)
	local last_activity = matrix.get_room_last_activity(room.id)

	local get_name = show_space and matrix.get_room_display_name_with_space or matrix.get_room_display_name

	local display = get_name(room.id)

	if last_activity and last_activity.timestamp > 0 then
		local time = os.date("%H:%M", math.floor(last_activity.timestamp / 1000))
		display = display .. " [" .. time .. "]"
		if room.unread_highlights and room.unread_highlights > 0 then
			display = display .. " 󰵛"
		elseif room.unread_notifications and room.unread_notifications > 0 then
			display = display .. " "
		elseif matrix.is_room_unread(room.id) then
			display = display .. " ⏺"
		end
	end

	return display
end

--- Sort rooms by name
--- @param a neoment.matrix.client.Room The first room
--- @param b neoment.matrix.client.Room The second room
--- @return boolean True if the first room comes before the second alphabetically
local function sort_by_name(a, b)
	local a_name = matrix.get_room_display_name(a.id):lower()
	local b_name = matrix.get_room_display_name(b.id):lower()

	if a_name == b_name then
		return a.id < b.id -- Sort by ID if names are the same
	end

	return a_name < b_name
end

--- Sort rooms by last activity
--- 1. Unread rooms first
--- 2. Then sort by most recent activity
--- @param a neoment.matrix.client.Room The first room
--- @param b neoment.matrix.client.Room The second room
--- @return boolean True if the first room is more recent than the second
local function sort_by_activity(a, b)
	local a_is_unread = matrix.is_room_unread(a.id)
	local b_is_unread = matrix.is_room_unread(b.id)

	if a_is_unread and not b_is_unread then
		return true -- Unread rooms come first
	elseif not a_is_unread and b_is_unread then
		return false -- Read rooms come after unread rooms
	end

	local a_last_timestamp = a.last_activity and a.last_activity.timestamp or 0
	local b_last_timestamp = b.last_activity and b.last_activity.timestamp or 0

	return (a_last_timestamp or 0) > (b_last_timestamp or 0)
end

--- Render a room
--- @param room neoment.matrix.client.Room The room object
--- @param lines table The lines to append the rendered room to
--- @param line_index number The current line index to start rendering
--- @param extmarks table The extmarks to append the room to
--- @param opts {section: neoment.rooms.Section, show_space: boolean, indentation_level: number} Options for rendering
local function render_room(room, lines, line_index, extmarks, opts)
	opts = opts or {}
	vim.validate("opts.show_space", opts.show_space, "boolean")
	vim.validate("opts.indentation_level", opts.indentation_level, "number")

	local display = get_room_line(room, opts.show_space)

	local indentation = string.rep("  ", opts.indentation_level)
	table.insert(lines, indentation .. display)
	--- @type neoment.rooms.RoomMark
	local extmark = {
		line = line_index,
		room_id = room.id,
		is_buffer = opts.section == "buffers",
		is_invited = opts.section == "invited",
		has_unread = (room.unread_notifications and room.unread_notifications > 0)
			or (room.unread_highlights and room.unread_highlights > 0),
	}
	table.insert(extmarks, extmark)
end

--- Render a space and its rooms or nested spaces
--- @param space neoment.matrix.client.Room The space room object
--- @param lines table The lines to append the rendered space to
--- @param line_index number The current line index to start rendering
--- @param extmarks table The extmarks to append the space rooms to
--- @param indentation_level number The indentation level (default is 1)
--- @return number The new line index after rendering
local function render_space(space, lines, line_index, extmarks, indentation_level)
	local is_folded = get_fold_state(space.id, true)
	local fold_arrow = get_section_fold_arrow(is_folded)
	local space_name = matrix.get_room_display_name(space.id)
	local indentation = string.rep("  ", indentation_level)
	table.insert(lines, string.format("%s%s %s", indentation, fold_arrow, space_name))

	M.section_lines[space.id] = line_index
	local new_line_index = line_index + 1

	if not is_folded then
		for _, r in ipairs(space.space_rooms) do
			if not matrix.has_room(r) then
				-- If the room is not found, skip it
				goto continue
			end

			local room = matrix.get_room(r)
			if matrix.is_space(room.id) then
				new_line_index = render_space(room, lines, new_line_index, extmarks, indentation_level + 1)
			else
				render_room(room, lines, new_line_index, extmarks, {
					show_space = false,
					indentation_level = indentation_level + 1,
				})
				new_line_index = new_line_index + 1
			end
			::continue::
		end
	end

	return new_line_index
end

--- Update the room list buffer
M.update_room_list = function()
	if not rooms_buffer_id or not api.nvim_buf_is_loaded(rooms_buffer_id) then
		return
	end

	local sync_status = sync.get_status()
	if sync_status.kind == "never" then
		util.buffer_write(rooms_buffer_id, { "No sync yet" }, 0, -1)
		return
	elseif sync_status.kind == "syncing" and sync_status.last_sync == nil then
		util.buffer_write(rooms_buffer_id, { "Syncing..." }, 0, -1)
		return
	end

	---@type table<neoment.rooms.Section, table<neoment.matrix.client.Room>>
	local section_rooms = {
		invited = {},
		buffers = {},
		favorites = {},
		people = {},
		spaces = {},
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
		elseif #room.space_rooms > 0 then
			-- Check if it's a nested space
			-- If it is, we skip it because when we render the parent space, we will render all nested spaces
			local parent_space = matrix.get_space(room.id)
			if not parent_space then
				table.insert(section_rooms.spaces, room)
			end
		else
			table.insert(section_rooms.rooms, room)
		end
		::continue::
	end

	-- Sort by activity (most recent first)
	table.sort(section_rooms.buffers, sort_by_activity)
	table.sort(section_rooms.favorites, sort_by_activity)
	table.sort(section_rooms.people, sort_by_activity)
	table.sort(section_rooms.spaces, sort_by_name)
	table.sort(section_rooms.rooms, sort_by_activity)
	table.sort(section_rooms.low_priority, sort_by_activity)

	-- Montar a lista
	local lines = {
		"Neoment - Last sync: " .. format_last_sync_time(),
		"",
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
	local line_index = #lines + 1 -- Starting after the header

	--- @type table<string, number>
	M.section_lines = {}
	--- @type neoment.rooms.Section[]
	local section_list = vim.tbl_values({
		#section_rooms.invited > 0 and "invited" or nil,
		#section_rooms.buffers > 0 and "buffers" or nil,
		"favorites",
		"people",
		#section_rooms.spaces > 0 and "spaces" or nil,
		"rooms",
		"low_priority",
	})

	for index, s in ipairs(section_list) do
		--- @type neoment.rooms.Section
		local section = s
		local is_folded = get_fold_state(section)
		local fold_arrow = get_section_fold_arrow(is_folded)
		local icon = get_section_icon(section)
		table.insert(
			lines,
			string.format("%s %s  %s (%d)", fold_arrow, icon, sections[section], #section_rooms[section])
		)
		M.section_lines[section] = line_index
		line_index = line_index + 1

		if not is_folded then
			for _, r in ipairs(section_rooms[section]) do
				--- @type neoment.matrix.client.Room
				local room = r

				if matrix.is_space(room.id) then
					line_index = render_space(room, lines, line_index, extmarks, 1)
				else
					render_room(room, lines, line_index, extmarks, {
						section = section,
						show_space = true,
						indentation_level = 1,
					})
					line_index = line_index + 1
				end
			end
		end

		if index < #section_list then
			table.insert(lines, "")
			line_index = line_index + 1
		end
	end

	util.buffer_write(rooms_buffer_id, lines, 0, -1)

	M.room_list_extmarks = extmarks

	local ns_id = api.nvim_create_namespace("neoment_room_list")
	api.nvim_buf_clear_namespace(rooms_buffer_id, ns_id, 0, -1)

	-- Highlight the title
	vim.hl.range(rooms_buffer_id, ns_id, "NeomentRoomsTitle", { 0, 0 }, { 0, 7 })
	vim.hl.range(rooms_buffer_id, ns_id, "Comment", { 0, 7 }, { 0, -1 })

	-- Add user status line with highlighting
	-- Add user status as virtual text on the second line
	local user_display_name, user_status_text = get_logged_user_info()
	api.nvim_buf_set_extmark(rooms_buffer_id, ns_id, 1, 0, {
		virt_text = {
			{ "", "NeomentBubbleBorder" }, -- Left border
			{ user_display_name .. " │ " .. user_status_text, "NeomentBubbleContent" }, -- Use a nice highlight group for username
			{ "", "NeomentBubbleBorder" }, -- Right border
		},
		virt_text_pos = "inline",
	})

	-- Highlight the section titles
	for _, line in pairs(M.section_lines) do
		vim.hl.range(rooms_buffer_id, ns_id, "NeomentSectionTitle", { line - 1, 1 }, { line - 1, -1 })
	end

	-- Highlight the room lines
	for _, m in ipairs(extmarks) do
		--- @type neoment.rooms.RoomMark
		local mark = m
		if mark.is_buffer then
			api.nvim_buf_set_extmark(rooms_buffer_id, ns_id, mark.line - 1, 0, {
				line_hl_group = mark.has_unread and "NeomentBufferRoomUnread" or "NeomentBufferRoom",
			})
		elseif mark.has_unread then
			-- Apply bold highlight for unread rooms
			api.nvim_buf_set_extmark(rooms_buffer_id, ns_id, mark.line - 1, 0, {
				line_hl_group = "NeomentRoomUnread",
			})
		end
	end
end

--- Pick a room from the list and call a callback function with the selected room
--- @param callback function Callback function to call with the selected room
--- @param options? {prompt: string} Optional parameters for the picker
M.pick_room = function(callback, options)
	options = options or {}
	local rooms_and_spaces = vim.tbl_values(matrix.get_rooms())
	local rooms = vim.iter(rooms_and_spaces)
		:filter(function(room)
			return not matrix.is_space(room.id)
		end)
		:totable()

	vim.ui.select(rooms, {
		prompt = options.prompt or "Rooms",
		format_item = function(room)
			return get_room_line(room, true)
		end,
	}, function(c)
		--- @type neoment.matrix.client.Room|nil
		local choice = c
		if choice then
			callback(choice)
		end
	end)
end

--- Select a room from the list using a picker
M.pick = function()
	M.pick_room(function(choice)
		M.open_room(choice.id)
	end)
end

--- Get the buffer ID of the room list
--- @return number|nil
M.get_buffer_id = function()
	return rooms_buffer_id
end

--- Get the name of the room list buffer
M.get_buffer_name = function()
	return room_list_buffer_name
end

--- Mark a room as unread
--- @param room_id string The ID of the room to mark as unread
local function mark_unread(room_id)
	local room_name = matrix.get_room_display_name(room_id)

	matrix.send_event(
		room_id,
		{
			unread = true,
		},
		"m.marked_unread",
		function(response)
			error.match(
				response,
				vim.schedule_wrap(function()
					M.update_room_list()
					vim.notify("Room '" .. room_name .. "' marked as unread", vim.log.levels.INFO)
					return nil
				end),
				function(err)
					local error_msg = err.error or "unknown error"
					vim.notify(
						string.format("Failed to mark room '%s' as unread: %s", room_name, error_msg),
						vim.log.levels.ERROR
					)
					return nil
				end
			)
		end
	)
end

--- Mark a room as read
--- @param room_id string The ID of the room to mark as read
local function mark_read(room_id)
	local last_activity = matrix.get_room_last_activity(room_id)
	if not last_activity or not last_activity.event_id then
		vim.notify("No activity found in this room to mark as read.", vim.log.levels.INFO)
		return
	end

	local room_name = matrix.get_room_display_name(room_id)
	matrix.set_room_read_marker(
		room_id,
		{
			read_private = last_activity.event_id,
		},
		vim.schedule_wrap(function(response)
			error.match(response, function()
				M.update_room_list()
				vim.notify("Room '" .. room_name .. "' marked as read", vim.log.levels.INFO)
				return nil
			end, function(err)
				local error_msg = err.error or "unknown error"
				vim.notify(
					string.format("Failed to mark room '%s' as read: %s", room_name, error_msg),
					vim.log.levels.ERROR
				)
			end)
		end)
	)
end

--- Toggle the read status of the room under the cursor
M.toggle_read = function()
	local mark = get_room_mark_under_cursor()

	if not mark then
		return
	end

	if mark.is_invited then
		vim.notify("You cannot mark an invited room as read.", vim.log.levels.INFO)
		return
	end

	local room = matrix.get_room(mark.room_id)
	local is_unread = (room.unread_highlights and room.unread_highlights > 0)
		or (room.unread_notifications and room.unread_notifications > 0)
		or matrix.is_room_unread(mark.room_id)

	if is_unread then
		mark_read(mark.room_id)
		return
	end

	mark_unread(mark.room_id)
end

--- Toggle a tag on the room under the cursor
--- @param tag "m.favourite"|"m.lowpriority" The tag to toggle
local function toggle_room_tag(tag)
	local mark = get_room_mark_under_cursor()

	if not mark then
		return
	end

	local tag_label = tag == "m.favourite" and "favorites" or "low priority"
	if mark.is_invited then
		vim.notify("You cannot add an invited room to " .. tag_label .. ".", vim.log.levels.INFO)
		return
	end

	local room = matrix.get_room(mark.room_id)
	if not room then
		vim.notify("Room not found.", vim.log.levels.ERROR)
		return
	end

	local room_name = matrix.get_room_display_name(room.id)

	local action = {
		kind = "add",
		operation = matrix.add_room_tag,
		success = "added to",
		error = "adding " .. room_name .. " to",
	}

	local is_already_tagged = (tag == "m.favourite" and room.is_favorite)
		or (tag == "m.lowpriority" and room.is_lowpriority)

	if is_already_tagged then
		action = {
			kind = "remove",
			operation = matrix.remove_room_tag,
			success = "removed from",
			error = "removing " .. room_name .. " from",
		}
	end

	action.operation(room.id, tag, nil, function(response)
		error.match(response, function()
			if action.kind == "remove" then
				if tag == "m.favourite" then
					matrix.set_room_favorite(room.id, false)
				elseif tag == "m.lowpriority" then
					matrix.set_room_lowpriority(room.id, false)
				end
			end
			vim.schedule(function()
				M.update_room_list()
			end)
			vim.notify(string.format("%s %s %s", room_name, action.success, tag_label), vim.log.levels.INFO)
			return nil
		end, function(err)
			vim.notify(string.format("Error %s %s: %s", action.error, tag_label, err.error), vim.log.levels.ERROR)
		end)
	end)
end

--- Toggle the favorite status of the room under the cursor
M.toggle_favorite = function()
	toggle_room_tag("m.favourite")
end

--- Toggle the low priority status of the room under the cursor
M.toggle_low_priority = function()
	toggle_room_tag("m.lowpriority")
end

return M
