local client = require("neoment.matrix.client")

describe("matrix get_room_avatar", function()
	local matrix

	before_each(function()
		-- Reset modules so each test gets a fresh state
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.curl"] = {}

		-- Re-require with a fresh client
		local fresh_client = require("neoment.matrix.client")
		fresh_client.new("https://example.org", "token123")
		matrix = require("neoment.matrix")
	end)

	after_each(function()
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.matrix.client"] = nil
		package.loaded["neoment.matrix.api"] = nil
		package.loaded["neoment.matrix.event"] = nil
		package.loaded["neoment.curl"] = nil
	end)

	it("returns nil for a joined room with no avatar", function()
		local fresh_client = require("neoment.matrix.client")
		local room_id = "!room1:example.org"
		fresh_client.get_room(room_id)

		local result = matrix.get_room_avatar(room_id)
		assert.is_nil(result)
	end)

	it("returns avatar_url for a joined room that has one", function()
		local fresh_client = require("neoment.matrix.client")
		local room_id = "!room1:example.org"
		local room = fresh_client.get_room(room_id)
		room.avatar_url = "mxc://example.org/abc123"

		local result = matrix.get_room_avatar(room_id)
		assert.are.equal("mxc://example.org/abc123", result)
	end)

	it("returns nil for an invited room with no avatar", function()
		local fresh_client = require("neoment.matrix.client")
		local room_id = "!invited:example.org"
		fresh_client.get_invited_room(room_id)

		local result = matrix.get_room_avatar(room_id)
		assert.is_nil(result)
	end)

	it("returns avatar_url for an invited room that has one", function()
		local fresh_client = require("neoment.matrix.client")
		local room_id = "!invited:example.org"
		local invited = fresh_client.get_invited_room(room_id)
		invited.avatar_url = "mxc://example.org/invited_avatar"

		local result = matrix.get_room_avatar(room_id)
		assert.are.equal("mxc://example.org/invited_avatar", result)
	end)

	-- Regression test: opening room info for a joined room must not create an
	-- invited room entry, which previously caused the room to appear as invited.
	it("does NOT create an invited room entry when called for a joined room", function()
		local fresh_client = require("neoment.matrix.client")
		local room_id = "!room1:example.org"
		-- Simulate a joined room (no avatar set)
		fresh_client.get_room(room_id)

		assert.is_false(fresh_client.is_invited_room(room_id), "room should not be invited before the call")

		matrix.get_room_avatar(room_id)

		assert.is_false(
			fresh_client.is_invited_room(room_id),
			"get_room_avatar must not create an invited room entry for a joined room"
		)
	end)

	-- Regression test: opening room info for a room that is neither joined nor
	-- invited must not create invited room entries either.
	it("does NOT create an invited room entry for an unknown room", function()
		local fresh_client = require("neoment.matrix.client")
		local room_id = "!unknown:example.org"

		assert.is_false(fresh_client.is_invited_room(room_id))

		matrix.get_room_avatar(room_id)

		assert.is_false(
			fresh_client.is_invited_room(room_id),
			"get_room_avatar must not create an invited room entry for an unknown room"
		)
	end)
end)
