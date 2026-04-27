local M = {}

local constants = require("neoment.constants")
local notify = require("neoment.notify")
local config = require("neoment.config")
local api = vim.api
local sync = require("neoment.sync")
local matrix = require("neoment.matrix")
local util = require("neoment.util")
local error = require("neoment.error")
local storage = require("neoment.storage")

local room_list_buffer_name = "neoment://rooms"
local rooms_buffer_id = nil
--- @alias neoment.rooms.Section "invited" | "buffers" | "favorites" | "people" | "spaces" | "rooms" | "low_priority"

--- @type table<neoment.rooms.Section, boolean>
local room_list_fold_state = {}

--- Flag to track if fold state has been loaded from storage
local fold_state_loaded = false

--- Load the fold state from storage
local function load_fold_state()
	if fold_state_loaded then
		return
	end

	local ui_state = storage.load_ui_state()
	if ui_state and ui_state.room_list_fold_state then
		room_list_fold_state = ui_state.room_list_fold_state
	end
	fold_state_loaded = true
end

--- Save the fold state to storage
local function save_fold_state()
	storage.save_ui_state({ room_list_fold_state = room_list_fold_state })
end

--- Get the fold state for a section
--- @param section neoment.rooms.Section The section name
--- @param default? boolean Optional default value if the section is not found
--- @return boolean The fold state of the section
local function get_fold_state(section, default)
	load_fold_state()
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

-- Set the window width to 20% of the total columns, but no more than 50
local ROOM_LIST_WIDTH = math.min(50, math.floor(vim.o.columns * 0.2))

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

	notify.info("No room found on this line. Position the cursor directly over the room name.")
	return nil
end

