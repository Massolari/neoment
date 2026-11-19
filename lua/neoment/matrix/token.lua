local M = {}

local error = require("neoment.error")
local api = require("neoment.matrix.api")
local client = require("neoment.matrix.client")

--- Refresh the access token when it expires in less than this many seconds
local EXPIRY_SKEW = 60

--- Give up on a refresh request after this many seconds.
--- Every authenticated request waits for the refresh in progress, so one that never ends would block them all.
local REFRESH_TIMEOUT = 30

--- @alias neoment.matrix.token.Callback fun(result: neoment.Error<nil, neoment.matrix.api.Error>): any

--- The callbacks waiting for the refresh in progress, nil when there is none
--- @type neoment.matrix.token.Callback[]|nil
local pending = nil

--- @class neoment.matrix.token.Tokens
--- @field access_token string
--- @field refresh_token? string
--- @field expires_in? number Lifetime of the access token, in seconds.

--- Encode a list of key/value pairs as an `application/x-www-form-urlencoded` body
--- @param fields string[][] The `{ key, value }` pairs, in the order they are sent.
--- @return string
local function form_encode(fields)
	return table.concat(
		vim.tbl_map(function(field)
			return vim.uri_encode(field[1], "rfc3986") .. "=" .. vim.uri_encode(field[2], "rfc3986")
		end, fields),
		"&"
	)
end

--- Build the error for a session that can no longer be refreshed
--- @param cause? neoment.matrix.api.Error The error that made the session unusable.
--- @return neoment.matrix.api.Error
local function session_expired_error(cause)
	return {
		error = "Session expired, please log in again",
		errcode = cause and cause.errcode,
		status = cause and cause.status,
		session_expired = true,
	}
end

--- Tell if the server rejected a refresh for good, as opposed to a failure that may go away.
--- Rate limiting and timeouts are rejections of the request, not of the refresh token.
--- @param err neoment.matrix.api.Error
--- @return boolean
local function is_permanent_failure(err)
	local status = err.status
	if not status or status == 408 or status == 429 then
		return false
	end
	return status >= 400 and status < 500
end

--- Send the refresh request for the session's refresh method
--- @param c neoment.matrix.client.Client
--- @param callback fun(result: neoment.Error<neoment.matrix.token.Tokens, neoment.matrix.api.Error>): any
local function request_tokens(c, callback)
	local method = c.refresh or { kind = "legacy" }
	local raw = { "--max-time", tostring(REFRESH_TIMEOUT) }

	--- @param data table
	--- @param expires_in? number
	--- @return neoment.Error<neoment.matrix.token.Tokens, neoment.matrix.api.Error>
	local function to_tokens(data, expires_in)
		if type(data.access_token) ~= "string" then
			return error.err({ error = "The refresh response has no access token" })
		end
		return error.ok({
			access_token = data.access_token,
			refresh_token = type(data.refresh_token) == "string" and data.refresh_token or nil,
			expires_in = type(expires_in) == "number" and expires_in or nil,
		})
	end

	if method.kind == "oauth" then
		if not method.token_endpoint or not method.client_id then
			callback(error.err(session_expired_error()))
			return
		end

		api.post_raw(
			method.token_endpoint,
			form_encode({
				{ "grant_type", "refresh_token" },
				{ "refresh_token", c.refresh_token },
				{ "client_id", method.client_id },
			}),
			function(response)
				callback(error.try(response, function(data)
					return to_tokens(data, data.expires_in)
				end))
			end,
			{ headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }, raw = raw }
		)
		return
	end

	api.post(c.homeserver .. "/_matrix/client/v3/refresh", { refresh_token = c.refresh_token }, function(response)
		callback(error.try(response, function(data)
			local expires_in_ms = data.expires_in_ms
			return to_tokens(data, type(expires_in_ms) == "number" and expires_in_ms / 1000 or nil)
		end))
	end, { raw = raw })
end

