require("neoment.matrix.api")
local error_mod = require("neoment.error")

describe("Matrix API", function()
	local curl_mock

	before_each(function()
		-- Mock the curl module
		curl_mock = {}
		package.loaded["neoment.curl"] = curl_mock
		-- Reload api module to get the mocked curl
		package.loaded["neoment.matrix.api"] = nil
	end)

	after_each(function()
		-- Restore original modules
		package.loaded["neoment.curl"] = nil
		package.loaded["neoment.matrix.api"] = nil
	end)

	describe("get", function()
		it("should make a successful GET request", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local test_response = { flows = { { type = "m.login.password" } } }
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(endpoint, opts)
				assert.are.equal(test_endpoint, endpoint)
				assert.are.equal("application/json", opts.headers["Content-Type"])

				-- Simulate successful response
				opts.callback({
					status = 200,
					body = vim.json.encode(test_response),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get(test_endpoint, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			assert.are.same(test_response, result.data)
		end)

		it("should pass raw curl arguments through", function()
			local received_raw

			curl_mock.get = function(_, opts)
				received_raw = opts.raw
				opts.callback({ status = 200, body = "{}" })
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get("https://example.org/.well-known/matrix/client", function() end, { raw = { "-L" } })

			assert.are.same({ "-L" }, received_raw)
		end)

		it("should expose the HTTP status and errcode of an error response", function()
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(_, opts)
				opts.callback({
					status = 401,
					body = vim.json.encode({ errcode = "M_UNKNOWN_TOKEN", error = "Expired", soft_logout = true }),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get("https://matrix.org/_matrix/client/v3/sync", callback_spy)

			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.are.equal(401, result.error.status)
			assert.are.equal("M_UNKNOWN_TOKEN", result.error.errcode)
			assert.is_true(result.error.soft_logout)
		end)

		it("should expose the HTTP status when the body is not JSON", function()
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(_, opts)
				opts.callback({ status = 502, body = "<html>Bad gateway</html>" })
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get("https://matrix.org/_matrix/client/v3/sync", callback_spy)

			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.are.equal(502, result.error.status)
		end)

		it("should handle Matrix API error responses", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local error_response = { error = "Invalid token", errcode = "M_UNKNOWN_TOKEN" }
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(endpoint, opts)
				opts.callback({
					status = 401,
					body = vim.json.encode(error_response),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get(test_endpoint, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.are.equal("Invalid token", result.error.error)
			assert.are.equal("M_UNKNOWN_TOKEN", result.error.errcode)
		end)

		it("should handle invalid JSON responses", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(endpoint, opts)
				opts.callback({
					status = 200,
					body = "not valid json",
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get(test_endpoint, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.is_not_nil(string.match(result.error.error, "Failed to decode JSON response"))
		end)

		it("should accept a top-level JSON array", function()
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(_, opts)
				opts.callback({ status = 200, body = '[{"type":"m.room.name"}]' })
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get("https://matrix.org/_matrix/client/v3/rooms/!r/state", callback_spy)

			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			assert.are.equal("m.room.name", result.data[1].type)
		end)

		it("should return an error when the JSON body is not an object", function()
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(_, opts)
				opts.callback({ status = 200, body = "null" })
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get("https://matrix.org/.well-known/matrix/client", callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.matches("Unexpected JSON response", result.error.error, 1, true)
		end)

		it("should handle curl errors", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(endpoint, opts)
				opts.on_error({ message = "Connection refused" })
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get(test_endpoint, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.are.equal("Failed to make GET request", result.error.error)
		end)

		it("should merge custom headers", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local custom_headers = { Authorization = "Bearer token123" }
			local callback_spy = spy.new(function() end)

			curl_mock.get = function(endpoint, opts)
				assert.are.equal("Bearer token123", opts.headers.Authorization)
				assert.are.equal("application/json", opts.headers["Content-Type"])

				opts.callback({
					status = 200,
					body = vim.json.encode({ success = true }),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.get(test_endpoint, callback_spy, { headers = custom_headers })

			assert.spy(callback_spy).was_called()
		end)
	end)

	describe("get_sync", function()
		it("should make a successful synchronous GET request", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local test_response = { flows = { { type = "m.login.password" } } }

			curl_mock.get = function(endpoint, opts)
				assert.are.equal(test_endpoint, endpoint)
				return {
					status = 200,
					body = vim.json.encode(test_response),
					exit = 0,
				}
			end

			local api_reloaded = require("neoment.matrix.api")
			local result = api_reloaded.get_sync(test_endpoint)

			assert.is_true(error_mod.is_ok(result))
			assert.are.same(test_response, result.data)
		end)

		it("should handle curl errors in sync mode", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"

			curl_mock.get = function(endpoint, opts)
				opts.on_error({ message = "Connection timeout" })
			end

			local api_reloaded = require("neoment.matrix.api")
			local result = api_reloaded.get_sync(test_endpoint)

			assert.is_true(error_mod.is_error(result))
			assert.are.equal("Failed to make GET request", result.error.error)
		end)

		it("should handle pcall failures", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"

			curl_mock.get = function()
				error("Network error")
			end

			local api_reloaded = require("neoment.matrix.api")
			local result = api_reloaded.get_sync(test_endpoint)

			assert.is_true(error_mod.is_error(result))
			assert.are.equal("Failed to make GET request", result.error.error)
		end)
	end)

	describe("post", function()
		it("should make a successful POST request with body", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local test_body = { type = "m.login.password", user = "test", password = "secret" }
			local test_response = { access_token = "token123", user_id = "@test:matrix.org" }
			local callback_spy = spy.new(function() end)

			curl_mock.post = function(endpoint, opts)
				assert.are.equal(test_endpoint, endpoint)
				assert.are.equal(vim.json.encode(test_body), opts.body)
				assert.are.equal("application/json", opts.headers["Content-Type"])

				opts.callback({
					status = 200,
					body = vim.json.encode(test_response),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.post(test_endpoint, test_body, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			assert.are.same(test_response, result.data)
		end)

		it("should handle POST request without body", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local test_response = { success = true }
			local callback_spy = spy.new(function() end)

			curl_mock.post = function(endpoint, opts)
				assert.is_nil(opts.body)

				opts.callback({
					status = 200,
					body = vim.json.encode(test_response),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.post(test_endpoint, nil, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
		end)

		it("should handle POST errors", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local callback_spy = spy.new(function() end)

			curl_mock.post = function(endpoint, opts)
				opts.on_error({ message = "Connection refused" })
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.post(test_endpoint, {}, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.are.equal("Failed to make POST request", result.error.error)
		end)
	end)

	describe("post_raw", function()
		it("should make a POST request with raw body", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/login"
			local raw_body = '{"custom":"json"}'
			local test_response = { success = true }
			local callback_spy = spy.new(function() end)

			curl_mock.post = function(endpoint, opts)
				assert.are.equal(test_endpoint, endpoint)
				assert.are.equal(raw_body, opts.body)

				opts.callback({
					status = 200,
					body = vim.json.encode(test_response),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.post_raw(test_endpoint, raw_body, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
		end)
	end)

	describe("put", function()
		it("should make a successful PUT request", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/rooms/!room:matrix.org/state/m.room.name"
			local test_body = { name = "New Room Name" }
			local test_response = { event_id = "$event123" }
			local callback_spy = spy.new(function() end)

			curl_mock.put = function(endpoint, opts)
				assert.are.equal(test_endpoint, endpoint)
				assert.are.equal(vim.json.encode(test_body), opts.body)
				assert.are.equal("application/json", opts.headers["Content-Type"])

				opts.callback({
					status = 200,
					body = vim.json.encode(test_response),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.put(test_endpoint, test_body, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			assert.are.same(test_response, result.data)
		end)

		it("should handle PUT request without body", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/rooms/!room:matrix.org/state/m.room.name"
			local test_response = { event_id = "$event123" }
			local callback_spy = spy.new(function() end)

			curl_mock.put = function(endpoint, opts)
				assert.is_nil(opts.body)

				opts.callback({
					status = 200,
					body = vim.json.encode(test_response),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.put(test_endpoint, nil, callback_spy)

			assert.spy(callback_spy).was_called()
		end)

		it("should handle PUT errors", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/rooms/!room:matrix.org/state/m.room.name"
			local callback_spy = spy.new(function() end)

			curl_mock.put = function(endpoint, opts)
				opts.on_error({ message = "Connection refused" })
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.put(test_endpoint, {}, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.are.equal("Failed to make PUT request", result.error.error)
		end)
	end)

	describe("delete", function()
		it("should make a successful DELETE request", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/rooms/!room:matrix.org/redact/$event"
			local test_response = { event_id = "$redact123" }
			local callback_spy = spy.new(function() end)

			curl_mock.delete = function(endpoint, opts)
				assert.are.equal(test_endpoint, endpoint)
				assert.are.equal("application/json", opts.headers["Content-Type"])

				opts.callback({
					status = 200,
					body = vim.json.encode(test_response),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.delete(test_endpoint, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			assert.are.same(test_response, result.data)
		end)

		it("should handle DELETE errors", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/rooms/!room:matrix.org/redact/$event"
			local callback_spy = spy.new(function() end)

			curl_mock.delete = function(endpoint, opts)
				opts.on_error({ message = "Connection refused" })
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.delete(test_endpoint, callback_spy)

			assert.spy(callback_spy).was_called()
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.are.equal("Failed to make DELETE request", result.error.error)
		end)

		it("should merge custom headers for DELETE", function()
			local test_endpoint = "https://matrix.org/_matrix/client/r0/rooms/!room:matrix.org/redact/$event"
			local custom_headers = { Authorization = "Bearer token123" }
			local callback_spy = spy.new(function() end)

			curl_mock.delete = function(endpoint, opts)
				assert.are.equal("Bearer token123", opts.headers.Authorization)
				assert.are.equal("application/json", opts.headers["Content-Type"])

				opts.callback({
					status = 200,
					body = vim.json.encode({ success = true }),
				})
			end

			local api_reloaded = require("neoment.matrix.api")
			api_reloaded.delete(test_endpoint, callback_spy, { headers = custom_headers })

			assert.spy(callback_spy).was_called()
		end)
	end)

	describe("authed", function()
		local api
		local client
		local storage_mock
		--- Requests waiting for an answer, in the order they were sent
		local sent

		--- Answer the oldest request that is waiting
		--- @param status integer
		--- @param body table
		local function respond(status, body)
			local request = table.remove(sent, 1)
			request.opts.callback({ status = status, body = vim.json.encode(body), exit = 0 })
		end

		--- Requests sent to the refresh endpoint are answered right away
		--- @param status integer
		--- @param body table
		local function answer_refreshes_with(status, body)
			curl_mock.post = function(endpoint, opts)
				table.insert(sent, { method = "POST", endpoint = endpoint, opts = opts })
				if endpoint:match("/refresh$") then
					respond(status, body)
				end
			end
		end

		before_each(function()
			sent = {}
			storage_mock = {
				save_session = function() end,
				read_saved_session = function()
					return nil
				end,
			}
			package.loaded["neoment.storage"] = storage_mock
			package.loaded["neoment.matrix.client"] = nil
			package.loaded["neoment.matrix.token"] = nil

			for _, method in ipairs({ "get", "put", "delete" }) do
				curl_mock[method] = function(endpoint, opts)
					table.insert(sent, { method = method:upper(), endpoint = endpoint, opts = opts })
				end
			end
			curl_mock.post = function(endpoint, opts)
				table.insert(sent, { method = "POST", endpoint = endpoint, opts = opts })
			end

			client = require("neoment.matrix.client")
			client.new("https://matrix.example.org", "old-access")
			api = require("neoment.matrix.api")
		end)

		after_each(function()
			package.loaded["neoment.storage"] = nil
			package.loaded["neoment.matrix.client"] = nil
			package.loaded["neoment.matrix.token"] = nil
		end)

		--- Make the session one that expires and can be refreshed
		--- @param expires_in integer Seconds until the access token expires.
		local function make_expiring(expires_in)
			client.client.refresh_token = "old-refresh"
			client.client.expires_at = os.time() + expires_in
		end

		it("sets the Authorization header from the current token and keeps the other headers", function()
			api.authed.get("https://matrix.example.org/_matrix/client/v3/joined_rooms", function() end, {
				headers = { ["X-Custom"] = "1" },
			})

			assert.are.equal(1, #sent)
			assert.are.equal("Bearer old-access", sent[1].opts.headers["Authorization"])
			assert.are.equal("1", sent[1].opts.headers["X-Custom"])
			assert.are.equal("application/json", sent[1].opts.headers["Content-Type"])
		end)

		it("does not change the options passed by the caller", function()
			local opts = { headers = { ["X-Custom"] = "1" } }

			api.authed.get("https://matrix.example.org/x", function() end, opts)

			assert.are.same({ headers = { ["X-Custom"] = "1" } }, opts)
		end)

		it("sets the Authorization header on every request method", function()
			local noop = function() end
			api.authed.post("https://matrix.example.org/post", { a = 1 }, noop)
			api.authed.post_raw("https://matrix.example.org/post_raw", "raw", noop, {
				headers = { ["Content-Type"] = "image/png" },
			})
			api.authed.put("https://matrix.example.org/put", { a = 1 }, noop)
			api.authed.delete("https://matrix.example.org/delete", noop)

			assert.are.equal(4, #sent)
			for _, request in ipairs(sent) do
				assert.are.equal("Bearer old-access", request.opts.headers["Authorization"])
			end
			assert.are.equal("image/png", sent[2].opts.headers["Content-Type"])
		end)

		it("refreshes an expiring token before sending the request", function()
			make_expiring(30)
			answer_refreshes_with(
				200,
				{ access_token = "new-access", refresh_token = "new-refresh", expires_in_ms = 300000 }
			)
			local callback_spy = spy.new(function() end)

			api.authed.get("https://matrix.example.org/_matrix/client/v3/joined_rooms", callback_spy)

			-- The refresh request was answered, so only the GET is waiting
			assert.are.equal(1, #sent)
			assert.are.equal("GET", sent[1].method)
			assert.are.equal("Bearer new-access", sent[1].opts.headers["Authorization"])
			assert.are.equal("new-access", client.client.access_token)

			respond(200, { joined_rooms = {} })
			assert.spy(callback_spy).was_called(1)
			assert.is_true(error_mod.is_ok(callback_spy.calls[1].refs[1]))
		end)

		it("refreshes after a soft logout response and retries the request once", function()
			make_expiring(600)
			answer_refreshes_with(
				200,
				{ access_token = "new-access", refresh_token = "new-refresh", expires_in_ms = 300000 }
			)
			local callback_spy = spy.new(function() end)

			api.authed.get("https://matrix.example.org/_matrix/client/v3/sync", callback_spy)
			assert.are.equal("Bearer old-access", sent[1].opts.headers["Authorization"])

			respond(401, { errcode = "M_UNKNOWN_TOKEN", error = "Expired", soft_logout = true })

			-- The retry carries the new token and the same URL
			assert.are.equal(1, #sent)
			assert.are.equal("GET", sent[1].method)
			assert.are.equal("https://matrix.example.org/_matrix/client/v3/sync", sent[1].endpoint)
			assert.are.equal("Bearer new-access", sent[1].opts.headers["Authorization"])
			assert.spy(callback_spy).was_not_called()

			respond(200, { next_batch = "s2" })
			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			assert.are.equal("s2", result.data.next_batch)
		end)

		it("does not retry a second 401", function()
			make_expiring(600)
			answer_refreshes_with(200, { access_token = "new-access", expires_in_ms = 300000 })
			local callback_spy = spy.new(function() end)
			local expired = { errcode = "M_UNKNOWN_TOKEN", error = "Expired", soft_logout = true }

			api.authed.get("https://matrix.example.org/x", callback_spy)
			respond(401, expired)
			respond(401, expired)

			assert.are.equal(0, #sent)
			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.are.equal(401, result.error.status)
		end)

		it("does not refresh after a hard logout response and reports an expired session", function()
			make_expiring(600)
			answer_refreshes_with(200, { access_token = "new-access", expires_in_ms = 300000 })
			local handler_spy = spy.new(function() end)
			api.set_session_expired_handler(handler_spy)
			local callback_spy = spy.new(function() end)

			api.authed.get("https://matrix.example.org/x", callback_spy)
			respond(401, { errcode = "M_UNKNOWN_TOKEN", error = "Unknown token", soft_logout = false })

			assert.are.equal(0, #sent)
			assert.are.equal("old-access", client.client.access_token)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.is_true(result.error.session_expired)

			vim.wait(10)
			assert.spy(handler_spy).was_called(1)
		end)

		it("reports an expired session when there is no refresh token to use", function()
			local callback_spy = spy.new(function() end)

			api.authed.get("https://matrix.example.org/x", callback_spy)
			respond(401, { errcode = "M_UNKNOWN_TOKEN", error = "Expired", soft_logout = true })

			assert.are.equal(0, #sent)
			assert.is_true(callback_spy.calls[1].refs[1].error.session_expired)
		end)

		it("reports an expired session and tells the handler when the refresh is rejected", function()
			make_expiring(600)
			answer_refreshes_with(400, { errcode = "M_UNKNOWN_TOKEN", error = "Invalid refresh token" })
			local handler_spy = spy.new(function() end)
			api.set_session_expired_handler(handler_spy)
			local callback_spy = spy.new(function() end)

			api.authed.get("https://matrix.example.org/x", callback_spy)
			respond(401, { errcode = "M_UNKNOWN_TOKEN", error = "Expired", soft_logout = true })

			assert.are.equal(0, #sent)
			assert.spy(callback_spy).was_called(1)
			assert.is_true(callback_spy.calls[1].refs[1].error.session_expired)
			vim.wait(10)
			assert.spy(handler_spy).was_called(1)
		end)

		it("leaves the handler alone for errors that do not end the session", function()
			make_expiring(600)
			local handler_spy = spy.new(function() end)
			api.set_session_expired_handler(handler_spy)

			api.authed.get("https://matrix.example.org/x", function() end)
			respond(403, { errcode = "M_FORBIDDEN", error = "Forbidden" })

			vim.wait(10)
			assert.spy(handler_spy).was_not_called()
		end)

		it("sends one refresh when several requests find the token expired", function()
			make_expiring(600)
			local callback_spy = spy.new(function() end)
			local expired = { errcode = "M_UNKNOWN_TOKEN", error = "Expired", soft_logout = true }

			api.authed.get("https://matrix.example.org/a", callback_spy)
			api.authed.get("https://matrix.example.org/b", callback_spy)
			assert.are.equal(2, #sent)

			-- Both were sent with the old token, and both come back expired
			respond(401, expired)
			assert.are.equal(2, #sent)
			assert.are.equal("POST", sent[2].method)
			respond(401, expired)
			assert.are.equal(1, #vim.tbl_filter(function(request)
				return request.method == "POST"
			end, sent))

			-- The refresh answers, then both requests are sent again with the new token
			local refresh_request = table.remove(sent, 1)
			refresh_request.opts.callback({
				status = 200,
				body = vim.json.encode({ access_token = "new-access", expires_in_ms = 300000 }),
			})
			assert.are.equal(2, #sent)
			for _, request in ipairs(sent) do
				assert.are.equal("Bearer new-access", request.opts.headers["Authorization"])
			end

			respond(200, {})
			respond(200, {})
			assert.spy(callback_spy).was_called(2)
		end)

		it("fails with an error when not logged in", function()
			package.loaded["neoment.matrix.client"].client = nil
			local callback_spy = spy.new(function() end)

			api.authed.get("https://matrix.example.org/x", callback_spy)

			assert.are.equal(0, #sent)
			assert.is_true(error_mod.is_error(callback_spy.calls[1].refs[1]))
		end)

		describe("get_sync", function()
			it("sets the Authorization header from the current token", function()
				local received_headers
				curl_mock.get = function(_, opts)
					received_headers = opts.headers
					return { status = 200, body = vim.json.encode({ displayname = "Alice" }) }
				end

				local result = api.authed.get_sync("https://matrix.example.org/_matrix/client/v3/rooms/!r/event/$e")

				assert.is_true(error_mod.is_ok(result))
				assert.are.equal("Bearer old-access", received_headers["Authorization"])
			end)

			it("does not refresh an expiring token", function()
				make_expiring(30)
				curl_mock.get = function()
					return { status = 200, body = "{}" }
				end

				api.authed.get_sync("https://matrix.example.org/x")

				assert.are.equal(0, #sent)
			end)

			it("reports an expired session after a hard logout response", function()
				local handler_spy = spy.new(function() end)
				api.set_session_expired_handler(handler_spy)
				curl_mock.get = function()
					return {
						status = 401,
						body = vim.json.encode({ errcode = "M_UNKNOWN_TOKEN", error = "Unknown token" }),
					}
				end

				local result = api.authed.get_sync("https://matrix.example.org/x")

				assert.is_true(error_mod.is_error(result))
				assert.is_true(result.error.session_expired)
				vim.wait(10)
				assert.spy(handler_spy).was_called(1)
			end)
		end)
	end)
end)
