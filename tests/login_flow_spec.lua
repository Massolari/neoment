local error_mod = require("neoment.error")

describe("Login flow", function()
	--- Modules stubbed for the duration of each test
	local STUBBED_MODULES = {
		"neoment",
		"neoment.config",
		"neoment.notify",
		"neoment.sync",
		"neoment.rooms",
		"neoment.room",
		"neoment.storage",
		"neoment.matrix",
		"neoment.matrix.auth",
		"neoment.sso_listener",
		"neoment.highlight",
		"neoment.focus",
	}

	local neoment
	local auth
	local calls
	local notifications
	local listeners
	local original = {}

	--- Answers given to the prompts, in order
	local inputs
	local paste_answer
	local selected_method

	before_each(function()
		calls = { login_password = {}, login_token = {}, opened = {}, selects = 0, pastes = 0, toggled = 0 }
		notifications = {}
		listeners = {}
		inputs = {}
		paste_answer = nil
		selected_method = nil

		original.input = vim.fn.input
		original.inputsecret = vim.fn.inputsecret
		original.ui_input = vim.ui.input
		original.ui_select = vim.ui.select
		original.ui_open = vim.ui.open
		original.ssh_connection = vim.env.SSH_CONNECTION
		original.ssh_tty = vim.env.SSH_TTY
		vim.env.SSH_CONNECTION = nil
		vim.env.SSH_TTY = nil

		vim.fn.input = function()
			return table.remove(inputs, 1) or ""
		end
		vim.fn.inputsecret = function()
			return "hunter2"
		end
		vim.ui.input = function(_, on_confirm)
			calls.pastes = calls.pastes + 1
			on_confirm(paste_answer)
		end
		vim.ui.select = function(items, _, on_choice)
			calls.selects = calls.selects + 1
			calls.select_items = items
			on_choice(selected_method)
		end
		vim.ui.open = function(url)
			table.insert(calls.opened, url)
			return nil, nil
		end

		for _, name in ipairs(STUBBED_MODULES) do
			package.loaded[name] = nil
		end

		local function record(level)
			return function(msg)
				table.insert(notifications, { level = level, msg = msg })
			end
		end
		package.loaded["neoment.notify"] = { info = record("info"), warning = record("warning"), error = record("error") }
		package.loaded["neoment.config"] = {
			load = function() end,
			get = function()
				return { save_session = false }
			end,
		}
		package.loaded["neoment.sync"] = { start = function() end }
		package.loaded["neoment.rooms"] = {
			toggle_room_list = function()
				calls.toggled = calls.toggled + 1
			end,
		}
		package.loaded["neoment.room"] = {}
		package.loaded["neoment.storage"] = {
			restore_session = function()
				return false
			end,
		}
		package.loaded["neoment.highlight"] = { define_highlights = function() end }
		package.loaded["neoment.focus"] = { setup = function() end }
		package.loaded["neoment.matrix"] = {
			client = { user_id = "@alice:example.org" },
			is_logged_in = function()
				return false
			end,
			set_homeserver = function(homeserver)
				calls.homeserver = homeserver
			end,
		}
		package.loaded["neoment.sso_listener"] = {
			start = function(opts)
				local listener = {
					port = 4567,
					redirect_url = "http://127.0.0.1:4567/secret/",
					opts = opts,
					closed = false,
				}
				listener.close = function()
					listener.closed = true
				end
				table.insert(listeners, listener)
				return error_mod.ok(listener)
			end,
		}

		-- Keep the real parsing helpers, stub everything that talks to the network
		package.loaded["neoment.matrix.auth"] = nil
		local real_auth = require("neoment.matrix.auth")
		auth = {
			parse_server_name = real_auth.parse_server_name,
			parse_login_token = real_auth.parse_login_token,
			sso_redirect_url = real_auth.sso_redirect_url,
			methods = { "password", "sso" },
			login_result = error_mod.ok(nil),
		}
		auth.discover = function(_, callback)
			if auth.defer_discovery then
				calls.pending_discovery = function()
					callback("https://matrix.example.org")
				end
				return
			end
			callback("https://matrix.example.org")
		end
		auth.get_login_flows = function(_, callback)
			callback(auth.flows_result or error_mod.ok(auth.methods))
		end
		auth.login_password = function(user, password, callback, is_current)
			table.insert(calls.login_password, { user = user, password = password })
			if auth.defer_login then
				calls.pending_login = function()
					calls.login_was_current = is_current()
					callback(auth.login_result)
				end
				return
			end
			callback(auth.login_result)
		end
		auth.login_token = function(token, callback)
			table.insert(calls.login_token, token)
			callback(auth.login_result)
		end
		package.loaded["neoment.matrix.auth"] = auth

		neoment = require("neoment")
	end)

	after_each(function()
		vim.fn.input = original.input
		vim.fn.inputsecret = original.inputsecret
		vim.ui.input = original.ui_input
		vim.ui.select = original.ui_select
		vim.ui.open = original.ui_open
		vim.env.SSH_CONNECTION = original.ssh_connection
		vim.env.SSH_TTY = original.ssh_tty
		for _, name in ipairs(STUBBED_MODULES) do
			package.loaded[name] = nil
		end
	end)

	--- Run the login and wait for the scheduled callbacks to settle.
	local function run_login()
		neoment.init()
		vim.wait(50)
	end

	--- @param level string
	--- @param pattern string
	--- @return boolean
	local function notified(level, pattern)
		for _, n in ipairs(notifications) do
			if n.level == level and n.msg:find(pattern, 1, true) then
				return true
			end
		end
		return false
	end

	it("should use the only offered method without asking", function()
		auth.methods = { "password" }
		inputs = { "@alice:example.org" }

		run_login()

		assert.are.equal(0, calls.selects)
		assert.are.same({ { user = "@alice:example.org", password = "hunter2" } }, calls.login_password)
		assert.are.equal("https://matrix.example.org", calls.homeserver)
		assert.are.equal(1, calls.toggled)
	end)

	it("should ask which method to use when several are offered", function()
		inputs = { "@alice:example.org" }
		selected_method = "password"

		run_login()

		assert.are.equal(1, calls.selects)
		assert.are.same({ "password", "sso" }, calls.select_items)
		assert.are.equal(1, #calls.login_password)
	end)

	it("should open the browser with the listener's secret redirect URL", function()
		auth.methods = { "sso" }
		inputs = { "example.org" }

		run_login()

		assert.are.equal(1, #listeners)
		assert.are.equal(1, #calls.opened)
		assert.matches("redirectUrl=http%3a%2f%2f127.0.0.1%3a4567%2fsecret%2f", calls.opened[1], 1, true)

		listeners[1].opts.on_token("XYZ")
		vim.wait(50)

		assert.are.same({ "XYZ" }, calls.login_token)
		assert.is_true(notified("info", "Login successful"))
	end)

	it("should ask for the redirected URL right away in a remote session", function()
		vim.env.SSH_CONNECTION = "10.0.0.1 1234 10.0.0.2 22"
		auth.methods = { "sso" }
		inputs = { "example.org" }
		paste_answer = "http://127.0.0.1/?loginToken=XYZ"

		run_login()

		assert.are.equal(0, #listeners)
		assert.are.equal(1, calls.pastes)
		assert.are.same({ "XYZ" }, calls.login_token)
	end)

	it("should ask for the redirected URL after the listener times out", function()
		auth.methods = { "sso" }
		inputs = { "example.org" }
		paste_answer = "XYZ"

		run_login()
		assert.are.equal(0, calls.pastes)

		listeners[1].opts.on_timeout()
		vim.wait(50)

		assert.are.equal(1, calls.pastes)
		assert.are.same({ "XYZ" }, calls.login_token)
	end)

	it("should cancel the login when the paste prompt is cancelled", function()
		vim.env.SSH_TTY = "/dev/pts/1"
		auth.methods = { "sso" }
		inputs = { "example.org" }
		paste_answer = nil

		run_login()

		assert.are.same({}, calls.login_token)
		assert.is_true(notified("info", "Login cancelled"))
	end)

	it("should show an error when the pasted URL has no login token", function()
		vim.env.SSH_TTY = "/dev/pts/1"
		auth.methods = { "sso" }
		inputs = { "example.org" }
		paste_answer = "https://idp.example.org/error"

		run_login()

		assert.are.same({}, calls.login_token)
		assert.is_true(notified("error", "does not contain a login token"))
	end)

	it("should close a pending listener when the login is started again", function()
		auth.methods = { "sso" }
		inputs = { "example.org", "example.org" }

		run_login()
		run_login()

		assert.are.equal(2, #listeners)
		assert.is_true(listeners[1].closed)
		assert.is_false(listeners[2].closed)
	end)

	it("should ask for the username when a homeserver URL is entered", function()
		auth.methods = { "password" }
		auth.discover = function(server_name, callback)
			callback(server_name)
		end
		inputs = { "https://matrix.example.org/", "alice" }

		run_login()

		assert.are.equal("https://matrix.example.org", calls.homeserver)
		assert.are.same({ { user = "alice", password = "hunter2" } }, calls.login_password)
	end)

	it("should show an error when the login methods cannot be fetched", function()
		auth.flows_result = error_mod.err({ error = "Could not fetch login methods from https://matrix.example.org" })
		inputs = { "example.org" }

		run_login()

		assert.is_true(notified("error", "Could not fetch login methods"))
		assert.are.equal(0, calls.selects)
	end)

	it("should ignore a stale login attempt when a newer one was started", function()
		auth.methods = { "sso" }
		auth.defer_discovery = true
		inputs = { "example.org", "example.org" }

		run_login()
		local stale_discovery = calls.pending_discovery
		run_login()
		local current_discovery = calls.pending_discovery

		stale_discovery()
		vim.wait(50)
		assert.are.equal(0, #listeners)

		current_discovery()
		vim.wait(50)
		assert.are.equal(1, #listeners)
		assert.are.equal(1, #calls.opened)
	end)

	it("should ignore the timeout of a listener that is no longer pending", function()
		auth.methods = { "sso" }
		inputs = { "example.org", "example.org" }

		run_login()
		run_login()

		listeners[1].opts.on_timeout()
		vim.wait(50)

		assert.are.equal(0, calls.pastes)
		assert.is_false(notified("warning", "Did not receive the login"))
	end)

	it("should ignore the login result of a superseded attempt", function()
		auth.methods = { "password" }
		auth.defer_login = true
		inputs = { "@alice:example.org", "@alice:example.org" }

		run_login()
		local stale_login = calls.pending_login
		run_login()

		stale_login()
		vim.wait(50)

		assert.are.equal(0, calls.toggled)
		assert.is_false(notified("info", "Login successful"))
	end)

	it("should mark a login as superseded when a newer attempt is cancelled early", function()
		auth.methods = { "password" }
		auth.defer_login = true
		inputs = { "@alice:example.org", "" }

		run_login()
		local stale_login = calls.pending_login
		run_login()

		stale_login()
		vim.wait(50)

		assert.is_false(calls.login_was_current)
		assert.are.equal(0, calls.toggled)
	end)

	it("should keep a login current while no newer attempt was started", function()
		auth.methods = { "password" }
		auth.defer_login = true
		inputs = { "@alice:example.org" }

		run_login()
		calls.pending_login()
		vim.wait(50)

		assert.is_true(calls.login_was_current)
		assert.are.equal(1, calls.toggled)
	end)

	it("should ignore a paste prompt from a superseded attempt", function()
		vim.env.SSH_TTY = "/dev/pts/1"
		auth.methods = { "sso" }
		inputs = { "example.org", "example.org" }
		local pending_prompts = {}
		vim.ui.input = function(_, on_confirm)
			table.insert(pending_prompts, on_confirm)
		end

		run_login()
		run_login()
		pending_prompts[1]("XYZ")

		assert.are.same({}, calls.login_token)
	end)

	it("should show the server error when the token is rejected", function()
		auth.methods = { "sso" }
		auth.login_result = error_mod.err({ errcode = "M_FORBIDDEN", error = "Invalid login token" })
		inputs = { "example.org" }

		run_login()
		listeners[1].opts.on_token("XYZ")
		vim.wait(50)

		assert.is_true(notified("error", "Invalid login token"))
		assert.are.equal(0, calls.toggled)
	end)
end)
