local M = {}

local client = require("neoment.matrix.client")
local error = require("neoment.error")
local api = require("neoment.matrix.api")
local util = require("neoment.util")

--- @type table<string, neoment.matrix.client.MessageAttachmentType>
local attachment_types = {
	["m.image"] = "image",
	["m.file"] = "file",
	["m.audio"] = "audio",
	["m.location"] = "location",
	["m.video"] = "video",
	["m.sticker"] = "image",
}

--- Get the thumbnail from an event
--- @param event neoment.matrix.ClientEventWithoutRoomID The event to get the thumbnail from
--- @return neoment.matrix.client.MessageImage|nil The thumbnail object
local function get_thumbnail(event)
	if event.content.info and event.content.info.thumbnail_url and event.content.info.thumbnail_info then
		return {
			type = "image",
			filename = "thumbnail",
			url = util.mxc_to_url(client.client.homeserver, event.content.info.thumbnail_url)
				.. "?access_token="
				.. client.client.access_token,
			height = event.content.info.thumbnail_info.h,
			width = event.content.info.thumbnail_info.w,
			mimetype = event.content.info.thumbnail_info.mimetype,
		}
	end
	return nil
end

--- Get an attachment from an event
--- @param event neoment.matrix.ClientEventWithoutRoomID The event to get the attachment from
--- @param attachment_type neoment.matrix.client.MessageAttachmentType The type of the attachment
--- @return neoment.matrix.client.MessageAttachment The attachment object
local function get_attachment(event, attachment_type)
	-- Handle location first because it has a different structure
	if attachment_type == "location" then
		local geo_uri = event.content.geo_uri
		local google_maps_url = nil

		if geo_uri then
			local latitude, longitude = geo_uri:match("geo:([%-%d%.]+),([%-%d%.]+)")
			if latitude and longitude then
				google_maps_url = "https://maps.google.com/?q=" .. latitude .. "," .. longitude
			end
		end

		local thumbnail = get_thumbnail(event)

		return {
			type = "location",
			url = google_maps_url,
			thumbnail = thumbnail,
		}
	end

	-- Create a partial attachment object with the base fields
	--- @type neoment.matrix.client.MessageAttachment
	local attachment = {
		type = attachment_type,
		mimetype = event.content.info and event.content.info.mimetype,
		mxc_url = event.content.url,
		url = util.mxc_to_url(client.client.homeserver, event.content.url)
			.. "?access_token="
			.. client.client.access_token,
		filename = event.content.filename,
	}

	-- Add the specific fields based on the attachment type
	if attachment_type == "image" then
		attachment.height = event.content.info and event.content.info.h
		attachment.width = event.content.info and event.content.info.w
	elseif attachment_type == "file" then
		attachment.size = event.content.info and event.content.info.size
	elseif attachment_type == "audio" then
		attachment.size = event.content.info and event.content.info.size
		attachment.duration = event.content.info and event.content.info.duration
	elseif attachment_type == "video" then
		local thumbnail = get_thumbnail(event)

		attachment.duration = event.content.info and event.content.info.duration
		attachment.thumbnail = thumbnail
		attachment.size = event.content.info and event.content.info.size
	end

	return attachment
end

--- Add an event to the pending events
--- @param room_id string The room ID
--- @param target_event_id string The ID of the event that this event is related to
--- @param event neoment.matrix.ClientEventWithoutRoomID The event to add
local function add_pending_event(room_id, target_event_id, event)
	local room = client.get_room(room_id)

	-- Remove the event in the room's events table and add to the pending events table
	room.events[event.event_id] = nil
	room.pending_events[target_event_id] = event
end

--- Fetch a room event by its ID.
--- @param room_id string The ID of the room.
--- @param event_id string The ID of the event.
--- @return neoment.Error<neoment.matrix.ClientEventWithoutRoomID, neoment.matrix.api.Error> The event object.
local function fetch_room_event_by_id(room_id, event_id)
	return api.get_sync(client.client.homeserver .. "/_matrix/client/v3/rooms/" .. room_id .. "/event/" .. event_id, {
		headers = {
			Authorization = "Bearer " .. client.client.access_token,
		},
	})
end

