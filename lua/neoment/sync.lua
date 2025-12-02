local M = {}

local notify = require("neoment.notify")
local storage = require("neoment.storage")
local matrix = require("neoment.matrix")
local error = require("neoment.error")

--- @type neoment.sync.Status
local status = { kind = "never" }
local error_count = 0

local keep_syncing = true

--- @alias neoment.sync.Status { kind: "never" } | neoment.sync.StatusSyncing | neoment.sync.StatusStopped

--- @class neoment.sync.StatusSyncing
--- @field kind "syncing"
--- @field last_sync? number The last time the sync was performed.
--- @field current_count number The current number of syncs performed.

--- @class neoment.sync.StatusStopped : neoment.sync.StatusSyncing
--- @field kind "stopped"

---@class neoment.sync.Options
---@field save_session boolean Whether to save the session periodically.

--- Start the synchronization process.
--- @param client neoment.matrix.client.Client The Matrix client instance.
--- @param on_done fun(updated_rooms: table<string>): any Callback function to be called after synchronization.
--- @param options neoment.sync.Options Options for synchronization.
M.start = function(client, on_done, options)
	keep_syncing = true
	-- Prevent multiple syncs at the same time
	if status.kind == "syncing" then
		return
	end

	if status.kind == "stopped" then
		status = {
			kind = "syncing",
			last_sync = status.last_sync,
			current_count = status.current_count,
		}
	else
		status = {
			kind = "syncing",
			current_count = 0,
		}
	end

	-- Prepare sync options
	---@type neoment.matrix.SyncOptions
	local sync_options = {}

	-- On first sync, request full state to get room names and other essential metadata
	if status.kind == "never" then
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
		status = error.match(data, function(actual_data)
			local sync_data = actual_data.sync
			--- @type neoment.sync.Status
			local new_status = {
				kind = "stopped",
				last_sync = os.time(),
				current_count = status.current_count + 1,
			}
			client.sync_token = sync_data.next_batch

			-- Save the token periodically (every 10 syncs)
			if options.save_session and status.current_count % 10 == 0 then
				storage.save_session()
			end

			if on_done then
				vim.schedule(function()
					on_done(actual_data.updated_rooms)
				end)
			end

			return new_status
		end, function(err)
			if error_count < 3 then
				error_count = error_count + 1
				notify.error("Error syncing: " .. err.error .. "\nRetrying...")
				vim.defer_fn(function()
					M.start(client, on_done, options)
				end, 1000)
			else
				notify.error("Error syncing: " .. err.error)
			end

			--- @type neoment.sync.Status
			return {
				kind = "stopped",
				last_sync = status.last_sync,
				current_count = status.current_count,
			}
		end)

		if keep_syncing then
			M.start(client, on_done, options)
		end
	end)
end

--- Stop the synchronization process.
M.stop = function()
	keep_syncing = false
	if status.kind == "syncing" then
		status.kind = "stopped"
	end
	notify.info("Synchronization stopped")
end

--- Get the current status of the synchronization process.
--- @return neoment.sync.Status The current status of the synchronization process.
M.get_status = function()
	return status
end

return M