--- Format the last synchronization time
--- @return string, string Formatted sync status icon and time
local function format_sync_status()
	local sync_status = sync.get_status()

	-- Never synced
	if sync_status.last_sync == nil then
		if sync_status.kind == "syncing" then
			return "◇", "connecting"
		end
		return "◇", "offline"
	end

	-- Calculate relative time since last sync
	local now = os.time()
	local diff = now - sync_status.last_sync

	if diff < 60 then
		return "●", "synced"
	elseif diff < 3600 then
		return "●", math.floor(diff / 60) .. "m ago"
	else
		return "○", vim.fn.strftime("%H:%M", sync_status.last_sync)
	end
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
		if util.win_count() == 1 then
			local win = api.nvim_open_win(0, true, {
				split = "right",
				width = vim.o.columns - ROOM_LIST_WIDTH,
			})
			vim.wo[win].winfixbuf = false
		else
			-- @fixme, need to check is it a normal windows.
			-- Move the cursor to the right window
			vim.cmd("wincmd l")
		end
	end

	if matrix.is_space(room_id) then
		require("neoment.space").open_space(room_id)
		return
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
				notify.error("Error joining room: " .. err.error)
			end)
		end)
		return
	end
	matrix.leave_room(room_id, function(response)
		error.match(response, function()
			notify.info("Left room: " .. room_name)
			return nil
		end, function(err)
			notify.error("Error leaving room: " .. err.error)
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
		save_fold_state()

		-- Update the fold arrow in the buffer
		local current_line_text = api.nvim_buf_get_lines(0, current_line - 1, current_line, false)[1]
		local new_symbol = get_fold_state(section) and "" or ""
		local new_line = new_symbol .. current_line_text:sub(2)
		util.buffer_write(0, { new_line }, current_line - 1, current_line)

		M.update_room_list()
	else
		notify.info("No section found on this line. Position the cursor over a section title.")
	end
end

--- Create a new buffer for the room list
local function switch_to_room_list_buffer()
	if not rooms_buffer_id or not api.nvim_buf_is_loaded(rooms_buffer_id) then
		rooms_buffer_id = api.nvim_create_buf(false, false) -- listed=false, scratch=false
		api.nvim_buf_set_name(rooms_buffer_id, room_list_buffer_name)
		vim.bo[rooms_buffer_id].filetype = "neoment_rooms"
	end

	api.nvim_set_current_buf(rooms_buffer_id)
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
	api.nvim_win_set_width(new_win, ROOM_LIST_WIDTH)

	switch_to_room_list_buffer()
	vim.wo[new_win][0].winfixbuf = true
	vim.wo[new_win][0].number = false
	vim.wo[new_win][0].relativenumber = false
	vim.wo[new_win][0].cursorline = true
	vim.wo[new_win][0].winfixwidth = true
	vim.wo[new_win][0].signcolumn = "no"
	M.update_room_list()
end

--- Get the fold arrow for the section
--- @param is_folded boolean Whether the section is folded
local function get_section_fold_arrow(is_folded)
	local icon = config.get().icon
	return is_folded and icon.right_arrow or icon.down_arrow
end

--- Get the icon for the section
--- @param section neoment.rooms.Section The section name
--- @return string The icon for the section
local function get_section_icon(section)
	local icon = config.get().icon
	if section == "invited" then
		return icon.invite
	elseif section == "buffers" then
		return icon.buffer
	elseif section == "favorites" then
		return icon.favorite
	elseif section == "people" then
		return icon.people
	elseif section == "spaces" then
		return icon.space
	elseif section == "rooms" then
		return icon.room
	elseif section == "low_priority" then
		return icon.low_priority
	else
		return ""
	end
end

--- Get the room icon based on room type
--- @param room neoment.matrix.client.InvitedRoom|neoment.matrix.client.Room The room object
--- @return string The icon for the room
local function get_room_icon(room)
	local icon = config.get().icon
	if matrix.is_space(room.id) then
		return icon.space
	elseif room.is_direct then
		return icon.people
	else
		return icon.room
	end
end

--- Format relative time from timestamp
--- @param timestamp number The timestamp in milliseconds
--- @return string The formatted relative time
local function format_relative_time(timestamp)
	local now = os.time() * 1000
	local diff = now - timestamp
	local seconds = diff / 1000
	local minutes = seconds / 60
	local hours = minutes / 60
	local days = hours / 24

	if days >= 7 then
		return vim.fn.strftime("%d/%m", math.floor(timestamp / 1000))
	elseif days >= 1 then
		local d = math.floor(days)
		return d .. "d"
	elseif hours >= 1 then
		local h = math.floor(hours)
		return h .. "h"
	elseif minutes >= 1 then
		local m = math.floor(minutes)
		return m .. "m"
	else
		return "now"
	end
end

--- @class neoment.rooms.RoomLineInfo
--- @field name string The display name of the room
--- @field time string|nil The formatted time of last activity
--- @field notification_icon string|nil The notification icon to display
--- @field room_icon string The icon for the room type
--- @field is_unread boolean Whether the room has unread messages

--- Get the line info for a room
--- @param room neoment.matrix.client.Room|neoment.matrix.client.InvitedRoom The room object
--- @param show_space boolean Whether to show the space name in the line
--- @return neoment.rooms.RoomLineInfo The room line info
local function get_room_line_info(room, show_space)
	local last_activity = matrix.get_room_last_activity(room.id)
	local get_name = show_space and matrix.get_room_display_name_with_space or matrix.get_room_display_name
	local config_icon = config.get().icon

	local info = {
		name = get_name(room.id),
		time = nil,
		notification_icon = nil,
		room_icon = get_room_icon(room),
		is_unread = false,
	}

	if last_activity and last_activity.timestamp > 0 then
		info.time = format_relative_time(last_activity.timestamp)

		if room.unread_highlights and room.unread_highlights > 0 then
			info.notification_icon = config_icon.bell
			info.is_unread = true
		elseif room.unread_notifications and room.unread_notifications > 0 then
			info.notification_icon = config_icon.dot_circle
			info.is_unread = true
		elseif matrix.is_room_unread(room.id) then
			info.notification_icon = config_icon.dot
			info.is_unread = true
		end
	end

	return info
end

--- Get the line for a room (legacy format for picker compatibility)
--- @param room neoment.matrix.client.Room|neoment.matrix.client.InvitedRoom The room object
--- @param show_space boolean Whether to show the space name in the line
--- @return string The formatted line for the room
local function get_room_line(room, show_space)
	local info = get_room_line_info(room, show_space)
	local display = info.name

	if info.time then
		display = display .. " [" .. info.time .. "]"
		if info.notification_icon then
			display = display .. " " .. info.notification_icon
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

	local info = get_room_line_info(room, opts.show_space)
	local indentation = string.rep("  ", opts.indentation_level)

	-- Build the line: just the room name (highlights and virtual text will add the rest)
	table.insert(lines, indentation .. info.name)

	--- @type neoment.rooms.RoomMark
	local extmark = {
		line = line_index,
		room_id = room.id,
		is_buffer = opts.section == "buffers",
		is_invited = opts.section == "invited",
		has_unread = (room.unread_notifications and room.unread_notifications > 0)
			or (room.unread_highlights and room.unread_highlights > 0),
		is_space = false,
		indentation_level = opts.indentation_level,
		room_info = info, -- Store info for highlight application
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

	-- Add extmark for the space line so it's clickable
	--- @type neoment.rooms.RoomMark
	local space_mark = {
		line = line_index,
		room_id = space.id,
		is_buffer = false,
		is_invited = false,
		has_unread = false,
		is_space = true,
		indentation_level = indentation_level,
	}
	table.insert(extmarks, space_mark)

	M.section_lines[space.id] = line_index
	local new_line_index = line_index + 1

	if not is_folded then
		for _, r in ipairs(space.space_rooms) do
			if not matrix.has_room(r) or not matrix.is_user_member_of_room(r) then
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

--- Get the virtual lines for the last message
--- @param display_last_message neoment.config.DisplayLastMessage How to display the last message
--- @param room_mark neoment.rooms.RoomMark The room mark
--- @return table<table<[string, string]>>|nil The virtual lines for the last message, or nil if not applicable
local function get_last_message_virtual_lines(display_last_message, room_mark)
	if display_last_message == "no" or room_mark.is_space then
		return nil
	end

	local last_message = matrix.get_room_last_message(room_mark.room_id)
	if not last_message then
		return nil
	end

	local content
	if string.len(last_message.content) > 0 then
		content = last_message.content
	elseif last_message.attachment and last_message.attachment.filename then
		local config_icon = config.get().icon
		content = config_icon.file .. " " .. last_message.attachment.filename
	end

	if not content then
		return nil
	end

	-- Truncate long messages
	local max_length = 40
	if vim.fn.strdisplaywidth(content) > max_length then
		content = vim.fn.strcharpart(content, 0, max_length - 1) .. "…"
	end

	-- Remove newlines for cleaner display
	content = content:gsub("\n", " ")

	local indentation = string.rep("  ", room_mark.indentation_level)
	local config_icon = config.get().icon
	local tree_char = config_icon.vertical_bar

	if display_last_message == "message" then
		return {
			{
				{ indentation .. "  " .. tree_char .. " ", "NeomentLastMessageTree" },
				{ content, "NeomentLastMessage" },
			},
		}
	end

	local sender = matrix.get_display_name(last_message.sender)
	-- Truncate sender name if too long
	if vim.fn.strdisplaywidth(sender) > 15 then
		sender = vim.fn.strcharpart(sender, 0, 14) .. "…"
	end

	if display_last_message == "sender_message" then
		return {
			{
				{ indentation .. "  " .. tree_char .. " ", "NeomentLastMessageTree" },
				{ sender, "NeomentLastMessageSender" },
			},
			{
				{ indentation .. "  " .. tree_char .. " ", "NeomentLastMessageTree" },
				{ content, "NeomentLastMessage" },
			},
		}
	elseif display_last_message == "sender_message_inline" then
		return {
			{
				{ indentation .. "  " .. tree_char .. " ", "NeomentLastMessageTree" },
				{ sender .. ": ", "NeomentLastMessageSender" },
				{ content, "NeomentLastMessage" },
			},
		}
	end
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
	for _, room in pairs(matrix.get_user_rooms()) do
		-- Check if the room is open in a buffer
		for _, buf in ipairs(open_buffers) do
			if vim.b[buf].room_id == room.id and vim.bo[buf].filetype == constants.ROOM_FILETYPE then
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
		"", -- Logo line (will be filled with virtual text)
		"", -- User info line (will be filled with virtual text)
		"",
	}
	--- @class neoment.rooms.RoomMark
	--- @field line number
	--- @field room_id string
	--- @field is_buffer boolean
	--- @field is_invited boolean
	--- @field has_unread boolean
	--- @field is_space boolean
	--- @field indentation_level number
	--- @field room_info? neoment.rooms.RoomLineInfo

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
		local section_icon = get_section_icon(section)
		table.insert(
			lines,
			string.format("%s %s  %s (%d)", fold_arrow, section_icon, sections[section], #section_rooms[section])
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

	-- Header: Logo centered with decorations based on window width
	local win_width = ROOM_LIST_WIDTH
	-- Try to get actual window width if buffer is displayed
	for _, win in ipairs(api.nvim_list_wins()) do
		if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == rooms_buffer_id then
			win_width = api.nvim_win_get_width(win)
			break
		end
	end

	local title = "Neoment"
	local title_len = vim.fn.strdisplaywidth(title)
	local decoration_char = "─"
	local total_decoration = win_width - title_len - 2 -- -2 for spaces around title
	local left_len = math.floor(total_decoration / 2)
	local right_len = math.ceil(total_decoration / 2)

	api.nvim_buf_set_extmark(rooms_buffer_id, ns_id, 0, 0, {
		virt_text = {
			{ string.rep(decoration_char, left_len) .. " ", "NeomentHeaderDecoration" },
			{ title, "NeomentRoomsTitle" },
			{ " " .. string.rep(decoration_char, right_len), "NeomentHeaderDecoration" },
		},
		virt_text_pos = "overlay",
	})

	-- Header: User info with presence and sync status
	local config_icon = config.get().icon
	local icon = require("neoment.icon")
	local user_display_name, user_status_text = get_logged_user_info()
	local sync_icon, sync_text = format_sync_status()
	local sync_hl = sync_icon == "●" and "DiagnosticOk" or "Comment"

	api.nvim_buf_set_extmark(rooms_buffer_id, ns_id, 1, 0, {
		virt_text = {
			{ icon.border_left, "NeomentBubbleBorder" },
			{
				" " .. user_display_name .. " " .. config_icon.vertical_bar .. " " .. user_status_text .. " ",
				"NeomentBubbleContent",
			},
			{ icon.border_right, "NeomentBubbleBorder" },
			{ "  " .. sync_icon .. " ", sync_hl },
			{ sync_text, "Comment" },
		},
		virt_text_pos = "overlay",
	})

	-- Highlight the section titles
	for _, line in pairs(M.section_lines) do
		vim.hl.range(rooms_buffer_id, ns_id, "NeomentSectionTitle", { line - 1, 1 }, { line - 1, -1 })
	end

	local display_last_message = config.get().rooms.display_last_message

	-- Highlight the room lines with the new modern design
	for _, m in ipairs(extmarks) do
		--- @type neoment.rooms.RoomMark
		local mark = m

		local line_hl_group = nil
		if mark.is_buffer then
			line_hl_group = mark.has_unread and "NeomentBufferRoomUnread" or "NeomentBufferRoom"
		elseif mark.has_unread then
			-- Apply bold highlight for unread rooms
			line_hl_group = "NeomentRoomUnread"
		end

		local last_message_lines = get_last_message_virtual_lines(display_last_message, mark)

		-- Build end-of-line virtual text (time + notification badge)
		local eol_virt_text = {}
		local room_info = mark.room_info
		if room_info then
			if room_info.time then
				table.insert(eol_virt_text, { " " .. room_info.time, "NeomentRoomTime" })
			end
			if room_info.notification_icon then
				local notif_hl = "NeomentNotificationDot"
				if room_info.notification_icon == config_icon.bell then
					notif_hl = "NeomentNotificationBell"
				elseif room_info.notification_icon == config_icon.dot_circle then
					notif_hl = "NeomentNotificationCircle"
				end
				table.insert(eol_virt_text, { " " .. room_info.notification_icon, notif_hl })
			end
		end

		-- Set extmark with line highlight and virtual lines (last message)
		if line_hl_group or last_message_lines then
			api.nvim_buf_set_extmark(rooms_buffer_id, ns_id, mark.line - 1, 0, {
				line_hl_group = line_hl_group,
				virt_lines = last_message_lines,
			})
		end

		-- Add a separate extmark for EOL elements (time + notification)
		if #eol_virt_text > 0 then
			api.nvim_buf_set_extmark(rooms_buffer_id, ns_id, mark.line - 1, 0, {
				virt_text = eol_virt_text,
				virt_text_pos = "eol",
			})
		end

		-- Add inline icon extmark for rooms (not spaces, they have fold arrows)
		if room_info and not mark.is_space then
			local icon_hl = mark.is_buffer and "NeomentRoomIconBuffer"
				or (room_info.is_unread and "NeomentRoomIconUnread" or "NeomentRoomIcon")
			local indentation_offset = mark.indentation_level * 2
			api.nvim_buf_set_extmark(rooms_buffer_id, ns_id, mark.line - 1, indentation_offset, {
				virt_text = { { room_info.room_icon .. "  ", icon_hl } },
				virt_text_pos = "inline",
			})
		end
	end
end

--- Format the room to be displayed in the picker
--- @param rooms_and_spaces neoment.matrix.client.Room[] The list of rooms
--- @return neoment.config.PickerRoom[] The formatted rooms for the picker
local function rooms_to_picker_rooms(rooms_and_spaces)
	local icon = config.get().icon

	return vim.iter(ipairs(rooms_and_spaces))
		:map(function(_, room)
			local line
			if matrix.is_space(room.id) then
				line = icon.space .. "  " .. matrix.get_room_display_name(room.id)
			else
				local room_icon = room.is_direct and icon.people or icon.room
				line = room_icon .. "  " .. get_room_line(room, true)
			end
			return { room = room, line = line }
		end)
		:totable()
end

--- Pick a room from the list and call a callback function with the selected room
--- @param callback fun(room: neoment.matrix.client.Room)
--- @param options neoment.config.PickerOptions
M.pick_room = function(callback, options)
	local rooms_and_spaces = rooms_to_picker_rooms(matrix.get_user_rooms())
	local picker = config.get().picker.rooms

	picker(rooms_and_spaces, callback, options)
end

--- Select a room from the list using a picker
M.pick = function()
	M.pick_room(function(room)
		M.open_room(room.id)
	end, { prompt = "Select a room:" })
end

--- Select an open room from the list using a picker
M.pick_open = function()
	local room_buffers = vim.tbl_filter(function(buf)
		if not api.nvim_buf_is_loaded(buf) then
			return false
		end

		return vim.bo[buf].filetype == constants.ROOM_FILETYPE
	end, api.nvim_list_bufs())

	if #room_buffers == 0 then
		notify.info("No open rooms")
		return
	end

	local open_rooms = vim.tbl_map(function(buf)
		return matrix.get_room(vim.b[buf].room_id)
	end, room_buffers)

	local formatted_rooms = rooms_to_picker_rooms(open_rooms)

	local picker = config.get().picker.open_rooms
	picker(formatted_rooms, function(room)
		M.open_room(room.id)
	end, { prompt = "Select an open room:" })
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
					notify.info("Room '" .. room_name .. "' marked as unread")
					return nil
				end),
				function(err)
					local error_msg = err.error or "unknown error"
					notify.error(string.format("Failed to mark room '%s' as unread: %s", room_name, error_msg))
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
		notify.info("No activity found in this room to mark as read.")
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
				notify.info("Room '" .. room_name .. "' marked as read")
				return nil
			end, function(err)
				local error_msg = err.error or "unknown error"
				notify.error(string.format("Failed to mark room '%s' as read: %s", room_name, error_msg))
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
		notify.info("You cannot mark an invited room as read.")
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
		notify.info("You cannot add an invited room to " .. tag_label .. ".")
		return
	end

	M.toggle_room_tag(tag, mark.room_id)
end

--- Toggle a tag on a room by ID
--- @param tag "m.favourite"|"m.lowpriority" The tag to toggle
--- @param room_id string The ID of the room to toggle the tag on
--- @param callback? function The callback to call after toggling the tag
M.toggle_room_tag = function(tag, room_id, callback)
	local room = matrix.get_room(room_id)
	if not room then
		notify.error("Room not found.")
		return
	end

	local tag_label = tag == "m.favourite" and "favorites" or "low priority"

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
			local is_add = action.kind == "add"
			if tag == "m.favourite" then
				matrix.set_room_favorite(room.id, is_add)
			elseif tag == "m.lowpriority" then
				matrix.set_room_lowpriority(room.id, is_add)
			end

			vim.schedule(function()
				if M.get_buffer_id() then
					M.update_room_list()
				end
				if callback then
					callback()
				end
			end)
			notify.info(string.format("%s %s %s", room_name, action.success, tag_label))
			return nil
		end, function(err)
			notify.error(string.format("Error %s %s: %s", action.error, tag_label, err.error))
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

--- Toggle the direct status of the room under the cursor (local only)
M.toggle_direct = function()
	local mark = get_room_mark_under_cursor()

	if not mark then
		return
	end

	if mark.is_invited then
		notify.info("You cannot mark an invited room as direct.")
		return
	end

	M.toggle_direct_on(mark.room_id)
end

--- Toggle the direct status of a room by ID (local only)
--- @param room_id string The ID of the room to toggle direct status on
M.toggle_direct_on = function(room_id)
	local room = matrix.get_room(room_id)
	if not room then
		notify.error("Room not found.")
		return
	end

	local room_name = matrix.get_room_display_name(room.id)
	local new_direct_status = not room.is_direct

	matrix.set_room_direct(room.id, new_direct_status)
	M.update_room_list()

	local action = new_direct_status and "marked as direct" or "unmarked as direct"
	notify.info(string.format("%s %s", room_name, action))
end

--- Refresh the state of the room under the cursor.
--- This fetches the full room state from the server, useful for
--- getting state events that may have been missed during sync.
M.refresh_room_state = function()
	local mark = get_room_mark_under_cursor()

	if not mark then
		return
	end

	local room_id = mark.room_id
	local room = matrix.get_room(room_id)
	local room_name = room and room.name or room_id

	notify.info(string.format("Refreshing state for %s...", room_name))

	matrix.refresh_room_state(room_id, function(result)
		error.match(result, function(updated)
			if updated then
				notify.info(string.format("State updated for %s", room_name))
				M.update_room_list()
				require("neoment.room").update_room(room_id)
			else
				notify.info(string.format("No new state for %s", room_name))
			end
			return nil
		end, function(err)
			notify.error(string.format("Failed to refresh state: %s", err.error or "Unknown error"))
		end)
	end)
end

--- Show information about the room under the cursor
M.show_room_info = function()
	local mark = get_room_mark_under_cursor()

	if not mark then
		return
	end

	local room_id = mark.room_id

	-- Open the window using the same logic as opening a room
	local current_buf = api.nvim_get_current_buf()
	if current_buf == rooms_buffer_id then
		if util.win_count() == 1 then
			local win = api.nvim_open_win(0, true, {
				split = "right",
				width = vim.o.columns - ROOM_LIST_WIDTH,
			})
			vim.wo[win].winfixbuf = false
		else
			vim.cmd("wincmd l")
		end
	end

	require("neoment.room_info").open_info(room_id)
end

--- Change the current user's presence status
M.change_status = function()
	local current_presence = matrix.get_current_user_presence()
	local current_status = current_presence and current_presence.presence or "offline"

	local options = { "online", "unavailable", "offline" }
	local prompt = string.format("Change status (current: %s):", current_status)

	vim.ui.select(options, {
		prompt = prompt,
		format_item = function(item)
			local icon = ""
			if item == "online" then
				icon = "●"
			elseif item == "unavailable" then
				icon = "◐"
			else
				icon = "○"
			end
			return string.format("%s %s", icon, item)
		end,
	}, function(choice)
		if not choice then
			return
		end

		-- Set the desired presence for future syncs
		matrix.set_desired_presence(choice)
		M.update_room_list()
		notify.info("Status will change to '" .. choice .. "' on next sync")
	end)
end

return M
