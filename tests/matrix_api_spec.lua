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
end)
