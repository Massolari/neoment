describe("room forward_message", function()
	local room
	local buf
	--- The params given to `matrix.send_message`
	local sent

	before_each(function()
		package.loaded["neoment.room"] = nil

		sent = {}
		package.loaded["neoment.matrix"] = {
			client = { homeserver = "https://example.org" },
			send_message = function(room_id, params)
				table.insert(sent, { room_id = room_id, params = params })
			end,
			get_room_display_name = function()
				return "Target"
			end,
		}
		package.loaded["neoment.rooms"] = {
			pick_room = function(callback)
				callback({ id = "!target:example.org" })
			end,
		}
		package.loaded["neoment.storage"] = {}
		package.loaded["neoment.notify"] = {
			info = function() end,
			error = function() end,
		}

		room = require("neoment.room")
		room.open_room = function() end

		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "[img: x.png]" })
		vim.api.nvim_win_set_cursor(0, { 1, 1 })
	end)

	after_each(function()
		vim.api.nvim_buf_delete(buf, { force = true })
		package.loaded["neoment.room"] = nil
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.rooms"] = nil
		package.loaded["neoment.storage"] = nil
		package.loaded["neoment.notify"] = nil
	end)

	it("forwards the media of an attachment with a valid mxc URI", function()
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "x.png",
			attachment = {
				type = "image",
				mimetype = "image/png",
				url = "https://example.org/_matrix/client/v1/media/download/example.org/x",
				mxc_url = "mxc://example.org/x",
				filename = "x.png",
				size = 10,
			},
		}

		room.forward_message()

		assert.equals(1, #sent)
		assert.equals("!target:example.org", sent[1].room_id)
		assert.are.same({
			filename = "x.png",
			url = "mxc://example.org/x",
			mimetype = "image/png",
			size = 10,
		}, sent[1].params.attachment)
	end)

	it("forwards only the body of an attachment without a valid mxc URI", function()
		-- An `m.image` event whose `content.url` is `https://attacker.example/x.png` has no URL
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "x.png",
			attachment = { type = "image", mimetype = "image/png" },
		}

		room.forward_message()

		assert.equals(1, #sent)
		assert.equals("x.png", sent[1].params.message)
		assert.is_nil(sent[1].params.attachment)
	end)
end)
