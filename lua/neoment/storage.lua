local M = {}

local notify = require("neoment.notify")
local json = vim.json
local matrix = require("neoment.matrix")
local error = require("neoment.error")
local curl = require("neoment.curl")
local util = require("neoment.util")

--- Path to the data directory
local data_path = vim.fn.stdpath("data") .. "/neoment/data.json"

--- Path to the cache file
local cache_path = vim.fn.stdpath("cache") .. "/neoment/cache.json"

--- Path to the UI state file
local ui_state_path = vim.fn.stdpath("data") .. "/neoment/ui_state.json"

--- Path to the file with the OAuth client IDs, mapped by issuer
local oauth_clients_path = vim.fn.stdpath("data") .. "/neoment/oauth_clients.json"

--- The path of the directory where the images shown in rooms are downloaded
local media_path = vim.fn.stdpath("cache") .. "/neoment/media"

--- Get the path to a temporary file
--- @param file string The name of the file
--- @param opts {path: string[]}|nil Options for the temporary file
local function get_temp_path(file, opts)
	local directory = vim.fs.joinpath(vim.uv.os_tmpdir(), "neoment", unpack(opts and opts.path or {}))
	if vim.fn.isdirectory(directory) == 0 then
		vim.fn.mkdir(directory, "p")
	end
	return vim.fs.joinpath(directory, file)
end

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
		notify.error("Error opening file for writing: " .. path)
		return false
	end

	local success, serialized = pcall(json.encode, data)
	if not success then
		file:close()
		notify.error("Error serializing data to JSON: " .. serialized)
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
		notify.error("Error decoding JSON data: " .. decoded)
		return nil
	end

	return decoded
end

--- Strip unnecessary data from a room for storage
--- @param room neoment.matrix.client.Room The room to strip
--- @return neoment.matrix.client.Room The stripped room
local function get_stripped_room(room)
	local last_message = matrix.get_room_last_message(room.id)

	--- @type neoment.matrix.client.Room
	return {
		id = room.id,
		name = room.name,
		aliases = room.aliases,
		tombstone = room.tombstone,
		avatar_url = room.avatar_url,
		topic = room.topic,
		-- No need to store the event history
		events = {},
		pending_events = {},
		-- Store only the last message to display in the room list
		messages = last_message and { [last_message.id] = last_message } or {},
		-- The last activity is needed for sorting the room list
		last_activity = room.last_activity,
		-- Store these flags to display the room in the correct section of the room list
		is_direct = room.is_direct,
		is_favorite = room.is_favorite,
		is_lowpriority = room.is_lowpriority,
		-- Store the space rooms to restore the space structure
		space_rooms = room.space_rooms,
		-- Store the members to correctly display rooms that the user is a member of
		members = room.members,
		typing = {},
		-- Reset the tracked status as no room is open on restore
		is_tracked = false,
		-- Store unread counts to display in the room list
		unread_notifications = room.unread_notifications,
		unread_highlights = room.unread_highlights,
		unread = room.unread,
		read_receipt = room.read_receipt,
	}
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
		refresh_token = matrix.client.refresh_token,
		expires_at = matrix.client.expires_at,
		refresh = matrix.client.refresh,
		last_save = os.time(),
	}

	for room_id, room in pairs(matrix.get_rooms()) do
		cache_to_save.rooms[room_id] = get_stripped_room(room)
	end

	return write_file(cache_path, cache_to_save) and write_file(data_path, data_to_save)
end

--- Read the saved OAuth client IDs
--- @return table<string, string> The client IDs, mapped by issuer
local function read_oauth_clients()
	local clients = read_file(oauth_clients_path)
	return type(clients) == "table" and clients or {}
end

--- Get the OAuth client ID registered for an issuer.
--- The client IDs are not part of the session, so they are kept after logging out and even
--- when `save_session` is off: they are not credentials, and losing them registers a new client on every login.
--- @param issuer string The OAuth issuer
--- @return string|nil The client ID, nil when none is saved
function M.get_oauth_client_id(issuer)
	local client_id = read_oauth_clients()[issuer]
	return type(client_id) == "string" and client_id or nil
