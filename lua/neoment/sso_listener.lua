local M = {}

local error = require("neoment.error")

--- Maximum size of the request head we accept from the browser.
local MAX_REQUEST_SIZE = 8192

local SUCCESS_BODY = [[<!doctype html>
<html><head><meta charset="utf-8"><title>Neoment</title></head>
<body><p>Login complete. You can close this tab and return to Neovim.</p></body></html>]]

local FAILURE_BODY = [[<!doctype html>
<html><head><meta charset="utf-8"><title>Neoment</title></head>
<body><p>This request did not contain a login token.</p></body></html>]]

--- @class neoment.sso_listener.Options
--- @field on_token fun(token: string): any Called (scheduled) with the login token received from the browser.
--- @field on_timeout? fun(): any Called (scheduled) when no token arrives before the timeout.
--- @field timeout_ms? integer Time to wait for the browser, in milliseconds (default: 120000).

--- @class neoment.sso_listener.Listener
--- @field port integer The port the listener is bound to.
--- @field close fun() Stop listening. Safe to call more than once.

--- Build an HTTP response.
--- @param status string The status line suffix (e.g. "200 OK").
--- @param body string The HTML body.
--- @return string The raw HTTP response.
local function http_response(status, body)
	return table.concat({
		"HTTP/1.1 " .. status,
		"Content-Type: text/html; charset=utf-8",
		"Content-Length: " .. #body,
		"Connection: close",
		"",
		body,
	}, "\r\n")
end

--- Extract the login token from the request line of an HTTP request.
--- @param request string The raw request head.
--- @return string|nil The login token, if present.
local function parse_request(request)
	local target = request:match("^GET (%S+) HTTP/%d")
	if not target then
		return nil
	end

	local token = target:match("[?&]loginToken=([^&#]+)")
	if not token then
		return nil
	end

	return vim.uri_decode(token)
end

--- Start a loopback HTTP listener that waits for the SSO redirect with the login token.
--- @param opts neoment.sso_listener.Options
--- @return neoment.Error<neoment.sso_listener.Listener, string>
M.start = function(opts)
	local server = vim.uv.new_tcp()
	local timer = vim.uv.new_timer()
	if not server or not timer then
		return error.err("Could not create the SSO callback listener")
	end

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		timer:stop()
		timer:close()
		server:close()
	end

	local _, bind_err = server:bind("127.0.0.1", 0)
	if bind_err then
		close()
		return error.err("Could not bind the SSO callback listener: " .. bind_err)
	end

	local _, listen_err = server:listen(16, function(err)
		if err or closed then
			return
		end

		local socket = vim.uv.new_tcp()
		if not socket then
			return
		end
		server:accept(socket)

		local request = ""
		local function respond(status, body)
			socket:read_stop()
			socket:write(http_response(status, body), function()
				socket:shutdown(function()
					socket:close()
				end)
			end)
		end

		socket:read_start(function(read_err, chunk)
			if read_err or not chunk then
				socket:close()
				return
			end

			request = request .. chunk
			if not request:find("\r\n\r\n", 1, true) then
				if #request > MAX_REQUEST_SIZE then
					respond("400 Bad Request", FAILURE_BODY)
				end
				return
			end

			local token = parse_request(request)
			if not token or closed then
				respond("400 Bad Request", FAILURE_BODY)
				return
			end

			respond("200 OK", SUCCESS_BODY)
			close()
			vim.schedule(function()
				opts.on_token(token)
			end)
		end)
	end)
	if listen_err then
		close()
		return error.err("Could not start the SSO callback listener: " .. listen_err)
	end

	timer:start(opts.timeout_ms or 120000, 0, function()
		if closed then
			return
		end
		close()
		if opts.on_timeout then
			vim.schedule(opts.on_timeout)
		end
	end)

	return error.ok({
		port = server:getsockname().port,
		close = close,
	})
end

return M
