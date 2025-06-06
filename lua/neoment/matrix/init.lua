local M = {}

local error = require("neoment.error")
local api = require("neoment.matrix.api")
local markdown = require("neoment.markdown")
local util = require("neoment.util")
local event = require("neoment.matrix.event")
local client = require("neoment.matrix.client")

--- Create a new Matrix client.
M.new = client.new

--- Check if the client is logged in.
--- @return boolean True if the client is logged in, false otherwise.
M.is_logged_in = function()
	return client.client and client.client.access_token ~= nil
end

--- @class neoment.matrix.LoginResponse
--- @field access_token string An access token for the account. This access token can then be used to authorize other requests.
--- @field device_id string ID of the logged-in device. Will be the same as the corresponding parameter in the request, if one was specified.
--- @field expires_in_ms integer? The lifetime of the access token, in milliseconds. Once the access token has expired a new access token can be obtained by using the provided refresh token.
--- @field refresh_token string? A refresh token for the account. This token can be used to obtain a new access token when it expires by calling the /refresh endpoint.
--- @field user_id string The fully-qualified Matrix ID for the account.
--- @field well_known table? Optional client configuration provided by the server. If present, clients SHOULD use the provided object to reconfigure themselves.

--- Login to a Matrix server using the provided username and password.
--- @param username string The username to log in with.
--- @param password string The password to log in with.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any The callback function to handle the response.
M.login = function(username, password, callback)
	local homeserver = "https://" .. username:match("@.*:(.*)")
	client.new(homeserver)

	api.post(
		client.client.homeserver .. "/_matrix/client/v3/login",
		{
			type = "m.login.password",
			identifier = {
				type = "m.id.user",
				user = username,
			},
			password = password,
			device_id = client.client.device_id,
		},
		--- @param response neoment.Error<neoment.matrix.LoginResponse, neoment.matrix.api.Error>
		function(response)
			local result = error.map(response, function(data)
				client.client.access_token = data.access_token
				client.client.user_id = data.user_id
				return nil
			end) --[[@as neoment.Error<nil, neoment.matrix.api.Error>]]

			callback(result)
		end
	)
end

--- Logout from the Matrix server.
--- @param callback fun(result: neoment.Error<nil, neoment.matrix.api.Error>): any The callback function to handle the response.
M.logout = function(callback)
	if not client.client or not client.client.access_token then
		callback(error.ok(nil))
		return
	end
	api.post(client.client.homeserver .. "/_matrix/client/v3/logout", {}, function(response)
		local result = error.map(response, function()
			client.new(client.client.homeserver)
			return nil
		end)
		callback(result)
	end, {
		headers = {
			Authorization = "Bearer " .. client.client.access_token,
		},
	})
end

--- @class neoment.matrix.SyncResponse
--- @field account_data? neoment.matrix.AccountData The global private data created by this user.
--- @field device_lists? table Information on end-to-end device updates, as specified in End-to-end encryption.
--- @field device_one_time_keys_count? table<string, integer> Information on end-to-end encryption keys, as specified in End-to-end encryption.
--- @field next_batch string Required: The batch token to supply in the since param of the next /sync request.
--- @field presence? neoment.matrix.Presence The updates to the presence status of other users.
--- @field rooms? neoment.matrix.Rooms Updates to rooms.
--- @field to_device? table Information on the send-to-device messages for the client device, as defined in Send-to-Device messaging.

--- @class neoment.matrix.AccountData
--- @field events table<neoment.matrix.Event> List of events

--- @class neoment.matrix.Presence
--- @field events table<neoment.matrix.Event> List of events

--- @class neoment.matrix.Event
--- @field content table The fields in this object will vary depending on the type of event. When interacting with the REST API, this is the HTTP body.
--- @field type string The type of event.

--- @class neoment.matrix.Rooms
--- @field invite? table<string, neoment.matrix.InvitedRoom> The rooms that the user has been invited to, mapped as room ID to room information.
--- @field join? table<string, neoment.matrix.JoinedRoom> The rooms that the user has joined, mapped as room ID to room information.
--- @field knock? table<string, neoment.matrix.KnockedRoom> The rooms that the user has knocked upon, mapped as room ID to room information.
--- @field leave? table<string, neoment.matrix.LeftRoom> The rooms that the user has left or been banned from, mapped as room ID to room information.

--- @class neoment.matrix.InvitedRoom
--- @field invite_state neoment.matrix.InviteState The stripped state of a room that the user has been invited to.

--- @class neoment.matrix.InviteState
--- @field events table<neoment.matrix.StrippedStateEvent> The stripped state events that form the invite state.

--- @class neoment.matrix.StrippedStateEvent
--- @field content table The content for the event.
--- @field sender string The sender for the event.
--- @field state_key string The state_key for the event.
--- @field type string The type for the event.

