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
		package.loaded["neoment.matrix.oauth"] = nil
		package.loaded["neoment.matrix.token"] = nil
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
		package.loaded["neoment.matrix.oauth"] = nil
		package.loaded["neoment.matrix.token"] = nil
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

		it("should remove trailing slashes from a bare server name", function()
			assert.are.equal("example.org", auth.parse_server_name("example.org/"))
		end)

		it("should accept a homeserver URL without trailing slashes", function()
			local server_name, user_id = auth.parse_server_name("https://matrix.example.org/")

			assert.are.equal("https://matrix.example.org", server_name)
			assert.is_nil(user_id)
		end)
	end)

	describe("discover", function()
		it("should use the delegated homeserver with a bounded request time", function()
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

			assert.is_true(vim.tbl_contains(received_raw, "--max-time"))
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

		it("should fall back when the well-known body is JSON null", function()
			mock_get({
				["https://example.org/.well-known/matrix/client"] = { status = 200, body = "null" },
			})

			local homeserver
			auth.discover("example.org", function(result)
				homeserver = result
			end)

			assert.are.equal("https://example.org", homeserver)
		end)

		it("should look up well-known without the port and keep it for the fallback", function()
			local requested_url
			curl_mock.get = function(url, opts)
				requested_url = url
				opts.on_error({ message = "connection failed" })
			end

			local homeserver
			auth.discover("example.org:8448", function(result)
				homeserver = result
			end)

			assert.are.equal("https://example.org/.well-known/matrix/client", requested_url)
			assert.are.equal("https://example.org:8448", homeserver)
		end)

		it("should use a homeserver URL without discovery", function()
			curl_mock.get = function()
				error("unexpected request")
			end

			local homeserver
			auth.discover("http://localhost:8008", function(result)
				homeserver = result
			end)

			assert.are.equal("http://localhost:8008", homeserver)
		end)

		it("should fall back when base_url has no HTTP(S) scheme", function()
			mock_get({
				["https://example.org/.well-known/matrix/client"] = {
					status = 200,
					body = vim.json.encode({ ["m.homeserver"] = { base_url = "matrix.example.org" } }),
				},
			})

			local homeserver
			auth.discover("example.org", function(result)
				homeserver = result
			end)

			assert.are.equal("https://example.org", homeserver)
		end)

		it("should treat the URL scheme case-insensitively", function()
			local server_name = auth.parse_server_name("HTTPS://matrix.example.org")

			local homeserver
			auth.discover(server_name, function(result)
				homeserver = result
			end)

			assert.are.equal("HTTPS://matrix.example.org", homeserver)
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

		it("should not offer SSO when the server does not offer token login", function()
			mock_get({
				["https://matrix.example.org/_matrix/client/v3/login"] = flows_response({
					"m.login.sso",
					"m.login.password",
				}),
			})

			local result
			auth.get_login_flows("https://matrix.example.org", function(r)
				result = r
			end)

			assert.are.same({ "password" }, result.data)
		end)

		it("should error instead of stalling when flows is not a list", function()
			mock_get({
				["https://matrix.example.org/_matrix/client/v3/login"] = { status = 200, body = '{"flows":null}' },
			})

			local result
			auth.get_login_flows("https://matrix.example.org", function(r)
				result = r
			end)

			assert.is_true(error_mod.is_error(result))
		end)

		it("should skip malformed flow entries", function()
			mock_get({
				["https://matrix.example.org/_matrix/client/v3/login"] = {
					status = 200,
					body = '{"flows":["oops",{"type":null},{"type":"m.login.password"}]}',
				},
			})

			local result
			auth.get_login_flows("https://matrix.example.org", function(r)
				result = r
			end)

			assert.are.same({ "password" }, result.data)
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

		describe("with OAuth metadata", function()
			local LOGIN_URL = "https://matrix.example.org/_matrix/client/v3/login"
			local METADATA_URL = "https://matrix.example.org/_matrix/client/v1/auth_metadata"
			local metadata_response = {
				status = 200,
				body = vim.json.encode({
					issuer = "https://auth.example.org/",
					device_authorization_endpoint = "https://auth.example.org/oauth2/device",
					token_endpoint = "https://auth.example.org/oauth2/token",
					registration_endpoint = "https://auth.example.org/oauth2/registration",
					grant_types_supported = { "urn:ietf:params:oauth:grant-type:device_code" },
				}),
			}

			--- @return table result
			--- @return table|nil metadata
			local function get_flows()
				local result, metadata
				auth.get_login_flows("https://matrix.example.org", function(r, m)
					result, metadata = r, m
				end)
				return result, metadata
			end

			it("should offer OAuth device login first and return the metadata", function()
				mock_get({
					[LOGIN_URL] = flows_response({ "m.login.password", "m.login.sso", "m.login.token" }),
					[METADATA_URL] = metadata_response,
				})

				local result, metadata = get_flows()

				assert.are.same({ "oauth_device", "password", "sso" }, result.data)
				assert.are.equal("https://auth.example.org/oauth2/token", metadata.token_endpoint)
			end)

			it("should succeed on a server that only offers OAuth", function()
				mock_get({
					[LOGIN_URL] = flows_response({ "m.login.token" }),
					[METADATA_URL] = metadata_response,
				})

				local result = get_flows()

				assert.is_true(error_mod.is_ok(result))
				assert.are.same({ "oauth_device" }, result.data)
			end)

			it("should succeed when the login flows cannot be fetched", function()
				mock_get({ [METADATA_URL] = metadata_response })

				local result = get_flows()

				assert.are.same({ "oauth_device" }, result.data)
			end)

			it("should only drop OAuth device login when the metadata is missing", function()
				mock_get({
					[LOGIN_URL] = flows_response({ "m.login.password" }),
					[METADATA_URL] = { status = 404, body = '{"errcode":"M_UNRECOGNIZED","error":"nope"}' },
				})

				local result, metadata = get_flows()

				assert.are.same({ "password" }, result.data)
				assert.is_nil(metadata)
			end)

			it("should send both requests before either answers", function()
				local requested = {}
				local callbacks = {}
				curl_mock.get = function(url, opts)
					table.insert(requested, url)
					callbacks[url] = opts.callback
				end

				local result
				auth.get_login_flows("https://matrix.example.org", function(r)
					result = r
				end)

				assert.are.equal(2, #requested)
				callbacks[METADATA_URL](metadata_response)
				assert.is_nil(result)
				callbacks[LOGIN_URL](flows_response({ "m.login.password" }))
				assert.are.same({ "oauth_device", "password" }, result.data)
			end)
		end)
	end)

	describe("get_oauth_metadata", function()
		local METADATA_URL = "https://matrix.example.org/_matrix/client/v1/auth_metadata"

		--- @param overrides? table
		--- @return table
		local function metadata_response(overrides)
			return {
				status = 200,
				body = vim.json.encode(vim.tbl_extend("force", {
					issuer = "https://auth.example.org/",
					device_authorization_endpoint = "https://auth.example.org/oauth2/device",
					token_endpoint = "https://auth.example.org/oauth2/token",
					registration_endpoint = "https://auth.example.org/oauth2/registration",
					revocation_endpoint = "https://auth.example.org/oauth2/revoke",
					grant_types_supported = {
						"authorization_code",
						"refresh_token",
						"urn:ietf:params:oauth:grant-type:device_code",
					},
				}, overrides or {})),
			}
		end

		--- @param response table
		--- @return table|nil
		local function get_metadata(response)
			mock_get({ [METADATA_URL] = response })
			local metadata = "not called"
			auth.get_oauth_metadata("https://matrix.example.org", function(m)
				metadata = m
			end)
			return metadata
		end

		it("should return the endpoints when the device code grant is supported", function()
			assert.are.same({
				issuer = "https://auth.example.org/",
				device_authorization_endpoint = "https://auth.example.org/oauth2/device",
				token_endpoint = "https://auth.example.org/oauth2/token",
				registration_endpoint = "https://auth.example.org/oauth2/registration",
				revocation_endpoint = "https://auth.example.org/oauth2/revoke",
			}, get_metadata(metadata_response()))
		end)

		it("should accept a server without a revocation endpoint", function()
			local metadata = get_metadata(metadata_response({ revocation_endpoint = vim.NIL }))

			assert.is_not_nil(metadata)
			assert.is_nil(metadata.revocation_endpoint)
		end)

		it("should be unavailable when the device code grant is not listed", function()
			assert.is_nil(get_metadata(metadata_response({ grant_types_supported = { "authorization_code" } })))
		end)

		it("should be unavailable when the server does not know the endpoint", function()
			assert.is_nil(get_metadata({
				status = 404,
				body = vim.json.encode({ errcode = "M_UNRECOGNIZED", error = "Unrecognized request" }),
			}))
		end)

		it("should be unavailable when the body is not JSON", function()
			assert.is_nil(get_metadata({ status = 200, body = "<html>not found</html>" }))
		end)

		it("should be unavailable when the body is not an object", function()
			assert.is_nil(get_metadata({ status = 200, body = "[]" }))
		end)

		it("should be unavailable without a registration endpoint", function()
			assert.is_nil(get_metadata(metadata_response({ registration_endpoint = vim.NIL })))
		end)

		it("should be unavailable when an endpoint is not an HTTP URL", function()
			assert.is_nil(get_metadata(metadata_response({ token_endpoint = "ftp://auth.example.org/token" })))
		end)

		it("should be unavailable when the request fails", function()
			mock_get({})
			local metadata = "not called"
			auth.get_oauth_metadata("https://matrix.example.org", function(m)
				metadata = m
			end)

			assert.is_nil(metadata)
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
				refresh_token = true,
				device_id = client.client.device_id,
			}, sent_body)
			assert.are.equal("secret", client.client.access_token)
			assert.are.equal("@alice:example.org", client.client.user_id)
		end)

		it("should record the refresh token and expiry time of an expiring login", function()
			client.new("https://matrix.example.org")
			curl_mock.post = function(_, opts)
				opts.callback({
					status = 200,
					body = vim.json.encode({
						access_token = "secret",
						refresh_token = "refresh-secret",
						expires_in_ms = 300000,
						user_id = "@alice:example.org",
					}),
				})
			end

			local before = os.time()
			auth.login_password("@alice:example.org", "hunter2", function() end)

			assert.are.equal("refresh-secret", client.client.refresh_token)
			assert.is_true(client.client.expires_at >= before + 300)
			assert.is_true(client.client.expires_at <= os.time() + 300)
		end)

		it("should leave the refresh fields unset when the server issues a non-expiring token", function()
			client.new("https://matrix.example.org")
			curl_mock.post = function(_, opts)
				opts.callback({
					status = 200,
					body = vim.json.encode({ access_token = "secret", user_id = "@alice:example.org" }),
				})
			end

			auth.login_password("@alice:example.org", "hunter2", function() end)

			assert.are.equal("secret", client.client.access_token)
			assert.is_nil(client.client.refresh_token)
			assert.is_nil(client.client.expires_at)
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

		it("should reject a bare server name in matrix.login", function()
			curl_mock.get = function()
				error("unexpected request")
			end

			local result
			matrix.login("example.org", "hunter2", function(r)
				result = r
			end)

			assert.is_true(error_mod.is_error(result))
			assert.matches("Invalid Matrix ID", result.error.error, 1, true)
		end)

		it("should not store credentials on a client replaced during the request", function()
			client.new("https://old.example.org")
			local respond
			curl_mock.post = function(_, opts)
				respond = function()
					opts.callback({
						status = 200,
						body = vim.json.encode({ access_token = "secret", user_id = "@alice:old.example.org" }),
					})
				end
			end

			local result
			auth.login_password("@alice:old.example.org", "hunter2", function(r)
				result = r
			end)
			client.set_homeserver("https://new.example.org")
			respond()

			assert.is_true(error_mod.is_error(result))
			assert.is_nil(client.client.access_token)
			assert.is_nil(client.client.user_id)
		end)

		it("should not store credentials when the login attempt is no longer current", function()
			client.new("https://matrix.example.org")
			curl_mock.post = function(_, opts)
				opts.callback({
					status = 200,
					body = vim.json.encode({ access_token = "secret", user_id = "@alice:example.org" }),
				})
			end

			local result
			auth.login_token("XYZ", function(r)
				result = r
			end, function()
				return false
			end)

			assert.is_true(error_mod.is_error(result))
			assert.is_nil(client.client.access_token)
		end)

		it("should switch to the homeserver from the login response well_known", function()
			client.new("https://example.org")
			curl_mock.post = function(_, opts)
				opts.callback({
					status = 200,
					body = vim.json.encode({
						access_token = "secret",
						user_id = "@alice:example.org",
						well_known = { ["m.homeserver"] = { base_url = "https://matrix.example.org/" } },
					}),
				})
			end

			auth.login_password("@alice:example.org", "hunter2", function() end)

			assert.are.equal("https://matrix.example.org", client.client.homeserver)
			assert.are.equal("secret", client.client.access_token)
		end)
	end)

	describe("login_oauth", function()
		local METADATA = {
			issuer = "https://auth.example.org/",
			device_authorization_endpoint = "https://auth.example.org/oauth2/device",
			token_endpoint = "https://auth.example.org/oauth2/token",
			registration_endpoint = "https://auth.example.org/oauth2/registration",
			revocation_endpoint = "https://auth.example.org/oauth2/revoke",
		}
		local WHOAMI_URL = "https://matrix.example.org/_matrix/client/v3/account/whoami"

		--- The requests sent to the whoami endpoint and the revocation endpoint
		local whoami_requests
		local revocations
		--- What whoami answers
		local whoami_answer

		before_each(function()
			whoami_requests = {}
			revocations = {}
			whoami_answer = { status = 200, body = vim.json.encode({ user_id = "@alice:example.org" }) }
			curl_mock.get = function(url, opts)
				assert.are.equal(WHOAMI_URL, url)
				table.insert(whoami_requests, opts.headers)
				opts.callback(whoami_answer)
			end
			curl_mock.post = function(url, opts)
				table.insert(revocations, { url = url, body = opts.body })
				opts.callback({ status = 200, body = "", exit = 0 })
			end
			client.new("https://matrix.example.org")
		end)

		--- @param tokens? table
		--- @param is_current? fun(): boolean
		--- @return table
		local function login(tokens, is_current)
			local result
			auth.login_oauth(
				tokens or { access_token = "AT", refresh_token = "RT", expires_in = 300, token_type = "Bearer" },
				METADATA,
				"client-1",
				function(r)
					result = r
				end,
				is_current
			)
			return result
		end

		it("stores the tokens, the expiry time and the OAuth refresh method", function()
			local before = os.time()
			local result = login()

			assert.is_true(error_mod.is_ok(result))
			assert.are.equal("AT", client.client.access_token)
			assert.are.equal("RT", client.client.refresh_token)
			assert.is_true(client.client.expires_at >= before + 300)
			assert.is_true(client.client.expires_at <= os.time() + 300)
			assert.are.same({
				kind = "oauth",
				token_endpoint = METADATA.token_endpoint,
				client_id = "client-1",
				revocation_endpoint = METADATA.revocation_endpoint,
			}, client.client.refresh)
		end)

		it("reads the user ID with whoami using the new access token", function()
			login()

			assert.are.equal(1, #whoami_requests)
			assert.are.equal("Bearer AT", whoami_requests[1]["Authorization"])
			assert.are.equal("@alice:example.org", client.client.user_id)
		end)

		it("logs in without refresh when the response has no refresh token", function()
			local result = login({ access_token = "AT", expires_in = 300 })

			assert.is_true(error_mod.is_ok(result))
			assert.are.equal("AT", client.client.access_token)
			assert.is_nil(client.client.refresh_token)
			assert.is_nil(client.client.expires_at)
			assert.is_false(require("neoment.matrix.token").is_stale())
		end)

		it("errors without touching the client when the response has no access token", function()
			local result = login({ refresh_token = "RT", expires_in = 300 })

			assert.is_true(error_mod.is_error(result))
			assert.is_nil(client.client.access_token)
			assert.is_nil(client.client.refresh)
			assert.are.equal(0, #whoami_requests)
		end)

		it("drops the tokens when the client was replaced during the request", function()
			local requesting_client = client.client
			curl_mock.get = function(_, opts)
				client.client = nil
				client.new("https://other.example.org")
				opts.callback(whoami_answer)
			end

			local result = login()

			assert.is_true(error_mod.is_error(result))
			assert.is_nil(client.client.access_token)
			assert.is_nil(client.client.user_id)
			assert.is_nil(requesting_client.user_id)
			-- The new token is not left valid on the server
			assert.are.equal(1, #revocations)
		end)

		it("drops the tokens when the login attempt was superseded", function()
			local result = login(nil, function()
				return false
			end)

			assert.is_true(error_mod.is_error(result))
			assert.is_nil(client.client.access_token)
		end)

		it("leaves no access token and revokes the new one when whoami fails", function()
			whoami_answer = {
				status = 500,
				body = vim.json.encode({ errcode = "M_UNKNOWN", error = "Internal server error" }),
			}

			local result = login()

			assert.is_true(error_mod.is_error(result))
			assert.matches("Internal server error", result.error.error, 1, true)
			assert.is_nil(client.client.access_token)
			assert.is_nil(client.client.refresh_token)
			assert.is_nil(client.client.refresh)
			assert.is_nil(client.client.user_id)
			assert.are.equal(1, #revocations)
			assert.are.equal(METADATA.revocation_endpoint, revocations[1].url)
			assert.matches("token=RT", revocations[1].body, 1, true)
		end)

		it("does not revoke when the server has no revocation endpoint", function()
			whoami_answer = { status = 500, body = vim.json.encode({ errcode = "M_UNKNOWN", error = "Oops" }) }

			local without_revocation = vim.deepcopy(METADATA)
			without_revocation.revocation_endpoint = nil

			auth.login_oauth(
				{ access_token = "AT", refresh_token = "RT" },
				without_revocation,
				"client-1",
				function() end
			)

			assert.are.equal(0, #revocations)
			assert.is_nil(client.client.access_token)
		end)
	end)

	describe("logout", function()
		local LOGOUT_URL = "https://matrix.example.org/_matrix/client/v3/logout"

		--- Fill the client with a logged-in session
		local function login_session()
			client.new("https://matrix.example.org")
			client.client.device_id = "DEVICE1"
			client.client.access_token = "secret"
			client.client.refresh_token = "RT"
			client.client.expires_at = os.time() + 3600
			client.client.user_id = "@alice:example.org"
			client.client.sync_token = "s1"
			client.client.rooms["!room:example.org"] = { id = "!room:example.org" }
			client.client.spaces["!space:example.org"] = { id = "!space:example.org" }
			client.client.invited_rooms["!invite:example.org"] = { id = "!invite:example.org" }
			client.client.display_names["@bob:example.org"] = "Bob"
			client.client.user_presence["@bob:example.org"] = { presence = "online" }
		end

		it("clears the session after the server accepts the logout", function()
			login_session()
			curl_mock.post = function(url, opts)
				assert.are.equal(LOGOUT_URL, url)
				opts.callback({ status = 200, body = "{}" })
			end

			local result
			matrix.logout(function(r)
				result = r
			end)

			assert.is_true(error_mod.is_ok(result))
			assert.is_false(matrix.is_logged_in())
			assert.are.same({}, client.client.rooms)
			assert.are.same({}, client.client.spaces)
			assert.are.same({}, client.client.invited_rooms)
			assert.are.same({}, client.client.display_names)
			assert.are.same({}, client.client.user_presence)
			assert.is_nil(client.client.access_token)
			assert.is_nil(client.client.refresh_token)
			assert.is_nil(client.client.expires_at)
			assert.is_nil(client.client.refresh)
			assert.is_nil(client.client.user_id)
			assert.is_nil(client.client.sync_token)
			assert.are.equal("https://matrix.example.org", client.client.homeserver)
			assert.are.equal("DEVICE1", client.client.device_id)
		end)

		it("ignores a sync response that arrives after the logout", function()
			login_session()
			local sync_opts
			curl_mock.get = function(_, opts)
				sync_opts = opts
			end
			local sync_result
			matrix.sync({}, function(r)
				sync_result = r
			end)
			curl_mock.post = function(_, opts)
				opts.callback({ status = 200, body = "{}" })
			end
			matrix.logout(function() end)

			sync_opts.callback({
				status = 200,
				body = vim.json.encode({
					next_batch = "s2",
					rooms = { join = { ["!late:example.org"] = {} } },
				}),
			})
			vim.wait(50, function()
				return sync_result ~= nil
			end)

			assert.is_true(sync_result:is_error())
			assert.is_true(sync_result.error.session_expired)
			assert.is_nil(client.client.sync_token)
			assert.are.same({}, client.client.rooms)
		end)

		it("keeps the session when the server rejects the logout", function()
			login_session()
			curl_mock.post = function(_, opts)
				opts.callback({
					status = 500,
					body = vim.json.encode({ errcode = "M_UNKNOWN", error = "boom" }),
				})
			end

			local result
			matrix.logout(function(r)
				result = r
			end)

			assert.is_false(error_mod.is_ok(result))
			assert.is_true(matrix.is_logged_in())
			assert.are.equal("secret", client.client.access_token)
			assert.is_not_nil(client.client.rooms["!room:example.org"])
		end)

		it("clears the session after revoking an OAuth refresh token", function()
			login_session()
			client.client.refresh_token = "RT"
			client.client.refresh = {
				kind = "oauth",
				token_endpoint = "https://auth.example.org/oauth2/token",
				client_id = "client-1",
				revocation_endpoint = "https://auth.example.org/oauth2/revoke",
			}
			local revoked_url
			curl_mock.post = function(url, opts)
				revoked_url = url
				opts.callback({ status = 200, body = "", exit = 0 })
			end

			local result
			matrix.logout(function(r)
				result = r
			end)

			assert.is_true(error_mod.is_ok(result))
			assert.are.equal("https://auth.example.org/oauth2/revoke", revoked_url)
			assert.is_false(matrix.is_logged_in())
			assert.are.same({}, client.client.rooms)
			assert.is_nil(client.client.access_token)
			assert.is_nil(client.client.refresh_token)
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

		it("should return an error for a URL without a login token", function()
			local token, err = auth.parse_login_token("https://idp.example.org/error?code=denied")

			assert.is_nil(token)
			assert.matches("does not contain a login token", err, 1, true)
		end)

		it("should return nil for empty input", function()
			assert.is_nil(auth.parse_login_token(""))
			assert.is_nil(auth.parse_login_token(nil))
		end)
	end)
end)
