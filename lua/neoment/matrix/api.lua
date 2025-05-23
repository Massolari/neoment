local M = {}

local curl = require("neoment.curl")
local json = vim.json
local error = require("neoment.error")
--- @alias neoment.matrix.api.ErrCode "M_FORBIDDEN" | "M_UNKNOWN_TOKEN" | "M_MISSING_TOKEN" | "M_USER_LOCKED" | "M_USER_SUSPENDED" | "M_BAD_JSON" | "M_NOT_JSON" | "M_NOT_FOUND" | "M_LIMIT_EXCEEDED" | "M_UNRECOGNIZED" | "M_UNKNOWN"

--- @class neoment.matrix.api.Error
--- @field error string The human-readable error message.
--- @field errcode neoment.matrix.api.ErrCode The error code.

--- @class neoment.matrix.api.RequestOptions
--- @field headers table<string, string> A table of headers to include in the request.

--- Handle the response from a Matrix API request.
--- @generic A : table
--- @param response table The response from the API request.
local function handler(response)
	-- local data = json.decode(response.body)
	local ok, data = pcall(json.decode, response.body)
	if not ok then
		return error.error({ error = "Failed to decode JSON response" })
	end

	if data.error then
		return error.error(data)
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
			callback(error.error({ error = "Failed to make GET request", err = err }))
		end,
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
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
	local response = curl.get(endpoint, {
		on_error = function(err)
			return error.error({ error = "Failed to make GET request", err = err })
		end,
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
	})

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
			callback(error.error({ error = "Failed to make POST request", err = err }))
		end,
		body = body,
		headers = opts.headers or {},
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
			callback(error.error({ error = "Failed to make PUT request", err = err }))
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

return M