--- @class neoment.matrix.JoinedRoom
--- @field account_data? neoment.matrix.AccountData The private data that this user has attached to this room.
--- @field ephemeral? neoment.matrix.Ephemeral The new ephemeral events in the room (events that aren’t recorded in the timeline or state of the room).
--- @field state? neoment.matrix.State Updates to the state, between the time indicated by the since parameter, and the start of the timeline (or all state up to the start of the timeline, if since is not given, or full_state is true).
--- @field summary? neoment.matrix.RoomSummary Information about the room which clients may need to correctly render it to users.
--- @field timeline? neoment.matrix.Timeline The timeline of messages and state changes in the room.
--- @field unread_notifications? neoment.matrix.UnreadNotificationCounts Counts of unread notifications for this room.
--- @field unread_thread_notifications? table<string, neoment.matrix.ThreadNotificationCounts> If unread_thread_notifications was specified as true on the RoomEventFilter, the notification counts for each thread in this room. The object is keyed by thread root ID, with values matching unread_notifications. If a thread does not have any notifications it can be omitted from this object. If no threads have notification counts, this whole object can be omitted.

--- @class neoment.matrix.Ephemeral
--- @field events table<neoment.matrix.Event> List of events

--- @class neoment.matrix.State
--- @field events table<neoment.matrix.ClientEventWithoutRoomID> List of events

--- @class neoment.matrix.ClientEventWithoutRoomID
--- @field content table The body of this event, as created by the client which sent it.
--- @field event_id string The globally unique identifier for this event.
--- @field origin_server_ts integer Timestamp (in milliseconds since the unix epoch) on originating homeserver when this event was sent.
--- @field sender string Contains the fully-qualified ID of the user who sent this event.
--- @field state_key? string Present if, and only if, this event is a state event. The key making this piece of state unique in the room. Note that it is often an empty string. State keys starting with an @ are reserved for referencing user IDs, such as room members. With the exception of a few events, state events set with a given user’s ID as the state key MUST only be set by that user.
--- @field type string : The type of the event.
--- @field unsigned? neoment.matrix.UnsignedData Contains optional extra information about the event.

--- @class neoment.matrix.UnsignedData
--- @field age? integer The time in milliseconds that has elapsed since the event was sent. This field is generated by the local homeserver, and may be incorrect if the local time on at least one of the two servers is out of sync, which can cause the age to either be negative or greater than it actually is.
--- @field membership? string The room membership of the user making the request, at the time of the event. This property is the value of the membership property of the requesting user’s m.room.member state at the point of the event, including any changes caused by the event. If the user had yet to join the room at the time of the event (i.e, they have no m.room.member state), this property is set to leave. Homeservers SHOULD populate this property wherever practical, but they MAY omit it if necessary (for example, if calculating the value is expensive, servers might choose to only implement it in encrypted rooms). The property is not normally populated in events pushed to application services via the application service transaction API (where there is no clear definition of “requesting user”). Added in v1.11
--- @field prev_content? table The previous content for this event. This field is generated by the local homeserver, and is only returned if the event is a state event, and the client has permission to see the previous content. Changed in v1.2: Previously, this field was specified at the top level of returned events rather than in unsigned (with the exception of the GET .../notifications endpoint), though in practice no known server implementations honoured this.
--- @field redacted_because? neoment.matrix.ClientEventWithoutRoomID The event that redacted this event, if any.
--- @field transaction_id? string The client-supplied transaction ID, for example, provided via PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}, if the client being given the event is the same one which sent it.

--- @class neoment.matrix.RoomSummary
--- @field m.heroes? table<string> The users which can be used to generate a room name if the room does not have one. Required if the room’s m.room.name or m.room.canonical_alias state events are unset or empty.
--- @field m.invited_member_count? integer The number of users with membership of invite. If this field has not changed since the last sync, it may be omitted. Required otherwise.
--- @field m.joined_member_count? integer The number of users with membership of join, including the client’s own user ID. If this field has not changed since the last sync, it may be omitted. Required otherwise.

--- @class neoment.matrix.Timeline
--- @field events table<neoment.matrix.ClientEventWithoutRoomID> List of events.
--- @field limited? boolean True if the number of events returned was limited by the limit on the filter.
--- @field prev_batch? string A token that can be supplied to the from parameter of the /rooms/<room_id>/messages endpoint in order to retrieve earlier events. If no earlier events are available, this property may be omitted from the response.

--- @class neoment.matrix.UnreadNotificationCounts
--- @field highlight_count integer The number of unread notifications for this room with the highlight flag set.
--- @field notification_count integer The total number of unread notifications for this room.

--- @class neoment.matrix.ThreadNotificationCounts
--- @field highlight_count integer The number of unread notifications for this thread with the highlight flag set.
--- @field notification_count integer The total number of unread notifications for this thread.

--- @class neoment.matrix.KnockedRoom
--- @field knock_state neoment.matrix.KnockState The stripped state of a room that the user has knocked upon.

--- @class neoment.matrix.KnockState
--- @field knock_state neoment.matrix.KnockState The stripped state of a room that the user has knocked upon.

--- @class neoment.matrix.LeftRoom
--- @field account_data neoment.matrix.AccountData The private data that this user has attached to this room.
--- @field state neoment.matrix.State The state updates for the room up to the start of the timeline.
--- @field timeline neoment.matrix.Timeline The timeline of messages and state changes in the room up to the point when the user left.

