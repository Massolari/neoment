local error_mod = require("neoment.error")

describe("Matrix token refresh", function()
	local curl_mock
	local storage_mock
	local client
	local token
	local posts
	--- What the saved session file holds
	local saved_session

	--- Reply to the most recent request that is still waiting for an answer
	--- @param status integer
	--- @param body table
	local function respond(status, body)
		local request = table.remove(posts, 1)
		request.opts.callback({ status = status, body = vim.json.encode(body), exit = 0 })
	end

	--- Make a client as left by a login against a homeserver that issues expiring tokens
	--- @param fields? table
	local function login(fields)
		client.new("https://matrix.example.org", "old-access")
		client.client.user_id = "@alice:example.org"
		client.client.refresh_token = "old-refresh"
		client.client.expires_at = os.time() - 10
		for key, value in pairs(fields or {}) do
			client.client[key] = value
		end
	end

	before_each(function()
		posts = {}
		curl_mock = {
			post = function(endpoint, opts)
				table.insert(posts, { endpoint = endpoint, opts = opts })
			end,
		}
		saved_session = nil
		storage_mock = {
			save_session = spy.new(function() end),
			read_saved_session = spy.new(function()
				return saved_session
			end),
		}

		package.loaded["neoment.curl"] = curl_mock
		package.loaded["neoment.storage"] = storage_mock
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.token"] = nil

		client = require("neoment.matrix.client")
		token = require("neoment.matrix.token")
	end)

	after_each(function()
		package.loaded["neoment.curl"] = nil
		package.loaded["neoment.storage"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.token"] = nil
	end)

	describe("refresh with the legacy method", function()
		it("posts the refresh token to the homeserver without credentials", function()
			login()

			token.refresh(function() end)

			assert.are.equal(1, #posts)
			assert.are.equal("https://matrix.example.org/_matrix/client/v3/refresh", posts[1].endpoint)
			assert.are.same({ refresh_token = "old-refresh" }, vim.json.decode(posts[1].opts.body))
			assert.is_nil(posts[1].opts.headers["Authorization"])
		end)

		it("stores the rotated tokens and the new expiry time", function()
			login()
			local callback_spy = spy.new(function() end)

			token.refresh(callback_spy)
			local before = os.time()
			respond(200, { access_token = "new-access", refresh_token = "new-refresh", expires_in_ms = 300000 })

			assert.are.equal("new-access", client.client.access_token)
			assert.are.equal("new-refresh", client.client.refresh_token)
			assert.is_true(client.client.expires_at >= before + 300)
			assert.is_true(client.client.expires_at <= os.time() + 300)
			assert.spy(callback_spy).was_called(1)
			assert.is_true(error_mod.is_ok(callback_spy.calls[1].refs[1]))
		end)

		it("keeps the old refresh token when the response has none", function()
			login()

			token.refresh(function() end)
			respond(200, { access_token = "new-access", expires_in_ms = 300000 })

			assert.are.equal("new-access", client.client.access_token)
			assert.are.equal("old-refresh", client.client.refresh_token)
		end)

		it("treats the token as non-expiring when the response has no lifetime", function()
			login()

			token.refresh(function() end)
			respond(200, { access_token = "new-access" })

			assert.is_nil(client.client.expires_at)
			assert.is_false(token.is_stale())
		end)

		it("saves the session with the new tokens before the callback runs", function()
			login()
			local saved_access, saved_refresh
			storage_mock.save_session = spy.new(function()
				saved_access = client.client.access_token
				saved_refresh = client.client.refresh_token
			end)
			local saved_before_callback
			local callback = function()
				saved_before_callback = #storage_mock.save_session.calls
			end

			token.refresh(callback)
			respond(200, { access_token = "new-access", refresh_token = "new-refresh", expires_in_ms = 300000 })

			assert.are.equal(1, saved_before_callback)
			assert.are.equal("new-access", saved_access)
			assert.are.equal("new-refresh", saved_refresh)
		end)

		it(
			"stores and saves the new tokens before the callback runs when the response comes in a fast event",
			function()
				login()
				local in_fast_event = vim.in_fast_event
				local saved_access
				storage_mock.save_session = spy.new(function()
					saved_access = client.client.access_token
				end)
				local saved_before_callback
				local callback_spy = spy.new(function()
					saved_before_callback = #storage_mock.save_session.calls
				end)

				token.refresh(callback_spy)
				---@diagnostic disable-next-line: duplicate-set-field
				vim.in_fast_event = function()
					return true
				end
				local ok, err = pcall(respond, 200, { access_token = "new-access", expires_in_ms = 300000 })
				vim.in_fast_event = in_fast_event
				assert(ok, err)

				-- Nothing is used before the main loop gets the response
				assert.are.equal("old-access", client.client.access_token)
				assert.spy(callback_spy).was_not_called()

				vim.wait(100, function()
					return #callback_spy.calls > 0
				end)
				assert.are.equal(1, saved_before_callback)
				assert.are.equal("new-access", saved_access)
			end
		)

		it("gives up on a refresh request that does not end", function()
			login()

			token.refresh(function() end)

			local raw = posts[1].opts.raw
			assert.are.equal("--max-time", raw[1])
			assert.is_true(tonumber(raw[2]) > 0)
		end)

		it("does not write a session file when saving sessions is disabled", function()
			local config = require("neoment.config")
			local original = config.get().save_session
			config.get().save_session = false
			login()

			token.refresh(function() end)
			respond(200, { access_token = "new-access", expires_in_ms = 300000 })
			config.get().save_session = original

			assert.spy(storage_mock.save_session).was_not_called()
			assert.are.equal("new-access", client.client.access_token)
		end)
	end)

	describe("refresh with the OAuth method", function()
		before_each(function()
			login({
				refresh = {
					kind = "oauth",
					token_endpoint = "https://auth.example.org/oauth2/token",
					client_id = "client 1",
				},
			})
		end)

		it("posts a form-encoded refresh_token grant to the token endpoint", function()
			token.refresh(function() end)

			assert.are.equal(1, #posts)
			assert.are.equal("https://auth.example.org/oauth2/token", posts[1].endpoint)
			assert.are.equal("application/x-www-form-urlencoded", posts[1].opts.headers["Content-Type"])
			assert.are.equal(
				"grant_type=refresh_token&refresh_token=old-refresh&client_id=client%201",
				posts[1].opts.body
			)
			assert.is_nil(posts[1].opts.headers["Authorization"])
		end)

		it("stores the rotated tokens and an expiry time from expires_in in seconds", function()
			token.refresh(function() end)
			local before = os.time()
			respond(200, { access_token = "new-access", refresh_token = "new-refresh", expires_in = 300 })

			assert.are.equal("new-access", client.client.access_token)
			assert.are.equal("new-refresh", client.client.refresh_token)
			assert.is_true(client.client.expires_at >= before + 300)
			assert.is_true(client.client.expires_at <= os.time() + 300)
			assert.spy(storage_mock.save_session).was_called(1)
		end)

		it("keeps the refresh method after a refresh", function()
			token.refresh(function() end)
			respond(200, { access_token = "new-access", refresh_token = "new-refresh", expires_in = 300 })

			assert.are.equal("oauth", client.client.refresh.kind)
			assert.are.equal("client 1", client.client.refresh.client_id)
		end)
	end)

	describe("ensure_fresh", function()
		it("does nothing when the session has no expiry time", function()
			login()
			client.client.expires_at = nil
			local callback_spy = spy.new(function() end)

			token.ensure_fresh(callback_spy)

			assert.are.equal(0, #posts)
			assert.spy(callback_spy).was_called(1)
			assert.is_true(error_mod.is_ok(callback_spy.calls[1].refs[1]))
		end)

		it("does nothing when the token is far from expiring", function()
			login({ expires_at = os.time() + 600 })
			local callback_spy = spy.new(function() end)

			token.ensure_fresh(callback_spy)

			assert.are.equal(0, #posts)
			assert.spy(callback_spy).was_called(1)
		end)

		it("refreshes first when the token expires within 60 seconds", function()
			login({ expires_at = os.time() + 30 })
			local seen_token
			local callback = function()
				seen_token = client.client.access_token
			end

			token.ensure_fresh(callback)
			assert.are.equal(1, #posts)
			assert.is_nil(seen_token)

			respond(200, { access_token = "new-access", expires_in_ms = 300000 })
			assert.are.equal("new-access", seen_token)
		end)

		it("refreshes when the token already expired", function()
			login({ expires_at = os.time() - 5 })

			token.ensure_fresh(function() end)

			assert.are.equal(1, #posts)
		end)

		it("does not try to refresh a session without a refresh token", function()
			login({ expires_at = os.time() - 5 })
			client.client.refresh_token = nil

			token.ensure_fresh(function() end)

			assert.are.equal(0, #posts)
		end)
	end)

	describe("concurrent refreshes", function()
		it("sends one request for three callers and gives all of them the new token", function()
			login()
			local seen = {}
			local function waiting()
				table.insert(seen, client.client.access_token)
			end

			token.ensure_fresh(waiting)
			token.ensure_fresh(waiting)
			token.refresh(waiting)

			assert.are.equal(1, #posts)
			assert.are.equal(0, #seen)

			respond(200, { access_token = "new-access", refresh_token = "new-refresh", expires_in_ms = 300000 })

			assert.are.same({ "new-access", "new-access", "new-access" }, seen)
			assert.spy(storage_mock.save_session).was_called(1)
		end)

		it("sends a new request once the previous refresh finished", function()
			login()

			token.refresh(function() end)
			respond(200, { access_token = "second-access", expires_in_ms = 300000 })
			token.refresh(function() end)

			assert.are.equal(1, #posts)
		end)

		it("gives every waiting caller the failure", function()
			login()
			local results = {}
			local function waiting(result)
				table.insert(results, result)
			end

			token.refresh(waiting)
			token.refresh(waiting)
			respond(400, { errcode = "M_UNKNOWN_TOKEN", error = "Invalid refresh token" })

			assert.are.equal(2, #results)
			assert.is_true(results[1].error.session_expired)
			assert.is_true(results[2].error.session_expired)
		end)
	end)

	describe("failures", function()
		--- @return neoment.matrix.api.Error
		local function failed_refresh(reply)
			local callback_spy = spy.new(function() end)
			token.refresh(callback_spy)
			reply()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			return result.error
		end

		it("reports a rejected refresh token as an expired session", function()
			login()

			local err = failed_refresh(function()
				respond(401, { errcode = "M_UNKNOWN_TOKEN", error = "Invalid refresh token" })
			end)

			assert.is_true(err.session_expired)
			assert.are.equal("M_UNKNOWN_TOKEN", err.errcode)
			assert.are.equal(401, err.status)
		end)

		it("reports an OAuth invalid_grant as an expired session", function()
			login({ refresh = { kind = "oauth", token_endpoint = "https://auth.example.org/token", client_id = "c" } })

			local err = failed_refresh(function()
				respond(400, { error = "invalid_grant", error_description = "The refresh token is invalid" })
			end)

			assert.is_true(err.session_expired)
		end)

		it("reports an incomplete OAuth configuration as an expired session", function()
			login({ refresh = { kind = "oauth" } })

			local callback_spy = spy.new(function() end)
			token.refresh(callback_spy)

			assert.are.equal(0, #posts)
			assert.is_true(callback_spy.calls[1].refs[1].error.session_expired)
		end)

		it("keeps the session and the tokens after a network error", function()
			login()

			local err = failed_refresh(function()
				table.remove(posts, 1).opts.on_error({ message = "curl: connection refused", exit = 7 })
			end)

			assert.is_nil(err.session_expired)
			assert.are.equal("old-access", client.client.access_token)
			assert.are.equal("old-refresh", client.client.refresh_token)
			assert.spy(storage_mock.save_session).was_not_called()
		end)

		it("keeps the session after a server error", function()
			login()

			local err = failed_refresh(function()
				respond(503, { errcode = "M_UNKNOWN", error = "Try again later" })
			end)

			assert.is_nil(err.session_expired)
			assert.are.equal("old-refresh", client.client.refresh_token)
		end)

		it("keeps the session after a rate limit response", function()
			login()

			local err = failed_refresh(function()
				respond(429, { errcode = "M_LIMIT_EXCEEDED", error = "Too many requests", retry_after_ms = 1000 })
			end)

			assert.is_nil(err.session_expired)
		end)

		it("retries on the next request after a transient failure", function()
			login()

			token.refresh(function() end)
			respond(503, { errcode = "M_UNKNOWN", error = "Try again later" })
			token.ensure_fresh(function() end)

			assert.are.equal(1, #posts)
			respond(200, { access_token = "new-access", expires_in_ms = 300000 })
			assert.are.equal("new-access", client.client.access_token)
		end)

		it("ignores the response when the client was replaced during the request", function()
			login()
			local other = nil

			token.refresh(function(result)
				other = result
			end)
			client.set_homeserver("https://other.example.org")
			respond(200, { access_token = "new-access", refresh_token = "new-refresh", expires_in_ms = 300000 })

			assert.is_true(error_mod.is_error(other))
			assert.is_nil(client.client.access_token)
			assert.is_nil(client.client.refresh_token)
			assert.spy(storage_mock.save_session).was_not_called()
		end)
	end)

	describe("rotation race with another instance", function()
		local rejected = { errcode = "M_UNKNOWN_TOKEN", error = "Invalid refresh token" }

		--- The session as saved by the instance that refreshed first
		--- @param fields? table
		local function save_session_from_other_instance(fields)
			saved_session = vim.tbl_extend("force", {
				homeserver = "https://matrix.example.org",
				user_id = "@alice:example.org",
				access_token = "other-access",
				refresh_token = "other-refresh",
				expires_at = os.time() + 300,
			}, fields or {})
		end

		it("uses the credentials saved by the other instance when they are still valid", function()
			login()
			save_session_from_other_instance()
			local callback_spy = spy.new(function() end)

			token.refresh(callback_spy)
			respond(400, rejected)

			assert.are.equal(0, #posts)
			assert.are.equal("other-access", client.client.access_token)
			assert.are.equal("other-refresh", client.client.refresh_token)
			assert.spy(callback_spy).was_called(1)
			assert.is_true(error_mod.is_ok(callback_spy.calls[1].refs[1]))
		end)

		it("refreshes with the saved refresh token when the saved access token expired too", function()
			login()
			save_session_from_other_instance({ expires_at = os.time() - 5 })
			local callback_spy = spy.new(function() end)

			token.refresh(callback_spy)
			respond(400, rejected)

			assert.are.equal(1, #posts)
			assert.are.same({ refresh_token = "other-refresh" }, vim.json.decode(posts[1].opts.body))

			respond(200, { access_token = "new-access", refresh_token = "new-refresh", expires_in_ms = 300000 })
			assert.are.equal("new-access", client.client.access_token)
			assert.are.equal("new-refresh", client.client.refresh_token)
			assert.is_true(error_mod.is_ok(callback_spy.calls[1].refs[1]))
		end)

		it("re-reads the session file only once", function()
			login()
			save_session_from_other_instance({ expires_at = os.time() - 5 })
			local callback_spy = spy.new(function() end)

			token.refresh(callback_spy)
			respond(400, rejected)
			respond(400, rejected)

			assert.spy(storage_mock.read_saved_session).was_called(1)
			assert.is_true(callback_spy.calls[1].refs[1].error.session_expired)
		end)

		it("ends the session when the saved refresh token is the one that was rejected", function()
			login()
			save_session_from_other_instance({ refresh_token = "old-refresh" })
			local callback_spy = spy.new(function() end)

			token.refresh(callback_spy)
			respond(400, rejected)

			assert.are.equal(0, #posts)
			assert.is_true(callback_spy.calls[1].refs[1].error.session_expired)
		end)

		it("ends the session when there is no saved session", function()
			login()
			local callback_spy = spy.new(function() end)

			token.refresh(callback_spy)
			respond(400, rejected)

			assert.is_true(callback_spy.calls[1].refs[1].error.session_expired)
		end)

		it("does not take the credentials of another account", function()
			login()
			save_session_from_other_instance({ user_id = "@bob:example.org" })
			local callback_spy = spy.new(function() end)

			token.refresh(callback_spy)
			respond(400, rejected)

			assert.are.equal("old-access", client.client.access_token)
			assert.is_true(callback_spy.calls[1].refs[1].error.session_expired)
		end)

		it("does not read the session file after a transient failure", function()
			login()
			save_session_from_other_instance()

			token.refresh(function() end)
			respond(503, { errcode = "M_UNKNOWN", error = "Try again later" })

			assert.spy(storage_mock.read_saved_session).was_not_called()
			assert.are.equal("old-access", client.client.access_token)
		end)
	end)
end)
