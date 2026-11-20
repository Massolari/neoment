local M = {}

local curl = require("neoment.curl")
local json = vim.json
local error = require("neoment.error")
local client = require("neoment.matrix.client")
--- @alias neoment.matrix.api.ErrCode "M_FORBIDDEN" | "M_UNKNOWN_TOKEN" | "M_MISSING_TOKEN" | "M_USER_LOCKED" | "M_USER_SUSPENDED" | "M_BAD_JSON" | "M_NOT_JSON" | "M_NOT_FOUND" | "M_LIMIT_EXCEEDED" | "M_UNRECOGNIZED" | "M_UNKNOWN"

--- @class neoment.matrix.api.Error
--- @field error string The human-readable error message.
--- @field errcode neoment.matrix.api.ErrCode The error code.
--- @field status? integer The HTTP status of the response, when the server answered.
--- @field soft_logout? boolean Set on `M_UNKNOWN_TOKEN` when the access token expired but the device is still valid, so it can be refreshed.
--- @field stale? boolean Set when the response belongs to a session that ended while the request was in flight and must be discarded.
--- @field session_expired? boolean Set when the session can no longer be used and the user has to log in again.

--- @class neoment.matrix.api.RequestOptions
--- @field headers? table<string, string> A table of headers to include in the request.
--- @field raw? string[] Additional curl arguments (e.g. `{ "-L" }` to follow redirects).

--- Handle the response from a Matrix API request.
--- @generic A : table
--- @param response table The response from the API request.
local function handler(response)
	-- local data = json.decode(response.body)
	local ok, data = pcall(json.decode, response.body)
	if not ok then
		return error.err({ error = "Failed to decode JSON response: " .. response.body, status = response.status })
	end

	if type(data) ~= "table" then
		return error.err({ error = "Unexpected JSON response: " .. response.body, status = response.status })
	end

	if data.error then
		data.status = response.status
		return error.err(data)
	end

	return error.ok(data)
end

--- Make a GET request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.get = function(endpoint, callback, opts)
	opts = opts or {}
	curl.get(endpoint, {
		on_error = function(err)
			callback(error.err({ error = "Failed to make GET request", err = err }))
		end,
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
		raw = opts.raw,
		callback = function(response)
			callback(handler(response))
		end,
	})
end

--- Make a syncronous GET request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
--- @return neoment.Error<A, neoment.matrix.api.Error> The response body as a Lua table.
M.get_sync = function(endpoint, opts)
	opts = opts or {}

	local ok, response = pcall(curl.get, endpoint, {
		on_error = function(err)
			error(vim.inspect(err))
		end,
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
	})

	if not ok then
		return error.err({ error = "Failed to make GET request", err = response })
	end

	return handler(response)
end

--- Make a POST request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param body? table The request body to send.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.post = function(endpoint, body, callback, opts)
	opts = opts or {}
	opts.headers = vim.tbl_extend("force", {
		["Content-Type"] = "application/json",
	}, opts.headers or {})

	M.post_raw(endpoint, body and json.encode(body) or nil, callback, opts)
end

--- Make a POST request to the Matrix API without encoding the body.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param body? any The request body to send.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.post_raw = function(endpoint, body, callback, opts)
	opts = opts or {}
	curl.post(endpoint, {
		on_error = function(err)
			callback(error.err({ error = "Failed to make POST request", err = err }))
		end,
		body = body,
		headers = opts.headers or {},
		raw = opts.raw,
		callback = function(response)
			callback(handler(response))
		end,
	})
end

--- Make a PUT request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param body? table The request body to send.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.put = function(endpoint, body, callback, opts)
	opts = opts or {}
	curl.put(endpoint, {
		on_error = function(err)
			callback(error.err({ error = "Failed to make PUT request", err = err }))
		end,
		body = body and json.encode(body) or nil,
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
		callback = function(response)
			callback(handler(response))
		end,
	})
end

--- Make a DELETE request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.delete = function(endpoint, callback, opts)
	opts = opts or {}
	curl.delete(endpoint, {
		on_error = function(err)
			callback(error.err({ error = "Failed to make DELETE request", err = err }))
		end,
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
		callback = function(response)
			callback(handler(response))
		end,
	})
end

-- Authenticated requests

--- Called, scheduled, when a request shows that the session can no longer be used
--- @type fun()|nil
local session_expired_handler = nil

--- Set the function called when the session can no longer be used and the user has to log in again.
--- It can be called several times for the same session, as concurrent requests fail together.
--- @param handler fun()|nil
M.set_session_expired_handler = function(handler)
	session_expired_handler = handler
end

--- Tell if an error means that the access token is not known by the server
--- @param err neoment.matrix.api.Error
--- @return boolean
local function is_unknown_token(err)
	return err.status == 401 and err.errcode == "M_UNKNOWN_TOKEN"
end

