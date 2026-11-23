local room = require("neoment.room")

describe("Room", function()
	describe("update_buffer_lines_diff", function()
		it("should not update when lines are identical", function()
			local old_lines = { "line1", "line2", "line3" }
			local new_lines = { "line1", "line2", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.spy(set_lines_spy).was_not_called()
		end)

		it("should update only changed lines in the middle", function()
			local old_lines = { "line1", "line2", "line3", "line4" }
			local new_lines = { "line1", "changed", "modified", "line4" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 1, 3, false, { "changed", "modified" })
		end)

		it("should handle lines added at the end", function()
			local old_lines = { "line1", "line2" }
			local new_lines = { "line1", "line2", "line3", "line4" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 2, 2, false, { "line3", "line4" })
		end)

		it("should handle lines removed from the end", function()
			local old_lines = { "line1", "line2", "line3", "line4" }
			local new_lines = { "line1", "line2" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 2, 4, false, {})
		end)

		it("should handle lines added at the beginning", function()
			local old_lines = { "line2", "line3" }
			local new_lines = { "line1", "line2", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 0, false, { "line1" })
		end)

		it("should handle lines removed from the beginning", function()
			local old_lines = { "line1", "line2", "line3" }
			local new_lines = { "line2", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 1, false, {})
		end)

		it("should handle complete replacement", function()
			local old_lines = { "old1", "old2", "old3" }
			local new_lines = { "new1", "new2", "new3", "new4" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 3, false, { "new1", "new2", "new3", "new4" })
		end)

		it("should handle empty old buffer", function()
			local old_lines = {}
			local new_lines = { "line1", "line2", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 0, false, { "line1", "line2", "line3" })
		end)

		it("should handle empty new buffer", function()
			local old_lines = { "line1", "line2", "line3" }
			local new_lines = {}

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 3, false, {})
		end)

		it("should handle both buffers empty", function()
			local old_lines = {}
			local new_lines = {}

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_not_called()
		end)

		it("should handle single line change", function()
			local old_lines = { "line1", "old_line", "line3" }
			local new_lines = { "line1", "new_line", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 1, 2, false, { "new_line" })
		end)

		it("should optimize when changes are at the end with same prefix", function()
			local old_lines = { "same", "same", "old1", "old2" }
			local new_lines = { "same", "same", "new1", "new2", "new3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 2, 4, false, { "new1", "new2", "new3" })
		end)

		it("should optimize when changes are at the beginning with same suffix", function()
			local old_lines = { "old1", "old2", "same", "same" }
			local new_lines = { "new1", "new2", "new3", "same", "same" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 2, false, { "new1", "new2", "new3" })
		end)

		it("should handle whitespace-only changes", function()
			local old_lines = { "line1", "  line2  ", "line3" }
			local new_lines = { "line1", " line2 ", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 1, 2, false, { " line2 " })
		end)
	end)

	describe("inline images", function()
		local MEDIA = "https://example.org/_matrix/client/v1/media/download/example.org/"
		local room_under_test
		local buf
		--- The URLs given to `storage.fetch_image_source`
		local fetched
		local original_snacks

		before_each(function()
			package.loaded["neoment.room"] = nil
			package.loaded["neoment.util"] = nil
			fetched = {}
			original_snacks = _G.Snacks

			package.loaded["neoment.matrix"] = {
				client = { homeserver = "https://example.org", access_token = "secret_token" },
				get_user_id = function()
					return "@me:example.org"
				end,
				get_display_name = function(user_id)
					return user_id
				end,
				get_typing_users = function()
					return {}
				end,
			}
			package.loaded["neoment.storage"] = {
				fetch_image_source = function(url)
					table.insert(fetched, url)
				end,
			}
			package.loaded["snacks.image.terminal"] = {
				detect = function(callback)
					callback()
				end,
			}
			_G.Snacks = { image = { placement = { clean = function() end } } }

			room_under_test = require("neoment.room")
			buf = vim.api.nvim_create_buf(false, true)
		end)

		after_each(function()
			vim.api.nvim_buf_delete(buf, { force = true })
			_G.Snacks = original_snacks
			package.loaded["neoment.room"] = nil
			package.loaded["neoment.util"] = nil
			package.loaded["neoment.matrix"] = nil
			package.loaded["neoment.storage"] = nil
			package.loaded["snacks.image.terminal"] = nil
		end)

		--- Render one message line for each attachment
		--- @param attachments table[]
		local function render(attachments)
			local lines = {}
			local line_to_message = room_under_test._get_buffer_data(buf).line_to_message
			for index, attachment in ipairs(attachments) do
				table.insert(lines, "attachment")
				line_to_message[index] = {
					id = "$event" .. index,
					sender = "@alice:example.org",
					timestamp = 1000,
					content = "attachment",
					is_header = true,
					attachment = attachment,
				}
			end
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			room_under_test._apply_highlights(buf, "!room:example.org", lines)
		end

		it("fetches nothing for attachments that are not homeserver images", function()
			render({
				{ type = "image", mimetype = "image/png", url = nil },
				{ type = "image", mimetype = "image/png", url = "https://attacker.example/x.png?access_token=old" },
				{ type = "file", mimetype = "application/pdf", url = MEDIA .. "file" },
				{ type = "audio", mimetype = "audio/ogg", url = MEDIA .. "voice" },
				{
					type = "location",
					url = "https://maps.google.com/?q=1,2",
					thumbnail = { type = "image", url = MEDIA .. "map" },
				},
			})

			assert.are.same({}, fetched)
		end)

		it("fetches a homeserver image and a video thumbnail", function()
			render({
				{ type = "image", mimetype = "image/png", url = MEDIA .. "photo", width = 10, height = 10 },
				{
					type = "video",
					mimetype = "video/mp4",
					url = MEDIA .. "clip",
					thumbnail = { type = "image", url = MEDIA .. "clip_thumb", width = 5, height = 5 },
				},
			})

			assert.are.same({ MEDIA .. "photo", MEDIA .. "clip_thumb" }, fetched)
		end)
	end)
end)
