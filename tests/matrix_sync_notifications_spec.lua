describe("matrix sync notification counts", function()
	local room_id = "!room:example.org"

	local client
	local matrix
	local count_changes
	local clear_calls

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
	end

	--- Build a sync response for the joined room
	--- @param room_data table The joined room data
	--- @return table The sync response
	local function joined_sync(room_data)
		return { rooms = { join = { [room_id] = room_data } } }
	end

	before_each(function()
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.curl"] = {}
		package.loaded["neoment.rooms"] = { update_room_list = function() end }

		count_changes = {}
		clear_calls = 0
		package.loaded["neoment.notify"] = {
			desktop_message = function() end,
			room_counts_changed = function(room, old, new)
				table.insert(count_changes, { room_id = room.id, old = old, new = new })
			end,
			clear_candidates = function()
				clear_calls = clear_calls + 1
			end,
		}

		client = require("neoment.matrix.client")
		client.new("https://example.org", "token123")
		client.client.user_id = "@me:example.org"
		client.client.sync_token = "since"
		matrix = require("neoment.matrix")

		local room = client.get_room(room_id)
		room.unread_notifications = 2
		room.unread_highlights = 0
	end)

	after_each(function()
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.curl"] = nil
		package.loaded["neoment.notify"] = nil
		package.loaded["neoment.rooms"] = nil
	end)

	it("reports a rising count once, after storing it", function()
		run_sync(joined_sync({ unread_notifications = { notification_count = 3, highlight_count = 0 } }))

		assert.are.equal(1, #count_changes)
		assert.are.equal(room_id, count_changes[1].room_id)
		assert.are.same({ notification_count = 2, highlight_count = 0 }, count_changes[1].old)
		assert.are.same({ notification_count = 3, highlight_count = 0 }, count_changes[1].new)
		assert.are.equal(3, client.get_room(room_id).unread_notifications)
	end)

	it("passes an unchanged count through without a change", function()
		run_sync(joined_sync({ unread_notifications = { notification_count = 2, highlight_count = 0 } }))

		assert.are.equal(1, #count_changes)
		assert.are.same(count_changes[1].old, count_changes[1].new)
	end)

	it("does not report counts for a sync without them", function()
		run_sync(joined_sync({ timeline = { events = {} } }))

		assert.are.equal(0, #count_changes)
		assert.are.equal(2, client.get_room(room_id).unread_notifications)
	end)

	it("clears the notification candidates at the end of each sync", function()
		run_sync(joined_sync({ unread_notifications = { notification_count = 3, highlight_count = 0 } }))

		assert.are.equal(1, clear_calls)
	end)

	it("stores the joined member count from the summary", function()
		run_sync(joined_sync({ summary = { ["m.joined_member_count"] = 2 } }))

		assert.are.equal(2, client.get_room(room_id).joined_member_count)
	end)

	it("keeps the joined member count when the summary omits it", function()
		client.get_room(room_id).joined_member_count = 5

		run_sync(joined_sync({ summary = { ["m.heroes"] = {} } }))

		assert.are.equal(5, client.get_room(room_id).joined_member_count)
	end)
end)

describe("notify with the server source through a sync", function()
	local room_id = "!room:example.org"
	local original_config

	before_each(function()
		original_config = vim.g.neoment
		for _, module in ipairs({
			"neoment.matrix",
			"neoment.matrix.client",
			"neoment.matrix.api",
			"neoment.matrix.event",
			"neoment.notify",
			"neoment.config",
		}) do
			package.loaded[module] = nil
		end
		package.loaded["neoment.curl"] = {}
		package.loaded["neoment.rooms"] = { update_room_list = function() end }
		package.loaded["neoment.sync"] = {
			get_status = function()
				return { kind = "syncing", last_sync = 1 }
			end,
		}
		package.loaded["neoment.focus"] = {
			is_focused = function()
				return false
			end,
		}
	end)

	after_each(function()
		vim.g.neoment = original_config
		for _, module in ipairs({
			"neoment.matrix",
			"neoment.matrix.client",
			"neoment.matrix.api",
			"neoment.matrix.event",
			"neoment.notify",
			"neoment.config",
			"neoment.curl",
			"neoment.rooms",
			"neoment.sync",
			"neoment.focus",
		}) do
			package.loaded[module] = nil
		end
	end)

	--- Sync a message from Alice with the given notification count, starting from a count of 1
	--- @param notification_count integer
	--- @return table The desktop notifications sent
	local function sync_message_with_count(notification_count)
		local sent = {}
		vim.g.neoment = {
			desktop_notifications = {
				handler = function(title, content)
					table.insert(sent, { title = title, content = content })
				end,
			},
		}
		require("neoment.config").load()

		local client = require("neoment.matrix.client")
		client.new("https://example.org", "token123")
		client.client.user_id = "@me:example.org"
		client.client.sync_token = "since"
		client.client.display_names["@alice:example.org"] = { display_name = "Alice", timestamp = 0 }
		client.get_room(room_id).name = "Group"
		client.get_room(room_id).unread_notifications = 1
		local matrix = require("neoment.matrix")

		local api = require("neoment.matrix.api")
		local error = require("neoment.error")
		api.get = function(_, callback)
			callback(error.ok({
				next_batch = "next",
				rooms = {
					join = {
						[room_id] = {
							timeline = {
								events = {
									{
										event_id = "$1",
										type = "m.room.message",
										sender = "@alice:example.org",
										origin_server_ts = 1000,
										content = { msgtype = "m.text", body = "hi there" },
									},
								},
							},
							unread_notifications = { notification_count = notification_count, highlight_count = 0 },
						},
					},
				},
			}))
		end

		local done = false
		matrix.sync({}, function()
			done = true
		end)
		vim.wait(100, function()
			return done
		end)
		assert.is_true(done)

		return sent
	end

	it("sends one notification with the newest incoming message for a rising count", function()
		local sent = sync_message_with_count(2)

		assert.are.same({ { title = "[Group] Alice", content = "hi there" } }, sent)
	end)

	it("sends no notification for an unchanged count", function()
		local sent = sync_message_with_count(1)

		assert.are.same({}, sent)
	end)
end)
