describe("session expiry", function()
	local STUBBED_MODULES = {
		"neoment",
		"neoment.config",
		"neoment.notify",
		"neoment.sync",
		"neoment.rooms",
		"neoment.room",
		"neoment.storage",
		"neoment.matrix",
		"neoment.matrix.api",
		"neoment.matrix.auth",
		"neoment.sso_listener",
		"neoment.highlight",
		"neoment.focus",
	}

	local neoment
	local calls
	local matrix_mock
	local api_mock

	before_each(function()
		calls = { stop = 0, clear_session = 0, errors = {}, handler = nil }
		matrix_mock = {
			client = {
				homeserver = "https://matrix.example.org",
				access_token = "token",
				user_id = "@alice:example.org",
			},
			is_logged_in = function()
				return matrix_mock.client ~= nil and matrix_mock.client.access_token ~= nil
			end,
			set_homeserver = function(homeserver)
				matrix_mock.client = { homeserver = homeserver }
			end,
		}
		api_mock = {
			set_session_expired_handler = function(handler)
				calls.handler = handler
			end,
		}

		package.loaded["neoment.config"] = {
			load = function() end,
			get = function()
				return { save_session = true }
			end,
		}
		package.loaded["neoment.notify"] = {
			error = function(message)
				table.insert(calls.errors, message)
			end,
			info = function() end,
			warning = function() end,
		}
		package.loaded["neoment.sync"] = {
			stop = function()
				calls.stop = calls.stop + 1
			end,
		}
		package.loaded["neoment.rooms"] = { toggle_room_list = function() end }
		package.loaded["neoment.room"] = {}
		package.loaded["neoment.storage"] = {
			clear_session = function()
				calls.clear_session = calls.clear_session + 1
				return true
			end,
		}
		package.loaded["neoment.matrix"] = matrix_mock
		package.loaded["neoment.matrix.api"] = api_mock
		package.loaded["neoment.matrix.auth"] = {}
		package.loaded["neoment.sso_listener"] = {}
		package.loaded["neoment.highlight"] = { define_highlights = function() end }
		package.loaded["neoment.focus"] = { setup = function() end }
		package.loaded["neoment"] = nil

		neoment = require("neoment")
	end)

	after_each(function()
		for _, module in ipairs(STUBBED_MODULES) do
			package.loaded[module] = nil
		end
	end)

	describe("on_session_expired", function()
		it("stops syncing, clears the saved session, resets the client and asks to log in again", function()
			neoment.on_session_expired()

			assert.are.equal(1, calls.stop)
			assert.are.equal(1, calls.clear_session)
			assert.are.same({ homeserver = "https://matrix.example.org" }, matrix_mock.client)
			assert.are.equal(1, #calls.errors)
			assert.matches("log in again", calls.errors[1], 1, true)
		end)

		it("does nothing the second time, when concurrent requests fail together", function()
			neoment.on_session_expired()
			neoment.on_session_expired()

			assert.are.equal(1, calls.stop)
			assert.are.equal(1, calls.clear_session)
			assert.are.equal(1, #calls.errors)
		end)

		it("does nothing when not logged in", function()
			matrix_mock.client = nil

			neoment.on_session_expired()

			assert.are.equal(0, calls.stop)
			assert.are.equal(0, calls.clear_session)
			assert.are.same({}, calls.errors)
		end)
	end)

	it("is registered with the api when the plugin starts", function()
		neoment.init()

		assert.are.equal(neoment.on_session_expired, calls.handler)
	end)
end)