--- Call a function in the main loop.
--- Network callbacks run where vim.fn is not allowed, and the session file is written and read with it.
--- @param fn fun()
local function on_main_loop(fn)
	if vim.in_fast_event() then
		vim.schedule(fn)
	else
		fn()
	end
end

--- Write the session to disk, so a rotated refresh token is not lost
local function persist()
	if not require("neoment.config").get().save_session then
		return
	end
	require("neoment.storage").save_session()
end

--- Take the credentials from the saved session when it holds a newer refresh token than the client.
--- Refresh tokens rotate, so when two instances share the session file the one that refreshes second
--- is rejected. The saved credentials are those of the instance that refreshed first.
--- @param c neoment.matrix.client.Client
--- @return boolean True if the client now holds the saved credentials.
local function adopt_saved_session(c)
	if not require("neoment.config").get().save_session then
		return false
	end

	local saved = require("neoment.storage").read_saved_session()
	if not saved or type(saved.access_token) ~= "string" or type(saved.refresh_token) ~= "string" then
		return false
	end
	if saved.refresh_token == c.refresh_token then
		return false
	end
	-- Never take the credentials of another account
	if saved.homeserver ~= c.homeserver or saved.user_id ~= c.user_id then
		return false
	end

	c.access_token = saved.access_token
	c.refresh_token = saved.refresh_token
	c.expires_at = saved.expires_at
	c.refresh = saved.refresh
	return true
end

--- Tell if the access token is expired or about to expire.
--- A session without an expiry time or without a refresh token is never stale, as it cannot be refreshed.
--- @return boolean
M.is_stale = function()
	local c = client.client
	if not c or not c.refresh_token or not c.expires_at then
		return false
	end
	return c.expires_at - os.time() < EXPIRY_SKEW
end

--- Refresh the access token.
--- While a refresh is in progress no other is started: the callback waits for it and gets its result.
--- A failure that the server reports as permanent is returned with `session_expired` set and leaves
--- the session for the caller to end, any other failure leaves the session untouched.
--- @param callback neoment.matrix.token.Callback
M.refresh = function(callback)
	if pending then
		table.insert(pending, callback)
		return
	end

	local c = client.client
	if not c or not c.refresh_token then
		callback(error.err(session_expired_error()))
		return
	end

	pending = { callback }

	--- @param result neoment.Error<nil, neoment.matrix.api.Error>
	local function finish(result)
		local callbacks = pending or {}
		pending = nil
		for _, waiting in ipairs(callbacks) do
			waiting(result)
		end
	end

	--- @param may_reread_session boolean Whether a rejection may still be answered by re-reading the saved session.
	local function run(may_reread_session)
		request_tokens(c, function(result)
			-- The tokens are stored and saved before any request can use them, so the saved session
			-- never holds a refresh token that was already consumed
			on_main_loop(function()
				-- The client was replaced (logout, new login) while the request was in flight
				if client.client ~= c then
					finish(error.err({ error = "The session changed during the token refresh" }))
					return
				end

				error.match(result, function(tokens)
					c.access_token = tokens.access_token
					-- The server may keep the refresh token instead of rotating it
					c.refresh_token = tokens.refresh_token or c.refresh_token
					c.expires_at = tokens.expires_in and os.time() + math.floor(tokens.expires_in) or nil
					persist()
					finish(error.ok(nil))
				end, function(err)
					if not is_permanent_failure(err) then
						finish(error.err(err))
						return
					end

					-- Another instance sharing the session file may have rotated the refresh token
					if may_reread_session and adopt_saved_session(c) then
						if M.is_stale() then
							run(false)
						else
							finish(error.ok(nil))
						end
						return
					end

					finish(error.err(session_expired_error(err)))
				end)
			end)
		end)
	end

	run(true)
end

--- Make sure the access token is not about to expire, refreshing it first if it is.
--- Does nothing when the session has no known expiry time.
--- @param callback neoment.matrix.token.Callback
M.ensure_fresh = function(callback)
	if not M.is_stale() then
		callback(error.ok(nil))
		return
	end
	M.refresh(callback)
end

return M
