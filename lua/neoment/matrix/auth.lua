local M = {}

local error = require("neoment.error")
local api = require("neoment.matrix.api")
local client = require("neoment.matrix.client")
local oauth = require("neoment.matrix.oauth")

--- @alias neoment.matrix.auth.Method "oauth_device"|"password"|"sso"

--- The OAuth 2.0 server metadata needed for the device authorization grant.
--- @class neoment.matrix.auth.OAuthMetadata
--- @field issuer string
--- @field device_authorization_endpoint string
--- @field token_endpoint string
--- @field registration_endpoint string
--- @field revocation_endpoint? string

--- Grant type of the OAuth 2.0 device authorization grant (RFC 8628).
local DEVICE_CODE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"

--- Login methods supported by the client, mapped from the Matrix login flow type.
--- @type table<string, neoment.matrix.auth.Method>
local SUPPORTED_FLOWS = {
	["m.login.password"] = "password",
	["m.login.sso"] = "sso",
}

--- Order in which supported methods are presented to the user.
--- @type neoment.matrix.auth.Method[]
local METHOD_ORDER = { "oauth_device", "password", "sso" }

--- Curl arguments that bound the time spent on discovery requests, so an unreachable host fails fast.
local DISCOVERY_CURL_ARGS = { "--connect-timeout", "5", "--max-time", "10" }

--- Check if a string is an HTTP(S) URL. The scheme is matched case-insensitively.
--- @param value string
--- @return boolean
local function is_http_url(value)
	return value:lower():match("^https?://") ~= nil
end

--- Read the homeserver base URL from a `.well-known/matrix/client` object.
--- Base URLs that are not HTTP(S) URLs are ignored, so a missing scheme never falls back to another protocol.
--- @param well_known any The decoded well-known object.
--- @return string|nil The homeserver base URL without trailing slashes, if present.
local function homeserver_from_well_known(well_known)
	local homeserver_info = type(well_known) == "table" and well_known["m.homeserver"]
	local base_url = type(homeserver_info) == "table" and homeserver_info.base_url
	if type(base_url) ~= "string" or not is_http_url(base_url) then
		return nil
	end
	return (base_url:gsub("/+$", ""))
end

--- Parse the user input of the login prompt.
--- Accepts a full Matrix ID (`@alice:example.org`), a bare server name (`example.org`),
--- or a homeserver URL (`https://matrix.example.org`), which is returned without trailing slashes.
--- @param input string The user input.
--- @return string|nil server_name The server name, or nil if the input is empty or invalid.
--- @return string|nil user_id The full Matrix ID, if the input was one.
M.parse_server_name = function(input)
	local trimmed = vim.trim(input or "")
	if trimmed == "" then
		return nil, nil
	end

	if trimmed:sub(1, 1) == "@" then
		local server_name = trimmed:match("^@[^:]+:(.+)$")
		if not server_name then
			return nil, nil
		end
		return server_name, trimmed
	end

	return (trimmed:gsub("/+$", "")), nil
end

--- Discover the homeserver base URL for a server name using `/.well-known/matrix/client`.
--- Falls back to `https://<server_name>` when discovery fails, so it never errors.
--- A homeserver URL (`https://...`) is used as is, without discovery.
--- @param server_name string The server name (e.g. `example.org`) or homeserver URL.
--- @param callback fun(homeserver: string): any The callback receiving the homeserver base URL.
M.discover = function(server_name, callback)
	if is_http_url(server_name) then
		callback(server_name)
		return
	end

	local fallback = "https://" .. server_name
	-- The well-known lookup uses the hostname only; the port is for the fallback
	local hostname = server_name:gsub(":%d+$", "")

	api.get("https://" .. hostname .. "/.well-known/matrix/client", function(response)
		local homeserver = error.match(response, function(data)
			return homeserver_from_well_known(data) or fallback
		end, function()
			return fallback
		end)

		callback(homeserver)
	end, { raw = DISCOVERY_CURL_ARGS })
end

