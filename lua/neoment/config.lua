--- @class vim.var_accessor
--- @field neoment neoment.Config

--- @class neoment.Config
--- @field save_session? boolean Whether to save and restore sessions
--- @field icon? neoment.IconConfig Icon configuration
--- @field notifier fun(msg: string, level: vim.log.levels, opts?: table): nil Function to show notifications

--- @class neoment.IconConfig
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

--- @class neoment.InternalConfig
--- @field save_session boolean Whether to save and restore sessions
--- @field icon neoment.InternalIconConfig Icon configuration
--- @field notifier fun(msg: string, level: vim.log.levels, opts?: table): nil Function to show notifications

--- @class neoment.InternalIconConfig
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

local M = {}

--- @type neoment.InternalConfig
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
}

--- @type neoment.InternalConfig
local config = vim.deepcopy(default)

M.load = function()
	local user_config = vim.g.neoment or {}

	config = vim.tbl_deep_extend("force", default, user_config)
end

--- @return neoment.InternalConfig
M.get = function()
	return config
end

return M
