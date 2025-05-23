local M = {}
local json = vim.json
local matrix = require("neoment.matrix")
local error = require("neoment.error")
local curl = require("neoment.curl")
local util = require("neoment.util")

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
		invited_rooms = matrix.get_invited_rooms(),
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
		-- Create a simplified version of the room for storage
		local saved_room = vim.tbl_extend("force", room, {
			events = {},
			pending_events = {},
			messages = {},
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
		if cache.invited_rooms then
			for room_id, room_data in pairs(cache.invited_rooms) do
				matrix.set_invited_room(room_id, room_data)
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

--- Write a temporary file
--- @param name string The name of the file
--- @param url string The URL to fetch the file from
--- @return neoment.Error<string, string> The path to the temporary file or an error message
M.fetch_to_temp = function(name, url)
	vim.validate("name", name, "string")
	vim.validate("url", url, "string")

	-- Create temporary directory if it doesn't exist
	local temp_dir = "/tmp/neoment"
	if vim.fn.isdirectory(temp_dir) == 0 then
		vim.fn.mkdir(temp_dir, "p")
	end

	-- Sanitize the name to ensure it's a valid filename
	name = name:gsub("[^%w%.%-_]", "_")

	-- Create the full path for the temporary file
	local temp_path = temp_dir .. "/" .. name

	-- Check if the file already exists
	if vim.fn.filereadable(temp_path) == 1 then
		return error.ok(temp_path)
	end

	local response = curl.get(url, {
		output = temp_path,
		timeout = 30000, -- 30 seconds timeout
		on_error = function(err)
			return error.error("Failed to download file: " .. (err.message or "Unknown error"))
		end,
	})

	if response.exit ~= 0 then
		return error.error("Failed to download file: curl exited with code " .. response.exit)
	end

	if vim.fn.filereadable(temp_path) == 0 then
		return error.error("Failed to save downloaded file")
	end

	return error.ok(temp_path)
end

--- Save the image from the clipboard to a temporary file
--- @return neoment.Error<string, string> The path to the temporary file or an error message
M.save_clipboard_image = function()
	local temp_dir = "/tmp/neoment"
	if vim.fn.isdirectory(temp_dir) == 0 then
		vim.fn.mkdir(temp_dir, "p")
	end

	local temp_file = temp_dir .. "/" .. util.uuid() .. ".png"

	-- Try to get image from clipboard using platform-specific commands
	local success = false
	local error_msg = ""

	if vim.fn.has("mac") == 1 then
		local result = vim.fn.system(
			[[osascript -e "get the clipboard as «class PNGf»" | sed "s/«data PNGf//; s/»//" | xxd -r -p > ]]
				.. temp_file
		)
		success = vim.v.shell_error == 0

		if not success then
			error_msg = "No image found in clipboard or osascript error: " .. result
		end
	elseif vim.fn.has("linux") == 1 then
		-- Linux: Try using xclip
		local has_xclip = vim.fn.executable("xclip") == 1

		if has_xclip then
			-- Check if clipboard has a PNG image
			local result = vim.fn.system("xclip -selection clipboard -t TARGETS -o")
			if result:find("image/png") then
				vim.fn.system("xclip -selection clipboard -t image/png -o > " .. vim.fn.shellescape(temp_file))
				success = vim.v.shell_error == 0 and vim.fn.getfsize(temp_file) > 0
			else
				error_msg = "No image found in clipboard"
			end
		else
			error_msg = "The 'xclip' command is not available. Install with your package manager."
		end
	elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
		-- Windows: Try using PowerShell
		local ps_script = [[
		Add-Type -AssemblyName System.Windows.Forms;
		if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
			$img = [System.Windows.Forms.Clipboard]::GetImage();
			$img.Save(']] .. temp_file:gsub("\\", "\\\\") .. [[', [System.Drawing.Imaging.ImageFormat]::Png);
			Write-Output "success"
		} else {
			Write-Error "No image in clipboard"
			exit 1
		}
		]]

		local result = vim.fn.system({ "powershell", "-NoProfile", "-Command", ps_script })
		success = vim.v.shell_error == 0 and result:find("success") ~= nil

		if not success then
			error_msg = "No image found in clipboard or PowerShell error"
		end
	else
		error_msg = "Clipboard image upload not supported on this platform"
	end

	if not success then
		return error.error(error_msg)
	end

	-- Check if file was created and has content
	if vim.fn.filereadable(temp_file) == 0 or vim.fn.getfsize(temp_file) <= 0 then
		return error.error("Failed to save clipboard image to temporary file")
	end

	return error.ok(temp_file)
end

return M
