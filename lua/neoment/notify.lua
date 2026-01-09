local M = {}

local config = require("neoment.config")

--- Show a notification with Neoment prefix
--- @param msg string The message to display
--- @param level vim.log.levels The log level
local function notify(msg, level)
	vim.schedule(function()
		config.get().notifier("[Neoment] " .. msg, level)
	end)
end

--- Show a info notification
--- @param msg string The message to display
M.info = function(msg)
	notify(msg, vim.log.levels.INFO)
end

--- Show a warning notification
--- @param msg string The message to display
M.warning = function(msg)
	notify(msg, vim.log.levels.WARN)
end

--- Show an error notification
--- @param msg string The message to display
M.error = function(msg)
	notify(msg, vim.log.levels.ERROR)
end

--- Show a notification with options
--- Note: This function is run outside of vim.schedule, so be careful when using it in async contexts.
--- @param msg string The message to display
--- @param level vim.log.levels The log level
--- @param opts table Additional options for vim.notify
M.with_opts = function(msg, level, opts)
	return config.get().notifier("[Neoment] " .. msg, level, opts)
end

local powershell_cmd = [[& {
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null;
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null;

$Path = (Get-Item (Get-Command "nvim").Source).Directory.Parent.FullName;
$Icon = "$Path\share\icons\hicolor\128x128\apps\nvim.png";

$Xml = [Windows.Data.Xml.Dom.XmlDocument]::New();
$Xml.LoadXml(@"
<toast activationType="protocol">
  <visual>
    <binding template="ToastGeneric">
      <text hint-maxLines="1">$([Security.SecurityElement]::Escape(%q))</text>
      <text>$([Security.SecurityElement]::Escape(%q))</text>
      <image src="$Icon" placement="appLogoOverride"/>
    </binding>
  </visual>
</toast>
"@);

$Toast = [Windows.UI.Notifications.ToastNotification]::New($Xml);
$Toast.Priority = 1;
$Toast.Tag = "Neoment";
$Toast.Group = "Neovim";

[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Neoment").Show($Toast);
}]]

M.desktop = function(title, content)
	if jit.os == "Linux" or jit.os == "BSD" then
		vim.system({
			"gdbus",
			"call",
			"--session",
			"--dest=org.freedesktop.Notifications",
			"--object-path=/org/freedesktop/Notifications",
			"--method=org.freedesktop.Notifications.Notify",
			"--",
			"Neoment",
			"0",
			"neoment",
			title,
			content,
			"[]",
			string.format("{%s, %s}", '"urgency": <byte 1>', '"desktop-entry": <string "nvim">'),
			"-1",
		})
	elseif jit.os == "Windows" then
		vim.system({
			"powershell",
			"-NoProfile",
			"-Command",
			string.format(powershell_cmd, title, content),
		})
	elseif jit.os == "OSX" then
		vim.system({
			"osascript",
			"-e",
			[[
          on run argv
            display notification (item 1 of argv) with title "Neoment" subtitle (item 2 of argv)
          end run
         ]],
			"--",
			content,
			title,
		})
	end
end

--- Check if the message has a mention of the user
--- @param message neoment.matrix.client.Message The message to check
--- @return boolean True if the message mentions the user, false otherwise
local function message_has_mention(message)
	local user_id = require("neoment.matrix").get_user_id()
	if not user_id then
		return false
	end

	return string.find(message.formatted_content or message.content, user_id, 1, true) ~= nil
end

--- Send notification based on user notification level
--- @param level neoment.config.DesktopNotificationLevel
--- @param handler neoment.config.DesktopNotificationHandler
--- @param message neoment.matrix.client.Message
--- @param sender string
--- @return boolean True if the level was handled, false otherwise (the level is "none")
local function send_notification(level, handler, message, sender)
	if level == "all" then
		handler(sender, message.content)
		return true
	elseif level == "mentions" then
		if message_has_mention(message) then
			handler(sender, message.content)
		end
		return true
	end
	return false
end

--- Show a desktop notification for a message
--- @param room neoment.matrix.client.Room The room where the message was sent
--- @param message neoment.matrix.client.Message The sender of the message
M.desktop_message = function(room, message)
	local notifications_config = config.get().desktop_notifications
	if not notifications_config.enabled then
		return
	end

	local user_id = require("neoment.matrix").get_user_id()
	if not user_id or message.is_state or message.sender == user_id then
		return
	end

	local sender_name = require("neoment.matrix").get_display_name(message.sender)
	-- If the sender has the same name as the room, it's a DM, show the sender's name only
	local sender_with_room = sender_name == room.name and sender_name
		or string.format("[%s] %s", room.name, sender_name)

	-- Buffer rooms
	if room.is_tracked then
		local current_buf_room_id = vim.b.room_id
		local has_focus = require("neoment.focus").is_focused()
		local is_current_room = room.id == current_buf_room_id
		if has_focus and is_current_room then
			return
		end

		local handled =
			send_notification(notifications_config.buffer, notifications_config.handler, message, sender_with_room)
		if handled then
			return
		end
	end

	-- Favorite rooms
	if room.is_favorite then
		send_notification(notifications_config.favorites, notifications_config.handler, message, sender_with_room)
	elseif room.is_direct then
		send_notification(notifications_config.people, notifications_config.handler, message, sender_with_room)
	else
		-- Other rooms
		send_notification(notifications_config.rooms, notifications_config.handler, message, sender_with_room)
	end
end

return M
