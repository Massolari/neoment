--- @class vim.var_accessor
--- @field neoment neoment.config.Config

--- @class neoment.config.Config
--- @field save_session? boolean Whether to save and restore sessions
--- @field icon? neoment.config.Icon Icon configuration
--- @field notifier fun(msg: string, level: vim.log.levels, opts?: table): nil Function to show notifications
--- @field desktop_notifications? neoment.config.DesktopNotifications Configuration for desktop notifications
--- @field picker? neoment.config.Picker Picker configuration
--- @field rooms? neoment.config.Rooms

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

--- @class neoment.config.Rooms
--- @field display_last_message? neoment.config.DisplayLastMessage How to display the last message in the room list

--- @class neoment.config.DesktopNotifications
--- @field enabled? boolean Whether desktop notifications are enabled
--- @field handler? neoment.config.DesktopNotificationHandler Function to handle desktop notifications
--- @field buffer? neoment.config.DesktopNotificationLevel Notification level for buffer messages. When "none", it'll inherit from the other levels
--- @field favorites? neoment.config.DesktopNotificationLevel Notification level for favorite rooms
--- @field people? neoment.config.DesktopNotificationLevel Notification level for people rooms
--- @field rooms? neoment.config.DesktopNotificationLevel Notification level for non-favorite, non-direct rooms
--- @field per_room? table<string, neoment.config.DesktopNotificationLevel> Notification levels per room ID

--- @alias neoment.config.DesktopNotificationHandler fun(title: string, content: string): nil
--- @alias neoment.config.DesktopNotificationLevel "all"|"mentions"|"none"

--- @class neoment.config.InternalConfig
--- @field save_session boolean Whether to save and restore sessions
--- @field icon neoment.config.InternalIcon Icon configuration
--- @field notifier fun(msg: string, level: vim.log.levels, opts?: table): nil Function to show notifications
--- @field desktop_notifications neoment.config.InternalDesktopNotifications Configuration for desktop notifications
--- @field picker neoment.config.InternalPicker Picker configuration
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

--- @class neoment.config.InternalRooms
--- @field display_last_message neoment.config.DisplayLastMessage How to display the last message in the room list

--- @alias neoment.config.DisplayLastMessage "no"|"message"|"sender_message"|"sender_message_inline"

--- @class neoment.config.InternalDesktopNotifications
--- @field enabled boolean Whether desktop notifications are enabled
--- @field handler neoment.config.DesktopNotificationHandler Function to handle desktop notifications
--- @field buffer neoment.config.DesktopNotificationLevel Notification level for buffer messages. When "none", it'll inherit from the other levels
--- @field favorites neoment.config.DesktopNotificationLevel Notification level for favorite rooms
--- @field people neoment.config.DesktopNotificationLevel Notification level for people rooms
--- @field rooms neoment.config.DesktopNotificationLevel Notification level for non-favorite, non-direct rooms
--- @field per_room table<string, neoment.config.DesktopNotificationLevel> Notification levels per room ID

local M = {}

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
	rooms = {
		display_last_message = "message",
	},
}

--- @type neoment.config.InternalConfig
local config = vim.deepcopy(default)

M.load = function()
	local user_config = vim.g.neoment or {}

	config = vim.tbl_deep_extend("force", default, user_config)
end

--- @return neoment.config.InternalConfig
M.get = function()
	return config
end

return M
