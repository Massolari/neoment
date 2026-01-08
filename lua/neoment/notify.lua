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

M.desktop_message = function(sender, content)
	local notifier = config.get().desktop_notifier
	if notifier then
		notifier(require("neoment.matrix").get_display_name(sender), content)
	end
end

return M
