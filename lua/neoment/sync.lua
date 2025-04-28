local M = {}

local storage = require("neoment.storage")
local matrix = require("neoment.matrix")
local error = require("neoment.error")

M.last_sync = nil

local is_syncing = false
local keep_syncing = true
local sync_count = 0

---@class neoment.sync.Options
---@field save_session boolean Whether to save the session periodically.

--- Start the synchronization process.
--- @param client neoment.matrix.client.Client The Matrix client instance.
--- @param on_done fun(updated_rooms: table<string>): any Callback function to be called after synchronization.
--- @param options neoment.sync.Options Options for synchronization.
M.start = function(client, on_done, options)
	keep_syncing = true
	-- Prevent multiple syncs at the same time
	if is_syncing then
		return
	end

	is_syncing = true

	-- Prepare sync options
	---@type neoment.matrix.SyncOptions
	local sync_options = {}

	-- On first sync, request full state to get room names and other essential metadata
	if M.last_sync == nil then
		sync_options.full_state = true
	end

	-- Create a filter to minimize data transfer
	-- This filter limits timeline events to 1 per room and includes only necessary state events
	sync_options.filter = vim.uri_encode(
		vim.json.encode({
			room = {
				state = {
					lazy_load_members = true, -- Load members lazily
				},
				timeline = {
					limit = 1, -- Only get the latest message per room
					lazy_load_members = true, -- Load members lazily
				},
			},
		}),
		"rfc3986"
	)

	sync_options.timeout = 30000 -- Set a timeout for the sync request

	matrix.sync(sync_options, function(data)
		is_syncing = false

		error.match(data, function(actual_data)
			local sync_data = actual_data.sync
			M.last_sync = os.time()
			client.sync_token = sync_data.next_batch

			-- Save the token periodically (every 10 syncs)
			sync_count = sync_count + 1
			if options.save_session and sync_count % 10 == 0 then
				storage.save_session()
			end

			if on_done then
				vim.schedule(function()
					on_done(actual_data.updated_rooms)
				end)
			end
			return nil
		end, function(err)
			vim.notify("Error syncing: " .. err.error, vim.log.levels.ERROR)
		end)

		if keep_syncing then
			M.start(client, on_done, options)
		end
	end)
end

--- Stop the synchronization process.
M.stop = function()
	keep_syncing = false
end

return M
