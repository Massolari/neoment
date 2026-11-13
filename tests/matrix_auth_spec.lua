local error_mod = require("neoment.error")

describe("Matrix auth", function()
	local curl_mock
	local auth
	local client
	local matrix

	before_each(function()
		curl_mock = {}
		package.loaded["neoment.curl"] = curl_mock
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.auth"] = nil
		package.loaded["neoment.matrix"] = nil

		client = require("neoment.matrix.client")
		auth = require("neoment.matrix.auth")
		matrix = require("neoment.matrix")
	end)

	after_each(function()
		package.loaded["neoment.curl"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.auth"] = nil
		package.loaded["neoment.matrix"] = nil
	end)

	--- Make the mocked curl respond to GET requests based on the URL.
	--- @param responses table<string, table> Map of URL to response ({ status, body } or { fail = true })
	local function mock_get(responses)
		curl_mock.get = function(url, opts)
			local response = responses[url]
			if not response or response.fail then
				opts.on_error({ message = "connection failed" })
				return
			end
			opts.callback(response)
		end
	end

	describe("set_homeserver", function()
		it("should create the client when none exists", function()
			client.set_homeserver("https://matrix.example.org")

			assert.are.equal("https://matrix.example.org", client.client.homeserver)
		end)

		it("should point an existing client at the new homeserver", function()
			client.new("https://old.example.org")
			client.set_homeserver("https://new.example.org")

			assert.are.equal("https://new.example.org", client.client.homeserver)
		end)

		it("should discard the previous session state but keep the device ID", function()
			client.new("https://old.example.org", "old-token")
			client.client.device_id = "MYDEVICE"
			client.client.user_id = "@alice:old.example.org"
			client.client.sync_token = "s123"
			client.get_room("!room:old.example.org")
			client.get_invited_room("!invite:old.example.org")
			client.set_user_presence("@bob:old.example.org", { presence = "online" })

			client.set_homeserver("https://new.example.org")

			assert.are.equal("https://new.example.org", client.client.homeserver)
			assert.are.equal("MYDEVICE", client.client.device_id)
			assert.is_nil(client.client.access_token)
			assert.is_nil(client.client.user_id)
			assert.is_nil(client.client.sync_token)
			assert.are.same({}, client.get_rooms())
			assert.are.same({}, client.get_invited_rooms())
			assert.is_nil(client.get_user_presence("@bob:old.example.org"))
			assert.is_false(matrix.is_logged_in())
		end)
	end)

	describe("parse_server_name", function()
		it("should extract the server name from a full Matrix ID", function()
			local server_name, user_id = auth.parse_server_name("@alice:example.org")

			assert.are.equal("example.org", server_name)
			assert.are.equal("@alice:example.org", user_id)
		end)

		it("should accept a bare server name", function()
			local server_name, user_id = auth.parse_server_name("  mozilla.org ")

			assert.are.equal("mozilla.org", server_name)
			assert.is_nil(user_id)
		end)

		it("should keep the port of the server name", function()
			local server_name = auth.parse_server_name("@alice:localhost:8448")

			assert.are.equal("localhost:8448", server_name)
		end)

		it("should return nil for empty input", function()
			assert.is_nil(auth.parse_server_name(""))
			assert.is_nil(auth.parse_server_name("   "))
		end)

		it("should return nil for a Matrix ID without a server name", function()
			assert.is_nil(auth.parse_server_name("@alice"))
		end)
	end)

	describe("discover", function()
		it("should follow redirects and use the delegated homeserver", function()
			local received_raw
			curl_mock.get = function(url, opts)
				assert.are.equal("https://mozilla.org/.well-known/matrix/client", url)
				received_raw = opts.raw
				opts.callback({
					status = 200,
					body = vim.json.encode({ ["m.homeserver"] = { base_url = "https://mozilla.modular.im/" } }),
				})
			end

			local homeserver
			auth.discover("mozilla.org", function(result)
				homeserver = result
			end)

			assert.are.same({ "-L" }, received_raw)
			assert.are.equal("https://mozilla.modular.im", homeserver)
		end)

		it("should fall back when the well-known body is not JSON", function()
			mock_get({
				["https://example.org/.well-known/matrix/client"] = { status = 404, body = "<html>Not found</html>" },
			})

			local homeserver
			auth.discover("example.org", function(result)
				homeserver = result
			end)

			assert.are.equal("https://example.org", homeserver)
		end)

		it("should fall back when m.homeserver is missing", function()
			mock_get({
				["https://example.org/.well-known/matrix/client"] = {
					status = 200,
					body = vim.json.encode({ ["m.identity_server"] = { base_url = "https://vector.im" } }),
				},
			})

			local homeserver
			auth.discover("example.org", function(result)
				homeserver = result
			end)

			assert.are.equal("https://example.org", homeserver)
		end)

		it("should fall back when the request fails", function()
			mock_get({})

			local homeserver
			auth.discover("example.org", function(result)
				homeserver = result
			end)

			assert.are.equal("https://example.org", homeserver)
		end)
	end)

	describe("get_login_flows", function()
		local function flows_response(types)
			local flows = {}
			for _, flow_type in ipairs(types) do
				table.insert(flows, { type = flow_type })
			end
			return { status = 200, body = vim.json.encode({ flows = flows }) }
		end

		it("should return password and SSO when both are offered", function()
			mock_get({
				["https://matrix.example.org/_matrix/client/v3/login"] = flows_response({
					"m.login.sso",
					"m.login.token",
					"m.login.password",
				}),
			})

			local result
			auth.get_login_flows("https://matrix.example.org", function(r)
				result = r
			end)

			assert.is_true(error_mod.is_ok(result))
			assert.are.same({ "password", "sso" }, result.data)
		end)

		it("should return only SSO when the server offers SSO and token", function()
			mock_get({
				["https://mozilla.modular.im/_matrix/client/v3/login"] = flows_response({
					"m.login.sso",
					"m.login.token",
				}),
			})

			local result
			auth.get_login_flows("https://mozilla.modular.im", function(r)
				result = r
			end)

			assert.are.same({ "sso" }, result.data)
		end)

		it("should error with the advertised flows when none is supported", function()
			mock_get({
				["https://matrix.example.org/_matrix/client/v3/login"] = flows_response({
					"m.login.token",
					"m.login.application_service",
				}),
			})

			local result
			auth.get_login_flows("https://matrix.example.org", function(r)
				result = r
			end)

			assert.is_true(error_mod.is_error(result))
			assert.matches("m.login.token, m.login.application_service", result.error.error, 1, true)
		end)

		it("should error with the homeserver URL when the request fails", function()
			mock_get({})

			local result
			auth.get_login_flows("https://matrix.example.org", function(r)
				result = r
			end)

			assert.is_true(error_mod.is_error(result))
			assert.matches("https://matrix.example.org", result.error.error, 1, true)
		end)
	end)

	describe("login_password", function()
		it("should send a password login and store the credentials", function()
			client.new("https://matrix.example.org")
			local sent_url, sent_body
			curl_mock.post = function(url, opts)
				sent_url = url
				sent_body = vim.json.decode(opts.body)
				opts.callback({
					status = 200,
					body = vim.json.encode({ access_token = "secret", user_id = "@alice:example.org" }),
				})
			end

			local result
			auth.login_password("@alice:example.org", "hunter2", function(r)
				result = r
			end)

			assert.is_true(error_mod.is_ok(result))
			assert.are.equal("https://matrix.example.org/_matrix/client/v3/login", sent_url)
			assert.are.same({
				type = "m.login.password",
				identifier = { type = "m.id.user", user = "@alice:example.org" },
				password = "hunter2",
				device_id = client.client.device_id,
			}, sent_body)
			assert.are.equal("secret", client.client.access_token)
			assert.are.equal("@alice:example.org", client.client.user_id)
		end)

		it("should discover the homeserver when using matrix.login", function()
			client.new("https://stale.example.org")
			mock_get({
				["https://mozilla.org/.well-known/matrix/client"] = {
					status = 200,
					body = vim.json.encode({ ["m.homeserver"] = { base_url = "https://mozilla.modular.im" } }),
				},
			})
			local sent_url
			curl_mock.post = function(url, opts)
				sent_url = url
				opts.callback({
					status = 200,
					body = vim.json.encode({ access_token = "secret", user_id = "@alice:mozilla.org" }),
				})
			end

			matrix.login("@alice:mozilla.org", "hunter2", function() end)

			assert.are.equal("https://mozilla.modular.im/_matrix/client/v3/login", sent_url)
		end)
	end)

	describe("sso_redirect_url", function()
		it("should encode the redirect URL", function()
			local url = auth.sso_redirect_url("https://mozilla.modular.im", "http://127.0.0.1:4567/")

			assert.are.equal(
				"https://mozilla.modular.im/_matrix/client/v3/login/sso/redirect?redirectUrl=http%3a%2f%2f127.0.0.1%3a4567%2f",
				url
			)
		end)
	end)

	describe("login_token", function()
		it("should exchange the token and store the credentials", function()
			client.new("https://mozilla.modular.im")
			local sent_body
			curl_mock.post = function(_, opts)
				sent_body = vim.json.decode(opts.body)
				opts.callback({
					status = 200,
					body = vim.json.encode({ access_token = "secret", user_id = "@alice:mozilla.org" }),
				})
			end

			local result
			auth.login_token("XYZ", function(r)
				result = r
			end)

			assert.is_true(error_mod.is_ok(result))
			assert.are.same({
				type = "m.login.token",
				token = "XYZ",
				device_id = client.client.device_id,
			}, sent_body)
			assert.are.equal("@alice:mozilla.org", client.client.user_id)
		end)

		it("should return the server error when the token is rejected", function()
			client.new("https://mozilla.modular.im")
			curl_mock.post = function(_, opts)
				opts.callback({
					status = 403,
					body = vim.json.encode({ errcode = "M_FORBIDDEN", error = "Invalid login token" }),
				})
			end

			local result
			auth.login_token("XYZ", function(r)
				result = r
			end)

			assert.is_true(error_mod.is_error(result))
			assert.are.equal("M_FORBIDDEN", result.error.errcode)
			assert.is_nil(client.client.access_token)
		end)
	end)

	describe("parse_login_token", function()
		it("should extract the token from a redirect URL", function()
			assert.are.equal("XYZ", auth.parse_login_token("http://127.0.0.1:4567/?loginToken=XYZ"))
		end)

		it("should extract the token when it is not the first parameter", function()
			assert.are.equal("XYZ", auth.parse_login_token("http://127.0.0.1:4567/?foo=bar&loginToken=XYZ#frag"))
		end)

		it("should decode a percent-encoded token", function()
			assert.are.equal("a+b/c", auth.parse_login_token("http://127.0.0.1/?loginToken=a%2Bb%2Fc"))
		end)

		it("should accept a bare token", function()
			assert.are.equal("XYZ", auth.parse_login_token("  XYZ \n"))
		end)

		it("should return nil for empty input", function()
			assert.is_nil(auth.parse_login_token(""))
			assert.is_nil(auth.parse_login_token(nil))
		end)
	end)
end)
