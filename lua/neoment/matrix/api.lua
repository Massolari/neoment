local M = {}

local curl = require("plenary.curl")
local json = vim.json
local error = require("neoment.error")
--- @alias ErrCode "M_FORBIDDEN" | "M_UNKNOWN_TOKEN" | "M_MISSING_TOKEN" | "M_USER_LOCKED" | "M_USER_SUSPENDED" | "M_BAD_JSON" | "M_NOT_JSON" | "M_NOT_FOUND" | "M_LIMIT_EXCEEDED" | "M_UNRECOGNIZED" | "M_UNKNOWN"

--- @class neoment.matrix.api.Error
--- @field error string The human-readable error message.
--- @field errcode ErrCode The error code.

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
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
	})

	return handler(response)
end

--- Make a POST request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param body table The request body to send.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.post = function(endpoint, body, callback, opts)
	opts = opts or {}
	curl.post(endpoint, {
		body = json.encode(body),
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
		callback = function(response)
			callback(handler(response))
		end,
	})
end

--- Make a PUT request to the Matrix API.
--- @generic A : table
--- @param endpoint string The API endpoint to send the request to.
--- @param body table The request body to send.
--- @param callback fun(data: neoment.Error<A, neoment.matrix.api.Error>): any The callback function to handle the response.
--- @param opts? neoment.matrix.api.RequestOptions Optional parameters for the request.
M.put = function(endpoint, body, callback, opts)
	opts = opts or {}
	curl.put(endpoint, {
		body = json.encode(body),
		headers = vim.tbl_extend("force", {
			["Content-Type"] = "application/json",
		}, opts.headers or {}),
		callback = function(response)
			callback(handler(response))
		end,
	})
end

return M
