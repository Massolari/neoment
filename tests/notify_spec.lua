describe("notify desktop notifications", function()
	local STUBBED_MODULES = { "neoment.matrix", "neoment.sync", "neoment.focus", "neoment.config", "neoment.notify" }
	local USER_ID = "@me:server"

	local original_config
	local sent
	local sync_status
	local focused
	local notify

	--- Load the config with the given desktop notification settings and a recording handler
	--- @param desktop_notifications table
	local function load_config(desktop_notifications)
		vim.g.neoment = {
			desktop_notifications = vim.tbl_extend("force", {
				handler = function(title, content)
					table.insert(sent, { title = title, content = content })
				end,
			}, desktop_notifications),
		}
		require("neoment.config").load()
	end

	--- @param overrides table?
	--- @return neoment.matrix.client.Room
	local function make_room(overrides)
		return vim.tbl_extend("force", {
			id = "!room:server",
			name = "Group",
			aliases = {},
			messages = {},
			is_tracked = false,
			is_favorite = false,
			is_direct = false,
		}, overrides or {})
	end

	--- @param overrides table?
	--- @return neoment.matrix.client.Message
	local function make_message(overrides)
		return vim.tbl_extend("force", {
			id = "$event",
			sender = "@alice:server",
			content = "hello",
			timestamp = 1000,
			is_state = false,
		}, overrides or {})
	end

	--- @param notification_count integer
	--- @param highlight_count integer?
	--- @return neoment.matrix.UnreadNotificationCounts
	local function counts(notification_count, highlight_count)
		return { notification_count = notification_count, highlight_count = highlight_count or 0 }
	end

	before_each(function()
		original_config = vim.g.neoment
		sent = {}
		sync_status = { kind = "syncing", last_sync = 1 }
		focused = true
		vim.b.room_id = nil

		package.loaded["neoment.matrix"] = {
			get_user_id = function()
				return USER_ID
			end,
			get_display_name = function(user_id)
				return ({ ["@alice:server"] = "Alice", ["@bob:server"] = "Bob" })[user_id] or user_id
			end,
		}
		package.loaded["neoment.sync"] = {
			get_status = function()
				return sync_status
			end,
		}
		package.loaded["neoment.focus"] = {
			is_focused = function()
				return focused
			end,
		}
		package.loaded["neoment.config"] = nil
		package.loaded["neoment.notify"] = nil
		notify = require("neoment.notify")
	end)

	after_each(function()
		vim.g.neoment = original_config
		vim.b.room_id = nil
		for _, module in ipairs(STUBBED_MODULES) do
			package.loaded[module] = nil
		end
	end)

	describe("custom source", function()
		it("notifies every message in a favorite room set to all", function()
			load_config({ source = "custom", favorites = "all", rooms = "none" })

			notify.desktop_message(make_room({ is_favorite = true }), make_message())

			assert.are.same({ { title = "[Group] Alice", content = "hello" } }, sent)
		end)

		it("does not notify a message without a mention in a group room set to mentions", function()
			load_config({ source = "custom", rooms = "mentions" })

			notify.desktop_message(make_room(), make_message({ mentions = {} }))

			assert.are.same({}, sent)
		end)

		it("notifies a mention in a group room set to mentions", function()
			load_config({ source = "custom", rooms = "mentions" })

			notify.desktop_message(make_room(), make_message({ mentions = { USER_ID } }))

			assert.are.equal(1, #sent)
		end)

		it("lets a per_room alias override the room type level", function()
			load_config({ source = "custom", rooms = "all", per_room = { ["#group:server"] = "none" } })

			notify.desktop_message(make_room({ aliases = { "#group:server" } }), make_message())

			assert.are.same({}, sent)
		end)

		it("uses the buffer level for a room open in a buffer", function()
			load_config({ source = "custom", buffer = "all", rooms = "none" })

			notify.desktop_message(make_room({ is_tracked = true }), make_message())

			assert.are.equal(1, #sent)
		end)

		it("ignores the server push rules", function()
			load_config({ source = "custom", rooms = "all" })
			local room = make_room()

			-- A room muted on the server never raises its counts
			notify.desktop_message(room, make_message())
			notify.room_counts_changed(room, counts(0), counts(0))

			assert.are.equal(1, #sent)
		end)

		it("does not count rising counts as a notification", function()
			load_config({ source = "custom", rooms = "none" })

			notify.room_counts_changed(make_room(), counts(0), counts(3))

			assert.are.same({}, sent)
		end)

		it("skips the user's own messages", function()
			load_config({ source = "custom", rooms = "all" })

			notify.desktop_message(make_room(), make_message({ sender = USER_ID }))

			assert.are.same({}, sent)
		end)

		it("skips the focused room", function()
			load_config({ source = "custom", buffer = "all" })
			vim.b.room_id = "!room:server"

			notify.desktop_message(make_room({ is_tracked = true }), make_message())

			assert.are.same({}, sent)
		end)
	end)

	describe("server source", function()
		before_each(function()
			load_config({})
		end)

		it("is the default source", function()
			assert.are.equal("server", require("neoment.config").get().desktop_notifications.source)
		end)

		it("does not notify when a message arrives", function()
			notify.desktop_message(make_room(), make_message())

			assert.are.same({}, sent)
		end)

		it("notifies once when the count increases", function()
			local room = make_room()
			notify.desktop_message(room, make_message())

			notify.room_counts_changed(room, counts(2), counts(3))

			assert.are.same({ { title = "[Group] Alice", content = "hello" } }, sent)
		end)

		it("notifies once for several messages, showing the newest", function()
			local room = make_room()
			notify.desktop_message(room, make_message({ id = "$1", content = "first", timestamp = 1 }))
			notify.desktop_message(
				room,
				make_message({ id = "$2", sender = "@bob:server", content = "second", timestamp = 2 })
			)

			notify.room_counts_changed(room, counts(0), counts(4))

			assert.are.same({ { title = "[Group] Bob", content = "second" } }, sent)
		end)

		it("does not notify when the count is unchanged", function()
			local room = make_room()
			notify.desktop_message(room, make_message())

			notify.room_counts_changed(room, counts(2), counts(2))

			assert.are.same({}, sent)
		end)

		it("does not notify when the count decreases", function()
			notify.room_counts_changed(make_room(), counts(5), counts(0))

			assert.are.same({}, sent)
		end)

		it("notifies when only the highlight count increases", function()
			notify.room_counts_changed(make_room(), counts(1, 0), counts(1, 1))

			assert.are.equal(1, #sent)
		end)

		it("shows the message from another user when the newest is the user's own", function()
			local room = make_room()
			notify.desktop_message(room, make_message({ id = "$1", timestamp = 1 }))
			notify.desktop_message(room, make_message({ id = "$2", sender = USER_ID, content = "mine", timestamp = 2 }))

			notify.room_counts_changed(room, counts(0), counts(1))

			assert.are.same({ { title = "[Group] Alice", content = "hello" } }, sent)
		end)

		it("falls back to the newest stored message from another user", function()
			local room = make_room({
				messages = {
					["$1"] = make_message({ id = "$1", content = "old", timestamp = 1 }),
					["$2"] = make_message({ id = "$2", sender = USER_ID, content = "mine", timestamp = 2 }),
				},
			})

			notify.room_counts_changed(room, counts(0), counts(1))

			assert.are.same({ { title = "[Group] Alice", content = "old" } }, sent)
		end)

		it("does not fall back to a message older than the read receipt", function()
			local room = make_room({
				messages = { ["$1"] = make_message({ id = "$1", content = "read", timestamp = 1 }) },
				read_receipt = { event_id = "$1", ts = 5 },
			})

			notify.room_counts_changed(room, counts(0), counts(1))

			assert.are.same({ { title = "Group", content = "New notification" } }, sent)
		end)

		it("does not fall back to the message of an earlier notification", function()
			local room = make_room({
				messages = { ["$1"] = make_message({ id = "$1", content = "hello", timestamp = 1 }) },
			})
			notify.desktop_message(room, room.messages["$1"])
			notify.room_counts_changed(room, counts(0), counts(1))

			notify.room_counts_changed(room, counts(1), counts(2))

			assert.are.same({
				{ title = "[Group] Alice", content = "hello" },
				{ title = "Group", content = "New notification" },
			}, sent)
		end)

		it("shows the room name and a generic text without a message", function()
			notify.room_counts_changed(make_room(), counts(0), counts(1))

			assert.are.same({ { title = "Group", content = "New notification" } }, sent)
		end)

		it("shows only the sender's name in a room named after them", function()
			local room = make_room({ name = "Alice" })
			notify.desktop_message(room, make_message())

			notify.room_counts_changed(room, counts(0), counts(1))

			assert.are.same({ { title = "Alice", content = "hello" } }, sent)
		end)

		it("ignores the custom levels", function()
			load_config({ source = "server", per_room = { ["!room:server"] = "none" }, rooms = "none" })

			notify.room_counts_changed(make_room(), counts(0), counts(1))

			assert.are.equal(1, #sent)
		end)

		it("forgets the candidates once cleared", function()
			local room = make_room()
			notify.desktop_message(room, make_message({ content = "stale" }))

			notify.clear_candidates()
			notify.room_counts_changed(room, counts(0), counts(1))

			assert.are.same({ { title = "Group", content = "New notification" } }, sent)
		end)

		it("does not notify when notifications are disabled", function()
			load_config({ enabled = false })

			notify.room_counts_changed(make_room(), counts(0), counts(1))

			assert.are.same({}, sent)
		end)

		it("does not notify during the first sync", function()
			sync_status = { kind = "syncing", last_sync = nil }

			notify.room_counts_changed(make_room(), counts(0), counts(1))

			assert.are.same({}, sent)
		end)

		it("does not notify for the focused room", function()
			vim.b.room_id = "!room:server"

			notify.room_counts_changed(make_room(), counts(0), counts(1))

			assert.are.same({}, sent)
		end)

		it("notifies for the room in the current buffer when Neovim is unfocused", function()
			vim.b.room_id = "!room:server"
			focused = false

			notify.room_counts_changed(make_room(), counts(0), counts(1))

			assert.are.equal(1, #sent)
		end)
	end)
end)