--- Get the OAuth 2.0 server metadata when the homeserver supports the device authorization grant.
--- The callback gets nil when it does not, whatever the reason: OAuth device login is then just unavailable.
--- @param homeserver string The homeserver base URL.
--- @param callback fun(metadata: neoment.matrix.auth.OAuthMetadata|nil): any
M.get_oauth_metadata = function(homeserver, callback)
	api.get(homeserver .. "/_matrix/client/v1/auth_metadata", function(response)
		if error.is_error(response) then
			callback(nil)
			return
		end

		local data = response.data
		local grants = type(data.grant_types_supported) == "table" and data.grant_types_supported or {}
		if not vim.tbl_contains(grants, DEVICE_CODE_GRANT) then
			callback(nil)
			return
		end

		for _, field in ipairs({ "issuer", "device_authorization_endpoint", "token_endpoint", "registration_endpoint" }) do
			if type(data[field]) ~= "string" or not is_http_url(data[field]) then
				callback(nil)
				return
			end
		end

		local revocation_endpoint = data.revocation_endpoint
		callback({
			issuer = data.issuer,
			device_authorization_endpoint = data.device_authorization_endpoint,
			token_endpoint = data.token_endpoint,
			registration_endpoint = data.registration_endpoint,
			revocation_endpoint = type(revocation_endpoint) == "string"
					and is_http_url(revocation_endpoint)
					and revocation_endpoint
				or nil,
		})
	end, { raw = DISCOVERY_CURL_ARGS })
end

--- Get the login methods supported by both the homeserver and the client.
--- The login flows and the OAuth metadata are requested at the same time. A server without OAuth
--- metadata only loses `oauth_device`, and an error is returned only when no method remains.
--- @param homeserver string The homeserver base URL.
--- @param callback fun(result: neoment.Error<neoment.matrix.auth.Method[], neoment.matrix.api.Error>, metadata?: neoment.matrix.auth.OAuthMetadata): any The metadata is given when `oauth_device` is one of the methods.
M.get_login_flows = function(homeserver, callback)
	--- @type neoment.Error<table, neoment.matrix.api.Error>|nil
	local flows_response
	local metadata
	local metadata_done = false

	local function finish()
		if not flows_response or not metadata_done then
			return
		end

		local available = {}
		local advertised = {}
		if flows_response:is_ok() then
			local supports_token = false
			local flows = type(flows_response.data.flows) == "table" and flows_response.data.flows or {}
			for _, flow in ipairs(flows) do
				local flow_type = type(flow) == "table" and flow.type
				if type(flow_type) == "string" then
					table.insert(advertised, flow_type)
					supports_token = supports_token or flow_type == "m.login.token"
					local method = SUPPORTED_FLOWS[flow_type]
					if method then
						available[method] = true
					end
				end
			end

			-- SSO hands back a login token, which can only be exchanged with m.login.token
			if not supports_token then
				available.sso = nil
			end
		end
		available.oauth_device = metadata ~= nil or nil

		local methods = vim.tbl_filter(function(method)
			return available[method] == true
		end, METHOD_ORDER)

		if #methods > 0 then
			callback(error.ok(methods), metadata)
		elseif flows_response:is_error() then
			callback(error.err({
				error = string.format(
					"Could not fetch login methods from %s: %s",
					homeserver,
					flows_response.error.error or "unknown error"
				),
			}))
		else
			callback(error.err({
				error = "No supported login method. The server offers: " .. table.concat(advertised, ", "),
			}))
		end
	end

	api.get(homeserver .. "/_matrix/client/v3/login", function(response)
		flows_response = response
		finish()
	end, { raw = DISCOVERY_CURL_ARGS })

	M.get_oauth_metadata(homeserver, function(result)
		metadata = result
		metadata_done = true
		finish()
	end)
end

--- Send a login request and store the credentials on success.
--- If the response includes a `well_known` object, the client uses its homeserver from then on.
--- The credentials are dropped if the client was replaced while the request was in flight,
--- or if `is_current` reports that the login attempt was superseded.
--- @param body table The login request body.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any
--- @param is_current? fun(): boolean Whether the login attempt that sent the request is still current.
local function login_request(body, callback, is_current)
	local requesting_client = client.client
	body.device_id = requesting_client.device_id

	api.post(
		requesting_client.homeserver .. "/_matrix/client/v3/login",
		body,
		--- @param response neoment.Error<neoment.matrix.LoginResponse, neoment.matrix.api.Error>
		function(response)
			if client.client ~= requesting_client or (is_current and not is_current()) then
				callback(error.err({ error = "The login was superseded by another login attempt" }))
				return
			end

			local result = error.map(response, function(data)
				requesting_client.access_token = data.access_token
				requesting_client.refresh_token = type(data.refresh_token) == "string" and data.refresh_token or nil
				requesting_client.expires_at = type(data.expires_in_ms) == "number"
						and os.time() + math.floor(data.expires_in_ms / 1000)
					or nil
				requesting_client.user_id = data.user_id
				requesting_client.homeserver = homeserver_from_well_known(data.well_known)
					or requesting_client.homeserver
				return nil
			end) --[[@as neoment.Error<nil, neoment.matrix.api.Error>]]

			callback(result)
		end
	)
end

