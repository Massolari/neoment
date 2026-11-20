local error_mod = require("neoment.error")

describe("Matrix logout", function()
	local MODULES = {
		"neoment.curl",
		"neoment.matrix",
		"neoment.matrix.api",
		"neoment.matrix.client",
		"neoment.matrix.oauth",
		"neoment.matrix.token",
	}
	local OAUTH_REFRESH = {
		kind = "oauth",
		token_endpoint = "https://auth.example.org/oauth2/token",
		client_id = "client-1",
		revocation_endpoint = "https://auth.example.org/oauth2/revoke",
	}

	local client
	local matrix
	--- The requests sent, oldest first
	local posts

	--- Answer the oldest request that is still waiting
	--- @param status integer
	--- @param body string
	local function respond(status, body)
		local request = table.remove(posts, 1)
		request.opts.callback({ status = status, body = body, exit = 0 })
	end

	--- @param fields? table
	local function login(fields)
		client.new("https://matrix.example.org", "AT")
		client.client.user_id = "@alice:example.org"
		for key, value in pairs(fields or {}) do
			client.client[key] = value
		end
	end

	--- @return neoment.Error<nil, neoment.matrix.api.Error>|nil
	local function logout()
		local result
		matrix.logout(function(r)
			result = r
		end)
		return result
	end

	before_each(function()
		posts = {}
		for _, name in ipairs(MODULES) do
			package.loaded[name] = nil
		end
		package.loaded["neoment.curl"] = {
			post = function(endpoint, opts)
				table.insert(posts, { endpoint = endpoint, opts = opts })
			end,
		}
		client = require("neoment.matrix.client")
		matrix = require("neoment.matrix")
	end)

	after_each(function()
		for _, name in ipairs(MODULES) do
			package.loaded[name] = nil
		end
	end)

	describe("of an OAuth session", function()
		before_each(function()
			login({ refresh_token = "RT", expires_at = os.time() + 300, refresh = OAUTH_REFRESH })
		end)

		it("sends only the revocation request, without credentials", function()
			local result
			matrix.logout(function(r)
				result = r
			end)

			assert.are.equal(1, #posts)
			assert.are.equal(OAUTH_REFRESH.revocation_endpoint, posts[1].endpoint)
			assert.is_nil(posts[1].opts.headers["Authorization"])
			assert.matches("token=RT", posts[1].opts.body, 1, true)
			assert.matches("client_id=client-1", posts[1].opts.body, 1, true)

			respond(200, "{}")

			assert.is_true(error_mod.is_ok(result))
			assert.are.equal(0, #posts)
		end)

		it("does not refresh an expired access token first", function()
			client.client.expires_at = os.time() - 10

			matrix.logout(function() end)

			assert.are.equal(1, #posts)
			assert.are.equal(OAUTH_REFRESH.revocation_endpoint, posts[1].endpoint)
		end)

		it("returns the error when the revocation fails", function()
			local result
			matrix.logout(function(r)
				result = r
			end)
			respond(500, vim.json.encode({ error = "server_error", error_description = "Try later" }))

			assert.is_true(error_mod.is_error(result))
			assert.matches("Try later", result.error.error, 1, true)
		end)
	end)

	it("sends /logout when an OAuth session has no revocation endpoint", function()
		login({
			refresh_token = "RT",
			expires_at = os.time() + 300,
			refresh = { kind = "oauth", token_endpoint = OAUTH_REFRESH.token_endpoint, client_id = "client-1" },
		})

		local result
		matrix.logout(function(r)
			result = r
		end)

		assert.are.equal(1, #posts)
		assert.are.equal("https://matrix.example.org/_matrix/client/v3/logout", posts[1].endpoint)
		assert.are.equal("Bearer AT", posts[1].opts.headers["Authorization"])

		respond(200, "{}")

		assert.is_true(error_mod.is_ok(result))
	end)

	it("sends /logout for a legacy session", function()
		login()

		matrix.logout(function() end)

		assert.are.equal("https://matrix.example.org/_matrix/client/v3/logout", posts[1].endpoint)
		assert.are.equal("Bearer AT", posts[1].opts.headers["Authorization"])
	end)

	it("sends /logout for an OAuth session without a refresh token", function()
		login({ refresh = OAUTH_REFRESH })

		matrix.logout(function() end)

		assert.are.equal("https://matrix.example.org/_matrix/client/v3/logout", posts[1].endpoint)
	end)

	it("succeeds without a request when nobody is logged in", function()
		client.new("https://matrix.example.org")

		assert.is_true(error_mod.is_ok(logout()))
		assert.are.equal(0, #posts)
	end)
end)
