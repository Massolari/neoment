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

		--- Assert that no field of an attachment, nor of its thumbnail, holds an access token
		--- @param attachment table
		local function assert_no_token(attachment)
			for key, value in pairs(attachment) do
				if type(value) == "table" then
					assert_no_token(value)
				elseif type(value) == "string" then
					assert.is_nil(value:find("access_token", 1, true), key)
				end
			end
		end

		it("have no downloadable URL for an image whose URL is not mxc://", function()
			event.handle(
				room_id,
				attachment_event("$image", {
					msgtype = "m.image",
					body = "x.png",
					url = "https://attacker.example/x.png",
					info = { mimetype = "image/png" },
				})
			)

			local message = client.get_room_message(room_id, "$image")
			assert.are.equal("x.png", message.content)
			assert.is_nil(message.attachment.url)
			assert.is_nil(message.attachment.mxc_url)
			assert_no_token(message.attachment)
		end)

		it("have no downloadable URL for a file whose URL is not mxc://", function()
			event.handle(
				room_id,
				attachment_event("$file", {
					msgtype = "m.file",
					body = "f.pdf",
					url = "https://attacker.example/f.pdf",
					info = { mimetype = "application/pdf" },
				})
			)

			local attachment = client.get_room_message(room_id, "$file").attachment
			assert.is_nil(attachment.url)
			assert_no_token(attachment)
		end)

		it("have no downloadable URL for a sticker whose URL is not mxc://", function()
			event.handle(room_id, {
				event_id = "$sticker",
				type = "m.sticker",
				sender = "@alice:example.org",
				origin_server_ts = 1000,
				content = {
					body = "wave",
					url = "https://attacker.example/wave.png",
					info = { mimetype = "image/png" },
				},
			})

			local attachment = client.get_room_message(room_id, "$sticker").attachment
			assert.is_nil(attachment.url)
			assert.is_nil(attachment.mxc_url)
			assert_no_token(attachment)
		end)

		it("have no thumbnail for a video whose thumbnail URL is not mxc://", function()
			event.handle(
				room_id,
				attachment_event("$video", {
					msgtype = "m.video",
					body = "clip.mp4",
					url = "mxc://example.org/clip",
					info = {
						mimetype = "video/mp4",
						thumbnail_url = "https://attacker.example/t.png",
						thumbnail_info = { h = 5, w = 5, mimetype = "image/png" },
					},
				})
			)

			local attachment = client.get_room_message(room_id, "$video").attachment
			assert.are.equal(MEDIA .. "clip", attachment.url)
			assert.is_nil(attachment.thumbnail)
			assert_no_token(attachment)
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
			storage.fetch_to_temp = function(name, url, callback, headers, directory)
				table.insert(
					downloads,
					{ name = name, url = url, callback = callback, headers = headers, directory = directory }
				)
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

		it("keeps the images in a directory only the user can read", function()
			fetch(MEDIA .. "abc", function()
				downloads[1].callback(require("neoment.error").ok("/tmp/neoment/file"))
			end)

			assert.are.equal(vim.fn.stdpath("cache") .. "/neoment/media", downloads[1].directory)
			assert.are.equal("rwx------", vim.fn.getfperm(downloads[1].directory))
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

		it("refuses a URL of another server", function()
			local result = fetch("https://maps.google.com/?q=1,2")

			assert.are.equal(0, #downloads)
			assert.is_true(result:is_error())
		end)

		it("refuses a cached URL of another server that holds an old token", function()
			local result = fetch("https://attacker.example/x.png?access_token=old")

			assert.are.equal(0, #downloads)
			assert.is_true(result:is_error())
		end)

		it("downloads a cached homeserver URL without its old token, with the current token in a header", function()
			client.client.access_token = "token-2"
			fetch(MEDIA .. "abc?access_token=old", function()
				downloads[1].callback(require("neoment.error").ok("/tmp/neoment/file"))
			end)

			assert.are.equal(1, #downloads)
			assert.are.equal(MEDIA .. "abc", downloads[1].url)
			assert.are.same({ Authorization = "Bearer token-2" }, downloads[1].headers)
		end)
	end)

	--- URIs that are not well-formed `mxc://<server-name>/<media-id>` URIs
	local INVALID_MXC = {
		"https://attacker.example/x.png",
		"https://attacker.example/mxc://example.org/abc",
		"mxc://example.org/../../v3/account/whoami",
		"mxc://../config",
		"mxc://example.org",
		"mxc://example.org/abc/def",
		"mxc://example.org/abc?x=1",
		"mxc://example.org:/abc",
		"",
	}

	describe("parse_mxc", function()
		it("gives the server name and media ID of a valid URI", function()
			local server_name, media_id = util.parse_mxc("mxc://example.org/AbC_123-x")
			assert.are.equal("example.org", server_name)
			assert.are.equal("AbC_123-x", media_id)
		end)

		it("accepts a server name with a port", function()
			local server_name, media_id = util.parse_mxc("mxc://example.org:8448/abc")
			assert.are.equal("example.org:8448", server_name)
			assert.are.equal("abc", media_id)
		end)

		it("accepts an IPv6 server name with a port", function()
			local server_name, media_id = util.parse_mxc("mxc://[1234:5678::abcd]:8448/abc")
			assert.are.equal("[1234:5678::abcd]:8448", server_name)
			assert.are.equal("abc", media_id)
		end)

		it("rejects anything that is not a well-formed mxc URI", function()
			for _, uri in ipairs(INVALID_MXC) do
				local server_name, media_id = util.parse_mxc(uri)
				assert.is_nil(server_name, uri)
				assert.is_nil(media_id, uri)
			end
		end)

		it("rejects nil", function()
			local server_name, media_id = util.parse_mxc(nil)
			assert.is_nil(server_name)
			assert.is_nil(media_id)
		end)
	end)

	describe("mxc_to_url", function()
		it("resolves a valid URI to the media download endpoint of the homeserver", function()
			assert.are.equal(
				"https://hs.example/_matrix/client/v1/media/download/example.org/AbC_123-x",
				util.mxc_to_url("https://hs.example", "mxc://example.org/AbC_123-x")
			)
		end)

		it("resolves anything else to no URL", function()
			for _, uri in ipairs(INVALID_MXC) do
				assert.is_nil(util.mxc_to_url("https://hs.example", uri), uri)
			end
			assert.is_nil(util.mxc_to_url("https://hs.example", nil))
		end)
	end)

	describe("media_headers", function()
		it("authenticates a media URL of the homeserver with the current token", function()
			assert.are.same({ Authorization = "Bearer token-1" }, util.media_headers(MEDIA .. "abc"))

			client.client.access_token = "token-2"

			assert.are.same({ Authorization = "Bearer token-2" }, util.media_headers(MEDIA .. "abc"))
		end)

		it("authenticates a URL resolved from an mxc URI, even with an old token in the query", function()
			local url = util.mxc_to_url("https://example.org", "mxc://example.org/abc")

			assert.are.same({ Authorization = "Bearer token-1" }, util.media_headers(url))
			assert.are.same({ Authorization = "Bearer token-1" }, util.media_headers(url .. "?access_token=old"))
		end)

		it("sends nothing to another server", function()
			assert.is_nil(util.media_headers("https://maps.google.com/?q=1,2"))
		end)

		it("sends nothing to another path of the homeserver", function()
			assert.is_nil(util.media_headers("https://example.org/_matrix/client/v3/account/whoami"))
			assert.is_nil(util.media_headers("https://example.org/_matrix/client/v1/media/download/a/../x"))
		end)

		it("sends nothing to a host that starts with the homeserver host", function()
			assert.is_nil(
				util.media_headers("https://example.org.evil.com/_matrix/client/v1/media/download/example.org/abc")
			)
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
