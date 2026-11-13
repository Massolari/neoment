local error_mod = require("neoment.error")
local sso_listener = require("neoment.sso_listener")

describe("SSO listener", function()
	local listener

	after_each(function()
		if listener then
			listener.close()
			listener = nil
		end
	end)

	--- Send a raw HTTP request to the listener and collect the response.
	--- @param port integer
	--- @param request string
	--- @return table state A table whose `response` field is filled once the server closes the connection.
	local function send(port, request)
		local state = { response = "", done = false }
		local socket = vim.uv.new_tcp()
		socket:connect("127.0.0.1", port, function(err)
			assert(not err, err)
			socket:write(request)
			socket:read_start(function(_, chunk)
				if chunk then
					state.response = state.response .. chunk
				else
					state.done = true
					socket:close()
				end
			end)
		end)
		return state
	end

	--- Start a listener and fail the test if it could not start.
	local function start(opts)
		local result = sso_listener.start(opts)
		assert.is_true(error_mod.is_ok(result))
		listener = result.data
		return listener
	end

	it("should bind to a port and deliver the login token", function()
		local received
		local l = start({
			on_token = function(token)
				received = token
			end,
		})

		assert.is_true(l.port > 0)

		local state = send(l.port, "GET /?loginToken=abc%2B1 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")

		assert.is_true(vim.wait(2000, function()
			return received ~= nil and state.done
		end))
		assert.are.equal("abc+1", received)
		assert.matches("^HTTP/1.1 200 OK", state.response)
		assert.matches("You can close this tab", state.response, 1, true)
	end)

	it("should reject requests without a token and keep listening", function()
		local received
		local l = start({
			on_token = function(token)
				received = token
			end,
		})

		local favicon = send(l.port, "GET /favicon.ico HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
		assert.is_true(vim.wait(2000, function()
			return favicon.done
		end))
		assert.matches("^HTTP/1.1 400", favicon.response)
		assert.is_nil(received)

		local callback = send(l.port, "GET /?loginToken=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
		assert.is_true(vim.wait(2000, function()
			return received ~= nil and callback.done
		end))
		assert.are.equal("xyz", received)
	end)

	it("should call on_timeout when no token arrives", function()
		local timed_out = false
		start({
			on_token = function() end,
			on_timeout = function()
				timed_out = true
			end,
			timeout_ms = 50,
		})

		assert.is_true(vim.wait(2000, function()
			return timed_out
		end))
	end)

	it("should allow close to be called more than once", function()
		local l = start({ on_token = function() end })

		assert.has_no.errors(function()
			l.close()
			l.close()
		end)
	end)

	it("should not call on_timeout after being closed", function()
		local timed_out = false
		local l = start({
			on_token = function() end,
			on_timeout = function()
				timed_out = true
			end,
			timeout_ms = 50,
		})
		l.close()

		vim.wait(200)
		assert.is_false(timed_out)
	end)
end)
