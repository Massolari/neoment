local M = {}

local error = require("neoment.error")
local matrix = require("neoment.matrix")
local notify = require("neoment.notify")
local config = require("neoment.config")

--- @alias neoment.notification_settings.GlobalLevel "all"|"mentions"
--- @alias neoment.notification_settings.RoomLevel "global"|"all"|"mentions"|"none"
--- @alias neoment.notification_settings.Category "one_to_one"|"group"

--- @class neoment.notification_settings.GlobalLevels
--- @field one_to_one neoment.notification_settings.GlobalLevel The level of rooms with two members
--- @field group neoment.notification_settings.GlobalLevel The level of rooms with three or more members

--- The labels of the levels, as Element shows them
local LEVEL_LABELS = {
	global = "Global settings",
	all = "All messages",
	mentions = "Mentions and replies only",
	none = "None",
}

--- The server-default underride rules of each global category: the plain one first, then the encrypted one
--- @type table<neoment.notification_settings.Category, string[]>
local CATEGORY_RULES = {
	one_to_one = { ".m.rule.room_one_to_one", ".m.rule.encrypted_room_one_to_one" },
	group = { ".m.rule.message", ".m.rule.encrypted" },
}

--- The headers of the global categories in the global window
local CATEGORY_HEADERS = {
	one_to_one = "One-to-one rooms (2 members)",
	group = "Group rooms (3+ members)",
}

local MARK_SELECTED = "(•)"
local MARK_UNSELECTED = "( )"
local CUSTOM_SOURCE_NOTICE =
	'Desktop notifications follow the desktop_notifications config (source = "custom"), not these settings.'

local namespace = vim.api.nvim_create_namespace("neoment_notification_settings")

--- The tweak that makes a notification play the default sound
local SOUND_TWEAK = { set_tweak = "sound", value = "default" }

--- Find a rule by ID in one kind of the ruleset
--- @param rules neoment.matrix.client.PushRuleset|nil
--- @param kind neoment.matrix.client.PushRuleKind
--- @param rule_id string
--- @return neoment.matrix.client.PushRule|nil
local function find_rule(rules, kind, rule_id)
	local kind_rules = rules and rules.global and rules.global[kind] or {}
	for _, rule in ipairs(kind_rules) do
		if rule.rule_id == rule_id then
			return rule
		end
	end
	return nil
end

--- Check if a rule notifies. The legacy "dont_notify" action and no action both mean it does not.
--- @param rule neoment.matrix.client.PushRule
--- @return boolean
local function notifies(rule)
	return vim.tbl_contains(rule.actions or {}, "notify")
end

--- Check if an override rule is the mute rule for a room: a single condition matching the room ID
--- @param rule neoment.matrix.client.PushRule
--- @param room_id string
--- @return boolean
local function is_room_mute_rule(rule, room_id)
	local conditions = rule.conditions or {}
	local condition = conditions[1]
	return #conditions == 1
		and condition.kind == "event_match"
		and condition.key == "room_id"
		and condition.pattern == room_id
		and not notifies(rule)
end

--- Get the global level of each room category
--- @param rules neoment.matrix.client.PushRuleset|nil
--- @return neoment.notification_settings.GlobalLevels
M.get_global_levels = function(rules)
	--- @param category neoment.notification_settings.Category
	--- @return neoment.notification_settings.GlobalLevel
	local function level_of(category)
		local rule = find_rule(rules, "underride", CATEGORY_RULES[category][1])
		return rule and rule.enabled and notifies(rule) and "all" or "mentions"
	end

	return { one_to_one = level_of("one_to_one"), group = level_of("group") }
end

--- Get the level a room sets for itself
--- @param rules neoment.matrix.client.PushRuleset|nil
--- @param room_id string
--- @return neoment.notification_settings.RoomLevel
M.get_room_level = function(rules, room_id)
	local override = find_rule(rules, "override", room_id)
	if override and override.enabled and is_room_mute_rule(override, room_id) then
		return "none"
	end

	local room_rule = find_rule(rules, "room", room_id)
	if room_rule and room_rule.enabled then
		return notifies(room_rule) and "all" or "mentions"
	end

	return "global"
end

--- Get the category a room falls in for push rules.
--- The server's one-to-one rule matches rooms with two joined members, whatever Neoment's direct flag says.
--- The flag is only used until a sync delivers the member count.
--- @param room neoment.matrix.client.Room
--- @return neoment.notification_settings.Category
local function get_room_category(room)
	if room.joined_member_count then
		return room.joined_member_count == 2 and "one_to_one" or "group"
	end
	return room.is_direct and "one_to_one" or "group"
end

--- Get the global level that applies to a room
--- @param rules neoment.matrix.client.PushRuleset|nil
--- @param room neoment.matrix.client.Room
--- @return neoment.notification_settings.GlobalLevel
M.get_applied_global_level = function(rules, room)
	return M.get_global_levels(rules)[get_room_category(room)]
end