end

--- Save the OAuth client ID registered for an issuer
--- @param issuer string The OAuth issuer
--- @param client_id string The client ID
--- @return boolean True if the client ID was saved successfully
function M.set_oauth_client_id(issuer, client_id)
	local clients = read_oauth_clients()
	clients[issuer] = client_id
	return write_file(oauth_clients_path, clients)
end

--- Forget the OAuth client ID of an issuer, so the next login registers again
--- @param issuer string The OAuth issuer
--- @return boolean True if the client ID is no longer saved
function M.clear_oauth_client_id(issuer)
	local clients = read_oauth_clients()
	if clients[issuer] == nil then
		return true
	end
	clients[issuer] = nil
	return write_file(oauth_clients_path, clients)
end

--- Read the saved session credentials without restoring them
--- @return table|nil The saved session data, nil when there is none
function M.read_saved_session()
	return read_file(data_path)
end

--- Restore the session data from the cache file
--- @return boolean, neoment.matrix.client.Client|nil True if the session was restored successfully, false otherwise
function M.restore_session()
	local cache = read_file(cache_path)
	local data = read_file(data_path)
	if not data or not data.access_token then
		return false
	end

	-- Check if the session data is too old (7 days).
	-- A session with a refresh token is bounded by the refresh token lifetime instead.
	local max_age = 7 * 24 * 60 * 60 -- 7 days in seconds
	if not data.refresh_token and data.last_save and os.time() - data.last_save > max_age then
		notify.warning("Session data is expired, please log in again")
		return false
	end

	-- Replace any client left by an unfinished login attempt
	matrix.set_homeserver(data.homeserver)
	matrix.client.access_token = data.access_token
	matrix.client.refresh_token = data.refresh_token
	matrix.client.expires_at = data.expires_at
	matrix.client.refresh = data.refresh
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

	notify.info("Matrix session restored for " .. matrix.client.user_id)

	return true
end

--- Clear the session data from the cache file
function M.clear_session()
	local cache_exists = vim.fn.filereadable(cache_path) == 1
	local data_exists = vim.fn.filereadable(data_path) == 1
	local ui_state_exists = vim.fn.filereadable(ui_state_path) == 1

	if not cache_exists and not data_exists and not ui_state_exists then
		notify.info("No session data found to remove")
		return true
	end

	if cache_exists then
		M.clear_cache()
	end

	if ui_state_exists then
		M.clear_ui_state()
	end

	if data_exists then
		-- Get information about the file before removing it
		local size_kb = math.floor(vim.fn.getfsize(data_path) / 1024)

		local success, err = os.remove(data_path)

		if not success then
			notify.error("Error removing session data: " .. (err or "unknown"))
			return false
		else
			notify.info("Neoment session data removed (" .. size_kb .. "KB)")
		end
	end
	return true
end

--- Clear the cache file
--- @return boolean True if the cache was cleared successfully, false otherwise
function M.clear_cache()
	local cache_exists = vim.fn.filereadable(cache_path) == 1
	if not cache_exists then
		notify.info("No cache file found to remove")
		return true
	end

	-- Get information about the file before removing it
	local size_kb = math.floor(vim.fn.getfsize(cache_path) / 1024)
	local success, err = os.remove(cache_path)
	if not success then
		notify.error("Error removing cache: " .. (err or "unknown"))
		return false
	end

	notify.info("Neoment cache removed (" .. size_kb .. "KB)")
	return true
end

