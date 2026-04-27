local M = {}

local config = require("neoment.config")
local constants = require("neoment.constants")
local icon = require("neoment.icon")
local notify = require("neoment.notify")
local util = require("neoment.util")
local matrix = require("neoment.matrix")

local ns_id = vim.api.nvim_create_namespace("neoment_room_info")

local IMAGE_WIDTH = 16
local IMAGE_HEIGHT = 8

--- @class neoment.info.BufferData
--- @field avatar neoment.info.BufferDataAvatar

--- @class neoment.info.BufferDataAvatar
--- @field placement snacks.image.Placement|nil
--- @field zoomed boolean

--- @type table<number, neoment.info.BufferData>
local buffer_data = {}

--- Initialize buffer data for a new buffer
--- @return neoment.info.BufferData
local function new_buffer_data()
	return {
		avatar = {
			placement = nil,
			zoomed = false,
		},
	}
end

--- Clean up avatar placement for a buffer
--- @param buffer_id number
M.cleanup_avatar = function(buffer_id)
	local data = buffer_data[buffer_id]
	if not data then
		return
	end

	if data.avatar.placement then
		data.avatar.placement:close()
		data.avatar.placement = nil
	end
	data.avatar = { placement = nil, zoomed = false }
end

--- Clean up the buffer data
--- @param buffer_id number
M.cleanup_buffer = function(buffer_id)
	M.cleanup_avatar(buffer_id)
	buffer_data[buffer_id] = nil
end

--- Render "No image" fallback text
--- @param buffer_id number
local function render_fallback_avatar(buffer_id)
	vim.api.nvim_buf_set_extmark(buffer_id, ns_id, 0, 0, {
		virt_lines = { {
			{ "No image", "Comment" },
		} },
	})
end

--- Render room avatar if Snacks is available, otherwise render fallback
--- @param buffer_id number The buffer ID
--- @param room_id string The room ID
local function render_avatar(buffer_id, room_id)
	M.cleanup_avatar(buffer_id)

	local avatar_url = matrix.get_room_avatar(room_id)

	if not Snacks or not avatar_url then
		render_fallback_avatar(buffer_id)
		return
	end

	local url = util.mxc_to_url(matrix.client.homeserver, avatar_url) .. "?access_token=" .. matrix.client.access_token

	require("snacks.image.terminal").detect(function()
		--- @type snacks.image.Opts
		local opts = {
			pos = { 1, 0 },
			height = IMAGE_HEIGHT,
			width = IMAGE_WIDTH,
			inline = true,
			type = "image",
		}

		local placement = Snacks.image.placement.new(buffer_id, url, opts)
		buffer_data[buffer_id].avatar.placement = placement
	end)
end

--- Helper to render a status line as bubble (active) or plain text (inactive)
--- @param buffer_id number The buffer ID
--- @param line number The line number to place the status on
--- @param active boolean Whether the status is active
--- @param status_icon string The icon to display for this status
--- @param label string The label to display for this status
--- @param key string The key to display in the hint for toggling this status
local function render_status(buffer_id, line, active, status_icon, label, key)
	local localleader = vim.g.maplocalleader or "\\"
	local hint = "  [" .. localleader .. key .. "] toggle"

	if active then
		vim.api.nvim_buf_set_extmark(buffer_id, ns_id, line, 0, {
			virt_text = {
				{ icon.border_left, "NeomentBubbleActiveBorder" },
				{ " " .. status_icon .. " " .. label .. " ", "NeomentBubbleActiveContent" },
				{ icon.border_right, "NeomentBubbleActiveBorder" },
				{ hint, "Comment" },
			},
			virt_text_pos = "overlay",
		})
	else
		vim.api.nvim_buf_set_extmark(buffer_id, ns_id, line, 0, {
			virt_text = {
				{ "  " .. status_icon .. " " .. label .. " ", "Comment" },
				{ hint, "Comment" },
			},
			virt_text_pos = "overlay",
		})
	end
end

