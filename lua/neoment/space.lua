local M = {}

local notify = require("neoment.notify")
local constants = require("neoment.constants")
local config = require("neoment.config")
local util = require("neoment.util")
local error = require("neoment.error")
local api = vim.api
local matrix = require("neoment.matrix")

--- Buffer data
--- @type table<number, neoment.space.BufferData>
local buffer_data = {}

--- @class neoment.space.BufferData
--- @field line_to_room table<number, neoment.space.LineRoom> Map of line_number to room_id
--- @field line_data table<number, neoment.space.LineData> Map of line_number to line data

--- @class neoment.space.LineRoom
--- @field room neoment.matrix.SpaceHierarchyRoomsChunk The room data
--- @field via table<string> List of via servers

--- @class neoment.space.LineData
--- @field is_rooms_title boolean Whether the line is the "Rooms:" title

--- Get the buffer data for a specific buffer
--- @param buffer_id number The ID of the buffer to get the data for
--- @return neoment.space.BufferData The buffer data for the specified buffer
local function get_buffer_data(buffer_id)
	if not buffer_data[buffer_id] then
		buffer_data[buffer_id] = {
			line_to_room = {},
			line_data = {},
		}
	end
	return buffer_data[buffer_id]
end

--- Get or create a buffer for a space
--- @param space_id string The ID of the space
--- @return number The buffer ID
local function get_or_create_buffer(space_id)
	-- Check if the buffer already exists
	local existing_buffer = util.get_existing_buffer(function(buf)
		return vim.b[buf].space_id == space_id
	end)
	if existing_buffer then
		api.nvim_set_current_buf(existing_buffer)
		return existing_buffer
	end

	local space_name = matrix.get_room_display_name(space_id)
	local buffer_name = string.format("neoment://space/%s/%s", space_id, space_name)
	local buffer_id = api.nvim_create_buf(true, false)

	api.nvim_buf_set_name(buffer_id, buffer_name)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buffer_id })
	vim.api.nvim_set_option_value("filetype", "neoment_space", { buf = buffer_id })
	vim.b[buffer_id].space_id = space_id
	util.buffer_write(buffer_id, { "Loading space..." }, 0, -1)

	return buffer_id
end

--- Get the room ID under the cursor
--- @return neoment.Error<neoment.space.LineRoom, string> The message under the cursor or an error
local function get_room_id_under_cursor()
	local line_number = api.nvim_win_get_cursor(0)[1]
	local buffer_id = vim.api.nvim_get_current_buf()
	local room = get_buffer_data(buffer_id).line_to_room[line_number]
	if not room then
		notify.error("No room or space under the cursor")
		return error.error("No room or space under the cursor")
	end

	return error.ok(room)
end

local function render_room_space_line(room, indent_level)
	local indent = string.rep("  ", indent_level)
	local icon = config.get().icon

	local is_space = room.room_type == "m.space"
	local prefix = is_space and icon.space or icon.room
	local name = room.name
	if not name or name == "" then
		local ok, room_name = pcall(matrix.get_room_display_name, room.room_id)
		if ok then
			name = room_name
		else
			name = "(No Name)"
		end
	end
	local topic = ""
	if room.topic and room.topic ~= "" then
		-- Remove newlines
		topic = room.topic:gsub("\n.*", "...")
		topic = " - " .. topic
	end
	local line = string.format("%s%s  %s (%d members)%s", indent, prefix, name, room.num_joined_members, topic)
	return line
end

