local M = {}

local markdown = require("neoment.markdown")
local util = require("neoment.util")
local matrix = require("neoment.matrix")
local error = require("neoment.error")

local api = vim.api

-- Constants
-- Highlight groups for the members of the room
local user_highlight_groups = {
	"@function",
	"@type",
	"@variable",
	"@keyword",
	"@string",
	"@number",
	"@constant",
	"@comment",
	"@property",
	"@constructor",
	"@conditional",
	"@operator",
	"@exception",
	"@field",
	"@namespace",
	"@include",
	"@parameter",
	"@tag",
	"@text.emphasis",
	"@text.title",
}

local SENDER_NAME_LENGTH = 19
local TIME_FORMAT = "%H:%M:%S"
local SEPARATOR_LENGTH = 60
local ns_id = api.nvim_create_namespace("neoment_highlight")

--- @class neoment.room.MessageRelation
--- @field message neoment.matrix.client.Message The message to reply to
--- @field relation "reply"|"replace" The relation to the message

--- Cache for user highlight groups
--- @type table<string, table<string, string>> A room ID to a table of user IDs and their assigned highlight groups
local room_user_highlights = {}

--- Buffer data
--- @type table<number, BufferData>
local buffer_data = {}

--- @class BufferData
--- @field line_to_message table<number, neoment.room.LineMessage> The mapping of lines to messages
--- @field image_placements table<neoment.room.ImagePlacement> The image placements in the room
--- @field extmarks_data table<number, ExtmarkData> The extmarks data for the room

--- @class neoment.room.ImagePlacement
--- @field placement snacks.image.Placement The image placement object
--- @field height number The image height
--- @field width number The image width
--- @field zoom boolean Whether the image is zoomed or not

--- @class ExtmarkData
--- @field reaction_users? table<string, string[]> The users who reacted to the message

--- Get the buffer data for a specific buffer
--- @param buffer_id number The ID of the buffer to get the data for
--- @return BufferData The buffer data for the specified buffer
local function get_buffer_data(buffer_id)
	if not buffer_data[buffer_id] then
		buffer_data[buffer_id] = {
			line_to_message = {},
			image_placements = {},
			extmarks_data = {},
		}
	end
	return buffer_data[buffer_id]
end

--- Get the image dimensions
--- @param image_width number The width of the image
--- @param image_height number The height of the image
--- @param zoom boolean Whether to zoom the image or not
--- @return {width: number, height: number} The dimensions of the image
local function get_image_dimensions(image_width, image_height, zoom)
	local win_width = vim.api.nvim_win_get_width(0)
	local win_height = vim.api.nvim_win_get_height(0)

	local width = image_width
	local height = image_height

	if zoom then
		width = math.min(image_width, win_width)
		height = math.min(image_height, win_height)
	else
		height = math.min(image_height, win_height * 0.2)
	end

	return {
		width = width,
		height = height,
	}
end

--- Show the buffer for a specific room
--- @param room_id string The ID of the room to create a chat buffer for
--- @return number The ID of the created buffer
M.open_room = function(room_id)
	-- Check if the buffer already exists
	local bufs = api.nvim_list_bufs()
	for _, buf in ipairs(bufs) do
		if api.nvim_buf_is_loaded(buf) then
			if vim.b[buf].room_id == room_id then
				api.nvim_set_current_buf(buf)
				M.update_buffer(buf)
				return buf
			end
		end
	end

	-- Create a new buffer for the room
	local buffer_name = "neoment://" .. matrix.get_room_name(room_id)
	local buffer_id = api.nvim_create_buf(true, false) -- listed=true, scratch=false
	api.nvim_buf_set_name(buffer_id, buffer_name)
	vim.b[buffer_id].room_id = room_id
	api.nvim_set_option_value("filetype", "neoment_room", { buf = buffer_id })
	api.nvim_set_option_value("buftype", "nofile", { buf = buffer_id })
	api.nvim_buf_set_lines(buffer_id, 0, -1, false, { string.rep(" ", 28) .. " │ Loading..." })

	api.nvim_set_current_buf(buffer_id)

	matrix.set_room_tracked(room_id, true)
	M.load_more_messages(buffer_id)
	matrix.fetch_joined_members(room_id, function()
		vim.schedule(function()
			M.update_buffer(buffer_id)
		end)
	end)
	return buffer_id
