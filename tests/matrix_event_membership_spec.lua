describe("matrix membership events", function()
	local room_id = "!room1:example.org"
	local user_id = "@me:example.org"
	local other_user_id = "@other:example.org"

	local client
	local event
	local matrix
	local original_confirm
	local confirm_calls

	--- Build a `m.room.member` event
	--- @param event_id string The event ID
	--- @param state_key string The user the membership applies to
	--- @param membership string The membership value
	--- @param timestamp? number The event timestamp
	--- @return table The event
	local function member_event(event_id, state_key, membership, timestamp)
		return {
			event_id = event_id,
			type = "m.room.member",
			sender = state_key,
			state_key = state_key,
			origin_server_ts = timestamp or 1000,
			content = { membership = membership },
		}
	end

	--- Run the callbacks scheduled by the event handlers
	local function flush_scheduled()
		vim.wait(20, function()
			return false
		end)
	end

	before_each(function()
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.curl"] = {}
		package.loaded["neoment.notify"] = { desktop_message = function() end }
		package.loaded["neoment.rooms"] = { update_room_list = function() end }

		client = require("neoment.matrix.client")
		client.new("https://example.org", "token123")
		client.client.user_id = user_id
		client.client.display_names[user_id] = { display_name = "Me", timestamp = 0 }
		client.client.display_names[other_user_id] = { display_name = "Other", timestamp = 0 }
		client.get_room(room_id).is_tracked = true

		event = require("neoment.matrix.event")
		matrix = require("neoment.matrix")

		confirm_calls = 0
		original_confirm = vim.fn.confirm
		vim.fn.confirm = function()
			confirm_calls = confirm_calls + 1
			return 1
		end
	end)

	after_each(function()
		vim.fn.confirm = original_confirm
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.curl"] = nil
		package.loaded["neoment.notify"] = nil
		package.loaded["neoment.rooms"] = nil
	end)

	describe("historical events", function()
		it("does not remove the room for a self leave", function()
			event.handle_multiple(room_id, { member_event("$leave", user_id, "leave") }, true)
			flush_scheduled()

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
		end)

		it("does not remove the room for a self ban", function()
			event.handle_multiple(room_id, { member_event("$ban", user_id, "ban") }, true)
			flush_scheduled()

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
		end)

		it("does not remove the room for a leave, invite and join sequence", function()
			event.handle_multiple(room_id, {
				member_event("$leave", user_id, "leave", 1000),
				member_event("$invite", user_id, "invite", 2000),
				member_event("$join", user_id, "join", 3000),
			}, true)
			flush_scheduled()

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
		end)

		it("keeps treating pending events released by a historical event as historical", function()
			client.get_room(room_id).pending_events["$target"] = {
				["$leave"] = member_event("$leave", user_id, "leave"),
			}

			event.handle_multiple(room_id, { member_event("$target", other_user_id, "join") }, true)
			flush_scheduled()

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
		end)

		it("still renders a self leave as a membership line", function()
			event.handle_multiple(room_id, { member_event("$leave", user_id, "leave") }, true)
			flush_scheduled()

			local message = client.get_room_message(room_id, "$leave")
			assert.is_not_nil(message)
			assert.are.equal("Membership: Me left the room", message.content)
		end)

		it("does not remove the room for another user's leave", function()
			event.handle_multiple(room_id, { member_event("$leave", other_user_id, "leave") }, true)
			flush_scheduled()

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
		end)
	end)

	describe("joined room events", function()
		it("does not remove the room for a self leave", function()
			event.handle_multiple(room_id, { member_event("$leave", user_id, "leave") })
			flush_scheduled()

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
			local message = client.get_room_message(room_id, "$leave")
			assert.is_not_nil(message)
			assert.are.equal("Membership: Me left the room", message.content)
		end)

		it("does not remove the room for a self ban", function()
			local ban = member_event("$ban", user_id, "ban")
			ban.sender = other_user_id
			event.handle_multiple(room_id, { ban })
			flush_scheduled()

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
			local message = client.get_room_message(room_id, "$ban")
			assert.is_not_nil(message)
			assert.are.equal("Membership: Me was banned from the room by Other", message.content)
		end)

		it("does not remove the room for a leave and join sequence", function()
			event.handle_multiple(room_id, {
				member_event("$leave", user_id, "leave", 1000),
				member_event("$join", user_id, "join", 2000),
			})
			flush_scheduled()

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
		end)
	end)

	describe("sync", function()
		--- Run a sync with the given response
		--- @param data table The `/sync` response
		local function run_sync(data)
			local api = require("neoment.matrix.api")
			local error = require("neoment.error")
			api.get = function(_, callback)
				callback(error.ok(vim.tbl_extend("keep", data, { next_batch = "next" })))
			end

			local done = false
			matrix.sync({}, function()
				done = true
			end)
			vim.wait(100, function()
				return done
			end)
			assert.is_true(done)
			flush_scheduled()
		end

		--- Build a sync response that lists a room as left
		--- @param left_room_id string The ID of the left room
		--- @param events table The timeline events of the left room
		--- @return table The sync response
		local function left_sync(left_room_id, events)
			return { rooms = { leave = { [left_room_id] = { timeline = { events = events } } } } }
		end

		--- Build a `m.room.member` event sent by another user
		--- @param event_id string The event ID
		--- @param membership string The membership value
		--- @return table The event
		local function removal_event(event_id, membership)
			local e = member_event(event_id, user_id, membership)
			e.sender = other_user_id
			return e
		end

		before_each(function()
			client.client.sync_token = "since"
		end)

		describe("rooms.join", function()
			it("does not remove the room for a self leave in the state", function()
				run_sync({
					rooms = {
						join = {
							[room_id] = {
								timeline = { events = { member_event("$join", other_user_id, "join", 2000) } },
								state = { events = { member_event("$leave", user_id, "leave") } },
							},
						},
					},
				})

				assert.are.equal(0, confirm_calls)
				assert.is_true(client.has_room(room_id))
			end)
		end)

		describe("rooms.leave", function()
			it("shows the dialog and removes the room when the user is kicked", function()
				run_sync(left_sync(room_id, { removal_event("$kick", "leave") }))

				assert.are.equal(1, confirm_calls)
				assert.is_false(client.has_room(room_id))
			end)

			it("shows the dialog and removes the room when the user is banned", function()
				run_sync(left_sync(room_id, { removal_event("$ban", "ban") }))

				assert.are.equal(1, confirm_calls)
				assert.is_false(client.has_room(room_id))
			end)

			it("removes the room without a dialog when the user leaves", function()
				run_sync(left_sync(room_id, { member_event("$leave", user_id, "leave") }))

				assert.are.equal(0, confirm_calls)
				assert.is_false(client.has_room(room_id))
			end)

			it("removes the invite without a dialog when the user rejects it", function()
				local invited_room_id = "!invited:example.org"
				client.get_invited_room(invited_room_id)

				run_sync(left_sync(invited_room_id, { member_event("$reject", user_id, "leave") }))

				assert.are.equal(0, confirm_calls)
				assert.is_false(client.is_invited_room(invited_room_id))
			end)

			it("ignores an unknown room", function()
				local unknown_room_id = "!unknown:example.org"

				run_sync(left_sync(unknown_room_id, { removal_event("$kick", "leave") }))

				assert.are.equal(0, confirm_calls)
				assert.is_false(client.has_room(unknown_room_id))
				assert.is_false(client.is_invited_room(unknown_room_id))
			end)

			it("removes the room without a dialog on the initial sync", function()
				client.client.sync_token = nil

				run_sync(left_sync(room_id, { removal_event("$kick", "leave") }))

				assert.are.equal(0, confirm_calls)
				assert.is_false(client.has_room(room_id))
			end)

			it("removes the room without a dialog when there is no membership event", function()
				run_sync(left_sync(room_id, {}))

				assert.are.equal(0, confirm_calls)
				assert.is_false(client.has_room(room_id))
			end)

			it("uses the last removal event in server order, ignoring timestamps", function()
				local self_leave = member_event("$leave", user_id, "leave", 2000)
				local kick = removal_event("$kick", "leave")
				kick.origin_server_ts = 1000

				run_sync(left_sync(room_id, { self_leave, kick }))

				assert.are.equal(1, confirm_calls)
				assert.is_false(client.has_room(room_id))
			end)

			it("ignores a non-removal membership event after the removal", function()
				run_sync(left_sync(room_id, {
					member_event("$leave", user_id, "leave", 1000),
					removal_event("$invite", "invite"),
				}))

				assert.are.equal(0, confirm_calls)
				assert.is_false(client.has_room(room_id))
			end)

			it("uses the membership event in the state when the timeline has none", function()
				run_sync({
					rooms = { leave = { [room_id] = { state = { events = { removal_event("$kick", "leave") } } } } },
				})

				assert.are.equal(1, confirm_calls)
				assert.is_false(client.has_room(room_id))
			end)
		end)
	end)

	describe("client.remove_room", function()
		it("removes an invited room", function()
			local invited_room_id = "!invited:example.org"
			client.get_invited_room(invited_room_id)
			assert.is_true(client.is_invited_room(invited_room_id))

			client.remove_room(invited_room_id)

			assert.is_false(client.is_invited_room(invited_room_id))
			assert.is_false(client.has_room(invited_room_id))
		end)
	end)

	describe("load_more_messages", function()
		--- Load a history page with the given response
		--- @param data table The `/messages` response
		local function load_page(data)
			local api = require("neoment.matrix.api")
			local error = require("neoment.error")
			api.get = function(_, callback)
				callback(error.ok(data))
			end

			client.get_room(room_id).prev_batch = { token = "token" }

			local done = false
			matrix.load_more_messages(room_id, function()
				done = true
			end)
			vim.wait(100, function()
				return done
			end)
			assert.is_true(done)
			flush_scheduled()
		end

		it("does not remove the room for a self leave in the chunk", function()
			load_page({
				chunk = { member_event("$leave", user_id, "leave") },
				["end"] = "next",
			})

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
		end)

		it("does not remove the room for a self leave in the state", function()
			load_page({
				chunk = { member_event("$join", other_user_id, "join") },
				state = { events = { member_event("$leave", user_id, "leave") } },
				["end"] = "next",
			})

			assert.are.equal(0, confirm_calls)
			assert.is_true(client.has_room(room_id))
		end)
	end)
end)
