--- @class vim.var_accessor
--- @field neoment neoment.config.Config

--- @class neoment.config.Config
--- @field save_session? boolean Whether to save and restore sessions
--- @field login_method? neoment.config.LoginMethod Force a login method instead of preferring OAuth and asking when several are offered
--- @field icon? neoment.config.Icon Icon configuration
--- @field notifier fun(msg: string, level: vim.log.levels, opts?: table): nil Function to show notifications
--- @field desktop_notifications? neoment.config.DesktopNotifications Configuration for desktop notifications
--- @field picker? neoment.config.Picker Picker configuration
--- @field room? neoment.config.Room
--- @field rooms? neoment.config.Rooms

--- @alias neoment.config.LoginMethod "password"|"sso"|"oauth_device"

--- @alias neoment.config.PickerFunction fun(items: neoment.config.PickerRoom[], callback: fun(room: neoment.matrix.client.Room), options: neoment.config.PickerOptions): nil

--- @class neoment.config.PickerOptions
--- @field prompt string Prompt to show in the picker

--- @class neoment.config.Picker
--- @field rooms? neoment.config.PickerFunction Custom picker for rooms
--- @field open_rooms? neoment.config.PickerFunction Custom picker for open rooms

--- @class neoment.config.PickerRoom
--- @field room neoment.matrix.client.Room The room object
--- @field line string The line to display in the picker

--- @class neoment.config.Icon
--- @field invite? string Icon for invites
--- @field buffer? string Icon for buffers
--- @field favorite? string Icon for favorites
--- @field people? string Icon for people
--- @field space? string Icon for spaces
--- @field room? string Icon for rooms
--- @field low_priority? string Icon for low priority rooms
--- @field reply? string Icon for replies
--- @field right_arrow? string Icon for right arrow
--- @field down_arrow? string Icon for down arrow
--- @field down_arrow_circle? string Icon for down arrow in a circle
--- @field bell? string Icon for notifications
--- @field dot? string Icon for dot
--- @field dot_circle? string Icon for dot in a circle
--- @field vertical_bar? string Icon for vertical bar
--- @field vertical_bar_thick? string Icon for thick vertical bar
--- @field tree_branch? string Icon for tree branch
--- @field image? string Icon for images
--- @field file? string Icon for files
--- @field audio? string Icon for audio files
--- @field location? string Icon for location
--- @field video? string Icon for video files

--- @class neoment.config.Room
--- @field on_open_attachment? neoment.config.RoomOpenAttachmentHandler Function to handle opening attachments

--- @class neoment.config.Rooms
--- @field display_last_message? neoment.config.DisplayLastMessage How to display the last message in the room list
--- @field room_title_format? neoment.config.RoomTitleFormat How to format room titles in the room list

--- @class neoment.config.DesktopNotifications
--- @field enabled? boolean Whether desktop notifications are enabled
--- @field source? neoment.config.DesktopNotificationSource What decides which messages notify: the account's push rules ("server") or the levels below ("custom")
--- @field handler? neoment.config.DesktopNotificationHandler Function to handle desktop notifications
--- @field buffer? neoment.config.DesktopNotificationLevel Notification level for buffer messages. When "none", it'll inherit from the other levels
--- @field favorites? neoment.config.DesktopNotificationLevel Notification level for favorite rooms
--- @field people? neoment.config.DesktopNotificationLevel Notification level for people rooms
--- @field rooms? neoment.config.DesktopNotificationLevel Notification level for non-favorite, non-direct rooms
--- @field per_room? table<string, neoment.config.DesktopNotificationLevel> Notification levels per room ID or alias

--- @alias neoment.config.DesktopNotificationHandler fun(title: string, content: string): nil
--- @alias neoment.config.DesktopNotificationLevel "all"|"mentions"|"none"
--- @alias neoment.config.DesktopNotificationSource "server"|"custom"

--- @class neoment.config.InternalConfig
--- @field save_session boolean Whether to save and restore sessions
--- @field login_method? neoment.config.LoginMethod Force a login method instead of preferring OAuth and asking when several are offered
--- @field icon neoment.config.InternalIcon Icon configuration
--- @field notifier fun(msg: string, level: vim.log.levels, opts?: table): nil Function to show notifications
--- @field desktop_notifications neoment.config.InternalDesktopNotifications Configuration for desktop notifications
--- @field picker neoment.config.InternalPicker Picker configuration
--- @field room neoment.config.InternalRoom
--- @field rooms neoment.config.InternalRooms

--- @class neoment.config.InternalPicker
--- @field rooms neoment.config.PickerFunction Custom picker for rooms
--- @field open_rooms neoment.config.PickerFunction Custom picker for open rooms

--- @class neoment.config.InternalIcon
--- @field invite string Icon for invites
--- @field buffer string Icon for buffers
--- @field favorite string Icon for favorites
--- @field people string Icon for people
--- @field space string Icon for spaces
--- @field room string Icon for rooms
--- @field low_priority string Icon for low priority rooms
--- @field reply string Icon for replies
--- @field right_arrow string Icon for right arrow
--- @field down_arrow string Icon for down arrow
--- @field down_arrow_circle string Icon for down arrow in a circle
--- @field bell string Icon for notifications
--- @field dot string Icon for dot
--- @field dot_circle string Icon for dot in a circle
--- @field vertical_bar string Icon for vertical bar
--- @field vertical_bar_thick string Icon for thick vertical bar
--- @field tree_branch string Icon for tree branch
--- @field image string Icon for images
--- @field file string Icon for files
--- @field audio string Icon for audio files
--- @field location string Icon for location
--- @field video string Icon for video files

