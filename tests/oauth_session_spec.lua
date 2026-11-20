describe("OAuth session round trip", function()
	local METADATA = {
		issuer = "https://auth.example.org/",
		device_authorization_endpoint = "https://auth.example.org/oauth2/device",
		token_endpoint = "https://auth.example.org/oauth2/token",
		registration_endpoint = "https://auth.example.org/oauth2/registration",
		revocation_endpoint = "https://auth.example.org/oauth2/revoke",
	}
	local MODULES = {
		"neoment.curl",
		"neoment.notify",
		"neoment.storage",
		"neoment.matrix",
		"neoment.matrix.api",
		"neoment.matrix.auth",
		"neoment.matrix.client",
		"neoment.matrix.oauth",
		"neoment.matrix.token",
	}

	local original_stdpath
	local temp_dir
	local posts

	before_each(function()
		temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir .. "/neoment", "p")
		original_stdpath = vim.fn.stdpath
		vim.fn.stdpath = function()
			return temp_dir
		end

		posts = {}
		for _, name in ipairs(MODULES) do
			package.loaded[name] = nil
		end
		package.loaded["neoment.notify"] = { info = function() end, error = function() end, warning = function() end }
		package.loaded["neoment.curl"] = {
			get = function(_, opts)
				opts.callback({ status = 200, body = vim.json.encode({ user_id = "@alice:example.org" }) })
			end,
			post = function(endpoint, opts)
				table.insert(posts, { endpoint = endpoint, opts = opts })
			end,
		}
	end)

	after_each(function()
		vim.fn.stdpath = original_stdpath
		vim.fn.delete(temp_dir, "rf")
		for _, name in ipairs(MODULES) do
			package.loaded[name] = nil
		end
	end)

	it("saves the OAuth refresh method and refreshes the restored session at the token endpoint", function()
		local client = require("neoment.matrix.client")
		local auth = require("neoment.matrix.auth")
		local storage = require("neoment.storage")
		local token = require("neoment.matrix.token")

		client.new("https://matrix.example.org")
		local login_result
		auth.login_oauth(
			{ access_token = "AT", refresh_token = "RT", expires_in = 300 },
			METADATA,
			"client-1",
			function(result)
				login_result = result
			end
		)
		assert.is_true(login_result:is_ok())
		assert.is_true(storage.save_session())

		local file = assert(io.open(temp_dir .. "/neoment/data.json", "r"))
		local saved = vim.json.decode(file:read("*all"))
		file:close()
		assert.are.same({
			kind = "oauth",
			token_endpoint = METADATA.token_endpoint,
			client_id = "client-1",
			revocation_endpoint = METADATA.revocation_endpoint,
		}, saved.refresh)
		assert.are.equal("RT", saved.refresh_token)
		assert.are.equal("@alice:example.org", saved.user_id)

		-- A new Neovim: nothing but the file is left, and the access token has expired in the meantime
		client.client = nil
		assert.is_true(storage.restore_session())
		client.client.expires_at = os.time() - 10

		local refreshed
		token.refresh(function(result)
			refreshed = result
		end)

		assert.are.equal(1, #posts)
		assert.are.equal(METADATA.token_endpoint, posts[1].endpoint)
		assert.matches("grant_type=refresh_token", posts[1].opts.body, 1, true)
		assert.matches("refresh_token=RT", posts[1].opts.body, 1, true)
		assert.matches("client_id=client-1", posts[1].opts.body, 1, true)

		posts[1].opts.callback({
			status = 200,
			body = vim.json.encode({ access_token = "AT2", refresh_token = "RT2", expires_in = 300 }),
		})

		assert.is_true(refreshed:is_ok())
		assert.are.equal("AT2", client.client.access_token)
		assert.are.equal("RT2", client.client.refresh_token)
		assert.are.equal("client-1", client.client.refresh.client_id)
	end)
end)
