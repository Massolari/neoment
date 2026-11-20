local M = {}

local error = require("neoment.error")
local api = require("neoment.matrix.api")
local curl = require("neoment.curl")
local util = require("neoment.util")

--- Grant type of the OAuth 2.0 device authorization grant (RFC 8628).
local DEVICE_CODE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"

--- Seconds between two polls when the server does not give an interval (RFC 8628, section 3.2).
local DEFAULT_INTERVAL = 5

--- Seconds added to the interval when the server asks to slow down (RFC 8628, section 3.5).
local SLOW_DOWN_STEP = 5

--- Curl arguments that bound the time of a request, so an unreachable server does not stall the login.
local REQUEST_CURL_ARGS = { "--connect-timeout", "5", "--max-time", "30" }

local FORM_HEADERS = { ["Content-Type"] = "application/x-www-form-urlencoded" }

--- @class neoment.matrix.oauth.Error: neoment.matrix.api.Error
--- @field code? string The OAuth error code (`expired_token`, `access_denied`, `invalid_client`...), when the server sent one.

--- @class neoment.matrix.oauth.DeviceCode
--- @field device_code string
--- @field user_code string The code the user enters on the verification page.
--- @field verification_url string The URL the user has to visit.
--- @field code_in_url boolean Whether `verification_url` already carries the user code.
--- @field expires_in number Seconds until the device code expires.
--- @field interval number Seconds between two polls.

--- Turn a failed OAuth request into an error with a message for the user.
--- OAuth servers put the error code in `error` and the message in `error_description`.
--- @param err table The error given by the API module.
--- @return neoment.matrix.oauth.Error
local function to_error(err)
	local description = type(err.error_description) == "string" and err.error_description or nil
	local code = type(err.error) == "string" and err.status and err.error or nil
	return {
		error = description or err.error or "unknown error",
		code = code,
		status = err.status,
	}
end

--- Get the client ID registered for the issuer, or register the client when there is none.
--- The client ID is saved per issuer and used again on later logins.
--- @param metadata neoment.matrix.auth.OAuthMetadata
--- @param callback fun(result: neoment.Error<string, neoment.matrix.oauth.Error>): any
M.register_client = function(metadata, callback)
	-- The storage module requires the Matrix module, which requires this one
	local storage = require("neoment.storage")

	local saved = storage.get_oauth_client_id(metadata.issuer)
	if saved then
		callback(error.ok(saved))
		return
	end

	api.post(metadata.registration_endpoint, {
		client_name = "Neoment",
		client_uri = "https://github.com/Massolari/neoment",
		grant_types = { DEVICE_CODE_GRANT, "refresh_token" },
		token_endpoint_auth_method = "none",
		application_type = "native",
	}, function(response)
		if response:is_error() then
			local err = to_error(response.error)
			err.error = "Could not register the client: " .. err.error
			callback(error.err(err))
			return
		end

		local client_id = response.data.client_id
		if type(client_id) ~= "string" or client_id == "" then
			callback(error.err({ error = "Could not register the client: the server returned no client ID" }))
			return
		end

		util.on_main_loop(function()
			storage.set_oauth_client_id(metadata.issuer, client_id)
			callback(error.ok(client_id))
		end)
	end, { raw = REQUEST_CURL_ARGS })
end

--- Ask the server for a device code, scoped to the Matrix client API and to this device.
--- A server that does not know the client ID anymore makes the saved one be forgotten.
--- @param metadata neoment.matrix.auth.OAuthMetadata
--- @param client_id string
--- @param device_id string The Matrix device ID of this client.
--- @param callback fun(result: neoment.Error<neoment.matrix.oauth.DeviceCode, neoment.matrix.oauth.Error>): any
M.request_device_code = function(metadata, client_id, device_id, callback)
	api.post_raw(
		metadata.device_authorization_endpoint,
		util.form_encode({
			{ "client_id", client_id },
			{ "scope", "urn:matrix:client:api:* urn:matrix:client:device:" .. device_id },
		}),
		function(response)
			if response:is_error() then
				local err = to_error(response.error)
				if err.code == "invalid_client" then
					util.on_main_loop(function()
						require("neoment.storage").clear_oauth_client_id(metadata.issuer)
						callback(error.err(err))
					end)
					return
				end
				callback(error.err(err))
				return
			end

			local data = response.data
			if
				type(data.device_code) ~= "string"
				or type(data.user_code) ~= "string"
				or type(data.verification_uri) ~= "string"
				or not util.is_http_url(data.verification_uri)
			then
				callback(error.err({ error = "The server returned an incomplete device authorization response" }))
				return
			end

			-- The URL is opened in a browser, so anything that is not HTTP(S) is ignored
			local complete = type(data.verification_uri_complete) == "string"
					and util.is_http_url(data.verification_uri_complete)
					and data.verification_uri_complete
				or nil
			callback(error.ok({
				device_code = data.device_code,
				user_code = data.user_code,
				verification_url = complete or data.verification_uri,
				code_in_url = complete ~= nil,
				expires_in = type(data.expires_in) == "number" and data.expires_in or 600,
				interval = type(data.interval) == "number" and data.interval or DEFAULT_INTERVAL,
			}))
		end,
		{ headers = FORM_HEADERS, raw = REQUEST_CURL_ARGS }
	)
