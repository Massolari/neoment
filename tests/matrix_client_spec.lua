describe("matrix client", function()
	local client

	before_each(function()
		package.loaded["neoment.matrix.client"] = nil
		client = require("neoment.matrix.client")
	end)

	after_each(function()
		package.loaded["neoment.matrix.client"] = nil
	end)

	describe("new", function()
		it("leaves the refresh fields unset", function()
			client.new("https://example.org", "token")

			assert.are.equal("token", client.client.access_token)
			assert.is_nil(client.client.refresh_token)
			assert.is_nil(client.client.expires_at)
			assert.is_nil(client.client.refresh)
		end)
	end)

	describe("set_homeserver", function()
		it("drops the refresh fields of the previous session", function()
			client.new("https://example.org", "token")
			client.client.refresh_token = "refresh"
			client.client.expires_at = os.time() + 300
			client.client.refresh = { kind = "legacy" }

			client.set_homeserver("https://other.example.org")

			assert.are.equal("https://other.example.org", client.client.homeserver)
			assert.is_nil(client.client.refresh_token)
			assert.is_nil(client.client.expires_at)
			assert.is_nil(client.client.refresh)
		end)
	end)
end)
