describe("media URLs", function()
	local room_id = "!room1:example.org"
	local MEDIA = "https://example.org/_matrix/client/v1/media/download/example.org/"

	local client
	local event
	local util

	--- Build a `m.room.message` event with an attachment
	--- @param event_id string
	--- @param content table
	--- @return table
	local function attachment_event(event_id, content)
		return {
			event_id = event_id,
			type = "m.room.message",
			sender = "@alice:example.org",
			origin_server_ts = 1000,
			content = content,
		}
	end

	before_each(function()
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.util"] = nil
		package.loaded["neoment.curl"] = {}
		package.loaded["neoment.notify"] = { desktop_message = function() end }
		package.loaded["neoment.rooms"] = { update_room_list = function() end }

		client = require("neoment.matrix.client")
		client.new("https://example.org", "token-1")
		client.client.user_id = "@me:example.org"
		client.client.display_names["@alice:example.org"] = { display_name = "Alice", timestamp = 0 }
		client.get_room(room_id).is_tracked = true

		event = require("neoment.matrix.event")
		util = require("neoment.util")
	end)

	after_each(function()
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.util"] = nil
		package.loaded["neoment.curl"] = nil
		package.loaded["neoment.notify"] = nil
		package.loaded["neoment.rooms"] = nil
	end)

	describe("stored attachments", function()
		it("carry no access token", function()
			event.handle(
				room_id,
				attachment_event("$image", {
					msgtype = "m.image",
					body = "photo.png",
					filename = "photo.png",
					url = "mxc://example.org/photo",
					info = { mimetype = "image/png", h = 10, w = 20 },
				})
			)

			local attachment = client.get_room_message(room_id, "$image").attachment
			assert.are.equal(MEDIA .. "photo", attachment.url)
			assert.are.equal("mxc://example.org/photo", attachment.mxc_url)
		end)

		it("carry no access token on the thumbnail of a video", function()
			event.handle(
				room_id,
				attachment_event("$video", {
					msgtype = "m.video",
					body = "clip.mp4",
					filename = "clip.mp4",
					url = "mxc://example.org/clip",
					info = {
						mimetype = "video/mp4",
						thumbnail_url = "mxc://example.org/clip_thumb",
						thumbnail_info = { h = 5, w = 5, mimetype = "image/jpeg" },
					},
				})
			)

			local attachment = client.get_room_message(room_id, "$video").attachment
			assert.are.equal(MEDIA .. "clip", attachment.url)
			assert.are.equal(MEDIA .. "clip_thumb", attachment.thumbnail.url)
		end)

		it("get the token current when they are displayed, not the one from when they were received", function()
			event.handle(
				room_id,
				attachment_event("$image", {
					msgtype = "m.image",
					body = "photo.png",
					filename = "photo.png",
					url = "mxc://example.org/photo",
					info = { mimetype = "image/png" },
				})
			)
			local attachment = client.get_room_message(room_id, "$image").attachment

			assert.are.equal(MEDIA .. "photo?access_token=token-1", util.media_url_with_token(attachment.url))

			-- The token is refreshed after the message was received
			client.client.access_token = "token-2"

			assert.are.equal(MEDIA .. "photo?access_token=token-2", util.media_url_with_token(attachment.url))
			assert.are.equal(MEDIA .. "photo", attachment.url)
		end)
	end)

	describe("media_url_with_token", function()
		it("appends the token as the first query parameter", function()
			assert.are.equal(MEDIA .. "abc?access_token=token-1", util.media_url_with_token(MEDIA .. "abc"))
		end)

		it("appends the token to an existing query", function()
			assert.are.equal(
				MEDIA .. "abc?width=10&access_token=token-1",
				util.media_url_with_token(MEDIA .. "abc?width=10")
			)
		end)

		it("replaces a token saved by an earlier version", function()
			assert.are.equal(
				MEDIA .. "abc?access_token=token-1",
				util.media_url_with_token(MEDIA .. "abc?access_token=old-token")
			)
			assert.are.equal(
				MEDIA .. "abc?width=10&access_token=token-1",
				util.media_url_with_token(MEDIA .. "abc?access_token=old-token&width=10")
			)
		end)

		it("does not add the token to a URL of another server", function()
			local url = "https://maps.google.com/?q=1,2"

			assert.are.equal(url, util.media_url_with_token(url))
			assert.are.equal(
				"https://example.org.evil.test/x",
				util.media_url_with_token("https://example.org.evil.test/x")
			)
		end)

		it("returns a missing URL as it is", function()
			assert.is_nil(util.media_url_with_token(nil))
		end)

		it("returns the URL as it is when there is no access token", function()
			client.client.access_token = nil

			assert.are.equal(MEDIA .. "abc", util.media_url_with_token(MEDIA .. "abc"))
		end)
	end)

	describe("media_headers", function()
		it("authenticates a media URL of the homeserver with the current token", function()
			assert.are.same({ Authorization = "Bearer token-1" }, util.media_headers(MEDIA .. "abc"))

			client.client.access_token = "token-2"

			assert.are.same({ Authorization = "Bearer token-2" }, util.media_headers(MEDIA .. "abc"))
		end)

		it("sends nothing to another server", function()
			assert.is_nil(util.media_headers("https://maps.google.com/?q=1,2"))
		end)
	end)

	describe("strip_access_token", function()
		it("removes the token and keeps the rest of the query", function()
			assert.are.equal(MEDIA .. "abc", util.strip_access_token(MEDIA .. "abc?access_token=t"))
			assert.are.equal(MEDIA .. "abc?width=10", util.strip_access_token(MEDIA .. "abc?width=10&access_token=t"))
			assert.are.equal(MEDIA .. "abc?width=10", util.strip_access_token(MEDIA .. "abc?access_token=t&width=10"))
			assert.are.equal(MEDIA .. "abc", util.strip_access_token(MEDIA .. "abc"))
		end)
	end)
end)