--- Convert a Matrix event to a message.
--- @param event neoment.matrix.ClientEventWithoutRoomID The event to convert.
--- @param replying_to? neoment.matrix.client.Message The message being replied to, if available.
--- @return neoment.matrix.client.Message The converted message object.
local function event_to_message(event, replying_to)
	-- Check if the content is formatted
	local content = event.content.body
	local formatted_content = nil
	if event.content.format == "org.matrix.custom.html" and event.content.formatted_body then
		formatted_content = event.content.formatted_body
	end

	if event.content["m.new_content"] then
		-- If the event is a replacement, use the new content
		content = event.content["m.new_content"].body or content
		formatted_content = event.content["m.new_content"].formatted_body or formatted_content
	end

	local mentions = {}
	if event.content["m.mentions"] then
		mentions = event.content["m.mentions"].user_ids or {}
	end
	if replying_to then
		for _, mention in ipairs(replying_to.mentions) do
			table.insert(mentions, mention)
		end
	end

	--- @type neoment.matrix.client.MessageAttachment|nil
	local attachment
	local attachment_type = attachment_types[event.content.msgtype] or attachment_types[event.type]
	if attachment_type and event.content.url then
		attachment = get_attachment(event, attachment_type)
	end

	--- @type neoment.matrix.client.Message
	return {
		id = event.event_id,
		sender = event.sender,
		content = content,
		formatted_content = formatted_content,
		timestamp = event.origin_server_ts,
		age = event.unsigned and event.unsigned.age or nil,
		was_edited = false,
		was_redacted = false,
		mentions = mentions,
		replying_to = replying_to,
		reactions = {},
		attachment = attachment,
		is_state = false,
	}
end

--- Convert a Matrix state event to a message.
--- @param event neoment.matrix.ClientEventWithoutRoomID The state event to convert.
--- @return neoment.matrix.client.Message? The converted message object.
local function state_event_to_message(event)
	local membership = event.content.membership
	local prev_content = event.unsigned and event.unsigned.prev_content or nil
	local sender_name = require("neoment.matrix").get_display_name_or_fetch(event.sender)
	local message_action
	if membership == "join" then
		message_action = "joined the room"
		if prev_content and prev_content.membership == "join" then
			if event.content.displayname ~= prev_content.displayname then
				if event.content.displayname then
					message_action = "changed display name from "
						.. prev_content.displayname
						.. " to "
						.. event.content.displayname
				else
					message_action = "removed their display name"
				end
			elseif event.content.avatar_url ~= prev_content.avatar_url then
				message_action = "changed avatar picture"
			end
		end
	elseif membership == "leave" then
		message_action = "left the room"
		if prev_content then
			if prev_content.membership == "invite" then
				if event.sender ~= event.state_key then
					message_action = "had their invite to the room revoked by " .. sender_name
				else
					message_action = "rejected the invite to the room"
				end
			elseif prev_content.membership == "join" and event.sender ~= event.state_key then
				message_action = "was removed from the room by " .. sender_name
			elseif prev_content.membership == "ban" then
				message_action = "was unbanned from the room by " .. sender_name
			elseif prev_content.membership == "knock" then
				if event.sender ~= event.state_key then
					message_action = "had their knock to the room denied by " .. sender_name
				else
					message_action = "retracted their knock to the room"
				end
			end
		end
	elseif membership == "invite" then
		message_action = "was invited to the room"
		if prev_content then
			if prev_content.membership == "leave" then
				message_action = "was re-invited to the room"
			elseif prev_content.membership == "knock" then
				message_action = "had their knock to the room accepted by " .. sender_name
			end
		end
	elseif membership == "ban" then
		message_action = "was banned from the room by " .. sender_name
		if prev_content and prev_content.membership == "join" then
			message_action = "was kicked and banned from the room by " .. sender_name
		end
	elseif membership == "knock" then
		message_action = "is knocking on the room"
		if prev_content and prev_content.membership == "invite" then
			message_action = "is re-knocking on the room"
		end
	else
		return nil -- Unsupported membership type
	end

	if event.content.displayname then
		require("neoment.matrix").set_display_name(
			event.state_key,
			event.content.displayname,
			event.origin_server_ts or 0
		)
	end

	local display_name = require("neoment.matrix").get_display_name(event.state_key)

	local content = string.format("%s %s", display_name, message_action)

	--- @type neoment.matrix.client.Message
	return {
		id = event.event_id,
		sender = event.sender,
		content = content,
		formatted_content = nil,
		timestamp = event.origin_server_ts,
		age = event.unsigned and event.unsigned.age or nil,
		was_edited = false,
		was_redacted = false,
		mentions = {},
		replying_to = nil,
		reactions = {},
		attachment = nil,
		is_state = true,
	}
end

