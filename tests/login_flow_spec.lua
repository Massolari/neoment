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
		"neoment.matrix.oauth",
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
	--- What the user answers to the offer to open the verification page
	local open_answer
	--- The configured `login_method`
	local login_method
	local oauth
	--- The OAuth device logins polling for the approval, oldest first
	local polls

	before_each(function()
		calls = {
			login_password = {},
			login_token = {},
			login_oauth = {},
			opened = {},
			selects = 0,
			select_prompts = {},
			pastes = 0,
			toggled = 0,
			synced = 0,
		}
		polls = {}
		open_answer = nil
		login_method = nil
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
		vim.ui.select = function(items, opts, on_choice)
			table.insert(calls.select_prompts, opts.prompt)
			if opts.prompt == "Login method:" then
				calls.selects = calls.selects + 1
				calls.select_items = items
				on_choice(selected_method)
			else
				on_choice(open_answer)
			end
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
		package.loaded["neoment.notify"] =
			{ info = record("info"), warning = record("warning"), error = record("error") }
		package.loaded["neoment.config"] = {
			load = function() end,
			get = function()
				return { save_session = false, login_method = login_method }
			end,
		}
		package.loaded["neoment.sync"] = {
			start = function()
				calls.synced = calls.synced + 1
			end,
		}
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
			client = { user_id = "@alice:example.org", device_id = "MYDEVICE" },
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
			callback(auth.flows_result or error_mod.ok(auth.methods), auth.oauth_metadata)
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
		auth.login_oauth = function(tokens, metadata, client_id, callback)
			table.insert(calls.login_oauth, { tokens = tokens, metadata = metadata, client_id = client_id })
			callback(auth.login_result)
		end
		package.loaded["neoment.matrix.auth"] = auth

		oauth = {
			register_result = error_mod.ok("client-1"),
			device_result = error_mod.ok({
				device_code = "DEV",
				user_code = "ABCD-EFGH",
				verification_url = "https://auth.example.org/link?code=ABCD-EFGH",
				code_in_url = true,
				expires_in = 600,
				interval = 5,
			}),
		}
		oauth.register_client = function(metadata, callback)
			calls.registered = metadata
			callback(oauth.register_result)
		end
		oauth.request_device_code = function(_, client_id, device_id, callback)
			calls.device_request = { client_id = client_id, device_id = device_id }
			callback(oauth.device_result)
		end
		oauth.poll = function(opts, callback)
			local poll = { opts = opts, finish = callback, cancelled = false }
			poll.cancel = function()
				poll.cancelled = true
			end
			table.insert(polls, poll)
			return poll
		end
		package.loaded["neoment.matrix.oauth"] = oauth

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

	it("should supersede a pending SSO login when a saved session is restored", function()
		auth.methods = { "sso" }
		inputs = { "example.org" }

		run_login()
		package.loaded["neoment.storage"].restore_session = function()
			return true
		end
		run_login()

		assert.is_true(listeners[1].closed)
		listeners[1].opts.on_token("XYZ")
		vim.wait(50)

		assert.are.same({}, calls.login_token)
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

	describe("login method selection", function()
		--- @param methods string[]
		local function offer(methods)
			auth.methods = methods
			if vim.tbl_contains(methods, "oauth_device") then
				auth.oauth_metadata = { issuer = "https://auth.example.org/" }
			end
			inputs = { "@alice:example.org" }
		end

		it("should use OAuth device login without asking when it is offered", function()
			offer({ "oauth_device", "password", "sso" })

			run_login()

			assert.are.equal(0, calls.selects)
			assert.are.equal("https://auth.example.org/", calls.registered.issuer)
			assert.are.same({}, calls.login_password)
		end)

		it("should use OAuth device login on a server that offers nothing else", function()
			offer({ "oauth_device" })

			run_login()

			assert.are.equal(1, #polls)
			assert.is_false(notified("error", "not offered"))
		end)

		it("should use the forced method even when OAuth is preferred", function()
			login_method = "password"
			offer({ "oauth_device", "password" })

			run_login()

			assert.are.equal(0, calls.selects)
			assert.are.equal(0, #polls)
			assert.are.equal(1, #calls.login_password)
		end)

		it("should use a forced OAuth device login", function()
			login_method = "oauth_device"
			offer({ "oauth_device", "password" })

			run_login()

			assert.are.equal(1, #polls)
			assert.are.same({}, calls.login_password)
		end)

		it("should use a forced method when it is the only one too", function()
			login_method = "sso"
			offer({ "sso" })

			run_login()

			assert.are.equal(1, #listeners)
		end)

		it("should show an error when the forced method is not offered", function()
			login_method = "sso"
			offer({ "oauth_device", "password" })

			run_login()

			assert.is_true(notified("error", "'sso'"))
			assert.is_true(notified("error", "oauth_device, password"))
			assert.are.equal(0, #polls)
			assert.are.same({}, calls.login_password)
			assert.are.equal(0, calls.toggled)
		end)

		it("should keep asking between password and SSO without OAuth", function()
			offer({ "password", "sso" })
			selected_method = "sso"

			run_login()

			assert.are.equal(1, calls.selects)
			assert.are.equal(1, #listeners)
		end)
	end)

	describe("OAuth device login", function()
		--- Start a login that uses OAuth device login
		local function run_oauth_login()
			auth.methods = { "oauth_device" }
			auth.oauth_metadata = { issuer = "https://auth.example.org/" }
			inputs = { "@alice:example.org" }
			run_login()
		end

		it("should request the device code for the registered client and this device", function()
			run_oauth_login()

			assert.are.same({ client_id = "client-1", device_id = "MYDEVICE" }, calls.device_request)
			assert.are.equal("client-1", polls[1].opts.client_id)
			assert.are.equal("DEV", polls[1].opts.device_code.device_code)
		end)

		it("should show the URL and the code", function()
			run_oauth_login()

			assert.is_true(notified("info", "https://auth.example.org/link?code=ABCD-EFGH"))
			assert.is_true(notified("info", "ABCD-EFGH"))
		end)

		it("should tell the user to enter the code when the URL does not carry it", function()
			oauth.device_result = error_mod.ok({
				device_code = "DEV",
				user_code = "ABCD-EFGH",
				verification_url = "https://auth.example.org/link",
				code_in_url = false,
				expires_in = 600,
				interval = 5,
			})

			run_oauth_login()

			assert.is_true(notified("info", "enter the code ABCD-EFGH"))
		end)

		it("should offer to open the browser in a local session and open it when accepted", function()
			open_answer = "Open in browser"

			run_oauth_login()

			assert.are.same({ "Verification page:" }, calls.select_prompts)
			assert.are.same({ "https://auth.example.org/link?code=ABCD-EFGH" }, calls.opened)
		end)

		it("should keep polling when the user does not open the browser", function()
			open_answer = "Not now"

			run_oauth_login()

			assert.are.same({}, calls.opened)
			assert.are.equal(1, #polls)
			assert.is_false(polls[1].cancelled)
		end)

		it("should keep polling when the browser cannot be opened", function()
			open_answer = "Open in browser"
			vim.ui.open = function()
				return nil, "no opener found"
			end

			run_oauth_login()

			assert.is_true(notified("warning", "no opener found"))
			assert.is_false(polls[1].cancelled)
		end)

		it("should never open a browser in a remote session", function()
			vim.env.SSH_CONNECTION = "10.0.0.1 1234 10.0.0.2 22"
			open_answer = "Open in browser"

			run_oauth_login()

			assert.are.same({}, calls.select_prompts)
			assert.are.same({}, calls.opened)
			assert.is_true(notified("info", "https://auth.example.org/link?code=ABCD-EFGH"))
			assert.are.equal(1, #polls)
		end)

		it("should log in, sync and open the room list once approved", function()
			run_oauth_login()
			local tokens = { access_token = "AT", refresh_token = "RT", expires_in = 300 }

			polls[1].finish(error_mod.ok(tokens))
			vim.wait(50)

			assert.are.same(tokens, calls.login_oauth[1].tokens)
			assert.are.equal("client-1", calls.login_oauth[1].client_id)
			assert.is_true(notified("info", "Login successful as @alice:example.org"))
			assert.are.equal(1, calls.synced)
			assert.are.equal(1, calls.toggled)
		end)

		it("should show an error and not log in when the login is denied", function()
			run_oauth_login()

			polls[1].finish(error_mod.err({ error = "The login was denied", code = "access_denied" }))
			vim.wait(50)

			assert.is_true(notified("error", "The login was denied"))
			assert.are.same({}, calls.login_oauth)
			assert.are.equal(0, calls.toggled)
		end)

		it("should show an error and not log in when the code expires", function()
			run_oauth_login()

			polls[1].finish(error_mod.err({ error = "The login code expired", code = "expired_token" }))
			vim.wait(50)

			assert.is_true(notified("error", "The login code expired"))
			assert.are.same({}, calls.login_oauth)
			assert.are.equal(0, calls.toggled)
		end)

		it("should show an error when the registration fails", function()
			oauth.register_result = error_mod.err({ error = "Could not register the client: nope" })

			run_oauth_login()

			assert.is_true(notified("error", "Could not register the client: nope"))
			assert.are.equal(0, #polls)
		end)

		it("should show an error when the device code cannot be requested", function()
			oauth.device_result = error_mod.err({ error = "Client not found", code = "invalid_client" })

			run_oauth_login()

			assert.is_true(notified("error", "Client not found"))
			assert.are.equal(0, #polls)
		end)

		it("should cancel the first poll and ignore its result when the login starts again", function()
			auth.methods = { "oauth_device" }
			auth.oauth_metadata = { issuer = "https://auth.example.org/" }
			inputs = { "example.org", "example.org" }

			run_login()
			run_login()

			assert.are.equal(2, #polls)
			assert.is_true(polls[1].cancelled)
			assert.is_false(polls[2].cancelled)

			polls[1].finish(error_mod.ok({ access_token = "STALE" }))
			vim.wait(50)

			assert.are.same({}, calls.login_oauth)
			assert.are.equal(0, calls.toggled)
		end)

		it("should cancel the polling when a saved session is restored", function()
			run_oauth_login()
			package.loaded["neoment.storage"].restore_session = function()
				return true
			end

			neoment.init()
			vim.wait(50)

			assert.is_true(polls[1].cancelled)
		end)
	end)

	describe("logout", function()
		local cleared
		local stopped

		before_each(function()
			cleared = 0
			stopped = 0
			package.loaded["neoment.sync"].stop = function()
				stopped = stopped + 1
			end
			package.loaded["neoment.storage"].clear_session = function()
				cleared = cleared + 1
				return true
			end
		end)

		it("should clear the saved session once the server accepts the logout", function()
			package.loaded["neoment.matrix"].logout = function(callback)
				callback(error_mod.ok(nil))
			end

			neoment.logout()

			assert.are.equal(1, stopped)
			assert.are.equal(1, cleared)
			assert.is_true(notified("info", "Logout successful"))
		end)

		it("should keep the saved session and show an error when the logout fails", function()
			package.loaded["neoment.matrix"].logout = function(callback)
				callback(error_mod.err({ error = "Revocation failed" }))
			end

			neoment.logout()

			assert.are.equal(0, cleared)
			assert.is_true(notified("error", "Logout failed: Revocation failed"))
		end)
	end)
end)