--- Apply highlights and extmarks to the buffer
--- @param buffer_id number The buffer ID
--- @param metadata table Table containing line positions for sections
local function apply_highlights(buffer_id, metadata)
	vim.api.nvim_buf_clear_namespace(buffer_id, ns_id, 0, -1)
	local config_icon = config.get().icon
	if not buffer_data[buffer_id] then
		buffer_data[buffer_id] = new_buffer_data()
	end

	-- 1. Header: Room name with decoration line below
	local win_width = 80
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buffer_id then
			win_width = vim.api.nvim_win_get_width(win)
			break
		end
	end

	local title = metadata.room_name
	local title_len = vim.fn.strdisplaywidth(title)
	local decoration_char = "─"
	local total_decoration = math.max(win_width - title_len - 2, 0) -- spaces around title
	local left_len = math.floor(total_decoration / 2)
	local right_len = math.ceil(total_decoration / 2)

	vim.api.nvim_buf_set_extmark(buffer_id, ns_id, metadata.header_line, 0, {
		virt_text = {
			{ string.rep(decoration_char, left_len) .. " ", "NeomentHeaderDecoration" },
			{ title, "NeomentRoomsTitle" },
			{ " " .. string.rep(decoration_char, right_len), "NeomentHeaderDecoration" },
		},
		virt_text_pos = "overlay",
	})

	-- 2. Status bubbles
	render_status(buffer_id, metadata.favorite_line, metadata.is_favorite, config_icon.favorite, "Favorite", "a")
	render_status(
		buffer_id,
		metadata.lowpriority_line,
		metadata.is_lowpriority,
		config_icon.low_priority,
		"Low Priority",
		"l"
	)

	if metadata.direct_line then
		render_status(buffer_id, metadata.direct_line, metadata.is_direct, config_icon.people, "Direct Message", "d")
	end

	-- 3. Section headers
	for _, line in ipairs(metadata.section_lines) do
		vim.hl.range(buffer_id, ns_id, "NeomentSectionTitle", { line, 0 }, { line, -1 })
	end

	-- 4. Secondary text: user IDs in members list
	for _, line in ipairs(metadata.member_id_lines) do
		local line_text = vim.api.nvim_buf_get_lines(buffer_id, line, line + 1, false)[1] or ""
		local id_start = line_text:find("%(@?[^)]+%)$")
		if id_start then
			vim.api.nvim_buf_set_extmark(buffer_id, ns_id, line, id_start - 1, {
				end_col = #line_text,
				hl_group = "Comment",
			})
		end
	end

	-- Render avatar
	render_avatar(buffer_id, metadata.room_id)
end

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
	vim.wo[win][0].wrap = true
	vim.wo[win][0].foldmethod = "manual"
	vim.wo[win][0].signcolumn = "no"
	vim.wo[win][0].number = false
	vim.wo[win][0].relativenumber = false

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
	local room
	if matrix.has_room(room_id) then
		room = matrix.get_room(room_id)
	elseif matrix.has_invited_room(room_id) then
		room = matrix.get_invited_room(room_id)
	end

	if not room then
		return
	end

	-- Initialize members_expanded state
	if vim.b[buffer_id].members_expanded == nil then
		vim.b[buffer_id].members_expanded = false
	end
	local lines = {}

	--- @type table
	local metadata = {
		room_id = room_id,
		room_name = matrix.get_room_display_name(room_id),
		header_line = 0,
		is_favorite = room.is_favorite,
		is_lowpriority = room.is_lowpriority,
		is_direct = room.is_direct,
		favorite_line = nil,
		lowpriority_line = nil,
		direct_line = nil,
		section_lines = {},
		member_id_lines = {},
	}

	-- Helper to track current line index (0-based)
	local function current_line()
		return #lines
	end

	-- Header line (room name, rendered via extmark)
	metadata.header_line = current_line()
	table.insert(lines, "")

	-- Room type
	local room_type = "Room"
	if matrix.is_space(room_id) then
		room_type = "Space"
	elseif room.is_direct then
		room_type = "Direct Message"
	end
	table.insert(lines, "Room Type: " .. room_type)
	table.insert(lines, "")

	-- Topic
	if room.topic and room.topic ~= "" then
		table.insert(lines, "Topic:")
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
		table.insert(lines, "Space: " .. space_name)
		table.insert(lines, "")
	end

	-- Status section
	table.insert(lines, "Status:")
	metadata.favorite_line = current_line()
	table.insert(lines, "")
	metadata.lowpriority_line = current_line()
	table.insert(lines, "")
	if room.is_direct ~= nil then
		metadata.direct_line = current_line()
		table.insert(lines, "")
	end
	table.insert(lines, "")

	-- Links section
	local aliases = matrix.get_room_aliases(room_id)
	local links_line = current_line()
	table.insert(metadata.section_lines, links_line)
	table.insert(lines, "── Links ──")
	table.insert(lines, "Room ID: " .. room_id)
	if #aliases > 0 then
		table.insert(lines, "Aliases:")
		vim.iter(aliases):each(function(alias)
			table.insert(lines, "  - " .. alias)
		end)
	end
	table.insert(lines, "")

	-- Members section
	local members = matrix.get_room_members(room_id)
	local member_count = vim.tbl_count(members)
	local members_line = current_line()
	table.insert(metadata.section_lines, members_line)

	if vim.b[buffer_id].members_expanded then
		table.insert(lines, string.format("── Members (%d) ──", member_count))

		local member_list = {}
		for user_id, member_name in pairs(members) do
			table.insert(member_list, { user_id = user_id, display_name = member_name })
		end
		table.sort(member_list, function(a, b)
			return a.display_name:lower() < b.display_name:lower()
		end)

		for _, member in ipairs(member_list) do
			local line_idx = current_line()
			if member.display_name and member.display_name ~= member.user_id then
				table.insert(lines, string.format("  - %s (%s)", member.display_name, member.user_id))
				table.insert(metadata.member_id_lines, line_idx)
			else
				table.insert(lines, string.format("  - %s", member.user_id))
			end
		end
	else
		table.insert(lines, string.format("── Members (%d) ── [Tab to expand]", member_count))
	end
	table.insert(lines, "")

	-- Set buffer contents
	util.buffer_write(buffer_id, lines, 0, -1)
	apply_highlights(buffer_id, metadata)
