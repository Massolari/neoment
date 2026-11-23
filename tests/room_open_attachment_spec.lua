describe("room open_attachment", function()
	local room
	local buf
	local handler_spy
	local ui_open_spy
	local original_ui_open
	--- The downloads started, as the arguments given to `storage.fetch_to_temp`
	local fetches
	local namespace = vim.api.nvim_create_namespace("neoment_room_extmarks")

	--- Flush callbacks queued with vim.schedule
	local function flush()
		vim.wait(50, function()
			return #handler_spy.calls > 0
		end)
	end

	--- Place an extmark at the start of line 1 and attach data to it
	--- @param data neoment.room.ExtmarkData
	local function seed_extmark(data)
		local id = vim.api.nvim_buf_set_extmark(buf, namespace, 0, 0, { end_row = 0, end_col = 5 })
		room._get_buffer_data(buf).extmarks_data[id] = data
	end

	before_each(function()
		package.loaded["neoment.room"] = nil

		handler_spy = spy.new(function() end)
		ui_open_spy = spy.new(function() end)
		fetches = {}
		original_ui_open = vim.ui.open
		vim.ui.open = ui_open_spy

		package.loaded["neoment.matrix"] = {
			client = {
				homeserver = "https://example.org",
				access_token = "secret_token",
			},
		}
		package.loaded["neoment.storage"] = {
			-- Simulate a completed download by calling the callback synchronously
			fetch_to_temp = function(filename, url, callback, headers)
				table.insert(fetches, { url = url, headers = headers })
				callback(require("neoment.error").ok("/tmp/" .. filename))
			end,
		}
		package.loaded["neoment.config"] = {
			get = function()
				return { room = { on_open_attachment = handler_spy } }
			end,
		}
		package.loaded["neoment.notify"] = {
			info = function() end,
			error = function() end,
		}

		room = require("neoment.room")

		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "[img: party]" })
		vim.api.nvim_win_set_cursor(0, { 1, 1 })
	end)

	after_each(function()
		vim.ui.open = original_ui_open
		vim.api.nvim_buf_delete(buf, { force = true })
		package.loaded["neoment.room"] = nil
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.storage"] = nil
		package.loaded["neoment.config"] = nil
		package.loaded["neoment.notify"] = nil
	end)

	it("passes a custom emoticon to the configured handler", function()
		seed_extmark({ emoticon_url = "mxc://example.org/emote", emoticon_title = "party" })

		room.open_attachment()
		flush()

		assert.spy(handler_spy).was_called(1)
		local path, attachment = handler_spy.calls[1].vals[1], handler_spy.calls[1].vals[2]
		assert.equals("/tmp/party.png", path)
		assert.equals("image", attachment.type)
		assert.equals("emoticon", attachment.origin)
		assert.equals("mxc://example.org/emote", attachment.mxc_url)
		assert.equals("party.png", attachment.filename)
		assert.equals("image/png", attachment.mimetype)
		assert.truthy(attachment.url:find("example.org", 1, true))
		assert.is_nil(attachment.url:find("access_token", 1, true))
		assert.spy(ui_open_spy).was_not_called()
	end)

	it("passes a custom reaction to the configured handler", function()
		seed_extmark({ reaction_mxc_url = "mxc://example.org/react", reaction_label = "thumbs" })

		room.open_attachment()
		flush()

		assert.spy(handler_spy).was_called(1)
		local path, attachment = handler_spy.calls[1].vals[1], handler_spy.calls[1].vals[2]
		assert.equals("/tmp/thumbs.png", path)
		assert.equals("image", attachment.type)
		assert.equals("reaction", attachment.origin)
		assert.equals("mxc://example.org/react", attachment.mxc_url)
		assert.is_nil(attachment.url:find("access_token", 1, true))
		assert.spy(ui_open_spy).was_not_called()
	end)

	it("passes a message attachment to the configured handler with its origin", function()
		local message_attachment = {
			type = "audio",
			mimetype = "audio/ogg",
			url = "https://example.org/_matrix/media/v3/download/example.org/voice",
			mxc_url = "mxc://example.org/voice",
			filename = "voice.ogg",
			duration = 1000,
			size = 100,
		}
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "voice.ogg",
			attachment = message_attachment,
		}

		room.open_attachment()
		flush()

		assert.spy(handler_spy).was_called(1)
		local path, attachment = handler_spy.calls[1].vals[1], handler_spy.calls[1].vals[2]
		assert.equals("/tmp/$eventvoice.ogg", path)
		assert.equals("audio", attachment.type)
		assert.equals("message", attachment.origin)
		assert.equals("voice.ogg", attachment.filename)
		assert.is_nil(message_attachment.origin)
	end)

	it("removes the access token from message attachment URLs passed to the handler", function()
		local url = "https://example.org/_matrix/media/v3/download/example.org/video?access_token=secret_token"
		local thumbnail_url =
			"https://example.org/_matrix/media/v3/download/example.org/thumb?access_token=secret_token"
		local message_attachment = {
			type = "video",
			mimetype = "video/mp4",
			url = url,
			mxc_url = "mxc://example.org/video",
			filename = "video.mp4",
			thumbnail = {
				type = "image",
				filename = "thumbnail",
				url = thumbnail_url,
				mxc_url = "mxc://example.org/thumb",
			},
		}
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "video.mp4",
			attachment = message_attachment,
		}

		room.open_attachment()
		flush()

		assert.spy(handler_spy).was_called(1)
		local attachment = handler_spy.calls[1].vals[2]
		assert.equals("https://example.org/_matrix/media/v3/download/example.org/video", attachment.url)
		assert.equals("https://example.org/_matrix/media/v3/download/example.org/thumb", attachment.thumbnail.url)
		assert.equals(url, message_attachment.url)
		assert.equals(thumbnail_url, message_attachment.thumbnail.url)
	end)

	it("downloads a message attachment with the current token in a header, not in the URL", function()
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "voice.ogg",
			attachment = {
				type = "audio",
				mimetype = "audio/ogg",
				url = "https://example.org/_matrix/client/v1/media/download/example.org/voice",
				mxc_url = "mxc://example.org/voice",
				filename = "voice.ogg",
			},
		}

		room.open_attachment()
		flush()

		assert.equals(1, #fetches)
		assert.equals("https://example.org/_matrix/client/v1/media/download/example.org/voice", fetches[1].url)
		assert.are.same({ Authorization = "Bearer secret_token" }, fetches[1].headers)
	end)

	it("does not download with a token saved by an earlier version", function()
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "voice.ogg",
			attachment = {
				type = "audio",
				mimetype = "audio/ogg",
				url = "https://example.org/_matrix/client/v1/media/download/example.org/voice?access_token=old_token",
				mxc_url = "mxc://example.org/voice",
				filename = "voice.ogg",
			},
		}

		room.open_attachment()
		flush()

		assert.equals("https://example.org/_matrix/client/v1/media/download/example.org/voice", fetches[1].url)
		assert.are.same({ Authorization = "Bearer secret_token" }, fetches[1].headers)
	end)

	it("sends no credentials to a URL that is not on the homeserver", function()
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "somewhere",
			attachment = { type = "location", url = "https://maps.google.com/?q=1,2" },
		}

		room.open_attachment()
		flush()

		assert.equals(1, #fetches)
		assert.equals("https://maps.google.com/?q=1,2", fetches[1].url)
		assert.is_nil(fetches[1].headers)
	end)

	it("does not download an image whose source is not mxc://", function()
		local notifications = {}
		package.loaded["neoment.notify"].info = function(message)
			table.insert(notifications, message)
		end
		-- An `m.image` event whose `content.url` is `https://attacker.example/x.png` has no URL
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "x.png",
			attachment = { type = "image", mimetype = "image/png" },
		}

		room.open_attachment()
		flush()

		assert.equals(0, #fetches)
		assert.spy(handler_spy).was_not_called()
		assert.are.same({ "This attachment has no downloadable media" }, notifications)
	end)

	it("does not download a custom emoticon whose mxc URI is malformed", function()
		seed_extmark({ emoticon_url = "mxc://example.org/../../v3/account/whoami", emoticon_title = "party" })

		room.open_attachment()
		flush()

		assert.equals(0, #fetches)
		assert.spy(handler_spy).was_not_called()
	end)

	it("downloads a custom emoticon with the current token in a header, not in the URL", function()
		seed_extmark({ emoticon_url = "mxc://example.org/emote", emoticon_title = "party" })

		room.open_attachment()
		flush()

		assert.equals(1, #fetches)
		assert.equals("https://example.org/_matrix/client/v1/media/download/example.org/emote", fetches[1].url)
		assert.are.same({ Authorization = "Bearer secret_token" }, fetches[1].headers)
	end)
end)
