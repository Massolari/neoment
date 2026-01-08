local M = {}

local config = require("neoment.config")
local notify = require("neoment.notify")
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
		save_session = config.get().save_session,
	})
	notify.info("Synchronization started")
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
				notify.error("Error logging in: " .. data.error.error)
			end)
			return
		end

		vim.schedule(function()
			notify.info("Login successful as " .. matrix.client.user_id)
		end)

		-- Save the session if configured
		if config.get().save_session then
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
	local highlight = require("neoment.highlight")
	highlight.define_highlights()
	config.load()
	require("neoment.focus").setup()

	vim.api.nvim_create_autocmd({ "ColorScheme" }, {
		group = vim.api.nvim_create_augroup("neoment_highlight", { clear = true }),
		pattern = { "*" },
		callback = highlight.define_highlights,
	})

	if matrix.is_logged_in() then
		rooms.toggle_room_list()
	else
		login()
	end
end

--- Join a room by its ID or alias
--- @param room_id_or_alias string The room ID (!room:server.com) or alias (#alias:server.com)
M.join_room = function(room_id_or_alias)
	if not matrix.is_logged_in() then
		notify.error("Not logged in")
		return
	end

	matrix.join_room(room_id_or_alias, function(join_response)
		error.match(join_response, function(room_id)
			notify.info("Successfully joined room " .. room_id_or_alias)
			vim.schedule(function()
				rooms.open_room(room_id)
			end)
			return nil
		end, function(err)
			notify.error("Failed to join room " .. room_id_or_alias .. ": " .. err.error)
		end)
	end)
end

--- Logout from the Matrix server
M.logout = function()
	sync.stop()

	matrix.logout(function(logged_out)
		error.match(logged_out, function()
			storage.clear_session()

			collectgarbage("collect")
			notify.info("Logout successful")
			return nil
		end, function(err)
			notify.error("Logout failed: " .. err.error)
		end)
	end)
end

return M
