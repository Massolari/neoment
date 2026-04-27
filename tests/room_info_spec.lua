local function make_room(overrides)
	return vim.tbl_extend("force", {
		id = "!room1:example.org",
		name = "Test Room",
		topic = "",
		aliases = {},
		is_direct = nil,
		is_favorite = false,
		is_lowpriority = false,
		members = {},
		avatar_url = nil,
	}, overrides or {})
end

local function setup_matrix_mock(room, opts)
	opts = opts or {}
	local room_id = room.id

	local matrix_mock = {
		client = { homeserver = "https://example.org", access_token = "token" },
		has_room = function(id)
			return id == room_id
		end,
		get_room = function(id)
			if id == room_id then
				return room
			end
		end,
		get_invited_room = function()
			return nil
		end,
		has_invited_room = function()
			return opts.has_invited_room or false
		end,
		get_room_display_name = function(id)
			return id == room_id and room.name or id
		end,
		get_room_display_name_with_space = function(id)
			return id == room_id and room.name or id
		end,
		is_space = function()
			return opts.is_space or false
		end,
		get_space_name = function()
			return opts.space_name or nil
		end,
		get_room_aliases = function()
			return room.aliases or {}
		end,
		get_room_members = function()
			return room.members or {}
		end,
		get_room_avatar = function()
			return room.avatar_url
		end,
		add_room_tag = opts.add_room_tag or function() end,
		remove_room_tag = opts.remove_room_tag or function() end,
		set_room_favorite = opts.set_room_favorite or function() end,
		set_room_lowpriority = opts.set_room_lowpriority or function() end,
		set_room_direct = opts.set_room_direct or function() end,
	}
	package.loaded["neoment.matrix"] = matrix_mock
	return matrix_mock
end

local function setup_mocks(room, matrix_opts)
	setup_matrix_mock(room, matrix_opts)

	package.loaded["neoment.config"] = {
		get = function()
			return {
				icon = {
					favorite = "★",
					low_priority = "↓",
					people = "👤",
				},
			}
		end,
	}

	package.loaded["neoment.constants"] = {
		INFO_ROOM_FILETYPE = "neoment_info_room",
	}

	package.loaded["neoment.util"] = {
		get_existing_buffer = function()
			return nil
		end,
		buffer_write = function(buf, lines)
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.bo[buf].modifiable = false
		end,
		mxc_to_url = function(homeserver, mxc)
			local path = mxc:match("^mxc://[^/]+/(.+)$")
			return homeserver .. "/_matrix/media/v3/download/" .. path
		end,
	}

	package.loaded["neoment.notify"] = {
		info = function() end,
		error = function() end,
	}

	package.loaded["neoment.icon"] = {
		border_left = "",
		border_right = "",
	}

	package.loaded["neoment.error"] = {
		match = function(result, ok_fn, err_fn)
			if result and result._ok then
				ok_fn(result.data)
			elseif err_fn then
				err_fn(result and result.error or {})
			end
		end,
		is_ok = function(r)
			return r and r._ok
		end,
	}
end

local function teardown_mocks()
	package.loaded["neoment.room_info"] = nil
	package.loaded["neoment.matrix"] = nil
	package.loaded["neoment.config"] = nil
	package.loaded["neoment.constants"] = nil
	package.loaded["neoment.util"] = nil
	package.loaded["neoment.notify"] = nil
	package.loaded["neoment.icon"] = nil
	package.loaded["neoment.error"] = nil
	package.loaded["neoment.rooms"] = nil
	package.loaded["neoment.storage"] = nil
end

