local M = {}

---@class neoment.matrix.client.Client
---@field homeserver string The URL of the Matrix server.
---@field device_id string The ID of the device.
---@field private rooms table<string, neoment.matrix.client.Room> A table to store rooms, mapped as room ID to room information.
---@field user_id? string The ID of the user.
---@field access_token? string The access token for authentication.
---@field sync_token? string The token to supply in the since param of the next /sync request. (next_batch)
---@field display_names table<string, string> A table to store display names for users.
M.client = nil

--- @class neoment.matrix.client.Room
--- @field id string The ID of the room.
--- @field is_tracked boolean Indicates if events for this room are being stored. If false, we only store the last message and state events.
--- @field name string The name of the room.
--- @field topic string The topic of the room.
--- @field members table<string, string> A table to store members of the room, mapped as user ID to display name.
--- @field events table<string, neoment.matrix.ClientEventWithoutRoomID> A table to store events associated with the room.
--- @field pending_events table<string, neoment.matrix.ClientEventWithoutRoomID> A table to store pending events associated with the room.
--- @field messages table<string, neoment.matrix.client.Message> A table to store messages associated with the room.
--- @field prev_batch? PreviousBatch The previous batch token for the room.
--- @field last_activity? integer The timestamp of the last activity in the room.
--- @field is_direct? boolean Indicates if the room is a direct chat.
--- @field is_favorite? boolean Indicates if the room is a favorite.
--- @field typing table<string, string> A table to store typing users, it contains the user IDs of users who are typing in the room.
--- @field fully_read? string The event ID of the last fully read message in the room.
--- @field unread_notifications integer The number of unread notifications for this room.

--- @class neoment.matrix.client.Message
--- @field id string The ID of the event.
--- @field sender string The ID of the user who sent the message.
--- @field content string The content of the message.
--- @field formatted_content? string The formatted content of the message, if available.
--- @field timestamp integer The timestamp of when the message was sent.
--- @field was_edited boolean Indicates if the message was edited.
--- @field was_redacted boolean Indicates if the message was redacted.
--- @field mentions table<string> A table to store mentions in the message, it contains the user IDs of users mentioned in the message.
--- @field replying_to? neoment.matrix.client.Message The message being replied to, if available.
--- @field reactions table<string, table<string>> A table to store reactions to the message, it contains the reaction strings as keys and the user IDs of users who reacted as values.
--- @field image? neoment.matrix.client.MessageImage The URL of the image, if the message contains an image.

--- @class neoment.matrix.client.PreviousBatchToken
--- @field token string The previous batch token for the room.

--- @alias PreviousBatch neoment.matrix.client.PreviousBatchToken|"End"|nil

--- @class neoment.matrix.client.MessageImage
--- @field url string The URL of the image.
--- @field height integer? The height of the image.
--- @field width integer? The width of the image.

--- Create a new MatrixClient instance.
--- @param homeserver string The URL of the Matrix server.
--- @param access_token? string The access token for authentication.
M.new = function(homeserver, access_token)
	if M.client then
		return
	end

	M.client = {
		homeserver = homeserver,
		device_id = "neovim-matrix-client",
		rooms = {},
		access_token = access_token,
		display_names = {},
	}
end

--- Create a new room
--- @param room_id string The ID of the room
--- @return neoment.matrix.client.Room The created room object
local function create_new_room(room_id)
	M.client.rooms[room_id] = {
		id = room_id,
		name = room_id,
		topic = "",
		events = {},
		pending_events = {},
		messages = {},
		is_direct = false,
		is_favorite = false,
		members = {},
		typing = {},
		unread_notifications = 0,
		is_tracked = false,
	}

	return M.client.rooms[room_id]
end

--- Get a room by its ID.
--- @param room_id string The ID of the room.
--- @return neoment.matrix.client.Room The room object if found, nil otherwise.
M.get_room = function(room_id)
	if not M.client or not M.client.rooms[room_id] then
		M.client.rooms[room_id] = create_new_room(room_id)
	end

	return M.client.rooms[room_id]
end

--- Get the list of messages in a room.
---- @param room_id string The ID of the room.
--- @return table<string, neoment.matrix.client.Message> The list of messages in the room.
M.get_room_messages = function(room_id)
	local messages = vim.tbl_values(M.get_room(room_id).messages)

	table.sort(messages, function(a, b)
		return a.timestamp < b.timestamp
	end)

	return messages
end

--- Get the last message in a room.
--- @param room_id string The ID of the room.
--- @return neoment.matrix.client.Message? The last message in the room.
M.get_room_last_message = function(room_id)
	local messages = M.get_room_messages(room_id)
	if #messages > 0 then
		return messages[#messages]
	end
	return nil
end

--- Set data for a room.
--- @param room_id string The ID of the room.
--- @param data neoment.matrix.client.Room The data to set for the room.
M.set_room = function(room_id, data)
	M.client.rooms[room_id] = data
end

--- Add a message to a room.
--- @param room_id string The ID of the room.
--- @param message neoment.matrix.client.Message The message to add to the room.
--- @return neoment.matrix.client.Message The added message object.
M.add_room_message = function(room_id, message)
	local room = M.get_room(room_id)

	if not room.is_tracked then
		room.messages = {}
	end

	room.messages[message.id] = message

	return message
end

--- Get the rooms
--- @return table<string, neoment.matrix.client.Room> A table containing all the rooms.
M.get_rooms = function()
	return M.client.rooms
end

--- Get a message by its ID.
--- @param room_id string The ID of the room.
--- @param message_id string The ID of the message.
--- @return neoment.matrix.client.Message? The message object if found, nil otherwise.
M.get_room_message = function(room_id, message_id)
	local room = M.get_room(room_id)

	return room.messages[message_id]
end

--- Check if a room event exists
--- @param room_id string The ID of the room.
--- @param event_id string The ID of the event.
--- @return boolean True if the event exists, false otherwise.
M.room_event_exists = function(room_id, event_id)
	local room = M.get_room(room_id)

	return room.events[event_id] ~= nil
end

--- Add an event to a room.
--- @param room_id string The ID of the room.
--- @param event neoment.matrix.ClientEventWithoutRoomID The event to add to the room.
--- @return neoment.matrix.ClientEventWithoutRoomID The added event object.
M.add_room_event = function(room_id, event)
	local room = M.get_room(room_id)

	if room.is_tracked then
		room.events[event.event_id] = event
	end

	return event
end

--- Set the tracked status of a room.
--- @param room_id string The ID of the room.
--- @param is_tracked boolean The tracked status to set.
--- @return neoment.matrix.client.Room The updated room object.
M.set_room_tracked = function(room_id, is_tracked)
	local room = M.get_room(room_id)

	if not is_tracked then
		room.messages = {}
		room.events = {}
		room.pending_events = {}
		room.prev_batch = nil
	end

	room.is_tracked = is_tracked
	return room
end

return M