end

--- @class neoment.matrix.oauth.PollOptions
--- @field metadata neoment.matrix.auth.OAuthMetadata
--- @field client_id string
--- @field device_code neoment.matrix.oauth.DeviceCode
--- @field now? fun(): number The current time in seconds, `os.time` by default.
--- @field defer? fun(fn: fun(), ms: integer) Calls a function after a delay, `vim.defer_fn` by default.

--- @class neoment.matrix.oauth.PollHandle
--- @field cancel fun() Stop polling. The callback is not called afterwards.

--- Tell if a failed request may succeed when it is sent again.
--- @param err table The error given by the API module.
--- @return boolean
local function is_transient(err)
	local status = err.status
	return not status or status == 408 or status == 429 or status >= 500
end

--- Poll the token endpoint until the user approves or refuses the login, or the device code expires.
--- The next request is only scheduled after the answer to the previous one, so requests never overlap.
--- @param opts neoment.matrix.oauth.PollOptions
--- @param callback fun(result: neoment.Error<table, neoment.matrix.oauth.Error>): any Called once with the token response, or the reason polling stopped.
--- @return neoment.matrix.oauth.PollHandle
M.poll = function(opts, callback)
	local now = opts.now or os.time
	local defer = opts.defer or vim.defer_fn
	local device = opts.device_code
	local interval = device.interval
	local deadline = now() + device.expires_in
	local active = true

	--- @param result neoment.Error<table, neoment.matrix.oauth.Error>
	local function finish(result)
		if not active then
			return
		end
		active = false
		callback(result)
	end

	local request

	local function schedule()
		defer(request, interval * 1000)
	end

	request = function()
		if not active then
			return
		end
		if now() >= deadline then
			finish(error.err({ error = "The login code expired", code = "expired_token" }))
			return
		end

		api.post_raw(
			opts.metadata.token_endpoint,
			util.form_encode({
				{ "grant_type", DEVICE_CODE_GRANT },
				{ "device_code", device.device_code },
				{ "client_id", opts.client_id },
			}),
			function(response)
				if not active then
					return
				end

				if response:is_ok() then
					finish(response)
					return
				end

				local err = response.error
				local code = err.status and err.error
				if code == "authorization_pending" then
					schedule()
				elseif code == "slow_down" then
					interval = interval + SLOW_DOWN_STEP
					schedule()
				elseif code == "expired_token" then
					finish(error.err({ error = "The login code expired", code = "expired_token" }))
				elseif code == "access_denied" then
					finish(error.err({ error = "The login was denied", code = "access_denied" }))
				elseif is_transient(err) then
					schedule()
				else
					finish(error.err(to_error(err)))
				end
			end,
			{ headers = FORM_HEADERS, raw = REQUEST_CURL_ARGS }
		)
	end

	schedule()

	return {
		cancel = function()
			active = false
		end,
	}
end

--- Revoke a token at the revocation endpoint (RFC 7009).
--- The request needs no access token, and a refresh is never started for it.
--- @param endpoint string The revocation endpoint.
--- @param client_id string
--- @param refresh_token string
--- @param callback fun(result: neoment.Error<nil, neoment.matrix.oauth.Error>): any
M.revoke = function(endpoint, client_id, refresh_token, callback)
	curl.post(endpoint, {
		body = util.form_encode({
			{ "token", refresh_token },
			{ "token_type_hint", "refresh_token" },
			{ "client_id", client_id },
		}),
		headers = FORM_HEADERS,
		raw = REQUEST_CURL_ARGS,
		on_error = function(err)
			callback(error.err({ error = "Failed to make POST request", err = err }))
		end,
		callback = function(response)
			-- The body of a successful revocation is empty or `{}`, so only the status tells the result
			if response.status >= 200 and response.status < 300 then
				callback(error.ok(nil))
				return
			end

			local ok, body = pcall(vim.json.decode, response.body)
			local err = ok
					and type(body) == "table"
					and to_error(vim.tbl_extend("force", body, { status = response.status }))
				or { error = "HTTP status " .. response.status, status = response.status }
			callback(error.err(err))
		end,
	})
end

return M
