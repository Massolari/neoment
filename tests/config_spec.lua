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
end)
