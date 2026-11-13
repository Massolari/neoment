local M = {}

local error = require("neoment.error")
local api = require("neoment.matrix.api")
local client = require("neoment.matrix.client")

--- @alias neoment.matrix.auth.Method "password"|"sso"

--- Login methods supported by the client, mapped from the Matrix login flow type.
--- @type table<string, neoment.matrix.auth.Method>
local SUPPORTED_FLOWS = {
	["m.login.password"] = "password",
	["m.login.sso"] = "sso",
}

--- Order in which supported methods are presented to the user.
--- @type neoment.matrix.auth.Method[]
local METHOD_ORDER = { "password", "sso" }

--- Parse the user input of the login prompt.
--- Accepts a full Matrix ID (`@alice:example.org`) or a bare server name (`example.org`).
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

	return trimmed, nil
end

--- Discover the homeserver base URL for a server name using `/.well-known/matrix/client`.
--- Falls back to `https://<server_name>` when discovery fails, so it never errors.
--- @param server_name string The server name (e.g. `example.org`).
--- @param callback fun(homeserver: string): any The callback receiving the homeserver base URL.
M.discover = function(server_name, callback)
	local fallback = "https://" .. server_name

	api.get("https://" .. server_name .. "/.well-known/matrix/client", function(response)
		local homeserver = error.match(response, function(data)
			local homeserver_info = type(data) == "table" and data["m.homeserver"]
			local base_url = type(homeserver_info) == "table" and homeserver_info.base_url
			if type(base_url) ~= "string" or base_url == "" then
				return fallback
			end
			return (base_url:gsub("/+$", ""))
		end, function()
			return fallback
		end)

		callback(homeserver)
	end, { raw = { "-L" } })
end

--- Get the login methods supported by both the homeserver and the client.
--- @param homeserver string The homeserver base URL.
--- @param callback fun(result: neoment.Error<neoment.matrix.auth.Method[], neoment.matrix.api.Error>): any
M.get_login_flows = function(homeserver, callback)
	api.get(homeserver .. "/_matrix/client/v3/login", function(response)
		if error.is_error(response) then
			callback(error.err({
				error = string.format(
					"Could not fetch login methods from %s: %s",
					homeserver,
					response.error.error or "unknown error"
				),
			}))
			return
		end

		local available = {}
		local advertised = {}
		for _, flow in ipairs(response.data.flows or {}) do
			table.insert(advertised, flow.type)
			local method = SUPPORTED_FLOWS[flow.type]
			if method then
				available[method] = true
			end
		end

		local methods = vim.tbl_filter(function(method)
			return available[method] == true
		end, METHOD_ORDER)

		if #methods == 0 then
			callback(error.err({
				error = "No supported login method. The server offers: " .. table.concat(advertised, ", "),
			}))
			return
		end

		callback(error.ok(methods))
	end)
end

--- Send a login request and store the credentials on success.
--- @param body table The login request body.
--- @param callback fun(data: neoment.Error<nil, neoment.matrix.api.Error>): any
local function login_request(body, callback)
	body.device_id = client.client.device_id

	api.post(
		client.client.homeserver .. "/_matrix/client/v3/login",
		body,
		--- @param response neoment.Error<neoment.matrix.LoginResponse, neoment.matrix.api.Error>
		function(response)
			local result = error.map(response, function(data)
				client.client.access_token = data.access_token
				client.client.user_id = data.user_id
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
M.login_password = function(user, password, callback)
	login_request({
		type = "m.login.password",
		identifier = {
			type = "m.id.user",
			user = user,
		},
		password = password,
	}, callback)
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
M.login_token = function(token, callback)
	login_request({
		type = "m.login.token",
		token = token,
	}, callback)
end

--- Extract the login token from a pasted redirect URL or a bare token.
--- @param input string|nil The user input.
--- @return string|nil The login token, or nil if the input is empty.
M.parse_login_token = function(input)
	local trimmed = vim.trim(input or "")
	if trimmed == "" then
		return nil
	end

	local token = trimmed:match("[?&]loginToken=([^&#]+)")
	if token then
		return vim.uri_decode(token)
	end

	return trimmed
end

return M
