local M = {}

local client = require("neoment.matrix.client")
local error = require("neoment.error")
local api = require("neoment.matrix.api")
local util = require("neoment.util")

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

	local mentions = {}
	if event.content["m.mentions"] then
		mentions = event.content["m.mentions"].user_ids or {}
	end
	if replying_to then
		for _, mention in ipairs(replying_to.mentions) do
			table.insert(mentions, mention)
		end
	end

	local image = nil
	if event.content.msgtype == "m.image" then
		image = {
			url = util.mxc_to_url(client.client.homeserver, event.content.url)
				.. "?access_token="
				.. client.client.access_token,
			height = event.content.info and event.content.info.h,
			width = event.content.info and event.content.info.w,
		}
	end

	return {
		id = event.event_id,
		sender = event.sender,
		content = content,
		formatted_content = formatted_content,
		timestamp = event.origin_server_ts,
		was_edited = false,
		was_redacted = false,
		mentions = mentions,
		replying_to = replying_to,
		reactions = {},
		image = image,
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
	client.get_room(room_id).last_activity =
		math.max(client.get_room(room_id).last_activity or 0, event.origin_server_ts)

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
				for i, user_id in ipairs(reaction_list) do
					if user_id == event.sender then
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
	-- Handle events without event_id
	if event.type == "m.tag" then
		if event.content.tags["m.favourite"] then
			client.get_room(room_id).is_favorite = true
			return true
		end
	end

	if not event.event_id then
		-- Skip events without an ID
		return false
	end

	-- Event already processed
	if client.room_event_exists(room_id, event.event_id) then
		return false
	end

	-- Store the event in the room's events table
	client.add_room_event(room_id, event)

	if event.type == "m.fully_read" then
		-- Update the fully read event ID
		client.get_room(room_id).fully_read = event.content.event_id
		return true
	elseif event.type == "m.room.message" then
		if handle_message(room_id, event) then
			return true
		end
	elseif event.type == "m.room.name" then
		client.get_room(room_id).name = event.content.name
		return true
	elseif event.type == "m.room.canonical_alias" then
		local alias = event.content.alias
		if not alias and event.content.alt_aliases then
			alias = event.content.alt_aliases[1]
		end

		if alias then
			client.get_room(room_id).name = event.content.alias
		end
		return true
	elseif event.type == "m.room.topic" then
		client.get_room(room_id).topic = event.content.topic
		return true
	elseif event.type == "m.room.member" then
		if event.content.membership == "join" then
			client.get_room(room_id).members[event.state_key] = event.state_key

			-- Fetch the display name if it is not already set
			local displayname = event.content.displayname
			if not displayname then
				displayname = require("neoment.matrix").get_display_name_or_fetch(event.state_key)
			end
			client.client.display_names[event.state_key] = displayname

			return true
		elseif event.content.membership == "leave" or event.content.membership == "ban" then
			client.get_room(room_id).members[event.state_key] = nil
			return true
		end
	elseif event.type == "m.room.redaction" then
		if handle_redaction(room_id, event) then
			return true
		end
	elseif event.type == "m.reaction" then
		local relates_to = event.content["m.relates_to"]
		if relates_to and relates_to.rel_type == "m.annotation" then
			local event_id = relates_to.event_id
			local reaction = relates_to.key
			local message = client.get_room(room_id).messages[event_id]
			if message then
				local current_reactions = message.reactions[reaction] or {}
				table.insert(current_reactions, event.sender)
				message.reactions[reaction] = current_reactions
				return true
			else
				-- If the message is not found, store the reaction in pending events
				add_pending_event(room_id, event_id, event)
			end
		end
	elseif event.type == "m.typing" then
		client.get_room(room_id).typing = event.content.user_ids
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
		if not event or not event.event_id then
			-- Skip events without an ID
			goto continue
		end

		if M.handle(room_id, event) then
			handled = true
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
