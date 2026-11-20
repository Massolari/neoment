local error_mod = require("neoment.error")

describe("Matrix OAuth", function()
	local METADATA = {
		issuer = "https://auth.example.org/",
		device_authorization_endpoint = "https://auth.example.org/oauth2/device",
		token_endpoint = "https://auth.example.org/oauth2/token",
		registration_endpoint = "https://auth.example.org/oauth2/registration",
		revocation_endpoint = "https://auth.example.org/oauth2/revoke",
	}

	local oauth
	--- The requests sent, oldest first
	local posts
	--- The client IDs held by the storage mock, mapped by issuer
	local saved_clients

	--- Answer the oldest request that is still waiting
	--- @param status integer
	--- @param body table|string
	local function respond(status, body)
		local request = table.remove(posts, 1)
		request.opts.callback({
			status = status,
			body = type(body) == "string" and body or vim.json.encode(body),
			exit = 0,
		})
	end

	--- Make the oldest request that is still waiting fail like a network error
	local function fail_to_connect()
		local request = table.remove(posts, 1)
		request.opts.on_error({ message = "connection failed" })
	end

	--- Decode an `application/x-www-form-urlencoded` body
	--- @param body string
	--- @return table<string, string>
	local function parse_form(body)
		local fields = {}
		for pair in body:gmatch("[^&]+") do
			local key, value = pair:match("^([^=]*)=(.*)$")
			fields[vim.uri_decode(key)] = vim.uri_decode(value)
		end
		return fields
	end

	before_each(function()
		posts = {}
		saved_clients = {}
		package.loaded["neoment.curl"] = {
			post = function(endpoint, opts)
				table.insert(posts, { endpoint = endpoint, opts = opts })
			end,
		}
		package.loaded["neoment.storage"] = {
			get_oauth_client_id = function(issuer)
				return saved_clients[issuer]
			end,
			set_oauth_client_id = function(issuer, client_id)
				saved_clients[issuer] = client_id
				return true
			end,
			clear_oauth_client_id = function(issuer)
				saved_clients[issuer] = nil
				return true
			end,
		}
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.oauth"] = nil

		oauth = require("neoment.matrix.oauth")
	end)

	after_each(function()
		package.loaded["neoment.curl"] = nil
		package.loaded["neoment.storage"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.oauth"] = nil
	end)

	describe("register_client", function()
		it("registers on the first login and saves the client id for the issuer", function()
			local result
			oauth.register_client(METADATA, function(r)
				result = r
			end)

			assert.are.equal(1, #posts)
			assert.are.equal(METADATA.registration_endpoint, posts[1].endpoint)
			assert.are.equal("application/json", posts[1].opts.headers["Content-Type"])
			assert.are.same({
				client_name = "Neoment",
				client_uri = "https://github.com/Massolari/neoment",
				grant_types = { "urn:ietf:params:oauth:grant-type:device_code", "refresh_token" },
				token_endpoint_auth_method = "none",
				application_type = "native",
			}, vim.json.decode(posts[1].opts.body))

			respond(201, { client_id = "client-1" })

			assert.is_true(error_mod.is_ok(result))
			assert.are.equal("client-1", result.data)
			assert.are.equal("client-1", saved_clients[METADATA.issuer])
		end)

		it("sends no request when a client id is saved for the issuer", function()
			saved_clients[METADATA.issuer] = "client-1"

			local result
			oauth.register_client(METADATA, function(r)
				result = r
			end)

			assert.are.equal(0, #posts)
			assert.are.equal("client-1", result.data)
		end)

		it("registers again on a different issuer and keeps the other client id", function()
			saved_clients["https://other.example.org/"] = "client-other"

			oauth.register_client(METADATA, function() end)
			respond(201, { client_id = "client-1" })

			assert.are.equal("client-1", saved_clients[METADATA.issuer])
			assert.are.equal("client-other", saved_clients["https://other.example.org/"])
		end)

		it("reports the message of the server when the registration fails", function()
			local result
			oauth.register_client(METADATA, function(r)
				result = r
			end)
			respond(400, { error = "invalid_client_metadata", error_description = "Unsupported grant type" })

			assert.is_true(error_mod.is_error(result))
			assert.matches("Unsupported grant type", result.error.error, 1, true)
			assert.is_nil(saved_clients[METADATA.issuer])
		end)

		it("reports an error when the response has no client id", function()
			local result
			oauth.register_client(METADATA, function(r)
				result = r
			end)
			respond(201, { client_id_issued_at = 1 })

			assert.is_true(error_mod.is_error(result))
			assert.is_nil(saved_clients[METADATA.issuer])
		end)

		it("reports an error when the request cannot be made", function()
			local result
			oauth.register_client(METADATA, function(r)
				result = r
			end)
			fail_to_connect()

			assert.is_true(error_mod.is_error(result))
		end)
	end)

	describe("request_device_code", function()
		local function request(callback)
			oauth.request_device_code(METADATA, "client-1", "MYDEVICE", callback)
		end

		it("sends the client id and the API and device scopes as a form", function()
			request(function() end)

			assert.are.equal(METADATA.device_authorization_endpoint, posts[1].endpoint)
			assert.are.equal("application/x-www-form-urlencoded", posts[1].opts.headers["Content-Type"])
			assert.are.same({
				client_id = "client-1",
				scope = "urn:matrix:client:api:* urn:matrix:client:device:MYDEVICE",
			}, parse_form(posts[1].opts.body))
		end)

		it("uses the complete verification URL when the server gives one", function()
			local result
			request(function(r)
				result = r
			end)
			respond(200, {
				device_code = "DEV",
				user_code = "ABCD-EFGH",
				verification_uri = "https://auth.example.org/link",
				verification_uri_complete = "https://auth.example.org/link?code=ABCD-EFGH",
				expires_in = 900,
				interval = 7,
			})

			assert.are.same({
				device_code = "DEV",
				user_code = "ABCD-EFGH",
				verification_url = "https://auth.example.org/link?code=ABCD-EFGH",
				code_in_url = true,
				expires_in = 900,
				interval = 7,
			}, result.data)
		end)

		it("falls back to the base verification URL and the default interval", function()
			local result
			request(function(r)
				result = r
			end)
			respond(200, {
				device_code = "DEV",
				user_code = "ABCD-EFGH",
				verification_uri = "https://auth.example.org/link",
				expires_in = 900,
			})

			assert.are.equal("https://auth.example.org/link", result.data.verification_url)
			assert.is_false(result.data.code_in_url)
			assert.are.equal(5, result.data.interval)
		end)

		it("forgets the saved client id when the server rejects the client", function()
			saved_clients[METADATA.issuer] = "client-1"
			saved_clients["https://other.example.org/"] = "client-other"

			local result
			request(function(r)
				result = r
			end)
			respond(401, { error = "invalid_client", error_description = "Client not found" })

			assert.is_true(error_mod.is_error(result))
			assert.matches("Client not found", result.error.error, 1, true)
			assert.is_nil(saved_clients[METADATA.issuer])
			assert.are.equal("client-other", saved_clients["https://other.example.org/"])
		end)

		it("keeps the client id on other errors", function()
			saved_clients[METADATA.issuer] = "client-1"

			local result
			request(function(r)
				result = r
			end)
			respond(400, { error = "invalid_scope", error_description = "Bad scope" })

			assert.is_true(error_mod.is_error(result))
			assert.are.equal("client-1", saved_clients[METADATA.issuer])
		end)

		it("reports an incomplete response", function()
			local result
			request(function(r)
				result = r
			end)
			respond(200, { device_code = "DEV" })

			assert.is_true(error_mod.is_error(result))
		end)
	end)

	describe("poll", function()
		local DEVICE = { device_code = "DEV", user_code = "ABCD", interval = 5, expires_in = 600 }

		local clock
		--- The delays asked for, oldest first
		local timers
		local results
		local handle

		--- Run the oldest scheduled timer, moving the clock forward by its delay
		local function fire_timer()
			local timer = table.remove(timers, 1)
			clock = clock + timer.ms / 1000
			timer.fn()
		end

		--- @param device? table
		local function start(device)
			handle = oauth.poll({
				metadata = METADATA,
				client_id = "client-1",
				device_code = vim.tbl_extend("force", DEVICE, device or {}),
				now = function()
					return clock
				end,
				defer = function(fn, ms)
					table.insert(timers, { fn = fn, ms = ms })
				end,
			}, function(result)
				table.insert(results, result)
			end)
		end

		before_each(function()
			clock = 1000
			timers = {}
			results = {}
		end)

		it("waits for the interval before the first request", function()
			start()

			assert.are.equal(0, #posts)
			assert.are.equal(5000, timers[1].ms)
		end)

		it("sends the device code and client id to the token endpoint", function()
			start()
			fire_timer()

			assert.are.equal(METADATA.token_endpoint, posts[1].endpoint)
			assert.are.equal("application/x-www-form-urlencoded", posts[1].opts.headers["Content-Type"])
			assert.are.same({
				grant_type = "urn:ietf:params:oauth:grant-type:device_code",
				device_code = "DEV",
				client_id = "client-1",
			}, parse_form(posts[1].opts.body))
		end)

		it("keeps the interval while the authorization is pending", function()
			start()
			fire_timer()
			respond(400, { error = "authorization_pending" })

			assert.are.equal(5000, timers[1].ms)
			assert.are.equal(0, #results)

			fire_timer()
			respond(400, { error = "authorization_pending" })

			assert.are.equal(5000, timers[1].ms)
		end)

		it("adds 5 seconds to the interval when asked to slow down", function()
			start()
			fire_timer()
			respond(400, { error = "slow_down" })

			assert.are.equal(10000, timers[1].ms)

			fire_timer()
			respond(400, { error = "slow_down" })

			assert.are.equal(15000, timers[1].ms)
			assert.are.equal(0, #results)
		end)

		it("gives the token response once the user approves", function()
			start()
			fire_timer()
			respond(200, { access_token = "AT", refresh_token = "RT", expires_in = 300, token_type = "Bearer" })

			assert.are.equal(1, #results)
			assert.is_true(error_mod.is_ok(results[1]))
			assert.are.equal("AT", results[1].data.access_token)
			assert.are.equal(0, #timers)
		end)

		it("stops with an expiry error when the server says the code expired", function()
			start()
			fire_timer()
			respond(400, { error = "expired_token" })

			assert.are.equal(1, #results)
			assert.are.equal("expired_token", results[1].error.code)
			assert.matches("expired", results[1].error.error, 1, true)
			assert.are.equal(0, #timers)
		end)

		it("stops with an expiry error when expires_in passes without approval", function()
			start({ expires_in = 12 })
			fire_timer()
			respond(400, { error = "authorization_pending" })
			fire_timer()
			respond(400, { error = "authorization_pending" })
			-- 15 seconds passed, past the 12 of the code
			fire_timer()

			assert.are.equal(0, #posts)
			assert.are.equal(1, #results)
			assert.are.equal("expired_token", results[1].error.code)
			assert.are.equal(0, #timers)
		end)

		it("stops with a denial error when the user refuses", function()
			start()
			fire_timer()
			respond(400, { error = "access_denied" })

			assert.are.equal(1, #results)
			assert.are.equal("access_denied", results[1].error.code)
			assert.matches("denied", results[1].error.error, 1, true)
			assert.are.equal(0, #timers)
		end)

		it("keeps polling after a network error", function()
			start()
			fire_timer()
			fail_to_connect()

			assert.are.equal(0, #results)
			assert.are.equal(5000, timers[1].ms)
		end)

		it("keeps polling after a server error status", function()
			start()
			fire_timer()
			respond(502, "<html>Bad gateway</html>")

			assert.are.equal(0, #results)
			assert.are.equal(1, #timers)
		end)

		it("stops with the message of the server on any other error", function()
			start()
			fire_timer()
			respond(400, { error = "invalid_grant", error_description = "The device code is not valid" })

			assert.are.equal(1, #results)
			assert.is_true(error_mod.is_error(results[1]))
			assert.matches("The device code is not valid", results[1].error.error, 1, true)
		end)

		it("sends no more requests once cancelled", function()
			start()
			handle.cancel()
			fire_timer()

			assert.are.equal(0, #posts)
			assert.are.equal(0, #results)
		end)

		it("ignores the answer to a request in flight when cancelled", function()
			start()
			fire_timer()
			handle.cancel()
			respond(200, { access_token = "AT" })

			assert.are.equal(0, #results)
			assert.are.equal(0, #timers)
		end)

		it("never schedules the next request while one is in flight", function()
			start()
			fire_timer()

			assert.are.equal(1, #posts)
			assert.are.equal(0, #timers)

			respond(400, { error = "authorization_pending" })

			assert.are.equal(1, #timers)
		end)
	end)

	describe("revoke", function()
		it("sends the refresh token and client id as a form without credentials", function()
			oauth.revoke(METADATA.revocation_endpoint, "client-1", "RT", function() end)

			assert.are.equal(METADATA.revocation_endpoint, posts[1].endpoint)
			assert.are.equal("application/x-www-form-urlencoded", posts[1].opts.headers["Content-Type"])
			assert.is_nil(posts[1].opts.headers["Authorization"])
			assert.are.same({
				token = "RT",
				token_type_hint = "refresh_token",
				client_id = "client-1",
			}, parse_form(posts[1].opts.body))
		end)

		it("succeeds on a 200 answer with an empty body", function()
			local result
			oauth.revoke(METADATA.revocation_endpoint, "client-1", "RT", function(r)
				result = r
			end)
			respond(200, "")

			assert.is_true(error_mod.is_ok(result))
		end)

		it("succeeds on a 200 answer with an empty object", function()
			local result
			oauth.revoke(METADATA.revocation_endpoint, "client-1", "RT", function(r)
				result = r
			end)
			respond(200, {})

			assert.is_true(error_mod.is_ok(result))
		end)

		it("reports an error with the message of the server on a non-2xx answer", function()
			local result
			oauth.revoke(METADATA.revocation_endpoint, "client-1", "RT", function(r)
				result = r
			end)
			respond(400, { error = "invalid_request", error_description = "Missing token" })

			assert.is_true(error_mod.is_error(result))
			assert.matches("Missing token", result.error.error, 1, true)
		end)

		it("reports an error on a non-2xx answer that is not JSON", function()
			local result
			oauth.revoke(METADATA.revocation_endpoint, "client-1", "RT", function(r)
				result = r
			end)
			respond(503, "<html>Unavailable</html>")

			assert.is_true(error_mod.is_error(result))
			assert.matches("503", result.error.error, 1, true)
		end)

		it("reports an error when the request cannot be made", function()
			local result
			oauth.revoke(METADATA.revocation_endpoint, "client-1", "RT", function(r)
				result = r
			end)
			fail_to_connect()

			assert.is_true(error_mod.is_error(result))
		end)
	end)
end)
