local M = {}

local constants = require("neoment.constants")
local config = require("neoment.config")
local notify = require("neoment.notify")
local sync = require("neoment.sync")
local rooms = require("neoment.rooms")
local room = require("neoment.room")
local storage = require("neoment.storage")
local matrix = require("neoment.matrix")
local auth = require("neoment.matrix.auth")
local sso_listener = require("neoment.sso_listener")
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
					if buf_room_id == room_id and vim.bo[buf].filetype == constants.ROOM_FILETYPE then
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

--- Handle the result of a login attempt
--- @param data neoment.Error<nil, neoment.matrix.api.Error> The login result
local function handle_login_result(data)
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
end

--- @class neoment.LoginContext
--- @field homeserver string The homeserver base URL
--- @field user_id? string The full Matrix ID, if the user entered one

--- Redirect URL used for SSO when the browser can't reach a local listener.
--- The page fails to load, and the user copies the URL from the address bar.
local MANUAL_SSO_REDIRECT_URL = "http://127.0.0.1/"

--- The SSO callback listener of the login in progress, if any
--- @type neoment.sso_listener.Listener|nil
local pending_sso_listener = nil

--- Stop the SSO callback listener of the login in progress, if any
local function close_pending_sso_listener()
	if pending_sso_listener then
		pending_sso_listener.close()
		pending_sso_listener = nil
	end
end

--- Check if Neovim is running in a remote (SSH) session
--- @return boolean
local function is_remote_session()
	return vim.env.SSH_CONNECTION ~= nil or vim.env.SSH_TTY ~= nil
end

--- Ask the user to paste the URL they were redirected to (or the login token) and log in with it
local function prompt_login_token()
	vim.ui.input({ prompt = "Paste the redirected URL or login token: " }, function(input)
		local token = auth.parse_login_token(input)
		if not token then
			notify.info("Login cancelled")
			return
		end

		auth.login_token(token, handle_login_result)
	end)
end

--- Log in with SSO by pasting the redirected URL
--- @param ctx neoment.LoginContext
local function manual_sso_login(ctx)
	local url = auth.sso_redirect_url(ctx.homeserver, MANUAL_SSO_REDIRECT_URL)
	notify.info(
		"Open this URL in your browser and log in. The page you are sent to will fail to load; copy its URL from the address bar:\n"
			.. url
	)
	-- Notifications are scheduled, so schedule the prompt to show it after the URL
	vim.schedule(prompt_login_token)
end

--- Log in with SSO through the browser
--- @param ctx neoment.LoginContext
local function sso_login(ctx)
	if is_remote_session() then
		manual_sso_login(ctx)
		return
	end

	local listener_result = sso_listener.start({
		on_token = function(token)
			pending_sso_listener = nil
			auth.login_token(token, handle_login_result)
		end,
		on_timeout = function()
			pending_sso_listener = nil
			notify.warning("Did not receive the login from the browser")
			manual_sso_login(ctx)
		end,
	})

	if error.is_error(listener_result) then
		notify.warning(listener_result.error)
		manual_sso_login(ctx)
		return
	end

	pending_sso_listener = listener_result.data
	local url = auth.sso_redirect_url(ctx.homeserver, string.format("http://127.0.0.1:%d/", pending_sso_listener.port))
	local _, open_error = vim.ui.open(url)
	if open_error then
		notify.warning("Could not open the browser (" .. open_error .. "). Open this URL to log in:\n" .. url)
	else
		notify.info("Waiting for the login in the browser...")
	end
end

--- Log in with a username and password
--- @param ctx neoment.LoginContext
local function password_login(ctx)
	local user = ctx.user_id
	if not user then
		user = vim.trim(vim.fn.input("Username: "))
		if user == "" then
			notify.info("Login cancelled")
			return
		end
	end

	local password = vim.fn.inputsecret("Password: ")
	if password == "" then
		notify.info("Login cancelled")
		return
	end

	auth.login_password(user, password, handle_login_result)
end

--- Login handlers, mapped by login method
--- @type table<neoment.matrix.auth.Method, fun(ctx: neoment.LoginContext)>
local LOGIN_HANDLERS = {
	password = password_login,
	sso = sso_login,
}

