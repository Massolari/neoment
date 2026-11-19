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

		it("get the token current when they are fetched, not the one from when they were received", function()
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

			assert.are.same({ Authorization = "Bearer token-1" }, util.media_headers(attachment.url))

			-- The token is refreshed after the message was received
			client.client.access_token = "token-2"

			assert.are.same({ Authorization = "Bearer token-2" }, util.media_headers(attachment.url))
			assert.are.equal(MEDIA .. "photo", attachment.url)
		end)
	end)

	describe("fetch_image_source", function()
		local storage
		local downloads

		before_each(function()
			package.loaded["neoment.storage"] = nil
			storage = require("neoment.storage")
			downloads = {}
			storage.fetch_to_temp = function(name, url, callback, headers)
				table.insert(downloads, { name = name, url = url, callback = callback, headers = headers })
			end
		end)

		after_each(function()
			package.loaded["neoment.storage"] = nil
		end)

		--- Fetch an image source and wait for the result
		--- @param url string
		--- @param complete? fun() Completes the download, if one was started
		--- @return neoment.Error<string, string>|nil
		local function fetch(url, complete)
			local result
			storage.fetch_image_source(url, function(r)
				result = r
			end)
			if complete then
				complete()
			end
			vim.wait(100, function()
				return result ~= nil
			end)
			return result
		end

		it("downloads homeserver media with the token in a header and gives the local file", function()
			local result = fetch(MEDIA .. "abc", function()
				downloads[1].callback(require("neoment.error").ok("/tmp/neoment/file"))
			end)

			assert.are.equal(1, #downloads)
			assert.are.equal(MEDIA .. "abc", downloads[1].url)
			assert.are.same({ Authorization = "Bearer token-1" }, downloads[1].headers)
			assert.are.equal("/tmp/neoment/file", result.data)
		end)

		it("keeps the same file name when the token changes, so the image stays cached", function()
			fetch(MEDIA .. "abc", function()
				downloads[1].callback(require("neoment.error").ok("/tmp/neoment/file"))
			end)
			client.client.access_token = "token-2"
			fetch(MEDIA .. "abc?access_token=old-token", function()
				downloads[2].callback(require("neoment.error").ok("/tmp/neoment/file"))
			end)

			assert.are.equal(downloads[1].name, downloads[2].name)
			assert.are.equal(MEDIA .. "abc", downloads[2].url)
			assert.are.same({ Authorization = "Bearer token-2" }, downloads[2].headers)
		end)

		it("downloads an image once while it is being downloaded", function()
			local results = {}
			for _ = 1, 2 do
				storage.fetch_image_source(MEDIA .. "abc", function(r)
					table.insert(results, r)
				end)
			end
			downloads[1].callback(require("neoment.error").ok("/tmp/neoment/file"))
			vim.wait(100, function()
				return #results == 2
			end)

			assert.are.equal(1, #downloads)
			assert.are.equal(2, #results)
			assert.are.equal("/tmp/neoment/file", results[2].data)
		end)

		it("gives a URL of another server as it is", function()
			local url = "https://maps.google.com/?q=1,2"
			local result = fetch(url)

			assert.are.equal(0, #downloads)
			assert.are.equal(url, result.data)
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