--- @class neoment.matrix.SyncOptions
--- @field filter? string The ID of a filter created using the filter API or a filter JSON object encoded as a string. The server will detect whether it is an ID or a JSON object by whether the first character is a "{" open brace. Passing the JSON inline is best suited to one off requests. Creating a filter using the filter API is recommended for clients that reuse the same filter multiple times, for example in long poll requests.
--- @field full_state? boolean Controls whether to include the full state for all rooms the user is a member of. If this is set to true, then all state events will be returned, even if since is non-empty. The timeline will still be limited by the since parameter. In this case, the timeout parameter will be ignored and the query will return immediately, possibly with an empty timeline. If false, and since is non-empty, only state which has changed since the point indicated by since will be returned. By default, this is false.
--- @field set_presence? string Controls whether the client is automatically marked as online by polling this API. If this parameter is omitted then the client is automatically marked as online when it uses this API. Otherwise if the parameter is set to “offline” then the client is not marked as being online when it uses this API. When set to “unavailable”, the client is marked as being idle. One of: [offline, online, unavailable].
--- @field timeout? integer The maximum time to wait, in milliseconds, before returning this request. If no events (or other data) become available before this time elapses, the server will return a response with empty fields. By default, this is 0, so the server will return immediately even if the response is empty.

--- Process the account data for a room
--- @param room_id string The ID of the room
--- @param account_data_events table<neoment.matrix.Event> The events in the account data
--- @return boolean True if the room list needs to be updated
local function process_room_account_data(room_id, account_data_events)
	local rooms_updated = false

	for _, e in ipairs(account_data_events) do
		if event.handle(room_id, e) then
			rooms_updated = true
		end
	end

	return rooms_updated
end

--- Fetch the display name of a user
--- @param user_id string The ID of the user.
--- @return string The display name of the user.
local function fetch_display_name(user_id)
	-- Get the display name from /profile endpoint
	local response =
		api.get_sync(client.client.homeserver .. "/_matrix/client/v3/profile/" .. user_id .. "/displayname")

	local result = error.map(response, function(data)
		if data.displayname then
			client.client.display_names[user_id] = data.displayname
			return data.displayname
		end
		return user_id
	end)

	return error.unwrap(result, user_id)
end

--- Handle account data from the sync response.
--- @param account_data neoment.matrix.AccountData The account data from the sync response
--- @return table<string> The list of updated rooms
local function handle_sync_account_data(account_data)
	local updated_rooms = {}

	for _, e in ipairs(account_data.events or {}) do
		---@type neoment.matrix.Event
		local event_ = e
		if event_.type == "m.direct" then
			for user_id, rooms in pairs(event_.content) do
				for _, room_id in ipairs(rooms) do
					if client.get_room(room_id) then
						client.get_room(room_id).is_direct = true
						if client.get_room(room_id).name == room_id then
							client.get_room(room_id).name = M.get_display_name_or_fetch(user_id)
						end
						table.insert(updated_rooms, room_id)
					end
				end
			end
		end
	end

	return updated_rooms
end

--- Handle joined rooms from the sync response.
--- @param invite_rooms table<string, neoment.matrix.InvitedRoom> The rooms that the user has been invited to
--- @return table<string> The list of updated rooms
local function handle_sync_invited_rooms(invite_rooms)
	local updated_rooms = {}

	for room_id, room_data in pairs(invite_rooms or {}) do
		-- Call `get_invited_room` to ensure the room is created if it doesn't exist
		client.get_invited_room(room_id)

		local room_updated = false

		-- Process timeline events
		if room_data.invite_state then
			for _, e in ipairs(room_data.invite_state.events) do
				--- @type neoment.matrix.StrippedStateEvent
				local event_ = e
				if event.handle_invited(room_id, event_) then
					room_updated = true
				end
			end
		end

		if room_updated then
			table.insert(updated_rooms, room_id)
		end
	end
	return updated_rooms
end