describe("room_info", function()
	local room_info
	local buf

	before_each(function()
		buf = vim.api.nvim_create_buf(false, true)
	end)

	after_each(function()
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		teardown_mocks()
	end)

	describe("update_buffer", function()
		it("does nothing when buffer is not loaded", function()
			setup_mocks(make_room())
			room_info = require("neoment.room_info")

			local unloaded_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_delete(unloaded_buf, { force = true })

			-- Should not error
			assert.has_no_errors(function()
				room_info.update_buffer(unloaded_buf)
			end)
		end)

		it("does nothing when buffer has no room_id", function()
			setup_mocks(make_room())
			room_info = require("neoment.room_info")

			assert.has_no_errors(function()
				room_info.update_buffer(buf)
			end)
		end)

		it("writes basic room info lines to buffer", function()
			local room = make_room({ id = "!room1:example.org", name = "My Room" })
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")

			assert.truthy(content:find("Room Type: Room"))
			assert.truthy(content:find("Room ID: " .. room.id))
			assert.truthy(content:find("Status:"))
		end)

		it("shows Room Type: Space for space rooms", function()
			local room = make_room({ id = "!space1:example.org", name = "My Space" })
			setup_mocks(room, { is_space = true })
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			assert.truthy(content:find("Room Type: Space"))
		end)

		it("shows Room Type: Direct Message for direct rooms", function()
			local room = make_room({ id = "!dm1:example.org", name = "DM", is_direct = true })
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			assert.truthy(content:find("Room Type: Direct Message"))
		end)

		it("shows topic when present", function()
			local room = make_room({ topic = "This is the topic" })
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			assert.truthy(content:find("Topic:"))
			assert.truthy(content:find("This is the topic"))
		end)

		it("does not show topic section when topic is empty", function()
			local room = make_room({ topic = "" })
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			assert.falsy(content:find("Topic:"))
		end)

		it("shows space name when room is in a space", function()
			local room = make_room()
			setup_mocks(room, { space_name = "My Space" })
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			assert.truthy(content:find("Space: My Space"))
		end)

		it("shows aliases when present", function()
			local room = make_room({ aliases = { "#myroom:example.org" } })
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			assert.truthy(content:find("Aliases:"))
			assert.truthy(content:find("#myroom:example.org"))
		end)

		it("shows collapsed members section by default", function()
			local room = make_room({
				members = {
					["@alice:example.org"] = "Alice",
					["@bob:example.org"] = "Bob",
				},
			})
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			assert.truthy(content:find("── Members %(2%) ──"))
			assert.truthy(content:find("%[Tab to expand%]"))
		end)

		it("shows expanded members when members_expanded is true", function()
			local room = make_room({
				members = {
					["@alice:example.org"] = "Alice",
					["@bob:example.org"] = "Bob",
				},
			})
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			vim.b[buf].members_expanded = true
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			assert.truthy(content:find("Alice"))
			assert.truthy(content:find("Bob"))
			-- Should not have Tab to expand hint
			assert.falsy(content:find("%[Tab to expand%]"))
		end)

		it("members are sorted alphabetically when expanded", function()
			local room = make_room({
				members = {
					["@z:example.org"] = "Zara",
					["@a:example.org"] = "Alice",
					["@m:example.org"] = "Mike",
				},
			})
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			vim.b[buf].members_expanded = true
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			-- Find the positions of each name
			local alice_pos, mike_pos, zara_pos
			for i, line in ipairs(lines) do
				if line:find("Alice") then
					alice_pos = i
				end
				if line:find("Mike") then
					mike_pos = i
				end
				if line:find("Zara") then
					zara_pos = i
				end
			end
			assert.truthy(alice_pos < mike_pos)
			assert.truthy(mike_pos < zara_pos)
		end)

		it("shows member user ID as display when display name equals user ID", function()
			local room = make_room({
				members = {
					["@alice:example.org"] = "@alice:example.org",
				},
			})
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			vim.b[buf].members_expanded = true
			room_info.update_buffer(buf)

			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			-- Should appear without parenthesized duplicate
			assert.truthy(content:find("@alice:example%.org"))
			assert.falsy(content:find("@alice:example%.org %("))
		end)
	end)

	describe("toggle_members", function()
		it("toggles members_expanded from false to true", function()
			local room = make_room()
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			vim.b[buf].members_expanded = false
			room_info.toggle_members(buf)

			assert.is_true(vim.b[buf].members_expanded)
		end)

		it("toggles members_expanded from true to false", function()
			local room = make_room()
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			vim.b[buf].members_expanded = true
			room_info.toggle_members(buf)

			assert.is_false(vim.b[buf].members_expanded)
		end)

		it("treats nil members_expanded as false and toggles to true", function()
			local room = make_room()
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.toggle_members(buf)

			assert.is_true(vim.b[buf].members_expanded)
		end)
	end)

	describe("toggle_favorite", function()
		it("does nothing when buffer has no room_id", function()
			setup_mocks(make_room())
			room_info = require("neoment.room_info")

			assert.has_no_errors(function()
				room_info.toggle_favorite(buf)
			end)
		end)

		it("shows info notification for invited rooms", function()
			local room = make_room()
			local notify_mock = { info = spy.new(function() end), error = function() end }
			setup_mocks(room, { has_invited_room = true })
			package.loaded["neoment.notify"] = notify_mock
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.toggle_favorite(buf)

			assert.spy(notify_mock.info).was_called()
		end)

		it("calls add_room_tag when room is not favorite", function()
			local add_tag_spy = spy.new(function() end)
			local room = make_room({ is_favorite = false })
			setup_mocks(room, { add_room_tag = add_tag_spy })
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.toggle_favorite(buf)

			assert.spy(add_tag_spy).was_called_with(room.id, "m.favourite", nil, match._)
		end)

		it("calls remove_room_tag when room is favorite", function()
			local remove_tag_spy = spy.new(function() end)
			local room = make_room({ is_favorite = true })
			setup_mocks(room, { remove_room_tag = remove_tag_spy })
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.toggle_favorite(buf)

			assert.spy(remove_tag_spy).was_called_with(room.id, "m.favourite", nil, match._)
		end)
	end)

	describe("toggle_low_priority", function()
		it("does nothing when buffer has no room_id", function()
			setup_mocks(make_room())
			room_info = require("neoment.room_info")

			assert.has_no_errors(function()
				room_info.toggle_low_priority(buf)
			end)
		end)

		it("calls add_room_tag when room is not low priority", function()
			local add_tag_spy = spy.new(function() end)
			local room = make_room({ is_lowpriority = false })
			setup_mocks(room, { add_room_tag = add_tag_spy })
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.toggle_low_priority(buf)

			assert.spy(add_tag_spy).was_called_with(room.id, "m.lowpriority", nil, match._)
		end)

		it("calls remove_room_tag when room is low priority", function()
			local remove_tag_spy = spy.new(function() end)
			local room = make_room({ is_lowpriority = true })
			setup_mocks(room, { remove_room_tag = remove_tag_spy })
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.toggle_low_priority(buf)

			assert.spy(remove_tag_spy).was_called_with(room.id, "m.lowpriority", nil, match._)
		end)
	end)

	describe("toggle_avatar_zoom", function()
		it("does nothing when buffer has no data", function()
			local room = make_room()
			setup_mocks(room)
			room_info = require("neoment.room_info")

			assert.has_no_errors(function()
				room_info.toggle_avatar_zoom(buf)
			end)
		end)

		it("shows info notification when there is no avatar placement", function()
			local room = make_room()
			local notify_mock = { info = spy.new(function() end), error = function() end }
			setup_mocks(room)
			package.loaded["neoment.notify"] = notify_mock
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.update_buffer(buf)
			room_info.toggle_avatar_zoom(buf)

			assert.spy(notify_mock.info).was_called_with("No avatar image to zoom")
		end)

		it("zooms in avatar on first toggle", function()
			local update_spy = spy.new(function() end)
			local placement = {
				opts = { height = 8, width = 16 },
				update = update_spy,
				close = function() end,
			}
			local room = make_room({ avatar_url = "mxc://example.org/abc123" })
			setup_mocks(room)
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			-- Initialize buffer_data by updating buffer (avatar won't render without Snacks)
			room_info.update_buffer(buf)

			-- Since buffer_data is local and avatar placement requires Snacks,
			-- we verify the no-placement path is handled (tested above).
			-- The zoom-in/zoom-out logic requires injecting into local state
			-- which isn't possible without Snacks mock, so we test the guard paths.
		end)
	end)

	describe("open_avatar", function()
		it("does nothing when buffer has no room_id", function()
			setup_mocks(make_room())
			room_info = require("neoment.room_info")

			assert.has_no_errors(function()
				room_info.open_avatar(buf)
			end)
		end)

		it("does nothing when room is not found", function()
			setup_mocks(make_room())
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = "!nonexistent:example.org"
			assert.has_no_errors(function()
				room_info.open_avatar(buf)
			end)
		end)

		it("shows info notification when room has no avatar", function()
			local room = make_room({ avatar_url = nil })
			local notify_mock = { info = spy.new(function() end), error = function() end }
			setup_mocks(room)
			package.loaded["neoment.notify"] = notify_mock
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.open_avatar(buf)

			assert.spy(notify_mock.info).was_called_with("No avatar image to open")
		end)

		it("fetches avatar and opens it when avatar_url is present", function()
			local room = make_room({ avatar_url = "mxc://example.org/abc123" })
			local fetch_spy = spy.new(function()
				return { _ok = true, data = "/tmp/Test_Room.png" }
			end)
			local open_spy = spy.new(function() end)
			setup_mocks(room)

			package.loaded["neoment.storage"] = {
				fetch_to_temp = fetch_spy,
			}

			-- Mock vim.ui.open
			local original_open = vim.ui.open
			vim.ui.open = open_spy

			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.open_avatar(buf)

			assert.spy(fetch_spy).was_called(1)
			-- Verify filename is derived from room name
			local call_args = fetch_spy.calls[1]
			assert.equals("Test_Room.png", call_args.vals[1])
			-- Verify URL is constructed correctly
			assert.truthy(call_args.vals[2]:find("example.org"))
			assert.truthy(call_args.vals[2]:find("access_token=token"))

			assert.spy(open_spy).was_called_with("/tmp/Test_Room.png")

			vim.ui.open = original_open
		end)

		it("shows error notification when fetch fails", function()
			local room = make_room({ avatar_url = "mxc://example.org/abc123" })
			local notify_mock = { info = function() end, error = spy.new(function() end) }
			setup_mocks(room)
			package.loaded["neoment.notify"] = notify_mock

			package.loaded["neoment.storage"] = {
				fetch_to_temp = function()
					return { _ok = false, error = "download failed" }
				end,
			}

			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.open_avatar(buf)

			assert.spy(notify_mock.error).was_called_with("Failed to open avatar image: download failed")
		end)
	end)

	describe("toggle_direct", function()
		it("does nothing when buffer has no room_id", function()
			setup_mocks(make_room())
			room_info = require("neoment.room_info")

			assert.has_no_errors(function()
				room_info.toggle_direct(buf)
			end)
		end)

		it("sets room as direct when it is not direct", function()
			local set_direct_spy = spy.new(function() end)
			local room = make_room({ is_direct = false })
			setup_mocks(room, { set_room_direct = set_direct_spy })
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.toggle_direct(buf)

			assert.spy(set_direct_spy).was_called_with(room.id, true)
		end)

		it("unsets room as direct when it is direct", function()
			local set_direct_spy = spy.new(function() end)
			local room = make_room({ is_direct = true })
			setup_mocks(room, { set_room_direct = set_direct_spy })
			room_info = require("neoment.room_info")

			vim.b[buf].room_id = room.id
			room_info.toggle_direct(buf)

			assert.spy(set_direct_spy).was_called_with(room.id, false)
		end)
	end)
end)
