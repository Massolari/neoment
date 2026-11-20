describe("sync with an expiring access token", function()
	local MODULES = {
		"neoment.curl",
		"neoment.notify",
		"neoment.rooms",
		"neoment.storage",
		"neoment.sync",
		"neoment.matrix",
		"neoment.matrix.api",
		"neoment.matrix.client",
		"neoment.matrix.event",
		"neoment.matrix.token",
	}

	local client
	local sync
	local notifications
	local saved
	--- Requests waiting for an answer, in the order they were sent
	local sent
	local on_done_spy

	--- Answer the oldest request that is waiting
	--- @param status integer
	--- @param body table
	local function respond(status, body)
		local request = table.remove(sent, 1)
		request.opts.callback({ status = status, body = vim.json.encode(body), exit = 0 })
	end

	--- Run the callbacks scheduled by the sync loop
	local function flush_scheduled()
		vim.wait(20, function()
			return false
		end)
	end

	before_each(function()
		sent = {}
		notifications = { error = {} }
		saved = 0
		on_done_spy = spy.new(function() end)

		package.loaded["neoment.curl"] = {
			get = function(endpoint, opts)
				table.insert(sent, { method = "GET", endpoint = endpoint, opts = opts })
			end,
			post = function(endpoint, opts)
				table.insert(sent, { method = "POST", endpoint = endpoint, opts = opts })
			end,
		}
		package.loaded["neoment.notify"] = {
			error = function(message)
				table.insert(notifications.error, message)
			end,
			info = function() end,
			desktop_message = function() end,
			room_counts_changed = function() end,
			clear_candidates = function() end,
		}
		package.loaded["neoment.rooms"] = { update_room_list = function() end }
		package.loaded["neoment.storage"] = {
			save_session = function()
				saved = saved + 1
			end,
			read_saved_session = function()
				return nil
			end,
		}
		for _, module in ipairs({
			"neoment.sync",
			"neoment.matrix",
			"neoment.matrix.api",
			"neoment.matrix.client",
			"neoment.matrix.event",
			"neoment.matrix.token",
		}) do
			package.loaded[module] = nil
		end

		client = require("neoment.matrix.client")
		client.new("https://matrix.example.org", "old-access")
		client.client.user_id = "@alice:example.org"
		client.client.sync_token = "s1"
		client.client.refresh_token = "old-refresh"
		client.client.expires_at = os.time() + 600

		sync = require("neoment.sync")
	end)

	after_each(function()
		sync.stop()
		for _, module in ipairs(MODULES) do
			package.loaded[module] = nil
		end
	end)

	it("refreshes after a soft logout and repeats /sync with the same since token", function()
		sync.start(client.client, on_done_spy, { save_session = false })

		assert.are.equal(1, #sent)
		local first = sent[1]
		assert.are.equal("GET", first.method)
		assert.matches("/_matrix/client/v3/sync?", first.endpoint, 1, true)
		assert.matches("since=s1", first.endpoint, 1, true)
		assert.are.equal("Bearer old-access", first.opts.headers["Authorization"])

		-- The long-poll comes back because the token expired
		respond(401, { errcode = "M_UNKNOWN_TOKEN", error = "Access token has expired", soft_logout = true })

		assert.are.equal(1, #sent)
		assert.are.equal("POST", sent[1].method)
		assert.are.equal("https://matrix.example.org/_matrix/client/v3/refresh", sent[1].endpoint)
		respond(200, { access_token = "new-access", refresh_token = "new-refresh", expires_in_ms = 300000 })

		-- The same request is repeated with the new token
		assert.are.equal(1, #sent)
		local repeated = sent[1]
		assert.are.equal("GET", repeated.method)
		assert.are.equal(first.endpoint, repeated.endpoint)
		assert.are.equal("Bearer new-access", repeated.opts.headers["Authorization"])
		assert.are.equal("s1", client.client.sync_token)

		respond(200, { next_batch = "s2" })
		flush_scheduled()

		assert.are.same({}, notifications.error)
		assert.are.equal("s2", client.client.sync_token)
		assert.spy(on_done_spy).was_called(1)
		assert.are.equal("new-refresh", client.client.refresh_token)

		-- The loop goes on from the new since token
		assert.are.equal(1, #sent)
		assert.matches("since=s2", sent[1].endpoint, 1, true)
		assert.are.equal("Bearer new-access", sent[1].opts.headers["Authorization"])
	end)

	it("refreshes before /sync when the token is about to expire", function()
		client.client.expires_at = os.time() + 20

		sync.start(client.client, on_done_spy, { save_session = false })

		assert.are.equal(1, #sent)
		assert.are.equal("POST", sent[1].method)
		respond(200, { access_token = "new-access", expires_in_ms = 300000 })

		assert.are.equal(1, #sent)
		assert.are.equal("GET", sent[1].method)
		assert.matches("since=s1", sent[1].endpoint, 1, true)
		assert.are.equal("Bearer new-access", sent[1].opts.headers["Authorization"])
		assert.are.same({}, notifications.error)
	end)

	it("stops without retrying when the refresh token is rejected", function()
		sync.start(client.client, on_done_spy, { save_session = false })
		respond(401, { errcode = "M_UNKNOWN_TOKEN", error = "Access token has expired", soft_logout = true })
		respond(400, { errcode = "M_UNKNOWN_TOKEN", error = "Invalid refresh token" })
		flush_scheduled()

		assert.are.equal(0, #sent)
		assert.are.same({}, notifications.error)
		assert.spy(on_done_spy).was_not_called()
		assert.are.equal("stopped", sync.get_status().kind)
	end)
end)