end

--- Close the buffer for a specific room
--- @param buffer_id number The ID of the buffer to close
--- @param room_id string The ID of the room to close
--- @return boolean True if the buffer was closed, false otherwise
M.close = function(buffer_id, room_id)
	matrix.set_room_tracked(room_id, false)

	buffer_data[buffer_id] = nil

	if not api.nvim_buf_is_loaded(buffer_id) then
		return false
	end

	api.nvim_buf_delete(buffer_id, { force = true })
	return false
end

--- Get the highlight group for a user in a room
--- @param room_id string The ID of the room
--- @param user_id string The ID of the user
--- @return string The highlight group assigned to the user
local function get_user_highlight(room_id, user_id)
	-- Initialize the room_user_highlights table if it doesn't exist
	if not room_user_highlights[room_id] then
		room_user_highlights[room_id] = {}
	end

	-- If the user already has a highlight assigned, return it
	if room_user_highlights[room_id][user_id] then
		return room_user_highlights[room_id][user_id]
	end

	-- Count the number of users with assigned highlights in the room
	local count = 0
	for _ in pairs(room_user_highlights[room_id]) do
		count = count + 1
	end

	-- Set the next highlight for the user, cycling through the user_highlight_groups list
	local highlight_index = (count % #user_highlight_groups) + 1
	room_user_highlights[room_id][user_id] = user_highlight_groups[highlight_index]

	return room_user_highlights[room_id][user_id]
end

--- Update the chat view by room ID
--- @param room_id string The ID of the room to update
M.update_room = function(room_id)
	-- Check if the buffer already exists
	local bufs = api.nvim_list_bufs()
	for _, buf in ipairs(bufs) do
		if api.nvim_buf_is_loaded(buf) then
			if vim.b[buf].room_id == room_id then
				M.update_buffer(buf)
				break
			end
		end
	end
end

--- Get a separator line with a text
--- @param text string The text to display
--- @return string The separator line with the text
local function get_separator_line(text)
	local text_length = vim.fn.strdisplaywidth(text)
	local line_length = (SEPARATOR_LENGTH - text_length - 2) / 2
	local line1_length = math.floor(line_length)
	local line2_length = math.ceil(line_length)
	local line1 = string.rep("─", line1_length)
	local line2 = string.rep("─", line2_length)
	return string.rep(" ", 28) .. " ├" .. line1 .. text .. line2
end

---@class neoment.room.LineMessage : neoment.matrix.client.Message
---@field is_header boolean Whether the line is a header or not
---@field is_last_read? boolean Whether the line is the last read message or not
---@field is_reaction? boolean Whether the line is a reaction or not
---@field is_date? boolean Whether the line is the date or not

--- Generate the lines from the room messages
--- @param buffer_id number The ID of the buffer to update
--- @return table The list of lines to display
local function messages_to_lines(buffer_id)
	local room_id = vim.b[buffer_id].room_id
	local lines = {}
	get_buffer_data(buffer_id).line_to_message = {}
	local line_to_message = get_buffer_data(buffer_id).line_to_message
	local line_index = 1
	local messages = matrix.get_room_messages(room_id)
	local last_read = matrix.get_room_last_read_message(room_id)
	local last_date = nil
	for index, msg in ipairs(messages) do
		---@type neoment.matrix.client.Message
		local message = msg

		-- Weekday month day, year
		local display_date = os.date("%A %B %d, %Y", math.floor(message.timestamp / 1000))
		if last_date ~= display_date then
			last_date = display_date
			local text = " " .. last_date .. " "
			local line = get_separator_line(text)
			table.insert(lines, line)
			line_to_message[line_index] = vim.tbl_extend("force", message, {
				is_header = true,
				is_date = true,
			})
			line_index = line_index + 1
		end
		local time = os.date(TIME_FORMAT, math.floor(message.timestamp / 1000))

		-- Get a friendly name for the sender
		local sender_name = matrix.get_display_name(message.sender)

		-- Check if the content exists
		local content = message.content or ""

		-- If there's a formatted content, convert it to markdown
		if message.formatted_content then
			content = markdown.from_html(message.formatted_content)
		end

		-- Take the 20 first characters of the content
		sender_name = sender_name:sub(1, SENDER_NAME_LENGTH)
		local header = time .. " " .. util.pad_left(sender_name, SENDER_NAME_LENGTH) .. " │"

		local content_lines = {}
		-- Handle replies
		local reply_to = message.replying_to
		if reply_to then
			local reply_content = reply_to.content or ""
			if reply_to.formatted_content then
				reply_content = markdown.from_html(reply_to.formatted_content)
			end
			local reply_sender = matrix.get_display_name(reply_to.sender)

			reply_content = reply_content:gsub("%z", "") -- Remove null characters

			table.insert(content_lines, "┃ " .. reply_sender .. ":")
			for line in reply_content:gmatch("[^\n]+") do
				table.insert(content_lines, "┃ " .. line)
			end
		end

		-- Check for null characters
		content = content:gsub("%z", "")

		-- Split the content into lines
		for line in content:gmatch("[^\n]+") do
			table.insert(content_lines, line)
		end

		-- If there's no content, add an empty line
		if #content_lines == 0 then
			table.insert(content_lines, "")
		end

		-- Mark the first line as containing the user's name
		table.insert(lines, header .. " " .. content_lines[1])
		line_to_message[line_index] = vim.tbl_extend("force", message, {
			is_header = true,
		})
		line_index = line_index + 1

		-- Add additional lines with indentation
		for i = 2, #content_lines do
			--- @type string
			local line = content_lines[i]
			local line_to_add = ""
			if vim.trim(line) ~= "" then
				line_to_add = " " .. line
			end

			table.insert(lines, string.rep(" ", 28) .. " │" .. line_to_add)
			line_to_message[line_index] = vim.tbl_extend("force", message, {
				is_header = false,
			})
			line_index = line_index + 1
		end

		-- Reactions
		if vim.tbl_count(message.reactions) > 0 then
			local reactions_line = ""

			for reaction, users in pairs(message.reactions) do
				local reaction_count = ""
				if #users > 1 then
					reaction_count = " " .. #users
				end
				reactions_line = reactions_line .. string.format(" %s%s", reaction, reaction_count)
			end

			table.insert(lines, string.rep(" ", 28) .. " │" .. reactions_line)
			line_to_message[line_index] = vim.tbl_extend("force", message, {
				is_header = false,
				is_reaction = true,
			})
			line_index = line_index + 1
		end

		-- If the last message read is not the last message, add a line indicating new messages
		if message.id == last_read and index < #messages then
			line_to_message[line_index] = vim.tbl_extend("force", message, {
				is_header = true,
				is_last_read = true,
			})
			line_index = line_index + 1
			local text = "  New messages  "
			local line = get_separator_line(text)
			table.insert(lines, line)
		end
	end

	local typing_users = matrix.get_typing_users(room_id)
	if not vim.tbl_isempty(typing_users) then
		local typing_line = "Typing: "
		for _, user in pairs(typing_users) do
			local display_name = matrix.get_display_name(user)
			typing_line = typing_line .. display_name .. ", "
		end
		typing_line = typing_line:sub(1, -3) -- Remove the last comma and space
		table.insert(lines, string.rep(" ", 28) .. " │ " .. typing_line)
	end

	return lines
end

--- Add edit text to a message
--- @param buffer_id number The ID of the buffer to add the edit text to
--- @param line_index number The index of the line to add the edit text to
local function add_edit_text(buffer_id, line_index)
	api.nvim_buf_set_extmark(buffer_id, ns_id, line_index - 1, 0, {
		virt_text = { { "(edited)", "Comment" } },
	})
end

--- Apply highlights to the lines in the buffer
--- @param buffer_id number The ID of the buffer to apply highlights to
--- @param room_id string The ID of the room to apply highlights to
--- @param lines table The lines to apply highlights to
local function apply_highlights(buffer_id, room_id, lines)
	api.nvim_buf_clear_namespace(buffer_id, ns_id, 0, -1)
	get_buffer_data(buffer_id).extmarks_data = {}
	-- Clear previous images
	for _, p in pairs(get_buffer_data(buffer_id).image_placements) do
		--- @type neoment.room.ImagePlacement
		local placement = p
		placement.placement:close()
	end
	get_buffer_data(buffer_id).image_placements = {}

	local images = {}

	for index, l in ipairs(lines) do
		--- @type string
		local line = l
		-- Apply styles for the vertical bar
		local bar_start = string.find(line, "│") or string.find(line, "├")
		if bar_start then
			vim.hl.range(buffer_id, ns_id, "FloatBorder", { index - 1, bar_start - 1 }, { index - 1, bar_start })
		end
		local time_end = string.len(TIME_FORMAT) -- Time ends after 8 characters
		local name_end = bar_start - 1 -- Name ends before the vertical bar

		local quote_start = string.find(line, "┃")
		if quote_start then
			vim.hl.range(buffer_id, ns_id, "Comment", { index - 1, quote_start }, { index - 1, -1 })
		end

		-- Mentions
		local mention_start, mention_end, link = line:find("%[.-%]%((%S+%))")
		if mention_start and mention_end then
			if link:find("https://matrix.to/#/@[^%s]+:[^%s]+%)") == 1 then
				local hlgroup = "NeomentMention"
				if link:find(matrix.get_user_id()) then
					hlgroup = "NeomentMentionUser"
				end

				vim.hl.range(buffer_id, ns_id, hlgroup, { index - 1, mention_start - 1 }, { index - 1, mention_end })
			end
		end

		---@type neoment.room.LineMessage
		local message = get_buffer_data(buffer_id).line_to_message[index]
		if message then
			-- Show a virtual text when the message was edited
			if message.was_edited then
				-- Add the edit text in the last line of this message
				local next_message = get_buffer_data(buffer_id).line_to_message[index + 1]
				if not next_message or next_message.id ~= message.id then
					add_edit_text(buffer_id, index)
				end
			end

			if message.is_header then
				-- Apply user highlights for the sender's name
				local user_id = message.sender
				local highlight_group = get_user_highlight(room_id, user_id)

				-- Create a dynamic highlight group that links to the Treesitter group
				local hl_group = "NeomentUser_" .. user_id:gsub("[^%w]", "_") .. room_id:gsub("[^%w]", "_")
				-- Try to link to the Treesitter highlight group
				api.nvim_set_hl(0, hl_group, { link = highlight_group, default = true })

				-- Add bold attribute to the linked group
				local hl = api.nvim_get_hl(0, { name = highlight_group, link = false })
				if hl then
					hl.bold = true
					--- @diagnostic disable-next-line: param-type-mismatch
					api.nvim_set_hl(0, hl_group, hl)
				end

				-- Apply highlight to the user's name
				vim.hl.range(buffer_id, ns_id, hl_group, { index - 1, time_end }, { index - 1, name_end })

				if message.image and Snacks then
					table.insert(images, {
						line = index,
						url = message.image.url,
						height = message.image.height,
						width = message.image.width,
					})
				end

				local message_start = bar_start + 1
				if message.was_redacted then
					vim.hl.range(buffer_id, ns_id, "Comment", { index - 1, message_start }, { index - 1, -1 })
				end

				-- Check if the message is the last read message and not the last message
				if message.is_last_read then
					vim.hl.range(buffer_id, ns_id, "Title", { index - 1, message_start }, { index - 1, -1 })
				end

				if message.is_date then
					vim.hl.range(buffer_id, ns_id, "FloatBorder", { index - 1, message_start }, { index - 1, -1 })
				end
			end

			-- Reactions
			if message.is_reaction then
				local reaction_start = line:find("")
				while reaction_start do
					local reaction_end = line:find("", reaction_start)
					if reaction_end then
						-- Check if the user sent this reaction
						-- We need to ge the emoji to get the reaction users
						local content = line:sub(reaction_start + 3, reaction_end - 1)
						-- Remove spaces and digits from the content
						content = content:gsub("[%s%d]+", "")
						local message_reactions = message.reactions[content] or {}
						--- @type table<string>
						local reaction_users = vim.tbl_map(function(r)
							--- @type neoment.matrix.client.MessageReaction
							local reaction = r
							return reaction.sender
						end, message_reactions)
						local border_hl = "NeomentReactionBorder"
						local content_hl = "NeomentReactionContent"
						local user_sent = vim.tbl_contains(reaction_users, matrix.get_user_id())
						-- If the user sent the reaction, we need to change the highlight group
						if user_sent then
							border_hl = "NeomentReactionUserBorder"
							content_hl = "NeomentReactionUserContent"
						end
						local left_border_id =
							vim.api.nvim_buf_set_extmark(buffer_id, ns_id, index - 1, reaction_start - 1, {
								end_col = reaction_start,
								hl_group = border_hl,
							})
						local content_id = vim.api.nvim_buf_set_extmark(buffer_id, ns_id, index - 1, reaction_start, {
							end_col = reaction_end - 1,
							hl_group = content_hl,
						})
						local right_border_id =
							vim.api.nvim_buf_set_extmark(buffer_id, ns_id, index - 1, reaction_end - 1, {
								end_col = reaction_end,
								hl_group = border_hl,
							})
						local extmarks_data = get_buffer_data(buffer_id).extmarks_data
						extmarks_data[left_border_id] = {
							reaction_users = reaction_users,
						}
						extmarks_data[content_id] = {
							reaction_users = reaction_users,
						}
						extmarks_data[right_border_id] = {
							reaction_users = reaction_users,
						}
						reaction_start = line:find("", reaction_end)
					else
						break
					end
				end
			end
		end
	end

	for _, image in ipairs(images) do
		local dimensions = get_image_dimensions(image.width, image.height, false)

		local placement = Snacks.image.placement.new(buffer_id, image.url, {
			pos = { image.line, 33 },
			height = dimensions.height,
			width = dimensions.width,
			inline = true,
			type = "image",
		})
		--- @type neoment.room.ImagePlacement
		local image_placement = {
			placement = placement,
			height = image.height,
			width = image.width,
			zoom = false,
		}
		table.insert(get_buffer_data(buffer_id).image_placements, image_placement)

		vim.schedule(function()
			placement:show()
		end)
	end

	-- Apply Comment highlight for the typing users, if any
	if not vim.tbl_isempty(matrix.get_typing_users(room_id)) then
		vim.hl.range(buffer_id, ns_id, "Comment", { #lines - 1, 31 }, { #lines - 1, -1 })
	end
end

--- Update the chat view with the latest messages
--- @param buffer_id number The ID of the buffer to update
M.update_buffer = function(buffer_id)
	if not api.nvim_buf_is_loaded(buffer_id) then
		return
	end
	local room_id = vim.b[buffer_id].room_id

	if not room_id then
		return
	end

	if buffer_id == api.nvim_get_current_buf() then
		M.mark_read(buffer_id)
	end

	local winbar = matrix.get_room_name(room_id)
	local topic = matrix.get_room_topic(room_id)
	if topic ~= "" then
		winbar = winbar .. " - " .. topic
	end
	vim.wo.winbar = winbar

	local lines = messages_to_lines(buffer_id)

	-- Update the buffer with the new lines
	api.nvim_set_option_value("modifiable", true, { buf = buffer_id })
	api.nvim_buf_set_lines(buffer_id, 0, -1, false, lines)
	api.nvim_set_option_value("modifiable", false, { buf = buffer_id })
	api.nvim_set_option_value("modified", false, { buf = buffer_id })

	-- Apply highlights for each line
	apply_highlights(buffer_id, room_id, lines)
end

--- Send a message to the room
--- @param room_id string The ID of the room to send the message to
--- @param message string The message to send
--- @param relation? neoment.room.MessageRelation The relation to the message
local function send_message(room_id, message, relation)
	local params = { message = message }

	if relation then
		if relation.relation == "reply" then
			params.reply_to = relation.message.id
		elseif relation.relation == "replace" then
			params.replace = relation.message.id
		end
	end

	matrix.send_message(room_id, params, function(response)
		error.map_error(response, function(err)
			vim.notify("Error sending message: " .. err.error, vim.log.levels.ERROR)
			return nil
		end)
	end)
end

--- Prompt the user for a message and send it to the room using a dedicated buffer
--- @param relation? neoment.room.MessageRelation The relation to the message
M.prompt_message = function(relation)
	local room_id = vim.b.room_id
	local room_win = vim.api.nvim_get_current_win()

	if not room_id then
		vim.notify("Couldn't identify the current room", vim.log.levels.ERROR)
		return
	end

	local room_name = matrix.get_room_name(room_id)
	local buffer_name = "neoment://Sending to " .. room_name

	-- Create a new buffer for input
	local input_buf = vim.api.nvim_create_buf(false, true) -- listed=false, scratch=true
	-- Store room_id and parent buffer in buffer variables
	vim.b[input_buf].room_id = room_id
	vim.b[input_buf].room_win = room_win
	vim.b[input_buf].members = matrix.get_room_other_members(room_id)

	local lines = {}

	if relation then
		vim.b[input_buf].relation = relation
		if relation.relation == "reply" then
			buffer_name = string.format("neoment://Replying to %s", matrix.get_display_name(relation.message.sender))
		elseif relation.relation == "replace" then
			buffer_name = string.format("neoment://Editing message on %s", room_name)
			for line in relation.message.content:gmatch("[^\n]+") do
				table.insert(lines, line)
			end
		end
	end

	vim.api.nvim_buf_set_name(input_buf, buffer_name)
	vim.api.nvim_set_option_value("filetype", "neoment_compose.markdown", { buf = input_buf })
	vim.api.nvim_set_option_value("omnifunc", "v:lua.neoment_compose_omnifunc", { buf = input_buf })

	-- Open split at bottom
	vim.cmd("botright 10split")

	vim.api.nvim_win_set_buf(0, input_buf)
	vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, lines)

	if relation and relation.relation == "replace" then
		-- Go to the end of the message (last line and last column)
		local last_line = vim.api.nvim_buf_line_count(input_buf)
		local last_col = vim.fn.strdisplaywidth(lines[#lines])
		vim.api.nvim_win_set_cursor(0, { last_line, last_col })
	else
		-- Start in insert mode
		vim.cmd("startinsert")
	end
end

--- Function to send message and close the compose buffer
--- @param compose_buf number The ID of the compose buffer
M.send_and_close_compose = function(compose_buf)
	local lines = vim.api.nvim_buf_get_lines(compose_buf, 0, -1, false)
	local message = table.concat(lines, "\n")
	local room_id = vim.b[compose_buf].room_id
	local room_win = vim.b[compose_buf].room_win
	local relation = vim.b[compose_buf].relation

	if not room_id then
		vim.notify("Couldn't identify the current room", vim.log.levels.ERROR)
		return
	end

	if not message or vim.trim(message) == "" then
		return
	end

	send_message(room_id, message, relation)

	vim.schedule(function()
		local current_win = vim.api.nvim_get_current_win()
		vim.api.nvim_set_current_win(room_win)
		vim.api.nvim_win_close(current_win, true)
	end)
end

--- Load more messages in the room
--- @param buffer_id? number The ID of the buffer to load more messages for
M.load_more_messages = function(buffer_id)
	local room_buffer = buffer_id or vim.api.nvim_get_current_buf()
	local room_id = vim.b[room_buffer].room_id

	if not room_id then
		vim.notify("Couldn't identify the current room", vim.log.levels.ERROR)
		return
	end

	local prev_batch = matrix.get_room_prev_batch(room_id)
	if prev_batch == "End" then
		vim.notify("No more messages to load", vim.log.levels.INFO)
		return
	end

	local notification = vim.notify("Loading more messages...", vim.log.levels.INFO, {
		timeout = false,
	})
	matrix.load_more_messages(room_id, function(response)
		local notify = error.match(response, function()
			vim.schedule(function()
				M.update_buffer(buffer_id or 0)
				if prev_batch == nil and room_buffer == api.nvim_get_current_buf() then
					-- Jump to the last message
					local last_line = api.nvim_buf_line_count(room_buffer)
					api.nvim_win_set_cursor(0, { last_line, 0 })
				end
			end)
			return {
				message = "Messages loaded",
				level = vim.log.levels.INFO,
			}
		end, function(err)
			return {
				message = "Error loading more messages: " .. (err.error or "Unknown error"),
				level = vim.log.levels.ERROR,
			}
		end)

		vim.notify(notify.message, notify.level, {
			-- For snacks
			id = notification and notification.id,
			-- For nvim-notify
			replace = notification,
			timeout = 3000,
		})
	end)

	return true
end

--- Mark the room as read
--- @param buffer_id number The ID of the buffer to mark as read
M.mark_read = function(buffer_id)
	local room_id = vim.b[buffer_id].room_id
	if not room_id then
		vim.notify("Couldn't identify the current room", vim.log.levels.ERROR)
		return
	end

	local last_message = matrix.get_room_last_message(room_id)
	if not last_message then
		return
	end

	local fully_read = matrix.get_room_last_read_message(room_id)
	if fully_read == last_message.id then
		return
	end

	matrix.set_room_read_marker(room_id, {
		read = last_message.id,
		fully_read = last_message.id,
	}, function(response)
		error.map(response, function()
			vim.schedule(function()
				M.update_buffer(buffer_id)
			end)
			return nil
		end)
	end)

	M.update_buffer(buffer_id)
end

--- Get the message under the cursor
--- @return neoment.Error<neoment.room.LineMessage, {}> The message under the cursor or an error
local function get_message_under_cursor()
	local line_number = vim.api.nvim_win_get_cursor(0)[1]
	local buffer_id = vim.api.nvim_get_current_buf()
	local message = get_buffer_data(buffer_id).line_to_message[line_number]

	if not message then
		vim.notify("No message under the cursor", vim.log.levels.ERROR)
		return error.error({})
	end

	return error.ok(message)
end

--- Edit the message under the cursor
M.edit_message = function()
	local error_message = get_message_under_cursor()
	error.map(error_message, function(message)
		if message.sender ~= matrix.get_user_id() then
			vim.notify("You can only edit your own messages", vim.log.levels.ERROR)
			return nil
		end

		M.prompt_message({
			message = message,
			relation = "replace",
		})
		return nil
	end)
end

--- Reply the message under the cursor
M.reply_message = function()
	local error_message = get_message_under_cursor()
	error.map(error_message, function(message)
		M.prompt_message({
			message = message,
			relation = "reply",
		})
		return nil
	end)
end

--- React to the message under the cursor
M.react_message = function()
	local error_message = get_message_under_cursor()
	error.map(error_message, function(message)
		local emoji = require("neoment.emoji")

		-- Prompt for a reaction
		return vim.ui.select(emoji(), {
			prompt = "Select reaction: ",
			format_item = function(e)
				return e.label
			end,
		}, function(choice)
			if not choice then
				return
			end
			local chosen_emoji = choice.insertText
			local current_buf = vim.api.nvim_get_current_buf()
			local room_id = vim.b[current_buf].room_id

			-- Get the reactions for the message
			local reactions = message.reactions[chosen_emoji]

			if reactions then
				-- If the user already made the same reaction, remove it
				--- @type neoment.matrix.client.MessageReaction|nil
				local already_reacted = vim.iter(reactions):find(function(r)
					--- @type neoment.matrix.client.MessageReaction
					local reaction = r
					return reaction.sender == matrix.get_user_id()
				end)

				if already_reacted then
					matrix.redact_event(room_id, already_reacted.event_id, nil, function(response)
						error.match(response, function()
							vim.schedule(function()
								M.update_buffer(current_buf)
							end)
							return nil
						end, function(err)
							vim.notify("Error removing reaction: " .. err.error, vim.log.levels.ERROR)
							return nil
						end)
					end)
					return
				end
			end

			matrix.send_reaction(room_id, message.id, chosen_emoji, function(response)
				error.map(response, function()
					return vim.schedule(function()
						M.update_buffer(current_buf)
					end)
				end)
			end)
		end)
	end)
end

-- Redact the message under the cursor
M.redact_message = function()
	local error_message = get_message_under_cursor()
	error.map(error_message, function(message)
		if message.sender ~= matrix.get_user_id() then
			vim.notify("You can only redact your own messages", vim.log.levels.ERROR)
			return nil
		end

		local reason = vim.fn.input("Redact message reason: ")

		local current_buf = vim.api.nvim_get_current_buf()
		matrix.redact_event(vim.b[current_buf].room_id, message.id, reason, function(response)
			error.match(response, function()
				vim.schedule(function()
					M.update_buffer(current_buf)
				end)
				return nil
			end, function(err)
				vim.notify("Error redacting message: " .. err.error, vim.log.levels.ERROR)
				return nil
			end)
		end)

		return nil
	end)
end

--- Handle the cursor hold event
--- Depending on the context, it will show a float window with information
--- @param buffer_id number The ID of the buffer to handle the cursor hold event for
M.handle_cursor_hold = function(buffer_id)
	local pos = vim.api.nvim_win_get_cursor(0)
	local extmark = vim.api.nvim_buf_get_extmarks(
		buffer_id,
		ns_id,
		{ pos[1] - 1, pos[2] },
		{ pos[1] - 1, pos[2] },
		{ details = true, overlap = true }
	)[1]
	if not extmark then
		return
	end

	local extmark_id = extmark[1]
	local data = get_buffer_data(buffer_id).extmarks_data[extmark_id]
	if not data then
		return
	end

	local reaction_users = data.reaction_users
	if reaction_users and #reaction_users > 0 then
		-- Create a float window with the reaction users
		local lines = {}
		local max_length = 0
		for _, user in ipairs(reaction_users) do
			local display_name = matrix.get_display_name(user)
			table.insert(lines, display_name)
			max_length = math.max(max_length, vim.fn.strdisplaywidth(display_name))
		end
		local height = math.min(5, #lines)

		util.open_float(lines, {
			width = max_length,
			height = height,
		})
	end
end

--- Toggle the zoom of the image under the cursor
M.toggle_image_zoom = function()
	local buffer_id = vim.api.nvim_get_current_buf()
	local line_number = vim.api.nvim_win_get_cursor(0)[1]
	local image_placements = get_buffer_data(buffer_id).image_placements
	for _, p in ipairs(image_placements) do
		--- @type neoment.room.ImagePlacement
		local placement = p
		if placement.placement.opts.pos[1] == line_number then
			placement.zoom = not placement.zoom
			local dimensions = get_image_dimensions(placement.width, placement.height, placement.zoom)
			placement.placement.opts.height = dimensions.height
			placement.placement.opts.width = dimensions.width
			placement.placement:update()
			return
		end
	end
	vim.notify("No image on this line", vim.log.levels.ERROR)
end

return M
