local notify = require("neoment.notify")

require("neoment.highlight").define_highlights()
require("neoment.config").load()

vim.api.nvim_create_autocmd({ "ColorScheme" }, {
	group = vim.api.nvim_create_augroup("neoment_highlight", { clear = true }),
	pattern = { "*" },
	callback = function()
		require("neoment.highlight").define_highlights()
	end,
})

-- Criar comandos
vim.api.nvim_create_user_command("Neoment", function(opts)
	local subcommand = opts.fargs[1]

	if not subcommand then
		require("neoment").init()
	elseif subcommand == "rooms" then
		require("neoment.rooms").pick()
	elseif subcommand == "sync_start" then
		require("neoment").sync_start()
	elseif subcommand == "sync_stop" then
		require("neoment.sync").stop()
	elseif subcommand == "clear" then
		require("neoment.storage").clear_cache()
	elseif subcommand == "join" then
		local room_id = opts.fargs[2]
		if not room_id then
			notify.error("Usage: :Neoment join <room_id_or_alias>")
			return
		end
		require("neoment").join_room(room_id)
	elseif subcommand == "logout" then
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
	elseif subcommand == "reload_config" then
		require("neoment.config").load()
		notify.info("Configuration reloaded")
	else
		notify.error("Unknown subcommand: " .. subcommand)
		notify.info("Available subcommands: rooms, sync_start, sync_stop, clear, logout, join, reload_config")
	end
end, {
	desc = "Neoment Matrix client",
	nargs = "*",
	complete = function(arglead)
		local subcommands = {
			"rooms",
			"sync_start",
			"sync_stop",
			"clear",
			"logout",
			"join",
			"reload_config",
		}
		if arglead == "" then
			return subcommands
		end
		local matches = {}
		for _, cmd in ipairs(subcommands) do
			if cmd:match("^" .. vim.pesc(arglead)) then
				table.insert(matches, cmd)
			end
		end
		return matches
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("neoment_room", {}),
	pattern = "neoment_room",
	callback = function(args)
		vim.treesitter.start(args.buf, "markdown")
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