--- Render rooms recursively
--- @param lines table<string> The lines to append to
--- @param children_state table<neoment.matrix.StrippedStateEvent> List of children state
--- @param rooms table<neoment.matrix.SpaceHierarchyRoomsChunk> List of room IDs
--- @param indent_level number Current indentation level
local function render_rooms(lines, children_state, rooms, indent_level)
	local spaces_rendered = {}
	local nested_spaces_rendered = {}
	for _, s in ipairs(children_state) do
		--- @type neoment.matrix.StrippedStateEvent
		local state = s

		--- @type neoment.matrix.SpaceHierarchyRoomsChunk
		local room = vim.iter(rooms):find(function(r)
			return r.room_id == state.state_key
		end)

		if not room then
			goto continue
		end

		if vim.iter(nested_spaces_rendered):find(function(id)
			return id == room.room_id
		end) then
			goto continue
		end

		local line = render_room_space_line(room, indent_level)
		table.insert(lines, line)
		get_buffer_data(api.nvim_get_current_buf()).line_to_room[#lines] = {
			room = room,
			via = state.content and state.content.via or {},
		}

		if #room.children_state > 0 then
			table.insert(spaces_rendered, room.room_id)
			nested_spaces_rendered = render_rooms(lines, room.children_state, rooms, indent_level + 1)
		end

		::continue::
	end
	return vim.iter({ spaces_rendered, nested_spaces_rendered }):flatten():totable()
end

--- Render spaces and their rooms recursively
--- @param rooms table<neoment.matrix.SpaceHierarchyRoomsChunk> List of room IDs
local function render_spaces(lines, rooms)
	local spaces_rendered = {}
	for _, r in ipairs(rooms) do
		--- @type neoment.matrix.SpaceHierarchyRoomsChunk
		local room = r

		if vim.iter(spaces_rendered):find(function(id)
			return id == room.room_id
		end) then
			goto continue
		end

		if room.room_type ~= "m.space" or #room.children_state == 0 then
			goto continue
		end

		local line, _ = render_room_space_line(room, 0)
		table.insert(lines, line)
		get_buffer_data(api.nvim_get_current_buf()).line_to_room[#lines] = {
			room = room,
			via = {},
		}
		local new_spaces_rendered = render_rooms(lines, room.children_state, rooms, 1)
		spaces_rendered = vim.iter({ spaces_rendered, new_spaces_rendered }):flatten():totable()

		::continue::
	end
end

--- Open the room under the cursor
M.open_room_under_cursor = function()
	local error_room = get_room_id_under_cursor()

	error.map(error_room, function(room)
		-- Check if the user has access to this room
		if not matrix.is_user_member_of_room(room.room.room_id) then
			local answer = vim.fn.confirm("Do you want to join this room?", "&Join\n&Cancel", 1, "Question")
			if answer ~= 1 then
				return nil
			end
			matrix.join_room(room.room.room_id, function(response)
				error.match(response, function()
					vim.schedule(function()
						require("neoment.room").open_room(room.room.room_id)
					end)
					return nil
				end, function(err)
					notify.error("Error joining room: " .. err.error)
				end)
			end, room.via)
			return nil
		end

		-- Check if it's a space or a room
		if matrix.is_space(room.room.room_id) then
			-- If it's a nested space, open the space details
			M.open_space(room.room.room_id)
		else
			-- Open the room
			require("neoment.rooms").open_room(room.room.room_id)
		end
		return nil
	end)
end

--- Apply highlights to the lines in the buffer
--- @param buffer_id number The ID of the buffer to apply highlights to
--- @param space_id string The ID of the room to apply highlights to
--- @param lines table The lines to apply highlights to
local function apply_highlights(buffer_id, space_id, lines)
	vim.hl.range(buffer_id, constants.ns_id, "NeomentRoomsTitle", { 0, 0 }, { 0, -1 })
	vim.hl.range(buffer_id, constants.ns_id, "Bold", { 2, 0 }, { 2, -1 })

	for index, l in ipairs(lines) do
		--- @type string
		local line = l
		--- @type neoment.space.LineRoom
		local room = get_buffer_data(buffer_id).line_to_room[index]
		local line_data = get_buffer_data(buffer_id).line_data[index]

		if line_data and line_data.is_rooms_title then
			vim.hl.range(buffer_id, constants.ns_id, "Bold", { index - 1, 0 }, { index - 1, -1 })
		end

		local icon = config.get().icon

		local space_icon = line:find(icon.space)
		local topic_separator_start, topic_separator_end = line:find(" - ", space_icon, true)
		if space_icon then
			vim.hl.range(
				buffer_id,
				constants.ns_id,
				"NeomentSectionTitle",
				{ index - 1, 0 },
				{ index - 1, (topic_separator_start or 0) - 1 },
				{ priority = 50 }
			)
		end

		if topic_separator_end then
			vim.hl.range(buffer_id, constants.ns_id, "Comment", { index - 1, topic_separator_end }, { index - 1, -1 })
		end

		if room and room.room and matrix.is_user_member_of_room(room.room.room_id) then
			local icon_pos = line:find(icon.space) or line:find(icon.room)
			if icon_pos then
				vim.api.nvim_buf_set_extmark(buffer_id, constants.ns_id, index - 1, icon_pos + 5, {
					virt_text = {
						{ icon.border_left, "NeomentBubbleBorder" },
						{ "Joined", "NeomentBubbleContent" },
						{ icon.border_right, "NeomentBubbleBorder" },
						{ " ", "Normal" },
					},
					virt_text_pos = "inline",
				})
			end
		end
	end
