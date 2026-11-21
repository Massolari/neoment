local error = require("neoment.error")

describe("notification settings", function()
	local ROOM_ID = "!room:server"
	local SOUND = { set_tweak = "sound", value = "default" }
	local STUBBED_MODULES = { "neoment.matrix", "neoment.notify", "neoment.config", "neoment.notification_settings" }

	local settings
	local server
	local requests
	local fail_next
	local errors
	local infos
	local rooms
	local original_config

	--- Build an underride rule
	--- @param rule_id string
	--- @param actions table
	--- @param enabled boolean?
	local function underride(rule_id, actions, enabled)
		return { rule_id = rule_id, default = true, enabled = enabled ~= false, actions = actions, conditions = {} }
	end

	--- The rules a new account gets from the server
	local function default_rules()
		return {
			global = {
				override = {
					{ rule_id = ".m.rule.master", default = true, enabled = false, actions = {}, conditions = {} },
					{
						rule_id = ".m.rule.is_user_mention",
						default = true,
						enabled = true,
						actions = { "notify", { set_tweak = "highlight" } },
						conditions = {},
					},
				},
				content = {},
				room = {},
				sender = {},
				underride = {
					underride(".m.rule.room_one_to_one", { "notify", { set_tweak = "sound", value = "default" } }),
					underride(
						".m.rule.encrypted_room_one_to_one",
						{ "notify", { set_tweak = "sound", value = "default" } }
					),
					underride(".m.rule.message", { "notify" }),
					underride(".m.rule.encrypted", { "notify" }),
				},
			},
		}
	end

	--- The mute override rule for a room
	--- @param room_id string
	local function mute_rule(room_id)
		return {
			rule_id = room_id,
			default = false,
			enabled = true,
			actions = {},
			conditions = { { kind = "event_match", key = "room_id", pattern = room_id } },
		}
	end

	--- A room rule
	--- @param room_id string
	--- @param actions table
	--- @param enabled boolean?
	local function room_rule(room_id, actions, enabled)
		return { rule_id = room_id, default = false, enabled = enabled ~= false, actions = actions }
	end

	--- Find the index of a rule in the fake server
	local function find_index(kind, rule_id)
		for index, rule in ipairs(server.rules.global[kind]) do
			if rule.rule_id == rule_id then
				return index
			end
		end
	end

	--- Answer a request of the fake server, failing it when asked to
	--- @param description string
	--- @param change fun()
	--- @param cb function
	local function answer(description, change, cb)
		table.insert(requests, description)
		if fail_next then
			fail_next = false
			cb(error.err({ error = "Server unavailable" }))
			return
		end
		change()
		cb(error.ok(nil))
	end

	--- Apply a level change and wait for its result
	--- @param fn function
	--- @param ... any
	--- @return neoment.Error
	local function run(fn, ...)
		local result
		local args = { ... }
		table.insert(args, function(r)
			result = r
		end)
		fn(unpack(args))
		assert.is_not_nil(result)
		return result
	end

	--- Get the lines of the current buffer
	local function current_lines()
		return vim.api.nvim_buf_get_lines(0, 0, -1, false)
	end

	--- Move to the line with the given text in the current window and press a key
	--- @param text string
	--- @param key string
	local function press_on(text, key)
		for index, line in ipairs(current_lines()) do
			if line:find(text, 1, true) then
				vim.api.nvim_win_set_cursor(0, { index, 0 })
				break
			end
		end
		vim.api.nvim_feedkeys(vim.keycode(key), "x", false)
		vim.wait(50, function()
			return false
		end)
	end

	--- @param source string?
	local function load_config(source)
		vim.g.neoment = { desktop_notifications = { source = source } }
		require("neoment.config").load()
	end

	before_each(function()
		original_config = vim.g.neoment
		for _, module in ipairs(STUBBED_MODULES) do
			package.loaded[module] = nil
		end

		server = { rules = default_rules() }
		requests = {}
		fail_next = false
		errors = {}
		rooms = { [ROOM_ID] = { id = ROOM_ID, name = "Group", joined_member_count = 3, is_direct = false } }
		local local_rules = vim.deepcopy(server.rules)

		infos = {}
		package.loaded["neoment.notify"] = {
			error = function(msg)
				table.insert(errors, msg)
			end,
			info = function(msg)
				table.insert(infos, msg)
			end,
		}
		package.loaded["neoment.matrix"] = {
			get_push_rules = function()
				return local_rules
			end,
			fetch_push_rules = function(cb)
				table.insert(requests, "GET")
				if server.fetch_fails then
					cb(error.err({ error = "Cannot fetch" }))
					return
				end
				local_rules = vim.deepcopy(server.rules)
				cb(error.ok(local_rules))
			end,
			set_push_rule = function(kind, rule_id, body, cb)
				answer("PUT " .. kind .. " " .. rule_id .. " " .. vim.json.encode(body.actions), function()
					local index = find_index(kind, rule_id)
					-- Replacing a rule keeps its enabled flag, as Synapse does
					local enabled = not index or server.rules.global[kind][index].enabled
					index = index or (#server.rules.global[kind] + 1)
					server.rules.global[kind][index] = {
						rule_id = rule_id,
						default = false,
						enabled = enabled,
						actions = body.actions,
						conditions = body.conditions,
					}
				end, cb)
			end,
			delete_push_rule = function(kind, rule_id, cb)
				answer("DELETE " .. kind .. " " .. rule_id, function()
					table.remove(server.rules.global[kind], find_index(kind, rule_id))
				end, cb)
			end,
			set_push_rule_actions = function(kind, rule_id, actions, cb)
				answer("ACTIONS " .. kind .. " " .. rule_id .. " " .. vim.json.encode(actions), function()
					server.rules.global[kind][find_index(kind, rule_id)].actions = actions
				end, cb)
			end,
			set_push_rule_enabled = function(kind, rule_id, enabled, cb)
				answer("ENABLED " .. kind .. " " .. rule_id .. " " .. tostring(enabled), function()
					server.rules.global[kind][find_index(kind, rule_id)].enabled = enabled
				end, cb)
			end,
			get_room = function(room_id)
				return rooms[room_id]
			end,
			get_room_display_name_with_space = function(room_id)
				return "Space/" .. rooms[room_id].name
			end,
			has_invited_room = function(room_id)
				return room_id == "!invited:server"
			end,
			--- Replace the local rules, as a sync would
			set_local_rules = function(rules)
				local_rules = rules
			end,
		}

		load_config("server")
		settings = require("neoment.notification_settings")
	end)

	after_each(function()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_config(win).relative ~= "" then
				vim.api.nvim_win_close(win, true)
			end
		end
		vim.g.neoment = original_config
		for _, module in ipairs(STUBBED_MODULES) do
			package.loaded[module] = nil
		end
	end)

	describe("global levels", function()
		it("are all messages with the server defaults", function()
			assert.are.same({ one_to_one = "all", group = "all" }, settings.get_global_levels(default_rules()))
		end)

		it("are mentions only for groups when the group rule does not notify", function()
			local rules = default_rules()
			rules.global.underride[3].actions = {}

			assert.are.equal("mentions", settings.get_global_levels(rules).group)
		end)

		it("are mentions only for one-to-one rooms when the one-to-one rule is disabled", function()
			local rules = default_rules()
			rules.global.underride[1].enabled = false

			assert.are.equal("mentions", settings.get_global_levels(rules).one_to_one)
		end)

		it("treat the legacy dont_notify action as not notifying", function()
			local rules = default_rules()
			rules.global.underride[3].actions = { "dont_notify" }

			assert.are.equal("mentions", settings.get_global_levels(rules).group)
		end)

		describe("applied to a room", function()
			local rules

			before_each(function()
				rules = default_rules()
				-- Tell the categories apart: one-to-one notifies, groups do not
				rules.global.underride[3].actions = {}
			end)

			it("use the group level for a direct room with three members", function()
				local room = { id = ROOM_ID, is_direct = true, joined_member_count = 3 }

				assert.are.equal("mentions", settings.get_applied_global_level(rules, room))
			end)

			it("use the one-to-one level for a two-member room not marked as direct", function()
				local room = { id = ROOM_ID, is_direct = false, joined_member_count = 2 }

				assert.are.equal("all", settings.get_applied_global_level(rules, room))
			end)

			it("ignore the direct toggle on a three-member room", function()
				local room = { id = ROOM_ID, is_direct = false, joined_member_count = 3 }
				assert.are.equal("mentions", settings.get_applied_global_level(rules, room))

				room.is_direct = true

				assert.are.equal("mentions", settings.get_applied_global_level(rules, room))
			end)

			it("fall back to the direct flag without a member count", function()
				assert.are.equal("all", settings.get_applied_global_level(rules, { id = ROOM_ID, is_direct = true }))
				assert.are.equal(
					"mentions",
					settings.get_applied_global_level(rules, { id = ROOM_ID, is_direct = false })
				)
			end)
		end)
	end)

	describe("room levels", function()
		local rules

		before_each(function()
			rules = default_rules()
		end)

		it("are global settings without a rule", function()
			assert.are.equal("global", settings.get_room_level(rules, ROOM_ID))
		end)

		it("are all messages with a room rule that notifies", function()
			table.insert(rules.global.room, room_rule(ROOM_ID, { "notify" }))

			assert.are.equal("all", settings.get_room_level(rules, ROOM_ID))
		end)

		it("are mentions only with a room rule that does not notify", function()
			table.insert(rules.global.room, room_rule(ROOM_ID, {}))

			assert.are.equal("mentions", settings.get_room_level(rules, ROOM_ID))
		end)

		it("treat the legacy dont_notify room rule as mentions only", function()
			table.insert(rules.global.room, room_rule(ROOM_ID, { "dont_notify" }))

			assert.are.equal("mentions", settings.get_room_level(rules, ROOM_ID))
		end)

		it("are none when a mute override wins over a room rule", function()
			table.insert(rules.global.room, room_rule(ROOM_ID, { "notify" }))
			table.insert(rules.global.override, mute_rule(ROOM_ID))

			assert.are.equal("none", settings.get_room_level(rules, ROOM_ID))
		end)

		it("ignore disabled rules", function()
			table.insert(rules.global.room, room_rule(ROOM_ID, { "notify" }, false))

			assert.are.equal("global", settings.get_room_level(rules, ROOM_ID))
		end)

		it("ignore an override with other conditions", function()
			local foreign = mute_rule(ROOM_ID)
			table.insert(foreign.conditions, { kind = "event_match", key = "type", pattern = "m.room.message" })
			table.insert(rules.global.override, foreign)

			assert.are.equal("global", settings.get_room_level(rules, ROOM_ID))
		end)
	end)

	describe("changing a room level", function()
		local MUTE = "PUT override " .. ROOM_ID .. " []"
		local ROOM_ALL = "PUT room " .. ROOM_ID .. " " .. vim.json.encode({ "notify", SOUND })
		local ROOM_MENTIONS = "PUT room " .. ROOM_ID .. " []"
		local DELETE_OVERRIDE = "DELETE override " .. ROOM_ID
		local DELETE_ROOM = "DELETE room " .. ROOM_ID

		--- Put the fake server and the local rules on a room level
		--- @param level string
		local function start_from(level)
			if level == "all" then
				table.insert(server.rules.global.room, room_rule(ROOM_ID, { "notify", SOUND }))
			elseif level == "mentions" then
				table.insert(server.rules.global.room, room_rule(ROOM_ID, {}))
			elseif level == "none" then
				table.insert(server.rules.global.override, mute_rule(ROOM_ID))
			end
			require("neoment.matrix").set_local_rules(vim.deepcopy(server.rules))
		end

		local expected = {
			global = {
				all = { DELETE_ROOM },
				mentions = { DELETE_ROOM },
				none = { DELETE_OVERRIDE },
			},
			all = {
				global = { ROOM_ALL },
				mentions = { ROOM_ALL },
				none = { ROOM_ALL, DELETE_OVERRIDE },
			},
			mentions = {
				global = { ROOM_MENTIONS },
				all = { ROOM_MENTIONS },
				none = { ROOM_MENTIONS, DELETE_OVERRIDE },
			},
			none = {
				global = { MUTE },
				all = { MUTE, DELETE_ROOM },
				mentions = { MUTE, DELETE_ROOM },
			},
		}

		for target, from_levels in pairs(expected) do
			for from, sequence in pairs(from_levels) do
				it(string.format("sends the requests to go from %s to %s", from, target), function()
					start_from(from)

					local result = run(settings.set_room_level, ROOM_ID, target)

					assert.is_true(error.is_ok(result))
					assert.are.same(vim.list_extend(vim.deepcopy(sequence), { "GET" }), requests)
					local matrix = require("neoment.matrix")
					assert.are.equal(target, settings.get_room_level(matrix.get_push_rules(), ROOM_ID))
				end)
			end
		end

		it("enables a disabled room rule it replaces", function()
			table.insert(server.rules.global.room, room_rule(ROOM_ID, {}, false))
			require("neoment.matrix").set_local_rules(vim.deepcopy(server.rules))

			local result = run(settings.set_room_level, ROOM_ID, "all")

			assert.is_true(error.is_ok(result))
			assert.are.same({ ROOM_ALL, "ENABLED room " .. ROOM_ID .. " true", "GET" }, requests)
			assert.are.equal("all", settings.get_room_level(require("neoment.matrix").get_push_rules(), ROOM_ID))
		end)

		it("enables a disabled mute override it replaces", function()
			local disabled = mute_rule(ROOM_ID)
			disabled.enabled = false
			table.insert(server.rules.global.override, disabled)
			require("neoment.matrix").set_local_rules(vim.deepcopy(server.rules))

			run(settings.set_room_level, ROOM_ID, "none")

			assert.are.same({ MUTE, "ENABLED override " .. ROOM_ID .. " true", "GET" }, requests)
			assert.are.equal("none", settings.get_room_level(require("neoment.matrix").get_push_rules(), ROOM_ID))
		end)

		it("marks the error as saved when only the re-fetch fails", function()
			server.fetch_fails = true

			local result = run(settings.set_room_level, ROOM_ID, "none")

			assert.is_true(error.is_error(result))
			assert.is_true(result.error.saved)
		end)

		it("re-fetches and reports the error when a request fails", function()
			fail_next = true

			local result = run(settings.set_room_level, ROOM_ID, "none")

			assert.is_true(error.is_error(result))
			assert.are.equal("Server unavailable", result.error.error)
			assert.are.same({ MUTE, "GET" }, requests)
		end)
	end)

	describe("changing a global level", function()
		it("sets both group rules to mentions only", function()
			local result = run(settings.set_global_level, "group", "mentions")

			assert.is_true(error.is_ok(result))
			assert.are.same({
				"ACTIONS underride .m.rule.message []",
				"ENABLED underride .m.rule.message true",
				"ACTIONS underride .m.rule.encrypted []",
				"ENABLED underride .m.rule.encrypted true",
				"GET",
			}, requests)
		end)

		it("enables both one-to-one rules with a notify action and the default sound", function()
			server.rules.global.underride[1].enabled = false
			require("neoment.matrix").set_local_rules(vim.deepcopy(server.rules))

			run(settings.set_global_level, "one_to_one", "all")

			assert.are.same({
				"ACTIONS underride .m.rule.room_one_to_one " .. vim.json.encode({ "notify", SOUND }),
				"ENABLED underride .m.rule.room_one_to_one true",
				"ACTIONS underride .m.rule.encrypted_room_one_to_one " .. vim.json.encode({ "notify", SOUND }),
				"ENABLED underride .m.rule.encrypted_room_one_to_one true",
				"GET",
			}, requests)
			local levels = settings.get_global_levels(require("neoment.matrix").get_push_rules())
			assert.are.equal("all", levels.one_to_one)
		end)

		it("sets group rules to all messages and leaves the mention rules alone", function()
			server.rules.global.underride[3].actions = {}
			server.rules.global.underride[4].actions = {}
			require("neoment.matrix").set_local_rules(vim.deepcopy(server.rules))

			run(settings.set_global_level, "group", "all")

			assert.are.same({
				'ACTIONS underride .m.rule.message ["notify"]',
				"ENABLED underride .m.rule.message true",
				'ACTIONS underride .m.rule.encrypted ["notify"]',
				"ENABLED underride .m.rule.encrypted true",
				"GET",
			}, requests)
			assert.are.same(default_rules().global.override, server.rules.global.override)
		end)

		it("sets one-to-one rules to mentions only", function()
			run(settings.set_global_level, "one_to_one", "mentions")

			assert.are.equal(
				"mentions",
				settings.get_global_levels(require("neoment.matrix").get_push_rules()).one_to_one
			)
		end)

		it("skips a rule the server does not have", function()
			table.remove(server.rules.global.underride, 4)
			require("neoment.matrix").set_local_rules(vim.deepcopy(server.rules))

			run(settings.set_global_level, "group", "mentions")

			assert.are.same({
				"ACTIONS underride .m.rule.message []",
				"ENABLED underride .m.rule.message true",
				"GET",
			}, requests)
		end)

		it("re-fetches and reports the error when a request fails", function()
			fail_next = true

			local result = run(settings.set_global_level, "group", "mentions")

			assert.is_true(error.is_error(result))
			assert.are.same({ "ACTIONS underride .m.rule.message []", "GET" }, requests)
		end)
	end)

	describe("windows", function()
		it("shows the global levels", function()
			settings.open_global()

			assert.are.same({
				"One-to-one rooms (2 members)",
				"  (•) All messages",
				"  ( ) Mentions and replies only",
				"",
				"Group rooms (3+ members)",
				"  (•) All messages",
				"  ( ) Mentions and replies only",
			}, current_lines())
		end)

		it("applies a global option and marks it", function()
			settings.open_global()
			local win = vim.api.nvim_get_current_win()

			-- The second "Mentions" line is the group one
			vim.api.nvim_win_set_cursor(0, { 7, 0 })
			vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
			vim.wait(50, function()
				return false
			end)

			assert.are.equal(win, vim.api.nvim_get_current_win())
			assert.are.same({
				"One-to-one rooms (2 members)",
				"  (•) All messages",
				"  ( ) Mentions and replies only",
				"",
				"Group rooms (3+ members)",
				"  ( ) All messages",
				"  (•) Mentions and replies only",
			}, current_lines())
		end)

		it("says the change was saved when only the reload fails", function()
			settings.open_global()
			server.fetch_fails = true

			vim.api.nvim_win_set_cursor(0, { 7, 0 })
			vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
			vim.wait(50, function()
				return false
			end)

			assert.are.equal(1, #errors)
			assert.matches("Saved, but could not reload", errors[1], 1, true)
		end)

		it("shows a room's settings with the applied global level", function()
			server.rules.global.underride[3].actions = {}
			require("neoment.matrix").set_local_rules(vim.deepcopy(server.rules))

			settings.open_room(ROOM_ID)

			assert.are.same({
				"(•) Global settings (Mentions and replies only)",
				"( ) All messages",
				"( ) Mentions and replies only",
				"( ) None",
			}, current_lines())
			assert.matches("Space/Group", vim.api.nvim_win_get_config(0).title[1][1], 1, true)
		end)

		it("follows a global change in the room's first option", function()
			server.rules.global.underride[3].actions = {}
			require("neoment.matrix").set_local_rules(vim.deepcopy(server.rules))
			run(settings.set_global_level, "group", "all")

			settings.open_room(ROOM_ID)

			assert.are.equal("(•) Global settings (All messages)", current_lines()[1])
		end)

		it("marks the new room option after a change", function()
			settings.open_room(ROOM_ID)

			press_on("None", "<CR>")

			assert.are.same({
				"( ) Global settings (All messages)",
				"( ) All messages",
				"( ) Mentions and replies only",
				"(•) None",
			}, current_lines())
		end)

		it("keeps the old mark and shows an error when a change fails", function()
			settings.open_room(ROOM_ID)
			fail_next = true

			press_on("None", "<CR>")

			assert.are.equal("(•) Global settings (All messages)", current_lines()[1])
			assert.are.equal("( ) None", current_lines()[4])
			assert.are.equal(1, #errors)
			assert.matches("Server unavailable", errors[1], 1, true)
		end)

		it("does nothing for the current option", function()
			settings.open_room(ROOM_ID)

			press_on("Global settings", "<CR>")

			assert.are.same({}, requests)
		end)

		it("shows the notice only under the custom source", function()
			settings.open_room(ROOM_ID)
			assert.is_false(vim.tbl_contains(current_lines(), ""))
			vim.api.nvim_win_close(0, true)

			load_config("custom")
			settings.open_room(ROOM_ID)

			local lines = current_lines()
			assert.matches('source = "custom"', lines[#lines], 1, true)
		end)

		it("closes with q", function()
			settings.open_global()
			local win = vim.api.nvim_get_current_win()

			vim.api.nvim_feedkeys("q", "x", false)

			assert.is_false(vim.api.nvim_win_is_valid(win))
		end)

		it("fetches the rules when they are missing", function()
			require("neoment.matrix").set_local_rules(nil)

			settings.open_global()
			vim.wait(50, function()
				return false
			end)

			assert.are.same({ "GET" }, requests)
			assert.are.equal("One-to-one rooms (2 members)", current_lines()[1])
		end)

		it("shows an error and no window when the rules cannot be loaded", function()
			require("neoment.matrix").set_local_rules(nil)
			server.fetch_fails = true
			local wins = #vim.api.nvim_list_wins()

			settings.open_global()
			vim.wait(50, function()
				return false
			end)

			assert.are.equal(wins, #vim.api.nvim_list_wins())
			assert.are.equal(1, #errors)
			assert.matches("Cannot fetch", errors[1], 1, true)
		end)
	end)

	describe("room list entry point", function()
		local rooms_module
		local list_buf

		before_each(function()
			package.loaded["neoment.rooms"] = nil
			package.loaded["neoment.sync"] = { get_status = function() end }
			package.loaded["neoment.storage"] = {}
			rooms_module = require("neoment.rooms")

			list_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, { "Rooms", "Group", "Invite" })
			vim.api.nvim_set_current_buf(list_buf)
			rooms_module.room_list_extmarks = {
				{ line = 2, room_id = ROOM_ID },
				{ line = 3, room_id = "!invited:server", is_invited = true },
			}
		end)

		after_each(function()
			vim.api.nvim_buf_delete(list_buf, { force = true })
			package.loaded["neoment.rooms"] = nil
			package.loaded["neoment.sync"] = nil
			package.loaded["neoment.storage"] = nil
		end)

		--- @param line integer
		--- @return integer The number of windows after opening the settings on that line
		local function open_on_line(line)
			vim.api.nvim_win_set_cursor(0, { line, 0 })
			local wins = #vim.api.nvim_list_wins()
			rooms_module.open_room_notification_settings()
			return #vim.api.nvim_list_wins() - wins
		end

		it("opens the settings of the room under the cursor", function()
			assert.are.equal(1, open_on_line(2))
			assert.are.equal("(•) Global settings (All messages)", current_lines()[1])
		end)

		it("opens no window on a section header", function()
			assert.are.equal(0, open_on_line(1))
			assert.matches("No room found", infos[1], 1, true)
		end)

		it("opens no window for an invited room", function()
			assert.are.equal(0, open_on_line(3))
			assert.matches("after joining", infos[1], 1, true)
		end)
	end)
end)