--- @class neoment.config.InternalRoom
--- @field on_open_attachment neoment.config.RoomOpenAttachmentHandler Function to handle opening attachments

--- @alias neoment.config.RoomOpenAttachmentHandler fun(path: string, attachment: neoment.matrix.client.MessageAttachment): nil

--- @class neoment.config.InternalRooms
--- @field display_last_message neoment.config.DisplayLastMessage How to display the last message in the room list
--- @field room_title_format neoment.config.RoomTitleFormat How to format room titles in the room list

--- @alias neoment.config.DisplayLastMessage "no"|"message"|"sender_message"|"sender_message_inline"
--- @alias neoment.config.RoomTitleFormat "space_room"|"room"|"room_space"

--- @class neoment.config.InternalDesktopNotifications
--- @field enabled boolean Whether desktop notifications are enabled
--- @field source neoment.config.DesktopNotificationSource What decides which messages notify: the account's push rules ("server") or the levels below ("custom")
--- @field handler neoment.config.DesktopNotificationHandler Function to handle desktop notifications
--- @field buffer neoment.config.DesktopNotificationLevel Notification level for buffer messages. When "none", it'll inherit from the other levels
--- @field favorites neoment.config.DesktopNotificationLevel Notification level for favorite rooms
--- @field people neoment.config.DesktopNotificationLevel Notification level for people rooms
--- @field rooms neoment.config.DesktopNotificationLevel Notification level for non-favorite, non-direct rooms
--- @field per_room table<string, neoment.config.DesktopNotificationLevel> Notification levels per room ID or alias

local M = {}

--- The values accepted by the `login_method` option
local LOGIN_METHODS = { "password", "sso", "oauth_device" }

--- The values accepted by the `desktop_notifications.source` option
local NOTIFICATION_SOURCES = { "server", "custom" }

--- The `desktop_notifications` keys that only apply to the "custom" source
local CUSTOM_NOTIFICATION_KEYS = { "buffer", "favorites", "people", "rooms", "per_room" }

--- Whether the warning about custom levels under the default source was already shown
local warned_about_custom_levels = false

--- Default picker for rooms using vim.ui.select
--- @param items neoment.config.PickerRoom[]
--- @param callback fun(room: neoment.matrix.client.Room)
--- @param options neoment.config.PickerOptions
local function default_room_picker(items, callback, options)
	vim.ui.select(items, {
		prompt = options.prompt,
		format_item = function(item)
			return item.line
		end,
	}, function(choice)
		if choice then
			callback(choice.room)
		end
	end)
end

--- @type neoment.config.InternalConfig
local default = {
	save_session = true,
	icon = {
		invite = "",
		buffer = "󰮫",
		favorite = "",
		people = "",
		space = "󰴖",
		room = "󰮧",
		low_priority = "󰘄",
		reply = "↳",
		right_arrow = "▶",
		down_arrow = "▼",
		down_arrow_circle = "",
		bell = "󰵛",
		dot = "•",
		dot_circle = "",
		vertical_bar = "│",
		vertical_bar_thick = "┃",
		tree_branch = "├",
		image = "󰋩",
		file = "󰈙",
		audio = "",
		location = "󰍎",
		video = "",
	},
	notifier = vim.notify,
	desktop_notifications = {
		enabled = true,
		source = "server",
		handler = function(title, content)
			require("neoment.notify").desktop(title, content)
		end,
		buffer = "all",
		favorites = "all",
		people = "all",
		rooms = "mentions",
		per_room = {},
	},
	picker = {
		rooms = default_room_picker,
		open_rooms = default_room_picker,
	},
	room = {
		on_open_attachment = function(path, attachment)
			if vim.fn.executable("mpv") == 1 and attachment.type == "audio" then
				vim.cmd("belowright split")
				vim.cmd.resize(3)
				vim.cmd.terminal("mpv " .. vim.fn.shellescape(path))
				vim.cmd.startinsert()
				return
			end
			vim.ui.open(path)
		end,
	},
	rooms = {
		display_last_message = "message",
		room_title_format = "room_space",
	},
}

--- @type neoment.config.InternalConfig
local config = vim.deepcopy(default)

M.load = function()
	local user_config = vim.g.neoment or {}

	config = vim.tbl_deep_extend("force", default, user_config)

	vim.validate("login_method", config.login_method, function(value)
		return value == nil or vim.tbl_contains(LOGIN_METHODS, value)
	end, "one of " .. table.concat(LOGIN_METHODS, ", "))

	vim.validate("desktop_notifications.source", config.desktop_notifications.source, function(value)
		return vim.tbl_contains(NOTIFICATION_SOURCES, value)
	end, "one of " .. table.concat(NOTIFICATION_SOURCES, ", "))

	-- The custom levels used to apply on their own; tell users who set them that the default changed
	local user_notifications = user_config.desktop_notifications or {}
	if not warned_about_custom_levels and user_notifications.source == nil then
		local has_custom_levels = vim.iter(CUSTOM_NOTIFICATION_KEYS):any(function(key)
			return user_notifications[key] ~= nil
		end)
		if has_custom_levels then
			warned_about_custom_levels = true
			require("neoment.notify").warning(
				"The desktop_notifications levels (buffer, favorites, people, rooms, per_room) are ignored because notifications now follow your Matrix push rules. Set desktop_notifications.source = \"custom\" to use them."
			)
		end
	end
end

--- @return neoment.config.InternalConfig
M.get = function()
	return config
end

return M
