describe("matrix receipt events", function()
	local room_id = "!room1:example.org"
	local user_id = "@me:example.org"

	local client
	local event

	--- Build a `m.receipt` event with the user's read receipt
	--- @param event_id string The event the receipt points to
	--- @param ts integer The server timestamp of the receipt
	--- @return table The event
	local function receipt_event(event_id, ts)
		return {
			type = "m.receipt",
			content = { [event_id] = { ["m.read"] = { [user_id] = { ts = ts } } } },
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
end)
