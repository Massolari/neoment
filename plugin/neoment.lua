local subcommands = {
	open_rooms = function()
		require("neoment.rooms").pick_open()
	end,
	rooms = function()
		require("neoment.rooms").pick()
	end,
	sync_start = function()
		require("neoment").sync_start()
	end,
	sync_stop = function()
		require("neoment.sync").stop()
	end,
	clear = function()
		require("neoment.storage").clear_cache()
	end,
	join = function(opts)
		local room_id = opts.fargs[2]
		if not room_id then
			require("neoment.notify").error("Usage: :Neoment join <room_id_or_alias>")
			return
		end
		require("neoment").join_room(room_id)
	end,
	logout = function()
		local notify = require("neoment.notify")
		local choice = vim.fn.confirm(
			"Are you sure you want to log out?\nAll saved data will be lost.",
			"&Yes\n&No",
			2, -- Default to "No"
			"Neoment"
		)

		if choice == 1 then -- 1 = "Yes"
			require("neoment").logout()
		else
			notify.info("Operation canceled")
		end
	end,
	reload_config = function()
		require("neoment.config").load()
		require("neoment.notify").info("Configuration reloaded")
	end,
}
local subcommands_names = vim.tbl_keys(subcommands)

vim.api.nvim_create_user_command("Neoment", function(opts)
	local notify = require("neoment.notify")
	local argument = opts.fargs[1]

	if not argument then
		require("neoment").init()
		return
	end

	local subcommand = subcommands[argument]

	if subcommand then
		subcommand(opts)
	else
		notify.error("Unknown subcommand: " .. subcommand)
		notify.info(string.format("Available subcommands: %s", table.concat(subcommands_names, ", ")))
	end
end, {
	desc = "Neoment Matrix client",
	nargs = "*",
	complete = function(arglead)
		if arglead == "" then
			return subcommands_names
		end
		local matches = {}
		for _, cmd in ipairs(subcommands_names) do
			if cmd:match("^" .. vim.pesc(arglead)) then
				table.insert(matches, cmd)
			end
		end
		return matches
	end,
})

--- Omnifunc for the compose buffer
--- It provides completion for the members of the room
--- @param findstart integer
--- @param base string
--- @return integer|table|nil
function _G.neoment_compose_omnifunc(findstart, base)
	if findstart == 1 then
		local line = vim.api.nvim_get_current_line()
		local col = vim.fn.col(".")

		--- @type integer|nil, integer|nil
		local start, finish = 0, 0
		while true do
			start, finish = string.find(line, "@[%w%.:_%-]*", start + 1)
			if start and col >= start and col <= finish + 1 then
				return start - 1
			elseif not start then
				break
			end
		end

		return -2
	else
		local buf = vim.api.nvim_get_current_buf()
		local res = {}
		--- @type table<string, string>
		local members = vim.b[buf].members or {}

		for id, name in pairs(members) do
			local lower_name = string.lower(name)
			if string.match(id, base) or string.match("@" .. lower_name, string.lower(base)) then
				table.insert(res, {
					word = id,
					abbr = name,
					menu = id,
					icase = 1,
				})
			end
		end

		return res
	end
end