end

--- Toggle a room tag (e.g. favorite, low priority) for the room displayed in this buffer
--- @param buffer_id number The buffer ID
--- @param tag "m.favourite"|"m.lowpriority"|"m.direct" The tag to toggle
local function toggle_tag(buffer_id, tag)
	local room_id = vim.b[buffer_id].room_id
	if not room_id then
		return
	end

	if matrix.has_invited_room(room_id) then
		notify.info("Cannot modify status for invited rooms")
		return
	end

	local rooms = require("neoment.rooms")
	if tag == "m.direct" then
		rooms.toggle_direct_on(room_id)
		M.update_buffer(buffer_id)
		return
	end

	---@cast tag "m.favourite"|"m.lowpriority"
	rooms.toggle_room_tag(tag, room_id, function()
		M.update_buffer(buffer_id)
	end)
end

--- Toggle favorite status for the room displayed in this buffer
--- @param buffer_id number The buffer ID
M.toggle_favorite = function(buffer_id)
	toggle_tag(buffer_id, "m.favourite")
end

--- Toggle low priority status for the room displayed in this buffer
--- @param buffer_id number The buffer ID
M.toggle_low_priority = function(buffer_id)
	toggle_tag(buffer_id, "m.lowpriority")
end

--- Toggle direct message status for the room displayed in this buffer
--- @param buffer_id number The buffer ID
M.toggle_direct = function(buffer_id)
	toggle_tag(buffer_id, "m.direct")
end

--- Toggle the expanded state of the members list
--- @param buffer_id number The buffer ID
M.toggle_members = function(buffer_id)
	local current = vim.b[buffer_id].members_expanded or false
	vim.b[buffer_id].members_expanded = not current
	M.update_buffer(buffer_id)
end

--- Toggle the avatar image zoom
--- @param buffer_id number The buffer ID
M.toggle_avatar_zoom = function(buffer_id)
	local data = buffer_data[buffer_id]
	if not data then
		return
	end

	local placement = data.avatar.placement
	if not placement then
		notify.info("No avatar image to zoom")
		return
	end

	local zoomed = data.avatar.zoomed or false
	data.avatar.zoomed = not zoomed

	if not zoomed then
		placement.opts.height = vim.api.nvim_win_get_height(0)
		placement.opts.width = vim.api.nvim_win_get_width(0)
	else
		placement.opts.height = IMAGE_HEIGHT
		placement.opts.width = IMAGE_WIDTH
	end
	placement:update()
end

return M