--- Copy the request options with the Authorization header set to an access token
--- @param opts neoment.matrix.api.RequestOptions
--- @param access_token string
--- @return neoment.matrix.api.RequestOptions
local function with_authorization(opts, access_token)
	return vim.tbl_extend("force", opts, {
		headers = vim.tbl_extend("force", opts.headers or {}, { Authorization = "Bearer " .. access_token }),
	})
end

--- Tell the handler when the session ended
--- @param result neoment.Error<any, neoment.matrix.api.Error> The final result of an authenticated request.
local function notify_if_session_expired(result)
	if result:is_error() and result.error.session_expired and session_expired_handler then
		vim.schedule(function()
			if session_expired_handler then
				session_expired_handler()
			end
		end)
	end
end

--- Send a request authenticated with the session's access token.
--- The token is refreshed first when it is about to expire. A `401 M_UNKNOWN_TOKEN` with `soft_logout`
--- means it expired anyway: it is refreshed and the request is sent once more. Without `soft_logout`
--- the server forgot the device, which is reported as an expired session.
--- @generic A : table
--- @param send fun(opts: neoment.matrix.api.RequestOptions, callback: fun(data: neoment.Error<A, neoment.matrix.api.Error>): any) Sends the request with the given options.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any
--- @param opts? neoment.matrix.api.RequestOptions
local function authed_request(send, callback, opts)
	-- The token module requires this one
	local token = require("neoment.matrix.token")
	opts = opts or {}

	--- @param result neoment.Error<A, neoment.matrix.api.Error>
	local function finish(result)
		notify_if_session_expired(result)
		callback(result)
	end

	--- @param is_retry boolean
	local function attempt(is_retry)
		token.ensure_fresh(function(fresh)
			if fresh:is_error() then
				return finish(fresh)
			end

			local c = client.client
			if not c or not c.access_token then
				return finish(error.err({ error = "Not logged in" }))
			end

			local sent_token = c.access_token
			send(with_authorization(opts, sent_token), function(response)
				if response:is_ok() or not is_unknown_token(response.error) or is_retry then
					return finish(response)
				end

				-- The client was replaced while the request was in flight
				if client.client ~= c then
					return finish(response)
				end

				-- A request sent at the same time may have refreshed the token already. The rejection is of
				-- the token that was replaced, so it says nothing about the current one.
				if c.access_token ~= sent_token then
					return attempt(true)
				end

				if not response.error.soft_logout or not c.refresh_token then
					return finish(error.err(vim.tbl_extend("force", response.error, { session_expired = true })))
				end

				token.refresh(function(refreshed)
					if refreshed:is_error() then
						return finish(refreshed)
					end
					attempt(true)
				end)
			end)
		end)
	end

	attempt(false)
end

--- Requests authenticated with the session's access token, refreshing it when needed.
--- They take the same arguments as the requests above, and set the Authorization header themselves.
M.authed = {}

--- Make an authenticated GET request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.authed.get = function(endpoint, callback, opts)
	authed_request(function(request_opts, cb)
		M.get(endpoint, cb, request_opts)
	end, callback, opts)
end

--- Make an authenticated POST request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param body? table The request body to send.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.authed.post = function(endpoint, body, callback, opts)
	authed_request(function(request_opts, cb)
		M.post(endpoint, body, cb, request_opts)
	end, callback, opts)
end

--- Make an authenticated POST request to the Matrix API without encoding the body.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param body? any The request body to send.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.authed.post_raw = function(endpoint, body, callback, opts)
	authed_request(function(request_opts, cb)
		M.post_raw(endpoint, body, cb, request_opts)
	end, callback, opts)
end

--- Make an authenticated PUT request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param body? table The request body to send.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.authed.put = function(endpoint, body, callback, opts)
	authed_request(function(request_opts, cb)
		M.put(endpoint, body, cb, request_opts)
	end, callback, opts)
end

--- Make an authenticated DELETE request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.authed.delete = function(endpoint, callback, opts)
	authed_request(function(request_opts, cb)
		M.delete(endpoint, cb, request_opts)
	end, callback, opts)
end

--- Make an authenticated synchronous GET request to the Matrix API.
--- It cannot wait for a token refresh, so it uses the current access token as it is. The sync loop and
--- the other requests keep the token fresh, and an expired token is reported as an error.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
--- @return neoment.Error<A, neoment.matrix.api.Error> The response body as a Lua table.
M.authed.get_sync = function(endpoint, opts)
	local c = client.client
	if not c or not c.access_token then
		return error.err({ error = "Not logged in" })
	end

	local response = M.get_sync(endpoint, with_authorization(opts or {}, c.access_token))
	if response:is_error() and is_unknown_token(response.error) and not response.error.soft_logout then
		response = error.err(vim.tbl_extend("force", response.error, { session_expired = true }))
	end

	notify_if_session_expired(response)
	return response
end

return M
