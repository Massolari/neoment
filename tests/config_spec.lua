describe("config", function()
	local config
	local original

	before_each(function()
		original = vim.g.neoment
		package.loaded["neoment.config"] = nil
		config = require("neoment.config")
	end)

	after_each(function()
		vim.g.neoment = original
		package.loaded["neoment.config"] = nil
	end)

	describe("login_method", function()
		it("is not set by default", function()
			vim.g.neoment = {}

			config.load()

			assert.is_nil(config.get().login_method)
		end)

		it("accepts each login method", function()
			for _, method in ipairs({ "password", "sso", "oauth_device" }) do
				vim.g.neoment = { login_method = method }

				config.load()

				assert.are.equal(method, config.get().login_method)
			end
		end)

		it("rejects any other value", function()
			vim.g.neoment = { login_method = "magic_link" }

			local ok, err = pcall(config.load)

			assert.is_false(ok)
			assert.matches("login_method", err, 1, true)
			assert.matches("password, sso, oauth_device", err, 1, true)
		end)
	end)

	describe("desktop_notifications.source", function()
		it("is server by default", function()
			vim.g.neoment = {}

			config.load()

			assert.are.equal("server", config.get().desktop_notifications.source)
		end)

		it("keeps the custom source", function()
			vim.g.neoment = { desktop_notifications = { source = "custom" } }

			config.load()

			assert.are.equal("custom", config.get().desktop_notifications.source)
		end)

		it("rejects any other value", function()
			vim.g.neoment = { desktop_notifications = { source = "push" } }

			local ok, err = pcall(config.load)

			assert.is_false(ok)
			assert.matches("desktop_notifications.source", err, 1, true)
			assert.matches("server, custom", err, 1, true)
		end)
	end)

	describe("custom levels warning", function()
		local original_notify
		local warnings

		before_each(function()
			original_notify = package.loaded["neoment.notify"]
			warnings = {}
			package.loaded["neoment.notify"] = {
				warning = function(msg)
					table.insert(warnings, msg)
				end,
			}
		end)

		after_each(function()
			package.loaded["neoment.notify"] = original_notify
		end)

		it("warns once when custom levels are set without a source", function()
			vim.g.neoment = { desktop_notifications = { rooms = "all" } }

			config.load()
			config.load()

			assert.are.equal(1, #warnings)
			assert.matches("ignored", warnings[1], 1, true)
			assert.matches('source = "custom"', warnings[1], 1, true)
		end)

		it("does not warn when the source is set", function()
			vim.g.neoment = { desktop_notifications = { rooms = "all", source = "server" } }

			config.load()

			assert.are.equal(0, #warnings)
		end)

		it("does not warn without custom levels", function()
			vim.g.neoment = { desktop_notifications = { enabled = true } }

			config.load()

			assert.are.equal(0, #warnings)
		end)
	end)
end)
