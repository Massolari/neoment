local M = {}

local sync = require("neoment.sync")
local rooms = require("neoment.rooms")
local room = require("neoment.room")
local storage = require("neoment.storage")
local matrix = require("neoment.matrix")
local error = require("neoment.error")

--- Handle synchronization data
--- @param updated_rooms table<string> The list of the IDs of the updated rooms
local function handle_sync(updated_rooms)
	-- Update the rooms list
	vim.schedule(function()
		local rooms_id = rooms.get_buffer_id()
		if rooms_id and vim.api.nvim_buf_is_loaded(rooms_id) then
			rooms.update_room_list()
		end

		for _, room_id in ipairs(updated_rooms) do
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) then
					local buf_room_id = vim.b[buf].room_id
					--- @type string
					local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
					if buf_room_id == room_id and not filetype:match("neoment_compose") then
						room.update_buffer(buf)
					end
				end
			end
		end
	end)
end

--- Helper function to synchronize the client
M.sync_start = function()
	sync.start(matrix.client, handle_sync, {
		save_session = vim.g.neoment.save_session,
	})
end

--- Login to the Matrix server
local function login()
	local restored = storage.restore_session()
	if restored then
		M.sync_start()
		vim.schedule(function()
			rooms.toggle_room_list()
		end)
		return
	end
	local username = vim.fn.input("Username: ")
	local password = vim.fn.inputsecret("Password: ")

	matrix.login(username, password, function(data)
		if error.is_error(data) then
    		vim.schedule(function()
				vim.notify("Error logging in: " .. data.error.error, vim.log.levels.ERROR)
			end)
			return
		end

    	vim.schedule(function()
			vim.notify("Login successful as " .. matrix.client.user_id, vim.log.levels.INFO)
		end)

		-- Save the session if configured
		if vim.g.neoment.save_session then
			vim.schedule(function()
				storage.save_session()
			end)
		end

		-- Start synchronization
		M.sync_start()
		vim.schedule(function()
			rooms.toggle_room_list()
		end)
	end)
end

--- Entry point for the plugin
--- If already logged in, open the room list
--- If not logged in, call the login function
M.init = function()
	if matrix.is_logged_in() then
		rooms.toggle_room_list()
	else
		login()
	end
end

--- Logout from the Matrix server
M.logout = function()
	sync.stop()

	matrix.logout(function(logged_out)
		error.match(logged_out, function()
			storage.clear_session()

			collectgarbage("collect")
			vim.notify("Logout successful", vim.log.levels.INFO)
			return nil
		end, function(err)
			vim.notify("Logout failed: " .. err.error, vim.log.levels.ERROR)
		end)
	end)
end

return M
