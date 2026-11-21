local M = {}

local config = require("neoment.config")
local notified_about_unable_to_notify = false

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

--- Get the ID of a notification for use in replacement
--- Works with both snacks.nvim (table with id field) and nvim-notify (direct value)
--- @param notification any The notification object returned by with_opts
--- @return table opts Table with id and replace fields for use in with_opts
M.get_id = function(notification)
	local id = notification and (type(notification) == "table" and notification.id or notification)
	return {
		id = id, -- For snacks
		replace = notification, -- For nvim-notify
	}
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
		if vim.fn.executable("gdbus") == 0 then
			if not notified_about_unable_to_notify then
				M.warning(
					"Desktop notifications are enabled but 'gdbus' is not available. Please install 'gdbus' to receive notifications."
				)
				notified_about_unable_to_notify = true
				return
			end
		end
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

	-- Prefer structured mentions from the Matrix event, if available
	if type(message.mentions) == "table" then
		for _, mentioned_id in ipairs(message.mentions) do
			if mentioned_id == user_id then
				return true
			end
		end
		return false
	end

	-- Fallback to string-based detection for compatibility
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

--- The newest incoming message of each room seen in the current sync, used by the server source
--- @type table<string, neoment.matrix.client.Message>
local candidates = {}

--- The timestamp of the message shown by the last server-source notification of each room
--- @type table<string, integer>
local last_notified = {}

--- Check the conditions under which no desktop notification is sent, whatever the source
--- @param room neoment.matrix.client.Room The room to notify about
--- @return boolean True if the notification must be skipped
local function should_skip(room)
	if not config.get().desktop_notifications.enabled then
		return true
	end

	-- Check if this is the initial sync.
	-- If so, skip notifications to avoid spamming the user.
	local sync_status = require("neoment.sync").get_status()
	if sync_status.kind == "syncing" and sync_status.last_sync == nil then
		return true
	end

	-- The user is already looking at this room
	local has_focus = require("neoment.focus").is_focused()
	return has_focus and room.id == vim.b.room_id
end

--- Check if a message comes from another user and can be notified
--- @param message neoment.matrix.client.Message The message to check
--- @return boolean True if the message is not a state event and was not sent by the user
local function is_incoming(message)
	local user_id = require("neoment.matrix").get_user_id()
	return user_id ~= nil and not message.is_state and message.sender ~= user_id
end

--- Format the title of a desktop notification for a message
--- @param room neoment.matrix.client.Room The room where the message was sent
--- @param sender string The ID of the user who sent the message
--- @return string The title, with the room name unless it is the sender's name
local function format_title(room, sender)
	local sender_name = require("neoment.matrix").get_display_name(sender)
	-- If the sender has the same name as the room, it's a DM, show the sender's name only
	return sender_name == room.name and sender_name or string.format("[%s] %s", room.name, sender_name)
end

--- Decide a message notification with the levels in the config
--- @param room neoment.matrix.client.Room The room where the message was sent
--- @param message neoment.matrix.client.Message The message to display notification for
local function desktop_message_custom(room, message)
	local notifications_config = config.get().desktop_notifications
	local sender_with_room = format_title(room, message.sender)

	-- Buffer rooms
	if room.is_tracked then
		local handled =
			send_notification(notifications_config.buffer, notifications_config.handler, message, sender_with_room)
		if handled then
			return
		end
	end

	-- Per-room override
	local room_config = vim.iter({ room.id, room.aliases })
		:flatten()
		:map(function(id_alias)
			return notifications_config.per_room[id_alias]
		end)
		:totable()[1]

	if room_config then
		send_notification(room_config, notifications_config.handler, message, sender_with_room)
		return
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

--- Show a desktop notification for a message.
--- With the "server" source, the message is only kept as the room's candidate for the notification
--- sent by `room_counts_changed`.
--- @param room neoment.matrix.client.Room The room where the message was sent
--- @param message neoment.matrix.client.Message The message to display notification for
M.desktop_message = function(room, message)
	if not is_incoming(message) then
		return
	end

	if config.get().desktop_notifications.source == "server" then
		local candidate = candidates[room.id]
		if not candidate or message.timestamp >= candidate.timestamp then
			candidates[room.id] = message
		end
		return
	end

	if should_skip(room) then
		return
	end

	desktop_message_custom(room, message)
end

--- Find the newest stored message in a room that was not sent by the user and may still be unread:
--- newer than the user's read receipt and than the message of the room's last notification
--- @param room neoment.matrix.client.Room The room to search
--- @return neoment.matrix.client.Message? The newest such message, if any
local function newest_unread_incoming_message(room)
	local after = math.max(room.read_receipt and room.read_receipt.ts or 0, last_notified[room.id] or 0)
	local newest = nil
	for _, message in pairs(room.messages) do
		if
			is_incoming(message)
			and message.timestamp > after
			and (not newest or message.timestamp > newest.timestamp)
		then
			newest = message
		end
	end
	return newest
end

--- Show a desktop notification when a sync raises a room's notification or highlight count.
--- Only used by the "server" source, where the homeserver's push rules decide what notifies.
--- @param room neoment.matrix.client.Room The room whose counts changed
--- @param old neoment.matrix.UnreadNotificationCounts The counts before the sync
--- @param new neoment.matrix.UnreadNotificationCounts The counts reported by the sync
M.room_counts_changed = function(room, old, new)
	local candidate = candidates[room.id]
	candidates[room.id] = nil

	local notifications_config = config.get().desktop_notifications
	if notifications_config.source ~= "server" then
		return
	end

	local increased = (new.notification_count or 0) > (old.notification_count or 0)
		or (new.highlight_count or 0) > (old.highlight_count or 0)
	if not increased or should_skip(room) then
		return
	end

	local message = candidate or newest_unread_incoming_message(room)
	if message then
		last_notified[room.id] = message.timestamp
		notifications_config.handler(format_title(room, message.sender), message.content)
	else
		notifications_config.handler(room.name, "New notification")
	end
end

--- Forget the messages kept for the notifications of the current sync
M.clear_candidates = function()
	candidates = {}
end

return M
