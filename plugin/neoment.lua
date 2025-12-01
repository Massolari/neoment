vim.g.neoment = vim.g.neoment or {}
vim.g.neoment.save_session = vim.g.neoment and vim.g.neoment.save_session or true

-- Definir grupos de highlight
vim.api.nvim_set_hl(0, "NeomentRoomsTitle", { link = "@text.title.2.markdown" })
vim.api.nvim_set_hl(0, "NeomentSectionTitle", { link = "Title" })
vim.api.nvim_set_hl(0, "NeomentBufferRoom", { link = "@keyword" })
vim.api.nvim_set_hl(0, "NeomentRoomUnread", { link = "Bold" })
vim.api.nvim_set_hl(0, "NeomentBufferRoomUnread", { link = "@keyword" })
vim.api.nvim_set_hl(0, "NeomentMention", { link = "ColorColumn" })
vim.api.nvim_set_hl(0, "NeomentMentionUser", { link = "@comment.error" })
vim.api.nvim_set_hl(0, "NeomentBubbleContent", { link = "ColorColumn" })
vim.api.nvim_set_hl(0, "NeomentBubbleBorder", { link = "ColorColumn" })
vim.api.nvim_set_hl(0, "NeomentBubbleActiveContent", { link = "IncSearch" })
vim.api.nvim_set_hl(0, "NeomentBubbleActiveBorder", { link = "IncSearch" })

local neoment_room_ns = vim.api.nvim_create_namespace("neoment_room")
vim.api.nvim_set_hl(neoment_room_ns, "NonText", { link = "FloatBorder" })

-- Apply bold to NeomentBufferRoom
local hl_buffer_room_undead = vim.api.nvim_get_hl(0, { name = "NeomentBufferRoomUnread", link = false })
if hl_buffer_room_undead then
	hl_buffer_room_undead.bold = true
	--- @diagnostic disable-next-line: param-type-mismatch
	vim.api.nvim_set_hl(0, "NeomentBufferRoomUnread", hl_buffer_room_undead)
end

-- Change the foreground with the background on NeomentBubbleBorder and NeomentBubbleActiveBorder
for _, hl_name in ipairs({ "NeomentBubbleActiveBorder", "NeomentBubbleBorder" }) do
	local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
	if hl then
		local new_fg = hl.bg
		hl.bg = hl.fg
		hl.fg = new_fg
		--- @diagnostic disable-next-line: param-type-mismatch
		vim.api.nvim_set_hl(0, hl_name, hl)
	end
end

-- Criar comandos
vim.api.nvim_create_user_command("Neoment", function(opts)
	local subcommand = opts.fargs[1]

	if not subcommand then
		require("neoment").init()
	elseif subcommand == "rooms" then
		require("neoment.rooms").pick()
	elseif subcommand == "stop" then
		require("neoment.sync").stop()
	elseif subcommand == "clear" then
		require("neoment.storage").clear_cache()
	elseif subcommand == "join" then
		local room_id = opts.fargs[2]
		if not room_id then
			vim.notify("Usage: :Neoment join <room_id_or_alias>", vim.log.levels.ERROR)
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
			vim.notify("Operation canceled", vim.log.levels.INFO)
		end
	else
		vim.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
		vim.notify("Available subcommands: rooms, stop, clear, logout, join", vim.log.levels.INFO)
	end
end, {
	desc = "Neoment Matrix client",
	nargs = "*",
	complete = function(arglead)
		local subcommands = { "rooms", "stop", "clear", "logout", "join" }
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
