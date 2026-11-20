local error_mod = require("neoment.error")

describe("sync", function()
	local STUBBED_MODULES = { "neoment.notify", "neoment.storage", "neoment.matrix", "neoment.sync" }

	local notifications
	local matrix_mock
	local sync_calls
	local sync

	--- Make `matrix.sync` answer the first request with a result and leave the following ones waiting
	--- @param first_result neoment.Error<table, table>
	local function answer_first_sync_with(first_result)
		matrix_mock.sync = function(_, callback)
			sync_calls = sync_calls + 1
			if sync_calls == 1 then
				callback(first_result)
			end
		end
	end

	before_each(function()
		notifications = { error = {}, info = {} }
		sync_calls = 0
		matrix_mock = {
			get_desired_presence = function()
				return nil
			end,
		}

		package.loaded["neoment.notify"] = {
			error = function(message)
				table.insert(notifications.error, message)
			end,
			info = function(message)
				table.insert(notifications.info, message)
			end,
		}
		package.loaded["neoment.storage"] = { save_session = function() end }
		package.loaded["neoment.matrix"] = matrix_mock
		package.loaded["neoment.sync"] = nil

		sync = require("neoment.sync")
	end)

	after_each(function()
		for _, module in ipairs(STUBBED_MODULES) do
			package.loaded[module] = nil
		end
	end)

	it("stops the loop without retrying when the session expired", function()
		answer_first_sync_with(error_mod.err({
			error = "Session expired, please log in again",
			errcode = "M_UNKNOWN_TOKEN",
			status = 401,
			session_expired = true,
		}))

		sync.start({}, function() end, { save_session = false })
		-- A retry would be scheduled after one second
		vim.wait(1200)

		assert.are.equal(1, sync_calls)
		assert.are.same({}, notifications.error)
		assert.are.equal("stopped", sync.get_status().kind)
	end)

	it("can be started again after the session expired", function()
		answer_first_sync_with(error_mod.err({ error = "Session expired", session_expired = true }))
		sync.start({}, function() end, { save_session = false })

		sync.start({}, function() end, { save_session = false })

		assert.are.equal(2, sync_calls)
	end)

	it("retries after another kind of error", function()
		answer_first_sync_with(error_mod.err({ error = "Failed to make GET request", status = 502 }))

		sync.start({}, function() end, { save_session = false })

		assert.are.equal(1, #notifications.error)
		assert.matches("Retrying...", notifications.error[1], 1, true)
		-- The loop goes on with the next request
		assert.are.equal(2, sync_calls)
	end)

	it("drops a stale response without stopping a sync started after it", function()
		local callbacks = {}
		matrix_mock.sync = function(_, callback)
			sync_calls = sync_calls + 1
			table.insert(callbacks, callback)
		end

		sync.start({}, function() end, { save_session = false })
		sync.stop()
		sync.start({}, function() end, { save_session = false })
		assert.are.equal(2, sync_calls)

		-- The request of the old session answers after the new loop started
		callbacks[1](error_mod.err({ error = "Session ended", stale = true }))
		assert.are.equal(2, sync_calls)
		assert.are.same({}, notifications.error)
		assert.are.equal("syncing", sync.get_status().kind)

		-- The new loop keeps going once its own request answers
		callbacks[2](error_mod.ok({ sync = { next_batch = "n" }, updated_rooms = {} }))
		assert.are.equal(3, sync_calls)
	end)
end)
