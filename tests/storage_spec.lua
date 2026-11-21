local error_mod = require("neoment.error")

describe("storage", function()
	local curl_mock
	local notify_mock
	local matrix_mock
	local util_mock
	local original_filereadable

	before_each(function()
		curl_mock = {}
		notify_mock = { info = function() end, error = function() end, warning = function() end }
		matrix_mock = {
			client = { homeserver = "https://example.org", access_token = "token" },
			get_invited_rooms = function()
				return {}
			end,
			get_rooms = function()
				return {}
			end,
			get_room_last_message = function()
				return nil
			end,
		}
		util_mock = {
			uuid = function()
				return "00000000-0000-0000-0000-000000000000"
			end,
		}

		package.loaded["neoment.curl"] = curl_mock
		package.loaded["neoment.notify"] = notify_mock
		package.loaded["neoment.matrix"] = matrix_mock
		package.loaded["neoment.util"] = util_mock
		-- Reload storage so it picks up our mocks
		package.loaded["neoment.storage"] = nil

		-- Stub vim.fn.filereadable so we control the cached-file branch
		original_filereadable = vim.fn.filereadable
	end)

	after_each(function()
		vim.fn.filereadable = original_filereadable
		package.loaded["neoment.curl"] = nil
		package.loaded["neoment.notify"] = nil
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.util"] = nil
		package.loaded["neoment.storage"] = nil
	end)

	describe("fetch_to_temp", function()
		it("invokes the callback with the cached path when the file already exists", function()
			-- Pretend the file is already in the cache
			vim.fn.filereadable = function()
				return 1
			end

			local curl_get_spy = spy.new(function() end)
			curl_mock.get = curl_get_spy

			local callback_spy = spy.new(function() end)

			local storage = require("neoment.storage")
			storage.fetch_to_temp("avatar.png", "https://example.org/avatar.png", callback_spy)

			-- The curl request should NOT be made when the file is cached
			assert.spy(curl_get_spy).was_not_called()

			-- The callback should be invoked with an ok Result
			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			assert.truthy(result.data:match("avatar%.png$"))
		end)

		describe("in a directory", function()
			local directory

			before_each(function()
				directory = vim.fn.tempname()
				vim.fn.mkdir(directory, "p")
			end)

			after_each(function()
				vim.fn.delete(directory, "rf")
			end)

			--- Write a file, as curl does with its output
			--- @param path string
			local function write(path)
				local file = assert(io.open(path, "w"))
				file:write("data")
				file:close()
			end

			it("downloads the file via curl and invokes the callback with the path on success", function()
				local captured_opts
				curl_mock.get = function(_, opts)
					captured_opts = opts
					write(opts.output)
					opts.callback({ exit = 0, status = 200, body = "", headers = {} })
				end
				local callback_spy = spy.new(function() end)

				local storage = require("neoment.storage")
				storage.fetch_to_temp("file.png", "https://example.org/file.png", callback_spy, nil, directory)

				assert.equals("function", type(captured_opts.on_error))
				assert.spy(callback_spy).was_called(1)
				local result = callback_spy.calls[1].refs[1]
				assert.is_true(error_mod.is_ok(result))
				assert.equals(vim.fs.joinpath(directory, "file.png"), result.data)
				assert.equals(1, vim.fn.filereadable(result.data))
			end)

			it("does not keep an interrupted download as the file", function()
				curl_mock.get = function(_, opts)
					-- curl wrote part of the file before the connection dropped
					write(opts.output)
					opts.on_error({ message = "Connection reset", exit = 56 })
				end
				local callback_spy = spy.new(function() end)

				local storage = require("neoment.storage")
				storage.fetch_to_temp("file.png", "https://example.org/file.png", callback_spy, nil, directory)

				assert.is_true(error_mod.is_error(callback_spy.calls[1].refs[1]))
				assert.are.same({}, vim.fn.readdir(directory))

				-- The next fetch downloads the file again
				local downloaded = false
				curl_mock.get = function()
					downloaded = true
				end
				storage.fetch_to_temp("file.png", "https://example.org/file.png", function() end, nil, directory)
				assert.is_true(downloaded)
			end)

			it("does not keep the body of an error response as the file", function()
				curl_mock.get = function(_, opts)
					write(opts.output)
					opts.callback({ exit = 0, status = 401, body = "", headers = {} })
				end

				local storage = require("neoment.storage")
				storage.fetch_to_temp("file.png", "https://example.org/file.png", function() end, nil, directory)

				assert.are.same({}, vim.fn.readdir(directory))
			end)
		end)

		it("propagates curl on_error to the callback", function()
			vim.fn.filereadable = function()
				return 0
			end

			curl_mock.get = function(_url, opts)
				opts.on_error({ message = "Connection refused" })
			end

			local callback_spy = spy.new(function() end)

			local storage = require("neoment.storage")
			storage.fetch_to_temp("file.png", "https://example.org/file.png", callback_spy)

			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.equals("Failed to download file: Connection refused", result.error)
		end)

		it("uses a generic error message when curl on_error has no message", function()
			vim.fn.filereadable = function()
				return 0
			end

			curl_mock.get = function(_url, opts)
				opts.on_error({})
			end

			local callback_spy = spy.new(function() end)

			local storage = require("neoment.storage")
			storage.fetch_to_temp("file.png", "https://example.org/file.png", callback_spy)

			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.equals("Failed to download file: Unknown error", result.error)
		end)

		it("reports an error when curl succeeds but the file was not saved", function()
			-- File is missing before AND after the curl call returns
			vim.fn.filereadable = function()
				return 0
			end

			curl_mock.get = function(_url, opts)
				opts.callback({ exit = 0, status = 200, body = "", headers = {} })
			end

			local callback_spy = spy.new(function() end)

			local storage = require("neoment.storage")
			storage.fetch_to_temp("file.png", "https://example.org/file.png", callback_spy)

			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.equals("Failed to save downloaded file", result.error)
		end)

		it("sanitizes the filename before writing to the temp path", function()
			vim.fn.filereadable = function()
				return 1
			end

			curl_mock.get = function() end

			local callback_spy = spy.new(function() end)

			local storage = require("neoment.storage")
			storage.fetch_to_temp("weird name with spaces!.png", "https://example.org/x.png", callback_spy)

			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			-- Non-alphanumeric characters (except . - _) must be replaced with underscores
			assert.truthy(result.data:match("weird_name_with_spaces_%.png$"))
			-- And the original (unsanitized) sequence must NOT appear in the path
			assert.is_nil(result.data:find("weird name with spaces!.png", 1, true))
		end)

		it("sends the headers it is given", function()
			vim.fn.filereadable = function()
				return 0
			end

			local captured_opts
			curl_mock.get = function(_, opts)
				captured_opts = opts
			end

			local storage = require("neoment.storage")
			storage.fetch_to_temp("file.png", "https://example.org/file.png", function() end, {
				Authorization = "Bearer token",
			})

			assert.are.same({ Authorization = "Bearer token" }, captured_opts.headers)
		end)

		it("reports an error response instead of keeping its body as the file", function()
			local reads = 0
			vim.fn.filereadable = function()
				reads = reads + 1
				-- Not cached before the download, the error body is on disk afterwards
				return reads == 1 and 0 or 1
			end

			curl_mock.get = function(_, opts)
				opts.callback({ exit = 0, status = 401, body = "", headers = {} })
			end

			local callback_spy = spy.new(function() end)

			local storage = require("neoment.storage")
			storage.fetch_to_temp("file.png", "https://example.org/file.png", callback_spy)

			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.equals("Failed to download file: HTTP status 401", result.error)
		end)

		it("validates that name is a string", function()
			local storage = require("neoment.storage")
			assert.has_error(function()
				storage.fetch_to_temp(nil, "https://example.org/file.png", function() end)
			end)
		end)

		it("validates that url is a string", function()
			local storage = require("neoment.storage")
			assert.has_error(function()
				storage.fetch_to_temp("file.png", nil, function() end)
			end)
		end)
	end)
	describe("restore_session", function()
		local original_stdpath
		local temp_dir

		before_each(function()
			temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir .. "/neoment", "p")
			original_stdpath = vim.fn.stdpath
			vim.fn.stdpath = function()
				return temp_dir
			end
		end)

		after_each(function()
			vim.fn.stdpath = original_stdpath
			vim.fn.delete(temp_dir, "rf")
		end)

		it("replaces a client left by an unfinished login attempt", function()
			local file = assert(io.open(temp_dir .. "/neoment/data.json", "w"))
			file:write(vim.json.encode({
				homeserver = "https://saved.example.org",
				access_token = "saved-token",
				user_id = "@alice:saved.example.org",
				last_save = os.time(),
			}))
			file:close()

			-- A client without a token, as left by a login attempt that was not finished
			matrix_mock.client = { homeserver = "https://other.example.org", device_id = "DEVICE" }
			matrix_mock.set_homeserver = function(homeserver)
				matrix_mock.client = { homeserver = homeserver, device_id = matrix_mock.client.device_id }
			end

			local storage = require("neoment.storage")

			assert.is_true(storage.restore_session())
			assert.are.equal("https://saved.example.org", matrix_mock.client.homeserver)
			assert.are.equal("saved-token", matrix_mock.client.access_token)
			assert.are.equal("@alice:saved.example.org", matrix_mock.client.user_id)
		end)

		--- Write a saved session file
		--- @param data table
		local function write_session(data)
			local file = assert(io.open(temp_dir .. "/neoment/data.json", "w"))
			file:write(vim.json.encode(vim.tbl_extend("keep", data, {
				homeserver = "https://saved.example.org",
				access_token = "saved-token",
				user_id = "@alice:saved.example.org",
			})))
			file:close()
			matrix_mock.client = { homeserver = "https://other.example.org", device_id = "DEVICE" }
			matrix_mock.set_homeserver = function(homeserver)
				matrix_mock.client = { homeserver = homeserver, device_id = matrix_mock.client.device_id }
			end
		end

		local EIGHT_DAYS = 8 * 24 * 60 * 60

		it("restores the refresh token, expiry and refresh method", function()
			local expires_at = os.time() - 100
			write_session({
				refresh_token = "saved-refresh",
				expires_at = expires_at,
				refresh = { kind = "oauth", token_endpoint = "https://auth.example.org/token", client_id = "abc" },
				last_save = os.time(),
			})

			local storage = require("neoment.storage")

			assert.is_true(storage.restore_session())
			assert.are.equal("saved-refresh", matrix_mock.client.refresh_token)
			assert.are.equal(expires_at, matrix_mock.client.expires_at)
			assert.are.same(
				{ kind = "oauth", token_endpoint = "https://auth.example.org/token", client_id = "abc" },
				matrix_mock.client.refresh
			)
		end)

		it("restores a session saved by an earlier version as non-expiring", function()
			write_session({ last_save = os.time() })

			local storage = require("neoment.storage")

			assert.is_true(storage.restore_session())
			assert.are.equal("saved-token", matrix_mock.client.access_token)
			assert.is_nil(matrix_mock.client.refresh_token)
			assert.is_nil(matrix_mock.client.expires_at)
			assert.is_nil(matrix_mock.client.refresh)
		end)

		it("restores a session older than 7 days when it holds a refresh token", function()
			write_session({ refresh_token = "saved-refresh", last_save = os.time() - EIGHT_DAYS })

			local storage = require("neoment.storage")

			assert.is_true(storage.restore_session())
		end)

		it("rejects a session older than 7 days when it holds no refresh token", function()
			write_session({ last_save = os.time() - EIGHT_DAYS })

			local storage = require("neoment.storage")

			assert.is_false(storage.restore_session())
		end)
	end)

	describe("save_session", function()
		local original_stdpath
		local temp_dir

		before_each(function()
			temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir .. "/neoment", "p")
			original_stdpath = vim.fn.stdpath
			vim.fn.stdpath = function()
				return temp_dir
			end
		end)

		after_each(function()
			vim.fn.stdpath = original_stdpath
			vim.fn.delete(temp_dir, "rf")
		end)

		it("round-trips the refresh token, expiry and refresh method", function()
			local refresh = { kind = "oauth", token_endpoint = "https://auth.example.org/token", client_id = "abc" }
			matrix_mock.client = {
				homeserver = "https://saved.example.org",
				device_id = "DEVICE",
				user_id = "@alice:saved.example.org",
				access_token = "token",
				refresh_token = "refresh",
				expires_at = 1234567890,
				refresh = refresh,
			}
			matrix_mock.set_homeserver = function(homeserver)
				matrix_mock.client = { homeserver = homeserver, device_id = matrix_mock.client.device_id }
			end

			local storage = require("neoment.storage")
			assert.is_true(storage.save_session())

			-- Drop the in-memory credentials so the restore has to read them from the file
			matrix_mock.client = { homeserver = "https://other.example.org", device_id = "DEVICE" }

			assert.is_true(storage.restore_session())
			assert.are.equal("token", matrix_mock.client.access_token)
			assert.are.equal("refresh", matrix_mock.client.refresh_token)
			assert.are.equal(1234567890, matrix_mock.client.expires_at)
			assert.are.same(refresh, matrix_mock.client.refresh)
		end)

		it("round-trips the joined member count of a room", function()
			local rooms = {
				["!room:example.org"] = {
					id = "!room:example.org",
					name = "Room",
					aliases = {},
					members = {},
					space_rooms = {},
					unread_notifications = 0,
					unread_highlights = 0,
					joined_member_count = 2,
				},
			}
			local restored = {}
			matrix_mock.client = {
				homeserver = "https://saved.example.org",
				device_id = "DEVICE",
				user_id = "@alice:saved.example.org",
				access_token = "token",
			}
			matrix_mock.get_rooms = function()
				return rooms
			end
			matrix_mock.set_room = function(room_id, data)
				restored[room_id] = data
			end
			matrix_mock.set_homeserver = function(homeserver)
				matrix_mock.client = { homeserver = homeserver, device_id = matrix_mock.client.device_id }
			end

			local storage = require("neoment.storage")
			assert.is_true(storage.save_session())
			assert.is_true(storage.restore_session())

			assert.are.equal(2, restored["!room:example.org"].joined_member_count)
		end)
	end)

	describe("oauth client ids", function()
		local original_stdpath
		local temp_dir
		local clients_file

		before_each(function()
			temp_dir = vim.fn.tempname()
			vim.fn.mkdir(temp_dir .. "/neoment", "p")
			clients_file = temp_dir .. "/neoment/oauth_clients.json"
			original_stdpath = vim.fn.stdpath
			vim.fn.stdpath = function()
				return temp_dir
			end
		end)

		after_each(function()
			vim.fn.stdpath = original_stdpath
			vim.fn.delete(temp_dir, "rf")
		end)

		it("round-trips a client id", function()
			local storage = require("neoment.storage")

			assert.is_true(storage.set_oauth_client_id("https://auth.example.org/", "client-1"))

			assert.are.equal("client-1", storage.get_oauth_client_id("https://auth.example.org/"))
		end)

		it("keeps a separate client id for each issuer", function()
			local storage = require("neoment.storage")

			storage.set_oauth_client_id("https://auth.example.org/", "client-1")
			storage.set_oauth_client_id("https://other.example.org/", "client-2")

			assert.are.equal("client-1", storage.get_oauth_client_id("https://auth.example.org/"))
			assert.are.equal("client-2", storage.get_oauth_client_id("https://other.example.org/"))
		end)

		it("clears the client id of one issuer only", function()
			local storage = require("neoment.storage")
			storage.set_oauth_client_id("https://auth.example.org/", "client-1")
			storage.set_oauth_client_id("https://other.example.org/", "client-2")

			assert.is_true(storage.clear_oauth_client_id("https://auth.example.org/"))

			assert.is_nil(storage.get_oauth_client_id("https://auth.example.org/"))
			assert.are.equal("client-2", storage.get_oauth_client_id("https://other.example.org/"))
		end)

		it("has no client id when the file does not exist", function()
			local storage = require("neoment.storage")

			assert.is_nil(storage.get_oauth_client_id("https://auth.example.org/"))
			assert.is_true(storage.clear_oauth_client_id("https://auth.example.org/"))
		end)

		it("ignores a corrupt file and replaces it on the next save", function()
			local file = assert(io.open(clients_file, "w"))
			file:write("{not json")
			file:close()
			local storage = require("neoment.storage")

			assert.is_nil(storage.get_oauth_client_id("https://auth.example.org/"))
			assert.is_true(storage.set_oauth_client_id("https://auth.example.org/", "client-1"))

			assert.are.equal("client-1", storage.get_oauth_client_id("https://auth.example.org/"))
		end)

		it("keeps the client ids when the session is cleared", function()
			local storage = require("neoment.storage")
			storage.set_oauth_client_id("https://auth.example.org/", "client-1")
			local file = assert(io.open(temp_dir .. "/neoment/data.json", "w"))
			file:write(vim.json.encode({ access_token = "token" }))
			file:close()

			assert.is_true(storage.clear_session())

			assert.are.equal(0, vim.fn.filereadable(temp_dir .. "/neoment/data.json"))
			assert.are.equal("client-1", storage.get_oauth_client_id("https://auth.example.org/"))
		end)
	end)
end)