end

--- Render the space details
--- @param space_id string The ID of the space
--- @param buffer_id number The buffer ID
--- @param hierarchy neoment.matrix.RoomsHierarchy The space hierarchy
local function render_space_details(space_id, buffer_id, hierarchy)
	-- TODO Remove
	-- print(vim.inspect(hierarchy))
	local space = matrix.get_room(space_id)
	if not space then
		notify.error("Space not found")
		return
	end

	local space_name = matrix.get_room_display_name(space_id)

	local lines = {}
	table.insert(lines, space_name)
	table.insert(lines, "")
	table.insert(lines, "Topic:")
	if space.topic then
		for _, line in ipairs(vim.split(space.topic, "\n")) do
			if line:match("%S") then
				table.insert(lines, line)
			end
		end
	else
		table.insert(lines, "No topic")
	end
	table.insert(lines, "")
	table.insert(lines, "Rooms:")
	get_buffer_data(buffer_id).line_data[#lines] = {
		is_rooms_title = true,
	}

	-- Create namespace for extmarks (for highlighting later if needed)
	api.nvim_buf_clear_namespace(buffer_id, constants.ns_id, 0, -1)

	if #hierarchy.rooms > 0 then
		render_spaces(lines, hierarchy.rooms)
	else
		table.insert(lines, "  No rooms in this space")
	end

	-- Set the buffer content
	util.buffer_write(buffer_id, lines, 0, -1)

	-- Apply highlights for each line
	apply_highlights(buffer_id, space_id, lines)
end

--- Open a space details view
--- @param space_id string The ID of the space
M.open_space = function(space_id)
	-- Open the buffer in the current window or a new one
	local current_buf = api.nvim_get_current_buf()
	local rooms_module = require("neoment.rooms")

	if current_buf == rooms_module.get_buffer_id() then
		-- If we're in the rooms list, open in a new window to the right
		if #api.nvim_list_wins() == 1 then
			vim.cmd("vsplit")
		end
		vim.api.nvim_win_set_width(0, 50)
		vim.cmd("wincmd l")
		-- here in new window, we need to set winfixbuf to false
		vim.api.nvim_set_option_value("winfixbuf", false, { win = 0 })
	end

	local buffer_id = get_or_create_buffer(space_id)
	api.nvim_set_current_buf(buffer_id)

	-- First fetch the space hierarchy to cache room names
	matrix.fetch_space_hierarchy(space_id, function(resultHierarchy)
		error.match(
			resultHierarchy,
			vim.schedule_wrap(function(hierarchy)
				render_space_details(space_id, buffer_id, hierarchy)
			end),
			function(err)
				notify.error("Failed to fetch space hierarchy: " .. err.error)
				return nil
			end
		)
	end)
end

--- Close the buffer for a specific space
--- @param buffer_id number The ID of the buffer to close
--- @return boolean True if the buffer was closed, false otherwise
M.close = function(buffer_id)
	buffer_data[buffer_id] = nil

	if not api.nvim_buf_is_loaded(buffer_id) then
		return false
	end

	api.nvim_buf_delete(buffer_id, { force = true })
	return false
end

return M