--- Handle joined rooms from the sync response.
--- @param joined_rooms table<string, neoment.matrix.JoinedRoom> The rooms that the user has joined
--- @return table<string> The list of updated rooms
local function handle_sync_joined_rooms(joined_rooms)
	local updated_rooms = {}

	for room_id, room_data in pairs(joined_rooms or {}) do
		-- Call `get_room` to ensure the room is created if it doesn't exist
		client.get_room(room_id)
		local room_updated = false

		-- Process account data events
		if
			room_data.account_data
			and room_data.account_data.events
			and process_room_account_data(room_id, room_data.account_data.events)
		then
			room_updated = true
		end

		-- Process timeline events
		if room_data.timeline then
			-- client.get_room(room_id).prev_batch = {
			-- 	token = room_data.timeline.prev_batch,
			-- }
			if event.handle_multiple(room_id, room_data.timeline.events) then
				room_updated = true
			end
		end

		-- Process state events
		if room_data.state and room_data.state.events and event.handle_multiple(room_id, room_data.state.events) then
			room_updated = true
		end

		if
			room_data.summary
			and not vim.tbl_isempty(room_data.summary)
			and client.get_room(room_id).name == room_id
		then
			local joined = room_data.summary["m.joined_member_count"] or 0
			local invited = room_data.summary["m.invited_member_count"] or 0
			local heroes = room_data.summary["m.heroes"] or {}
			if #heroes >= joined + invited - 1 then
				local names = {}
				for _, member in ipairs(heroes) do
					local displayname = M.get_display_name_or_fetch(member)
					table.insert(names, displayname)
				end
				local new_name = util.join(names, ", ")
				if new_name ~= "" then
					client.get_room(room_id).name = new_name
				end
			elseif joined + invited > 1 then
				local first = heroes[1]
				local second = heroes[2]
				local remaining = #heroes - 2
				client.get_room(room_id).name = string.format("%s, %s and %d others", first, second, remaining)
			elseif joined + invited <= 1 then
				local empty_status = ""
				if #heroes > 2 then
					local first = heroes[1]
					empty_status = string.format(" (was %s and %d others)", first, #heroes - 1)
				elseif #heroes == 1 then
					empty_status = string.format(" (was %s)", heroes[1])
				end
				client.get_room(room_id).name = string.format("Empty room%s", empty_status)
			end
		end

		if room_data.ephemeral and event.handle_multiple(room_id, room_data.ephemeral.events) then
			room_updated = true
		end

		if room_data.unread_notifications then
			client.get_room(room_id).unread_notifications = room_data.unread_notifications.notification_count
			client.get_room(room_id).unread_highlights = room_data.unread_notifications.highlight_count
		end

		if room_updated then
			table.insert(updated_rooms, room_id)
		end
	end
	return updated_rooms
end

--- Synchronize the client with the server.
--- @param options neoment.matrix.SyncOptions Options for synchronization.
--- @param callback fun(data: neoment.Error<{ sync: neoment.matrix.SyncResponse, updated_rooms: table<string> }, neoment.matrix.api.Error>): any The callback function to handle the response.
M.sync = function(options, callback)
	local params = {}
	if options.filter then
		table.insert(params, "filter=" .. options.filter)
	end
	if options.full_state then
		table.insert(params, "full_state=" .. tostring(options.full_state))
	end
	if options.set_presence then
		table.insert(params, "set_presence=" .. options.set_presence)
	end
	if client.client.sync_token then
		table.insert(params, "since=" .. client.client.sync_token)
	end
	if options.timeout then
		table.insert(params, "timeout=" .. options.timeout)
	end
	local query_params = ""
	if #params > 0 then
		query_params = "?" .. table.concat(params, "&")
	end

	api.get(
		client.client.homeserver .. "/_matrix/client/v3/sync" .. query_params,
		vim.schedule_wrap(function(response)
			local result = error.map(response, function(data)
				--- @type neoment.matrix.SyncResponse
				local sync_data = data
				client.client.sync_token = sync_data.next_batch

				local updated_rooms = {}

				if sync_data.rooms and sync_data.rooms.invite then
					local new_updated_rooms = handle_sync_invited_rooms(sync_data.rooms.invite)
					updated_rooms = vim.iter({ updated_rooms, new_updated_rooms }):flatten():totable()
				end

				if sync_data.rooms and sync_data.rooms.join then
					local new_updated_rooms = handle_sync_joined_rooms(sync_data.rooms.join)
					updated_rooms = vim.iter({ updated_rooms, new_updated_rooms }):flatten():totable()
				end

				if sync_data.account_data then
					local new_updated_rooms = handle_sync_account_data(sync_data.account_data)
					updated_rooms = vim.iter({ updated_rooms, new_updated_rooms }):flatten():totable()
				end

				return { sync = data, updated_rooms = updated_rooms }
			end) --[[@as neoment.Error<{ sync: neoment.matrix.SyncResponse, updated_rooms: table<string> }, neoment.matrix.api.Error>]]

			callback(result)
		end),
		{
			headers = {
				Authorization = "Bearer " .. client.client.access_token,
			},
		}
	)
end

--- Generate a txn_id
--- @return string A unique transaction ID.
local function generate_txn_id()
	return "neoment-" .. util.uuid()
end

--- @class neoment.matrix.SendResponse
--- @field event_id string The ID of the sent message.

--- @class neoment.matrix.SendMessageParams
--- @field message string The message to send.
--- @field reply_to? string The ID of the message being replied to.
--- @field replace? string The ID of the message being replaced.
--- @field attachment? {url: string, mimetype: string, filename: string, size: number} The attachment to send with the message.

--- Send a message to a room.
--- @param room_id string The ID of the room to send the message to.
--- @param params neoment.matrix.SendMessageParams The message to send and the ID of the message being replied to or replaced.
--- @param callback fun(data: neoment.Error<neoment.matrix.SendResponse, neoment.matrix.api.Error>): any The callback function to handle the response. The response will be the event ID of the sent message.
M.send_message = function(room_id, params, callback)
	local txn_id = generate_txn_id()
	-- Replace mentions
	local mentions = {}
	local formatted_body = markdown.to_html(params.message)

	formatted_body = formatted_body:gsub("(@[^%s]+:[^%s]+)", function(user_id)
		local display_name = M.get_display_name_or_fetch(user_id)

		-- If we didn't find a display name, maybe it's not a valid user ID
		if display_name == user_id then
			return user_id
		end
		table.insert(mentions, user_id)
		return string.format('<a href="https://matrix.to/#/%s">%s</a>', user_id, display_name)
	end)

	local content = {
		msgtype = "m.text",
		body = params.message,
		format = "org.matrix.custom.html",
		formatted_body = formatted_body,
	}

	if #mentions > 0 then
		content["m.mentions"] = {
			user_ids = mentions,
		}
	end

	if params.reply_to then
		content["m.relates_to"] = {
			["m.in_reply_to"] = {
				event_id = params.reply_to,
			},
		}
	end

	if params.replace then
		local new_content = content
		content = {
			msgtype = "m.text",
			body = "* " .. new_content.body,
			["m.new_content"] = new_content,
			["m.relates_to"] = {
				rel_type = "m.replace",
				event_id = params.replace,
			},
		}
	end

	local attachment = params.attachment
	if attachment then
		content.msgtype = util.get_msgtype(attachment.mimetype)
		content.filename = attachment.filename
		content.url = attachment.url
		content.info = {
			mimetype = attachment.mimetype,
			size = attachment.size,
		}
	end

	api.put(
		client.client.homeserver .. "/_matrix/client/v3/rooms/" .. room_id .. "/send/m.room.message/" .. txn_id,
		content,
		function(r)
			--- @type neoment.Error<neoment.matrix.SendResponse, neoment.matrix.api.Error>
			local response = r

			error.map(response, function(data)
				client.get_room(room_id).fully_read = data.event_id
				return data
			end)

			callback(response)
		end,
		{
			headers = {
				Authorization = "Bearer " .. client.client.access_token,
			},
		}
	)
end

--- Redact an event in a room.
--- @param room_id string The ID of the room.
--- @param event_id string The ID of the event to redact.
--- @param reason? string The reason for redacting the event.
--- @param callback fun(data: neoment.Error<string, neoment.matrix.api.Error>): any The callback function to handle the response. The response will be the event ID of the redaction.
M.redact_event = function(room_id, event_id, reason, callback)
	local body = { reason = "" }
	if reason then
		body.reason = reason
	end

	api.put(
		client.client.homeserver
			.. "/_matrix/client/v3/rooms/"
			.. room_id
			.. "/redact/"
			.. event_id
			.. "/"
			.. generate_txn_id(),
		body,
		function(response)
			local result = error.map(response, function(data)
				return data.event_id
			end) --[[@as neoment.Error<string, neoment.matrix.api.Error>]]

			callback(result)
		end,
		{
			headers = {
				Authorization = "Bearer " .. client.client.access_token,
			},
		}
	)
end

-- User

--- Get the user ID of the logged-in user.
--- @return string|nil The user ID of the logged-in user, or nil if not logged in.
M.get_user_id = function()
	if client.client and client.client.user_id then
		return client.client.user_id
	end
	return nil
end

-- Member

--- Get the display name of a user.
--- @param user_id string The ID of the user.
--- @return string The display name of the user.
M.get_display_name = function(user_id)
	return client.client.display_names[user_id] or user_id
end

--- Check if a user has a display name.
--- @param user_id string The ID of the user.
--- @return boolean True if the user has a display name, false otherwise.
M.has_display_name = function(user_id)
	return client.client.display_names[user_id] ~= nil
end

--- Get the display name of a user.
--- @param user_id string The ID of the user.
--- @return string The display name of the user.
M.get_display_name_or_fetch = function(user_id)
	if client.client.display_names[user_id] then
		return client.client.display_names[user_id]
	end
	return fetch_display_name(user_id)
end

-- Room

--- Loads more messages from a room.
--- @param room_id string The ID of the room.
--- @param on_done fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any The callback function to handle the response.
M.load_more_messages = function(room_id, on_done)
	if not client.get_room(room_id) then
		on_done(error.error({ error = "No room found with ID: " .. room_id }))
		return
	end

	local prev_batch = client.get_room(room_id).prev_batch
	if prev_batch == "End" then
		on_done(error.error({ error = "No more messages to load" }))
		return
	end

	local prev_batch_query = ""
	if prev_batch then
		prev_batch_query = prev_batch.token
	else
		prev_batch_query = client.client.sync_token
	end

	api.get(
		client.client.homeserver
			.. "/_matrix/client/v3/rooms/"
			.. room_id
			.. "/messages?limit=20&dir=b&from="
			.. prev_batch_query,
		vim.schedule_wrap(function(response)
			local result = error.try(response, function(data)
				if data["end"] then
					client.get_room(room_id).prev_batch = {
						token = data["end"],
					}
				else
					client.get_room(room_id).prev_batch = "End"
				end

				local chunk_events = data.chunk or {}
				if #chunk_events > 0 then
					local state_events = data.state and data.state.events or {}
					local events = vim.iter({ chunk_events, state_events }):flatten():totable()
					event.handle_multiple(room_id, events)
				elseif data["end"] then
					M.load_more_messages(room_id, on_done)
					return error.error({ error = "empty chunk" })
				end

				return error.ok({})
			end) --[[@as neoment.Error<{}, neoment.matrix.api.Error>]]

			error.match(result, function()
				on_done(error.ok(nil))
				return nil
			end, function(err)
				if err.error ~= "empty chunk" then
					on_done(error.error(err))
				end
			end)
		end),
		{
			headers = {
				Authorization = "Bearer " .. client.client.access_token,
			},
		}
	)
end

--- Send a message event to a room.
--- @param room_id string The ID of the room.
--- @param content table The content of the message event.
--- @param event_type string The type of the event (e.g., "m.room.message").
--- @param callback fun(data: neoment.Error<string, neoment.matrix.api.Error>): any The callback function to handle the response. The response will be the event ID of the sent message.
M.send_event = function(room_id, content, event_type, callback)
	api.put(
		client.client.homeserver
			.. "/_matrix/client/v3/rooms/"
			.. room_id
			.. "/send/"
			.. event_type
			.. "/"
			.. generate_txn_id(),
		content,
		function(response)
			local result = error.map(response, function(data)
				return data.event_id
			end) --[[@as neoment.Error<string, neoment.matrix.api.Error>]]

			callback(result)
		end,
		{
			headers = {
				Authorization = "Bearer " .. client.client.access_token,
			},
		}
	)
end

--- Send a reaction event to a room
--- @param room_id string The ID of the room.
--- @param message_id string The ID of the message to react to.
--- @param reaction string The reaction to send.
--- @param callback fun(data: neoment.Error<string, neoment.matrix.api.Error>): any The callback function to handle the response. The response will be the event ID of the sent message.
M.send_reaction = function(room_id, message_id, reaction, callback)
	local content = {
		msgtype = "m.text",
		body = reaction,
		["m.relates_to"] = {
			rel_type = "m.annotation",
			event_id = message_id,
			key = reaction,
		},
	}

	M.send_event(room_id, content, "m.reaction", callback)
end

--- @class neoment.matrix.ReadMarkers
--- @field fully_read? string The event ID the read marker should be located at. The event MUST belong to the room.
--- @field read? string The event ID the read marker should be located at. The event MUST belong to the room..
--- @field read_private? string The event ID to set the private read receipt location at.

--- Set the read marker for a room.
--- @param room_id string The ID of the room.
--- @param markers neoment.matrix.ReadMarkers The read markers for the room.
--- @param callback? fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any The callback function to handle the response.
M.set_room_read_marker = function(room_id, markers, callback)
	-- Set the read markers in the room object before sending the request
	-- This is to ensure that the room object is updated immediately
	-- If the request fails, this is not a problem, as the room object will be updated again
	local room = client.get_room(room_id)
	if markers.fully_read then
		room.fully_read = markers.fully_read
	end

	local read_receipt = markers.read or markers.read_private
	if read_receipt then
		room.read_receipt = {
			event_id = read_receipt,
			ts = os.time() * 1000, -- Convert to milliseconds
		}
	end

	room.unread = false

	api.post(client.client.homeserver .. "/_matrix/client/v3/rooms/" .. room_id .. "/read_markers", {
		["m.fully_read"] = markers.fully_read,
		["m.read"] = markers.read,
		["m.read.private"] = markers.read_private,
	}, function(response)
		if not callback then
			return
		end

		local result = error.map(response, function()
			return nil
		end) --[[@as neoment.Error<nil, neoment.matrix.api.Error>]]

		callback(result)
	end, {
		headers = {
			Authorization = "Bearer " .. client.client.access_token,
		},
	})
end

--- Join a room by ID.
--- @param room_id string The ID of the room to join.
--- @param callback fun(data: neoment.Error<string, neoment.matrix.api.Error>): any The callback function to handle the response. The response will be the room ID of the joined room.
M.join_room = function(room_id, callback)
	api.post(client.client.homeserver .. "/_matrix/client/v3/rooms/" .. room_id .. "/join", nil, function(response)
		local result = error.map(response, function(data)
			client.get_invited_rooms()[room_id] = nil
			return data.room_id
		end) --[[@as neoment.Error<string, neoment.matrix.api.Error>]]

		callback(result)
	end, {
		headers = {
			Authorization = "Bearer " .. client.client.access_token,
		},
	})
end

--- Leave a room by ID.
--- @param room_id string The ID of the room to leave.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any The callback function to handle the response. The response will be the room ID of the left room.
M.leave_room = function(room_id, callback)
	api.post(client.client.homeserver .. "/_matrix/client/v3/rooms/" .. room_id .. "/leave", nil, function(response)
		local result = error.map(response, function()
			-- If the room is invited, remove it from the list of invited rooms
			client.get_invited_rooms()[room_id] = nil
			return nil
		end) --[[@as neoment.Error<nil, neoment.matrix.api.Error>]]

		callback(result)
	end, {
		headers = {
			Authorization = "Bearer " .. client.client.access_token,
		},
	})
end

--- Get the name of the room.
--- @param room_id string The ID of the room.
--- @return string The name of the room.
M.get_room_name = function(room_id)
	if client.get_invited_rooms()[room_id] then
		return client.get_invited_room(room_id).name
	end
	return client.get_room(room_id).name
end

--- Set the name of the room.
--- @param room_id string The ID of the room.
--- @param name string The new name of the room.
M.set_room_name = function(room_id, name)
	client.get_room(room_id).name = name
end

--- Check if a room has a name
--- @param room_id string The ID of the room.
--- @return boolean True if the room has a name.
M.room_has_name = function(room_id)
	return client.get_room(room_id).name ~= room_id
end

--- Get the room topic
--- @param room_id string The ID of the room.
--- @return string The topic of the room.
M.get_room_topic = function(room_id)
	return client.get_room(room_id).topic
end

--- Set the room topic
--- @param room_id string The ID of the room.
--- @param topic string The new topic of the room.
M.set_room_topic = function(room_id, topic)
	client.get_room(room_id).topic = topic
end

--- Get the members of a room.
--- @param room_id string The ID of the room.
--- @return table<string, string> The members of the room. The keys are user IDs and the values are display names.
M.get_room_members = function(room_id)
	return vim.tbl_map(function(id)
		local displayname = client.client.display_names[id]
		if not displayname or displayname == vim.NIL then
			return id
		end
		return displayname
	end, client.get_room(room_id).members)
end

--- Get the other members of a room.
--- @param room_id string The ID of the room.
--- @return table<string, string> The other members of the room. The keys are user IDs and the values are display names.
M.get_room_other_members = function(room_id)
	local members = M.get_room_members(room_id)
	local user_id = M.get_user_id()

	if user_id then
		members[user_id] = nil
	end

	return members
end

--- @class neoment.matrix.JoinedMembersResponse
--- @field joined table<string, neoment.matrix.JoinedMember> The joined members of the room.

--- @class neoment.matrix.JoinedMember
--- @field display_name string The display name of the member.
--- @field avatar_url string The avatar URL of the member.

--- Fetch the joined members of a room.
--- @param room_id string The ID of the room.
--- @param callback fun(data: neoment.Error<table<string, neoment.matrix.JoinedMember>, neoment.matrix.api.Error>): any The callback function to handle the response. The response will be a table of user IDs and their display names.
M.fetch_joined_members = function(room_id, callback)
	api.get(client.client.homeserver .. "/_matrix/client/v3/rooms/" .. room_id .. "/joined_members", function(response)
		local result = error.map(response, function(d)
			--- @type neoment.matrix.JoinedMembersResponse
			local data = d
			for id, member in pairs(data.joined) do
				if member.display_name and member.display_name ~= vim.NIL then
					client.client.display_names[id] = member.display_name
				end
				client.get_room(room_id).members[id] = id
			end
			return data.joined
		end) --[[@as neoment.Error<table<string, neoment.matrix.JoinedMember>, neoment.matrix.api.Error>]]

		callback(result)
	end, {
		headers = {
			Authorization = "Bearer " .. client.client.access_token,
		},
	})
end

--- Get the last activity timestamp in a room.
--- @param room_id string The ID of the room.
--- @return neoment.matrix.client.LastActivity? The last activity timestamp in the room.
M.get_room_last_activity = function(room_id)
	return client.get_room(room_id).last_activity
end

--- Set the last activity in a room.
--- @param room_id string The ID of the room.
--- @param new_last_activity neoment.matrix.client.LastActivity The last activity timestamp to set in the room.
M.set_room_last_activity = function(room_id, new_last_activity)
	local last_activity = M.get_room_last_activity(room_id)
	local last_timestamp = last_activity and last_activity.timestamp or 0
	if last_timestamp < new_last_activity.timestamp then
		client.get_room(room_id).last_activity = new_last_activity
	end
end

--- Get the last read message ID in a room.
--- @param room_id string The ID of the room.
--- @return string? The last read message ID in the room.
M.get_room_last_read_message = function(room_id)
	return client.get_room(room_id).fully_read
end

--- Get the previous batch token for a room.
--- @param room_id string The ID of the room.
--- @return neoment.matrix.client.PreviousBatch The previous batch token for the room.
M.get_room_prev_batch = function(room_id)
	return client.get_room(room_id).prev_batch
end

--- Get the list of typing users in a room.
--- @param room_id string The ID of the room.
--- @return table<string> The list of typing users in the room.
M.get_typing_users = function(room_id)
	return client.get_room(room_id).typing
end

--- Get a display name for a room from the members
--- @param members table<string, string> The members of the room.
--- @return string The display name of the room.
local function get_room_display_name_from_members(members)
	-- Names of the members, excluding the logged user
	local names = {}
	local count = 0
	for id, name in pairs(members) do
		if id ~= M.get_user_id() then
			table.insert(names, name)
			count = count + 1
		end
		-- We don't need more than 2 names
		if count == 2 then
			break
		end
	end

	local displayname = util.join(names, ", ")

	-- If there are more than 2 members, add the count of remaining members
	if vim.tbl_count(members) > count + 1 then
		local remaining = vim.tbl_count(members) - count
		displayname = string.format("%s and %d others", displayname, remaining)
	end

	return displayname
end

--- Get a display name for a room or a invited room
--- @param room_id string The ID of the room.
--- @return string The display name of the room.
M.get_room_display_name = function(room_id)
	--- @type neoment.matrix.client.Room|neoment.matrix.client.InvitedRoom
	local room
	-- Check if it's a invited room
	if client.is_invited_room(room_id) then
		room = client.get_invited_room(room_id)
	else
		room = client.get_room(room_id)
	end

	if room.name ~= room.id then
		return room.name
	end

	local displayname = get_room_display_name_from_members(room.members)

	if displayname == "" then
		displayname = "Empty room"
	end

	return displayname
end

--- Upload a file to the Matrix server.
--- @param filepath string The path to the file to upload.
--- @param callback fun(data: neoment.Error<{ content_uri: string, filename: string, mimetype: string }, neoment.matrix.api.Error>): any The callback function to handle the response.
M.upload = function(filepath, callback)
	local filename = vim.fn.fnamemodify(filepath, ":t")
	local mimetype = vim.fn.systemlist("file --mime-type -b " .. vim.fn.shellescape(filepath))[1]

	api.post_raw(
		client.client.homeserver .. "/_matrix/media/v3/upload?filename=" .. vim.uri_encode(filename),
		filepath,
		function(response)
			local result = error.map(response, function(data)
				return { content_uri = data.content_uri, mimetype = mimetype, filename = filename }
			end) --[[@as neoment.Error<{ content_uri: string, filename: string, mimetype: string }, neoment.matrix.api.Error>]]

			callback(result)
		end,
		{
			headers = {
				Authorization = "Bearer " .. client.client.access_token,
				["Content-Type"] = mimetype,
			},
		}
	)
end

--- Check if a room is unread
--- @param room_id string The room ID
--- @return boolean True if the room has unread messages
M.is_room_unread = function(room_id)
	local room = M.get_room(room_id)

	-- Case 1: Room explicitly marked as unread by user
	if room.unread then
		return true
	end

	local last_activity_event = room.last_activity and room.last_activity.event_id

	-- If there is no last activity event, we don't consider it unread
	if not last_activity_event then
		return false
	end

	local read_receipt_event = room.read_receipt and room.read_receipt.event_id

	-- Case 3: Room is unread if the last activity hasn't been marked as read
	-- We check both read receipt and fully_read marker to determine this
	return read_receipt_event ~= last_activity_event and room.fully_read ~= last_activity_event
end

--- Add or remove a tag from a room.
--- @param room_id string The ID of the room.
--- @param tag "m.favourite"|"m.lowpriority" The tag to add or remove from the room.
--- @param user_id? string The ID of the user to add or remove the tag for. If not provided, the tag will be added or removed for the logged-in user.
--- @param is_add boolean If true, the tag will be added; if false, the tag will be removed.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any The callback function to handle the response.
local function add_remove_room_tag(room_id, tag, user_id, is_add, callback)
	local actual_user_id = user_id or M.get_user_id()
	if not actual_user_id then
		callback(error.error({ error = "No user ID provided" }))
		return
	end

	local url = client.client.homeserver
		.. "/_matrix/client/v3/user/"
		.. actual_user_id
		.. "/rooms/"
		.. room_id
		.. "/tags/"
		.. tag

	local actual_callback = function(response)
		local result = error.map(response, function()
			return nil
		end) --[[@as neoment.Error<nil, neoment.matrix.api.Error>]]

		callback(result)
	end
	local opts = {
		headers = {
			Authorization = "Bearer " .. client.client.access_token,
		},
	}

	if is_add then
		api.put(url, {
			order = 0, -- Default order, can be adjusted if needed
		}, actual_callback, opts)
	else
		api.delete(url, actual_callback, opts)
	end
end

--- Add a tag to a room
--- @param room_id string The ID of the room.
--- @param tag "m.favourite"|"m.lowpriority" The tag to add to the room.
--- @param user_id? string The ID of the user to add the tag for. If not provided, the tag will be added for the logged-in user.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any The callback function to handle the response.
M.add_room_tag = function(room_id, tag, user_id, callback)
	add_remove_room_tag(room_id, tag, user_id, true, callback)
end

--- Remove a tag from a room
--- @param room_id string The ID of the room.
--- @param tag "m.favourite"|"m.lowpriority" The tag to remove from the room.
--- @param user_id? string The ID of the user to remove the tag for. If not provided, the tag will be removed for the logged-in user.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any The callback function to handle the response.
M.remove_room_tag = function(room_id, tag, user_id, callback)
	add_remove_room_tag(room_id, tag, user_id, false, callback)
end

--- @type neoment.matrix.client.Client
M.client = nil
M.get_room = client.get_room
M.get_invited_room = client.get_invited_room
M.get_rooms = client.get_rooms
M.get_invited_rooms = client.get_invited_rooms
M.set_room = client.set_room
M.set_invited_room = client.set_invited_room
M.set_room_tracked = client.set_room_tracked
M.get_room_messages = client.get_room_messages
M.get_room_last_message = client.get_room_last_message
M.get_room_unread_mark = client.get_room_unread_mark

setmetatable(M, {
	__index = function(_, key)
		if key == "client" then
			return client.client
		end
	end,
})

return M