--- Labels shown when the user chooses a login method
--- @type table<neoment.matrix.auth.Method, string>
local LOGIN_METHOD_LABELS = {
	password = "Password",
	sso = "Single Sign-On (browser)",
}

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

	close_pending_sso_listener()

	local input = vim.fn.input("Matrix ID or server: ")
	local server_name, user_id = auth.parse_server_name(input)
	if not server_name then
		if vim.trim(input) == "" then
			notify.info("Login cancelled")
		else
			notify.error("Invalid Matrix ID or server: " .. input)
		end
		return
	end

	auth.discover(server_name, function(homeserver)
		matrix.set_homeserver(homeserver)

		auth.get_login_flows(homeserver, function(result)
			vim.schedule(function()
				if error.is_error(result) then
					notify.error(result.error.error)
					return
				end

				--- @type neoment.LoginContext
				local ctx = { homeserver = homeserver, user_id = user_id }
				local methods = result.data
				if #methods == 1 then
					LOGIN_HANDLERS[methods[1]](ctx)
					return
				end

				vim.ui.select(methods, {
					prompt = "Login method:",
					format_item = function(method)
						return LOGIN_METHOD_LABELS[method]
					end,
				}, function(method)
					if not method then
						notify.info("Login cancelled")
						return
					end
					LOGIN_HANDLERS[method](ctx)
				end)
			end)
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
--- @param room_id_or_alias_or_user_id string The room ID, alias, or user ID (for DMs) to join
M.join_room = function(room_id_or_alias_or_user_id)
	if not matrix.is_logged_in() then
		notify.error("Not logged in")
		return
	end

	-- Check if it is a user ID (Direct Message)
	if room_id_or_alias_or_user_id:match("^@") then
		local target_user_id = room_id_or_alias_or_user_id
		local current_user_id = matrix.get_user_id()

		-- Check if a DM already exists
		local existing_dm_room_id = nil
		for _, user_room in pairs(matrix.get_user_rooms()) do
			local members = matrix.get_room_members(user_room.id)
			if vim.tbl_count(members) == 2 and members[target_user_id] and members[current_user_id] then
				existing_dm_room_id = user_room.id
				break
			end
		end

		if existing_dm_room_id then
			notify.info("Opening existing DM with " .. target_user_id)
			vim.schedule(function()
				rooms.open_room(existing_dm_room_id)
			end)
			return
		end

		-- Create new DM
		notify.info("Creating DM with " .. target_user_id .. "...")
		matrix.create_room({
			invite = { target_user_id },
			is_direct = true,
			preset = "trusted_private_chat",
		}, function(response)
			error.match(response, function(room_id)
				notify.info("Created DM with " .. target_user_id)
				vim.schedule(function()
					rooms.open_room(room_id)
				end)
				return nil
			end, function(err)
				notify.error("Failed to create DM: " .. err.error)
			end)
		end)
		return
	end

	local existing_room_id = nil
	if room_id_or_alias_or_user_id:match("^!") then
		if matrix.is_user_member_of_room(room_id_or_alias_or_user_id) then
			existing_room_id = room_id_or_alias_or_user_id
		end
	else
		for _, user_room in pairs(matrix.get_user_rooms()) do
			local aliases = matrix.get_room_aliases(user_room.id)
			if vim.tbl_contains(aliases, room_id_or_alias_or_user_id) then
				existing_room_id = user_room.id
				break
			end
		end
	end

	if existing_room_id then
		notify.info("Room " .. room_id_or_alias_or_user_id .. " already joined. Opening...")
		vim.schedule(function()
			rooms.open_room(existing_room_id)
		end)
		return
	end

	matrix.join_room(room_id_or_alias_or_user_id, function(join_response)
		error.match(join_response, function(room_id)
			notify.info("Successfully joined room " .. room_id_or_alias_or_user_id)
			vim.schedule(function()
				rooms.open_room(room_id)
			end)
			return nil
		end, function(err)
			notify.error("Failed to join room " .. room_id_or_alias_or_user_id .. ": " .. err.error)
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