--- Write a temporary file
--- @param name string The name of the file
--- @param url string The URL to fetch the file from
--- @param callback fun(path: neoment.Error<string, string>): any The callback to call with the result, either the path to the temporary file or an error message
--- @param headers? table<string, string> Headers to send with the request, like the Authorization of a media download
--- @param directory? string The directory to save the file in, instead of the temporary directory. It must exist.
M.fetch_to_temp = function(name, url, callback, headers, directory)
	vim.validate("name", name, "string")
	vim.validate("url", url, "string")

	-- Sanitize the name to ensure it's a valid filename
	name = name:gsub("[^%w%.%-_]", "_")

	-- Create the full path for the temporary file
	local temp_path = directory and vim.fs.joinpath(directory, name) or get_temp_path(name)

	-- Check if the file already exists
	if vim.fn.filereadable(temp_path) == 1 then
		return callback(error.ok(temp_path))
	end

	-- The file is only given its name once complete, so an interrupted download is never reused
	local part_path = temp_path .. ".part"

	curl.get(url, {
		output = part_path,
		headers = headers,
		on_error = function(err)
			os.remove(part_path)
			callback(error.err("Failed to download file: " .. (err.message or "Unknown error")))
		end,
		callback = function(response)
			-- The body of an error response was saved as the file, and would be reused as the download
			if response.status and response.status >= 400 then
				os.remove(part_path)
				return callback(error.err("Failed to download file: HTTP status " .. response.status))
			end

			if not os.rename(part_path, temp_path) then
				os.remove(part_path)
				return callback(error.err("Failed to save downloaded file"))
			end

			callback(error.ok(temp_path))
		end,
	})
end

--- The callbacks waiting for each image download in progress, by file name
--- @type table<string, fun(result: neoment.Error<string, string>)[]>
local image_downloads = {}

--- Get the source to give the image viewer for a media URL.
--- Media of the user's homeserver is downloaded with the access token in a header and given as a local file:
--- the viewer caches images by source, and a URL holding the token would change every time it is refreshed.
--- The file is named after the URL, so each image is downloaded once. Other URLs are given as they are.
--- The images may come from private rooms, so they are kept in a directory only the user can read.
--- @param url string The media URL
--- @param callback fun(result: neoment.Error<string, string>) Called in the main loop with the source.
M.fetch_image_source = function(url, callback)
	-- Rooms saved by an earlier version have URLs with a token that is no longer valid
	local bare_url = util.strip_access_token(url)
	local headers = util.media_headers(bare_url)
	if not headers then
		callback(error.ok(url))
		return
	end

	local name = "image-" .. vim.fn.sha256(bare_url):sub(1, 32)
	-- A second download would write to the same file, and the viewer could read it half written
	if image_downloads[name] then
		table.insert(image_downloads[name], callback)
		return
	end
	image_downloads[name] = { callback }

	if vim.fn.isdirectory(media_path) == 0 then
		vim.fn.mkdir(media_path, "p")
	end
	vim.uv.fs_chmod(media_path, tonumber("700", 8))

	M.fetch_to_temp(name, bare_url, function(result)
		vim.schedule(function()
			local callbacks = image_downloads[name] or {}
			image_downloads[name] = nil
			for _, waiting in ipairs(callbacks) do
				waiting(result)
			end
		end)
	end, headers, media_path)
end

--- Save the image from the clipboard to a temporary file
--- @return neoment.Error<string, string> The path to the temporary file or an error message
M.save_clipboard_image = function()
	local temp_file = get_temp_path(util.uuid() .. ".png")

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
		return error.err(error_msg)
	end

	-- Check if file was created and has content
	if vim.fn.filereadable(temp_file) == 0 or vim.fn.getfsize(temp_file) <= 0 then
		return error.err("Failed to save clipboard image to temporary file")
	end

	return error.ok(temp_file)
end

--- Save UI state (section fold states, etc.)
--- @param state table The UI state to save
--- @return boolean True if the state was saved successfully, false otherwise
function M.save_ui_state(state)
	local existing = read_file(ui_state_path) or {}
	local merged = vim.tbl_deep_extend("force", existing, state)
	return write_file(ui_state_path, merged)
end

--- Load UI state
--- @return table|nil The UI state or nil if not found
function M.load_ui_state()
	return read_file(ui_state_path)
end

--- Clear the UI state file
--- @return boolean True if the UI state was cleared successfully, false otherwise
function M.clear_ui_state()
	local ui_state_exists = vim.fn.filereadable(ui_state_path) == 1
	if not ui_state_exists then
		return true
	end

	local success, err = os.remove(ui_state_path)
	if not success then
		notify.error("Error removing UI state: " .. (err or "unknown"))
		return false
	end

	return true
end

return M
