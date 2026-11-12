describe("room open_attachment", function()
	local room
	local buf
	local handler_spy
	local ui_open_spy
	local original_ui_open
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
			fetch_to_temp = function(filename, _url, callback)
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
end)