--- Run asynchronous steps one after the other, stopping at the first error
--- @param steps table<fun(cb: fun(result: neoment.Error<any, neoment.matrix.api.Error>))>
--- @param callback fun(result: neoment.Error<nil, neoment.matrix.api.Error>)
local function run_steps(steps, callback)
	local index = 0
	local function next_step(result)
		if result and error.is_error(result) then
			callback(result)
			return
		end
		index = index + 1
		if index > #steps then
			callback(error.ok(nil))
			return
		end
		steps[index](next_step)
	end
	next_step()
end

--- Run the steps of a change, then re-fetch the push rules whatever the outcome, so they hold the server state.
--- When only the re-fetch fails, the error has `saved = true`.
--- @param steps table<fun(cb: fun(result: neoment.Error<any, neoment.matrix.api.Error>))>
--- @param callback fun(result: neoment.Error<nil, neoment.matrix.api.Error>)
local function apply_and_refresh(steps, callback)
	run_steps(steps, function(change_result)
		matrix.fetch_push_rules(function(fetch_result)
			if error.is_error(change_result) then
				callback(change_result)
				return
			end
			if error.is_error(fetch_result) then
				-- The change was applied, only the reload failed
				callback(error.err(vim.tbl_extend("force", fetch_result.error, { saved = true })))
				return
			end
			callback(error.ok(nil))
		end)
	end)
end

--- Set the global level of a room category, on both its plain and encrypted rule
--- @param category neoment.notification_settings.Category
--- @param level neoment.notification_settings.GlobalLevel
--- @param callback fun(result: neoment.Error<nil, neoment.matrix.api.Error>)
M.set_global_level = function(category, level, callback)
	local rules = matrix.get_push_rules()
	local actions = {}
	if level == "all" then
		-- One-to-one rooms keep the sound of the server defaults, as Element does
		actions = category == "one_to_one" and { "notify", SOUND_TWEAK } or { "notify" }
	end
	local steps = {}

	for _, rule_id in ipairs(CATEGORY_RULES[category]) do
		-- Older servers may not have every rule, and server-default rules cannot be created
		if find_rule(rules, "underride", rule_id) then
			table.insert(steps, function(cb)
				matrix.set_push_rule_actions("underride", rule_id, actions, cb)
			end)
			table.insert(steps, function(cb)
				matrix.set_push_rule_enabled("underride", rule_id, true, cb)
			end)
		end
	end

	apply_and_refresh(steps, callback)
end

--- Set the level of a room.
--- The rule for the new level is created first, so a failure part-way leaves the room on a chosen level.
--- @param room_id string
--- @param level neoment.notification_settings.RoomLevel
--- @param callback fun(result: neoment.Error<nil, neoment.matrix.api.Error>)
M.set_room_level = function(room_id, level, callback)
	local rules = matrix.get_push_rules()
	local steps = {}

	--- Create or replace a rule, and enable it: replacing a rule keeps its enabled flag
	--- @param kind neoment.matrix.client.PushRuleKind
	--- @param body table
	local function put_rule(kind, body)
		table.insert(steps, function(cb)
			matrix.set_push_rule(kind, room_id, body, cb)
		end)
		local existing = find_rule(rules, kind, room_id)
		if existing and existing.enabled == false then
			table.insert(steps, function(cb)
				matrix.set_push_rule_enabled(kind, room_id, true, cb)
			end)
		end
	end

	if level == "none" then
		put_rule("override", {
			conditions = { { kind = "event_match", key = "room_id", pattern = room_id } },
			actions = {},
		})
	elseif level == "all" or level == "mentions" then
		-- Element reads a room rule as "All messages" only when it has a sound
		put_rule("room", { actions = level == "all" and { "notify", SOUND_TWEAK } or {} })
	end

	-- Only delete the rules that exist, to avoid errors for missing ones
	if level ~= "none" and find_rule(rules, "override", room_id) then
		table.insert(steps, function(cb)
			matrix.delete_push_rule("override", room_id, cb)
		end)
	end
	if (level == "none" or level == "global") and find_rule(rules, "room", room_id) then
		table.insert(steps, function(cb)
			matrix.delete_push_rule("room", room_id, cb)
		end)
	end

	apply_and_refresh(steps, callback)
end

--- @class neoment.notification_settings.Line
--- @field text string The text of the line
--- @field action? fun(cb: fun(result: neoment.Error<nil, neoment.matrix.api.Error>)) Applies the option, nil for headers and notices
--- @field selected? boolean Whether the option is the current one
--- @field dimmed? boolean Whether the line is shown dimmed

--- @param selected boolean
--- @param label string
--- @return string
local function option_text(selected, label)
	return (selected and MARK_SELECTED or MARK_UNSELECTED) .. " " .. label
end