--- Process a message event
--- @param room_id string The ID of the room
--- @param event neoment.matrix.ClientEventWithoutRoomID The event to process
--- @return boolean True if the room list needs to be updated
local function handle_message(room_id, event)
	-- Check if there is content in the event
	if not event.content or not event.content.body then
		return false
	end

	local replying_to = nil
	-- Handle related events
	if event.content["m.relates_to"] then
		-- Handle replacing
		local relates_to = event.content["m.relates_to"]
		if relates_to.rel_type == "m.replace" then
			---@type string
			local replaced_event_id = relates_to.event_id
			local replaced_message = client.get_room_message(room_id, replaced_event_id)

			if replaced_message then
				local new_content = event.content["m.new_content"]
				if new_content then
					replaced_message.content = new_content.body
					replaced_message.formatted_content = new_content.formatted_body
					replaced_message.was_edited = true
					return true
				end
			else
				-- If the message is not found, store the event in pending events
				add_pending_event(room_id, replaced_event_id, event)
				return false
			end
		elseif relates_to["m.in_reply_to"] then
			-- Handle replying
			local event_id = relates_to["m.in_reply_to"].event_id
			local replying_event = fetch_room_event_by_id(room_id, event_id)
			replying_to = error.match(replying_event, function(e)
				-- If the event was replaced, fetch the replacement event
				if e.unsigned and e.unsigned["m.relations"] and e.unsigned["m.relations"]["m.replace"] then
					local replacement = e.unsigned["m.relations"]["m.replace"]
					return event_to_message(replacement)
				end
				return event_to_message(e) --[[@as neoment.matrix.client.Message|nil]]
			end, function(_)
				return nil
			end)
		end
	end

	client.add_room_message(room_id, event_to_message(event, replying_to))

	-- Check if the events contains a "m.replace" relation applied to it
	-- If so, handle the replacement event
	if event.unsigned and event.unsigned["m.relations"] and event.unsigned["m.relations"]["m.replace"] then
		local replace_event = event.unsigned["m.relations"]["m.replace"]
		M.handle(room_id, replace_event)
	end

	-- Update the last activity timestamp
	require("neoment.matrix").set_room_last_activity(room_id, {
		timestamp = event.origin_server_ts,
		event_id = event.event_id,
		age = event.unsigned and event.unsigned.age or 0,
	})

	return true
end

--- Handle redaction events
--- @param room_id string The ID of the room
--- @param event neoment.matrix.ClientEventWithoutRoomID The event to process
--- @return boolean True if the room list needs to be updated
local function handle_redaction(room_id, event)
	---@type string
	local redacted_event_id = event.content.redacts
	local event_redacted = client.get_room(room_id).events[redacted_event_id]
	if event_redacted and not vim.tbl_isempty(event_redacted.content) then
		if event_redacted.type == "m.room.message" then
			local relates_to = event_redacted.content["m.relates_to"]
			if relates_to and relates_to.rel_type == "m.replace" and relates_to.event_id then
				client.get_room(room_id).messages[relates_to.event_id] = nil
			else
				local reason = event.content.reason
				local content = "[Redacted]"
				if reason then
					content = string.format("[Redacted: %s]", reason)
				end
				client.get_room(room_id).messages[redacted_event_id].content = content
				client.get_room(room_id).messages[redacted_event_id].formatted_content = content
				client.get_room(room_id).messages[redacted_event_id].was_redacted = true
			end
			return true
		elseif event_redacted.type == "m.reaction" then
			local relates_to = event_redacted.content["m.relates_to"]

			local reaction = relates_to.key
			local message_id = relates_to.event_id
			local message = client.get_room(room_id).messages[message_id]
			if message and message.reactions[reaction] then
				local reaction_list = message.reactions[reaction]
				for i, r in ipairs(reaction_list) do
					--- @type neoment.matrix.client.MessageReaction
					local reaction_data = r
					if reaction_data.event_id == event_redacted.event_id then
						table.remove(reaction_list, i)
						break
					end
				end
				if #reaction_list == 0 then
					message.reactions[reaction] = nil
				else
					message.reactions[reaction] = reaction_list
				end
				return true
			end
		end
	end

	add_pending_event(room_id, redacted_event_id, event)
	return false
end

