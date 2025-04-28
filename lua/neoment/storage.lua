local M = {}
local json = vim.json
local matrix = require("neoment.matrix")

--- Path to the data directory
local data_path = vim.fn.stdpath("data") .. "/neoment/data.json"

--- Path to the cache file
local cache_path = vim.fn.stdpath("cache") .. "/neoment/cache.json"

--- Write data to a file
--- @param path string The path to the file
--- @param data any The data to write
--- @return boolean True if the data was written successfully, false otherwise
local function write_file(path, data)
	if not data then
		return false
	end

	-- Ensure the directory exists
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	local file = io.open(path, "w")
	if not file then
		vim.notify("Error opening file for writing: " .. path, vim.log.levels.ERROR)
		return false
	end

	local success, serialized = pcall(json.encode, data)
	if not success then
		file:close()
		vim.notify("Error serializing data to JSON: " .. serialized, vim.log.levels.ERROR)
		return false
	end

	file:write(serialized)
	file:close()

	return true
end

--- Read data from a file
--- @param path string The path to the file
--- @return any|nil The data read from the file, or nil if the file does not exist or is empty
local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local content = file:read("*all")
	file:close()

	if not content or content == "" then
		return nil
	end

	local success, decoded = pcall(json.decode, content)
	if not success then
		vim.notify("Error decoding JSON data: " .. decoded, vim.log.levels.ERROR)
		return nil
	end

	return decoded
end

--- Save the session data to the cache file
--- @return boolean True if the session was saved successfully, false otherwise
function M.save_session()
	local cache_to_save = {
		rooms = {},
		sync_token = matrix.client.sync_token,
	}

	local data_to_save = {
		user_id = matrix.client.user_id,
		homeserver = matrix.client.homeserver,
		device_id = matrix.client.device_id,

		access_token = matrix.client.access_token,
		last_save = os.time(),
	}

	for room_id, room in pairs(matrix.get_rooms()) do
		local last_message = matrix.get_room_last_message(room_id)
		-- Create a simplified version of the room for storage
		local saved_room = vim.tbl_extend("force", room, {
			events = {},
			pending_events = {},
			messages = last_message and { [last_message.id] = last_message } or {}, -- Store only the last message
			typing = {},
		})
		saved_room.prev_batch = nil

		cache_to_save.rooms[room_id] = saved_room
	end

	return write_file(cache_path, cache_to_save) and write_file(data_path, data_to_save)
end

--- Restore the session data from the cache file
--- @return boolean, neoment.matrix.client.Client|nil True if the session was restored successfully, false otherwise
function M.restore_session()
	local cache = read_file(cache_path)
	local data = read_file(data_path)
	if not data or not data.access_token then
		return false
	end

	-- Check if the session data is too old (7 days)
	local max_age = 7 * 24 * 60 * 60 -- 7 days in seconds
	if data.last_save and os.time() - data.last_save > max_age then
		vim.notify("Session data is expired, please log in again", vim.log.levels.WARN)
		return false
	end

	matrix.new(data.homeserver, data.access_token)
	matrix.client.user_id = data.user_id
	if cache then
		matrix.client.sync_token = cache.sync_token

		-- Restore room data, if available
		if cache.rooms then
			for room_id, room_data in pairs(cache.rooms) do
				matrix.set_room(room_id, room_data)
			end
		end
	end

	vim.notify("Matrix session restored for " .. matrix.client.user_id, vim.log.levels.INFO)

	return true
end

--- Clear the session data from the cache file
function M.clear_session()
	local cache_exists = vim.fn.filereadable(cache_path) == 1
	local data_exists = vim.fn.filereadable(data_path) == 1

	if not cache_exists and not data_exists then
		vim.notify("No session data found to remove", vim.log.levels.INFO)
		return true
	end

	if cache_exists then
		M.clear_cache()
	end

	if data_exists then
		-- Get information about the file before removing it
		local size_kb = math.floor(vim.fn.getfsize(data_path) / 1024)

		local success, err = os.remove(data_path)

		if not success then
			vim.notify("Error removing session data: " .. (err or "unknown"), vim.log.levels.ERROR)
			return false
		else
			vim.notify("Neoment session data removed (" .. size_kb .. "KB)", vim.log.levels.INFO)
		end
	end
	return true
end

--- Clear the cache file
--- @return boolean True if the cache was cleared successfully, false otherwise
function M.clear_cache()
	local cache_exists = vim.fn.filereadable(cache_path) == 1
	if not cache_exists then
		vim.notify("No cache file found to remove", vim.log.levels.INFO)
		return true
	end

	-- Get information about the file before removing it
	local size_kb = math.floor(vim.fn.getfsize(cache_path) / 1024)
	local success, err = os.remove(cache_path)
	if not success then
		vim.notify("Error removing cache: " .. (err or "unknown"), vim.log.levels.ERROR)
		return false
	end

	vim.notify("Neoment cache removed (" .. size_kb .. "KB)", vim.log.levels.INFO)
	return true
end

return M
