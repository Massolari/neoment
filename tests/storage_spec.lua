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

		it("downloads the file via curl and invokes the callback with the path on success", function()
			-- Pretend the file does not exist before the download, and exists afterwards
			local calls = 0
			vim.fn.filereadable = function()
				calls = calls + 1
				if calls == 1 then
					return 0 -- before download
				end
				return 1 -- after download (inside the curl callback)
			end

			local captured_opts
			curl_mock.get = function(url, opts)
				captured_opts = opts
				-- Simulate a successful download
				opts.callback({ exit = 0, status = 200, body = "", headers = {} })
			end

			local callback_spy = spy.new(function() end)

			local storage = require("neoment.storage")
			storage.fetch_to_temp("file.png", "https://example.org/file.png", callback_spy)

			-- curl should be called with output and a callback
			assert.is_not_nil(captured_opts)
			assert.is_string(captured_opts.output)
			assert.equals("function", type(captured_opts.callback))
			assert.equals("function", type(captured_opts.on_error))

			-- The user's callback should be invoked once with an ok Result
			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_ok(result))
			assert.truthy(result.data:match("file%.png$"))
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

		it("reports an error when curl exits with a non-zero status", function()
			vim.fn.filereadable = function()
				return 0
			end

			curl_mock.get = function(_url, opts)
				opts.callback({ exit = 7, status = 0, body = "", headers = {} })
			end

			local callback_spy = spy.new(function() end)

			local storage = require("neoment.storage")
			storage.fetch_to_temp("file.png", "https://example.org/file.png", callback_spy)

			assert.spy(callback_spy).was_called(1)
			local result = callback_spy.calls[1].refs[1]
			assert.is_true(error_mod.is_error(result))
			assert.equals("Failed to download file: curl exited with code 7", result.error)
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
end)
