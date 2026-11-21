describe("matrix receipt events", function()
	local room_id = "!room1:example.org"
	local user_id = "@me:example.org"

	local client
	local event

	--- Build a `m.receipt` event with the user's read receipt
	--- @param event_id string The event the receipt points to
	--- @param ts integer The server timestamp of the receipt
	--- @return table The event
	--- @param data? table Extra receipt fields, such as `thread_id`
	--- @param user? string The user of the receipt, the current user by default
	local function receipt_event(event_id, ts, data, user)
		return {
			type = "m.receipt",
			content = {
				[event_id] = { ["m.read"] = { [user or user_id] = vim.tbl_extend("force", { ts = ts }, data or {}) } },
			},
		}
	end

	before_each(function()
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.curl"] = {}
		package.loaded["neoment.notify"] = {
			desktop_message = function() end,
			room_counts_changed = function() end,
			clear_candidates = function() end,
		}
		package.loaded["neoment.rooms"] = { update_room_list = function() end }

		client = require("neoment.matrix.client")
		client.new("https://example.org", "token123")
		client.client.user_id = user_id
		client.get_room(room_id)

		event = require("neoment.matrix.event")
	end)

	after_each(function()
		for _, module in ipairs({
			"neoment.matrix",
			"neoment.matrix.client",
			"neoment.matrix.api",
			"neoment.matrix.event",
			"neoment.curl",
			"neoment.notify",
			"neoment.rooms",
		}) do
			package.loaded[module] = nil
		end
	end)

	describe("marking a room read", function()
		before_each(function()
			require("neoment.matrix.api").authed.post = function() end
		end)

		it("uses the server timestamp of the read message", function()
			client.get_room(room_id).messages["$read"] = { id = "$read", timestamp = 1234 }

			require("neoment.matrix").set_room_read_marker(room_id, { read_private = "$read" })

			assert.are.same({ event_id = "$read", ts = 1234, is_local = true }, client.get_room_read_receipt(room_id))
		end)

		it("falls back to the local clock for a message it does not have", function()
			require("neoment.matrix").set_room_read_marker(room_id, { read = "$unknown" })

			local receipt = client.get_room_read_receipt(room_id)
			assert.are.equal("$unknown", receipt.event_id)
			assert.is_true(math.abs(receipt.ts - os.time() * 1000) < 5000)
		end)
	end)

	it("keeps a newer receipt over an older one", function()
		client.set_room_read_receipt(room_id, { event_id = "$new", ts = 2000 })

		event.handle(room_id, receipt_event("$old", 1000))

		assert.are.same({ event_id = "$new", ts = 2000 }, client.get_room_read_receipt(room_id))
	end)

	it("replaces a local receipt with the server's one, even with an older timestamp", function()
		-- The local clock was ahead of the server
		client.set_room_read_receipt(room_id, { event_id = "$read", ts = 5000, is_local = true })

		event.handle(room_id, receipt_event("$read", 1000))

		assert.are.same({ event_id = "$read", ts = 1000 }, client.get_room_read_receipt(room_id))
	end)

	it("keeps a local receipt when only another user's receipt arrives", function()
		local receipt = { event_id = "$read", ts = 5000, is_local = true }
		client.set_room_read_receipt(room_id, vim.deepcopy(receipt))

		event.handle(room_id, receipt_event("$other", 1000, nil, "@other:example.org"))

		assert.are.same(receipt, client.get_room_read_receipt(room_id))
	end)

	it("ignores thread receipts", function()
		client.set_room_read_receipt(room_id, { event_id = "$main", ts = 1000 })

		event.handle(room_id, receipt_event("$in_thread", 2000, { thread_id = "$root" }))

		assert.are.same({ event_id = "$main", ts = 1000 }, client.get_room_read_receipt(room_id))
	end)

	it("accepts a main-timeline receipt marked with the main thread", function()
		event.handle(room_id, receipt_event("$read", 2000, { thread_id = "main" }))

		assert.are.equal("$read", client.get_room_read_receipt(room_id).event_id)
	end)

	--- A `m.receipt` event with the user's read receipt and no timestamp
	--- @param event_id string The event the receipt points to
	--- @return table The event
	local function receipt_event_without_ts(event_id)
		return { type = "m.receipt", content = { [event_id] = { ["m.read"] = { [user_id] = {} } } } }
	end

	it("moves to a receipt without a timestamp and keeps the previous timestamp", function()
		client.set_room_read_receipt(room_id, { event_id = "$old", ts = 5000 })

		assert.has_no.errors(function()
			event.handle(room_id, receipt_event_without_ts("$read"))
		end)

		assert.are.same({ event_id = "$read", ts = 5000 }, client.get_room_read_receipt(room_id))
	end)

	it("accepts a receipt without a timestamp when there is none yet", function()
		event.handle(room_id, receipt_event_without_ts("$read"))

		assert.are.same({ event_id = "$read", ts = 0 }, client.get_room_read_receipt(room_id))
	end)

	it("keeps the receipt when one without a timestamp points to the same event", function()
		local receipt = { event_id = "$read", ts = 5000, is_local = true }
		client.set_room_read_receipt(room_id, vim.deepcopy(receipt))

		event.handle(room_id, receipt_event_without_ts("$read"))

		assert.are.same(receipt, client.get_room_read_receipt(room_id))
	end)
end)