--- Handle event
--- @param room_id string The room ID
--- @param event neoment.matrix.ClientEventWithoutRoomID
--- @return boolean True if the event was handled, false otherwise
M.handle = function(room_id, event)
	if event.event_id then
		-- Event already processed
		if client.room_event_exists(room_id, event.event_id) then
			return false
		end

		-- Store the event in the room's events table
		client.add_room_event(room_id, event)
	end

	if event.type == "m.fully_read" then
		-- Update the fully read event ID
		client.get_room(room_id).fully_read = event.content.event_id
		return true
	elseif event.type == "m.marked_unread" then
		-- Update the marked unread event ID
		client.get_room(room_id).unread = event.content.unread
	elseif event.type == "m.receipt" then
		local room_read_receipt = client.get_room_read_receipt(room_id)
		local last_user_receipt = room_read_receipt or {
			ts = 0,
			event_id = nil,
		}
		local user_id = require("neoment.matrix").get_user_id()

		for event_id, receipt in pairs(event.content) do
			for _, values in pairs(receipt) do
				for user, data in pairs(values) do
					if user == user_id then
						if data.ts > last_user_receipt.ts then
							last_user_receipt = {
								ts = data.ts,
								event_id = event_id,
							}
						end
					end
				end
			end
		end

		client.set_room_read_receipt(room_id, last_user_receipt)
	elseif event.type == "m.room.message" or event.type == "m.sticker" then
		if handle_message(room_id, event) then
			return true
		end
	elseif event.type == "m.room.name" then
		client.get_room(room_id).name = event.content.name
		return true
	elseif event.type == "m.room.canonical_alias" then
		local room = client.get_room(room_id)
		-- We only want to update the name with the alias if it is not already set
		if room.name == room.id then
			local alias = event.content.alias
			if not alias and event.content.alt_aliases then
				alias = event.content.alt_aliases[1]
			end

			if alias then
				client.get_room(room_id).name = event.content.alias
			end
			return true
		end
	elseif event.type == "m.room.topic" then
		client.get_room(room_id).topic = event.content.topic
		return true
	elseif event.type == "m.room.member" then
		if event.content.membership == "join" then
			client.get_room(room_id).members[event.state_key] = event.state_key
		elseif event.content.membership == "leave" or event.content.membership == "ban" then
			client.get_room(room_id).members[event.state_key] = nil
		end

		local message = state_event_to_message(event)
		if message then
			client.add_room_message(room_id, message)
		end
	elseif event.type == "m.room.redaction" then
		if handle_redaction(room_id, event) then
			return true
		end
	elseif event.type == "m.space.child" then
		client.add_space_child(room_id, event.state_key)
	elseif event.type == "m.reaction" then
		local relates_to = event.content["m.relates_to"]
		if relates_to and relates_to.rel_type == "m.annotation" then
			local event_id = relates_to.event_id
			local reaction = relates_to.key
			local message = client.get_room(room_id).messages[event_id]
			if message then
				local current_reactions = message.reactions[reaction] or {}
				table.insert(current_reactions, {
					event_id = event.event_id,
					sender = event.sender,
				})
				message.reactions[reaction] = current_reactions
				return true
			else
				-- If the message is not found, store the reaction in pending events
				add_pending_event(room_id, event_id, event)
			end
		end
	elseif event.type == "m.tag" then
		if event.content.tags["m.favourite"] then
			client.get_room(room_id).is_favorite = true
			return true
		elseif event.content.tags["m.lowpriority"] then
			client.get_room(room_id).is_lowpriority = true
			return true
		end
	elseif event.type == "m.typing" then
		client.get_room(room_id).typing = event.content.user_ids
		return true
	end

	return false
end

--- Handle invited room events
--- @param room_id string The room ID
--- @param event neoment.matrix.StrippedStateEvent The event to process
--- @return boolean True if the event was handled, false otherwise
M.handle_invited = function(room_id, event)
	if event.type == "m.room.name" then
		client.get_invited_room(room_id).name = event.content.name
		return true
	elseif event.type == "m.room.canonical_alias" then
		local alias = event.content.alias
		if not alias and event.content.alt_aliases then
			alias = event.content.alt_aliases[1]
		end

		if alias then
			client.get_invited_room(room_id).name = event.content.alias
		end
		return true
	elseif event.type == "m.room.topic" then
		client.get_invited_room(room_id).topic = event.content.topic
		return true
	elseif event.type == "m.room.member" and event.content.membership == "join" then
		client.get_invited_room(room_id).members[event.state_key] = event.content.displayname or event.state_key
		return true
	end

	return false
end

--- Handle multiple events
--- @param room_id string The room ID
--- @param events table A table of events to handle
--- @return boolean True if any event was handled, false otherwise
M.handle_multiple = function(room_id, events)
	local handled = false
	for _, event in ipairs(events) do
		if M.handle(room_id, event) then
			handled = true
		end

		if not event or not event.event_id then
			-- Skip events without an ID
			goto continue
		end

		-- Handle pending actions
		local pending_event = client.get_room(room_id).pending_events[event.event_id]
		if pending_event then
			if M.handle(room_id, pending_event) then
				client.get_room(room_id).pending_events[event.event_id] = nil
				handled = true
			end
		end

		::continue::
	end

	return handled
end

return M