--- Login with a username and password on the current homeserver.
--- @param user string The Matrix ID or localpart of the user.
--- @param password string The password.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any
--- @param is_current? fun(): boolean Whether the login attempt is still current when the response arrives.
M.login_password = function(user, password, callback, is_current)
	login_request({
		type = "m.login.password",
		identifier = {
			type = "m.id.user",
			user = user,
		},
		password = password,
		-- Servers that don't support refresh tokens ignore this
		refresh_token = true,
	}, callback, is_current)
end

--- Revoke the refresh token of a login that could not be completed.
--- Failing to do it is not reported: the login already failed, and the token is useless to the user.
--- @param refresh neoment.matrix.client.RefreshMethod
--- @param refresh_token? string
local function revoke_unused_token(refresh, refresh_token)
	if refresh_token and refresh.revocation_endpoint and refresh.client_id then
		oauth.revoke(refresh.revocation_endpoint, refresh.client_id, refresh_token, function() end)
	end
end

--- Finish a login with the OAuth 2.0 device authorization grant.
--- The tokens are stored on the client and the user ID is read with `whoami`, as the token response has none.
--- When that fails the new token is revoked and the client is reset, so no half logged-in session is left.
--- The tokens are dropped if the client was replaced while the request was in flight,
--- or if `is_current` reports that the login attempt was superseded.
--- @param tokens table The token response.
--- @param metadata neoment.matrix.auth.OAuthMetadata The OAuth server metadata.
--- @param client_id string The client ID the tokens were issued to.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any
--- @param is_current? fun(): boolean Whether the login attempt is still current.
M.login_oauth = function(tokens, metadata, client_id, callback, is_current)
	local requesting_client = client.client
	local superseded = error.err({ error = "The login was superseded by another login attempt" })

	if type(tokens.access_token) ~= "string" then
		callback(error.err({ error = "The server returned no access token" }))
		return
	end
	if client.client ~= requesting_client or (is_current and not is_current()) then
		callback(superseded)
		return
	end

	--- @type neoment.matrix.client.RefreshMethod
	local refresh = {
		kind = "oauth",
		token_endpoint = metadata.token_endpoint,
		client_id = client_id,
		revocation_endpoint = metadata.revocation_endpoint,
	}
	local refresh_token = type(tokens.refresh_token) == "string" and tokens.refresh_token or nil

	requesting_client.access_token = tokens.access_token
	requesting_client.refresh_token = refresh_token
	requesting_client.expires_at = refresh_token
			and type(tokens.expires_in) == "number"
			and os.time() + math.floor(tokens.expires_in)
		or nil
	requesting_client.refresh = refresh

	api.authed.get(requesting_client.homeserver .. "/_matrix/client/v3/account/whoami", function(response)
		local replaced = client.client ~= requesting_client
		if replaced or (is_current and not is_current()) then
			revoke_unused_token(refresh, refresh_token)
			callback(superseded)
			return
		end

		local user_id = response:is_ok() and response.data.user_id or nil
		if type(user_id) ~= "string" then
			revoke_unused_token(refresh, refresh_token)
			client.set_homeserver(requesting_client.homeserver)
			callback(
				response:is_error() and response
					or error.err({ error = "The server did not say which user the token belongs to" })
			)
			return
		end

		requesting_client.user_id = user_id
		callback(error.ok(nil))
	end)
end

--- Build the URL that starts the SSO login in the browser.
--- @param homeserver string The homeserver base URL.
--- @param redirect_url string The URL the browser is sent to after SSO, with the login token appended.
--- @return string The SSO redirect URL.
M.sso_redirect_url = function(homeserver, redirect_url)
	return homeserver .. "/_matrix/client/v3/login/sso/redirect?redirectUrl=" .. vim.uri_encode(redirect_url, "rfc2396")
end

--- Login with a token obtained through SSO on the current homeserver.
--- @param token string The login token.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any
--- @param is_current? fun(): boolean Whether the login attempt is still current when the response arrives.
M.login_token = function(token, callback, is_current)
	login_request({
		type = "m.login.token",
		token = token,
	}, callback, is_current)
end

--- Extract the login token from a pasted redirect URL or a bare token.
--- @param input string|nil The user input.
--- @return string|nil token The login token, or nil if the input is empty or a URL without a token.
--- @return string|nil err An error message when the input is a URL without a login token.
M.parse_login_token = function(input)
	local trimmed = vim.trim(input or "")
	if trimmed == "" then
		return nil
	end

	local token = trimmed:match("[?&]loginToken=([^&#]+)")
	if token then
		return vim.uri_decode(token)
	end

	if trimmed:match("^%a[%w+.-]*://") then
		return nil, "The URL does not contain a login token"
	end

	return trimmed
end

return M