--- Build the lines of the global window
--- @return neoment.notification_settings.Line[]
local function global_lines()
	local levels = M.get_global_levels(matrix.get_push_rules())
	local lines = {}

	for index, category in ipairs({ "one_to_one", "group" }) do
		if index > 1 then
			table.insert(lines, { text = "" })
		end
		table.insert(lines, { text = CATEGORY_HEADERS[category] })
		for _, level in ipairs({ "all", "mentions" }) do
			local selected = levels[category] == level
			table.insert(lines, {
				text = "  " .. option_text(selected, LEVEL_LABELS[level]),
				selected = selected,
				action = function(cb)
					M.set_global_level(category, level, cb)
				end,
			})
		end
	end

	return lines
end

--- Build the lines of a room window
--- @param room_id string
--- @return neoment.notification_settings.Line[]
local function room_lines(room_id)
	local rules = matrix.get_push_rules()
	local current = M.get_room_level(rules, room_id)
	local applied = M.get_applied_global_level(rules, matrix.get_room(room_id))
	local lines = {}

	for _, level in ipairs({ "global", "all", "mentions", "none" }) do
		local label = level == "global" and string.format("%s (%s)", LEVEL_LABELS.global, LEVEL_LABELS[applied])
			or LEVEL_LABELS[level]
		table.insert(lines, {
			text = option_text(current == level, label),
			selected = current == level,
			action = function(cb)
				M.set_room_level(room_id, level, cb)
			end,
		})
	end

	return lines
end

--- Open a settings window
--- @param title string The window title
--- @param build_lines fun(): neoment.notification_settings.Line[] Builds the lines from the current push rules
local function open_window(title, build_lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "neoment_notification_settings"

	local state = { lines = {}, saving = false }
	local win

	--- @param title_text string
	local function render(title_text)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		state.lines = build_lines()
		if config.get().desktop_notifications.source == "custom" then
			table.insert(state.lines, { text = "" })
			table.insert(state.lines, { text = CUSTOM_SOURCE_NOTICE, dimmed = true })
		end

		local texts = vim.tbl_map(function(line)
			return line.text
		end, state.lines)
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
		vim.bo[buf].modifiable = false

		vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
		for index, line in ipairs(state.lines) do
			if line.dimmed then
				vim.hl.range(buf, namespace, "Comment", { index - 1, 0 }, { index - 1, -1 })
			end
		end

		local width = 0
		for _, text in ipairs(texts) do
			width = math.max(width, vim.fn.strdisplaywidth(text))
		end
		width = math.min(math.max(width, vim.fn.strdisplaywidth(title_text)) + 2, math.floor(vim.o.columns * 0.8))
		local height = math.min(#texts, math.floor(vim.o.lines * 0.8))
		local win_config = {
			relative = "editor",
			width = width,
			height = height,
			row = math.floor((vim.o.lines - height) / 2),
			col = math.floor((vim.o.columns - width) / 2),
			border = "rounded",
			title = " " .. title_text .. " ",
			title_pos = "center",
		}

		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_set_config(win, win_config)
		else
			win_config.style = "minimal"
			win = vim.api.nvim_open_win(buf, true, win_config)
			vim.wo[win].cursorline = true
			-- Start on the current option
			for index, line in ipairs(state.lines) do
				if line.selected then
					vim.api.nvim_win_set_cursor(win, { index, 0 })
					break
				end
			end
		end
	end

	local function close()
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function apply()
		if state.saving then
			return
		end
		local line = state.lines[vim.api.nvim_win_get_cursor(win)[1]]
		if not line or not line.action or line.selected then
			return
		end

		state.saving = true
		render(title .. " (Saving…)")
		line.action(function(result)
			vim.schedule(function()
				state.saving = false
				if error.is_error(result) then
					local reason = result.error.error or "unknown error"
					if result.error.saved then
						notify.error("Saved, but could not reload the notification settings: " .. reason)
					else
						notify.error("Could not change the notification settings: " .. reason)
					end
				end
				render(title)
			end)
		end)
	end

	render(title)

	local opts = { buffer = buf, nowait = true, silent = true }
	vim.keymap.set("n", "<CR>", apply, opts)
	vim.keymap.set("n", "q", close, opts)
	vim.keymap.set("n", "<Esc>", close, opts)

	return win
end

--- Make sure the push rules are loaded before opening a window
--- @param on_ready fun()
local function with_push_rules(on_ready)
	if matrix.get_push_rules() then
		on_ready()
		return
	end

	matrix.fetch_push_rules(function(result)
		vim.schedule(function()
			if error.is_error(result) then
				notify.error("Could not load the notification settings: " .. (result.error.error or "unknown error"))
				return
			end
			on_ready()
		end)
	end)
end

--- Open the window with the global notification settings
M.open_global = function()
	with_push_rules(function()
		open_window("Notification settings", global_lines)
	end)
end

--- Open the window with the notification settings of a room
--- @param room_id string
M.open_room = function(room_id)
	with_push_rules(function()
		open_window(matrix.get_room_display_name_with_space(room_id), function()
			return room_lines(room_id)
		end)
	end)
end

return M
