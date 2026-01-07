local M = {}

--- Add padding to the left of a string
--- @param str string The string to pad
--- @param length number The desired length of the string after padding
M.pad_left = function(str, length)
	local str_length = vim.fn.strdisplaywidth(str)
	if str_length >= length then
		-- Return the original string cropped to the desired length
		str = M.take_until(str, length)
		str_length = vim.fn.strdisplaywidth(str)
	end

	local padding = string.rep(" ", length - str_length)
	return padding .. str
end

--- Take a substring until a certain length
--- @param str string The string to take from
--- @param length number The desired length of the string
--- @return string The substring until the specified length
M.take_until = function(str, length)
	local chars = vim.fn.split(str, "\\zs")
	local final_text = {}
	local current_size = 0

	for i = 1, #chars do
		local char = chars[i]
		local char_size = vim.fn.strdisplaywidth(char)
		current_size = current_size + char_size
		if current_size > length then
			break
		end
		table.insert(final_text, char)
	end

	return vim.fn.join(final_text, "")
end

--- Join a table of strings with a separator
--- @param list table The table of strings to join
--- @param sep string The separator to use
--- @return string The joined string
M.join = function(list, sep)
	local result = ""
	for i = 1, #list do
		result = result .. list[i]
		if i < #list then
			result = result .. sep
		end
	end
	return result
end

--- Convert mxc URI to a URL
--- @param homeserver string The homeserver URL
--- @param mxc_uri string The mxc URI to convert
--- @return string The converted URL
M.mxc_to_url = function(homeserver, mxc_uri)
	local mxc_prefix = "mxc://"
	if not mxc_uri or not mxc_uri:find(mxc_prefix) then
		return mxc_uri
	end

	local mxc_id = mxc_uri:sub(#mxc_prefix + 1)
	return string.format("%s/_matrix/client/v1/media/download/%s", homeserver, mxc_id)
end

--- Write to a non-modifiable buffer
--- @param buf number The buffer number
--- @param lines table<string> The lines to write
--- @param start number The starting line number
--- @param end_line number The ending line number
M.buffer_write = function(buf, lines, start, end_line)
	local lines_without_newlines = vim.iter(lines)
		:map(function(line)
			local no_new_lines, _ = line:gsub("\n", " ")
			return no_new_lines
		end)
		:totable()

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, start, end_line, false, lines_without_newlines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("modified", false, { buf = buf })
end

--- Get the existing buffer from a predicate
--- @param predicate fun(buf: number): boolean The predicate function to check each buffer
--- @return number|nil The buffer number if found, nil otherwise
M.get_existing_buffer = function(predicate)
	local bufs = vim.api.nvim_list_bufs()
	for _, buf in ipairs(bufs) do
		if vim.api.nvim_buf_is_loaded(buf) and predicate(buf) then
			return buf
		end
	end
	return nil
end

--- Open a float window
--- @param lines table The lines to display in the float window
--- @param opts vim.api.keyset.win_config The options for the float window
--- @return number, number The buffer number of the float window and the window number
M.open_float = function(lines, opts)
	local bufnr = vim.api.nvim_create_buf(false, true)
	local width = opts.width or 80
	local height = opts.height or 20

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_set_option_value("filetype", "neoment_float", { buf = bufnr })

	local win = vim.api.nvim_open_win(
		bufnr,
		false,
		vim.tbl_extend("force", {
			style = "minimal",
			relative = "cursor",
			width = width,
			height = height,
			row = 1,
			col = 0,
		}, opts)
	)

	local augroup = vim.api.nvim_create_augroup("neoment_float_" .. win, {})
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		callback = function()
			vim.api.nvim_buf_delete(bufnr, { force = true })
			vim.api.nvim_del_augroup_by_id(augroup)
		end,
	})

	return bufnr, win
end

--- Format milliseconds to a human-readable string
--- @param ms? number The time in milliseconds
--- @return string The formatted time string
M.format_milliseconds = function(ms)
	if not ms or ms < 0 then
		return "--:--"
	end
	local seconds = math.floor(ms / 1000)
	local minutes = math.floor(seconds / 60)
	local hours = math.floor(minutes / 60)

	seconds = seconds % 60
	minutes = minutes % 60

	if hours > 0 then
		return string.format("%02d:%02d:%02d", hours, minutes, seconds)
	else
		return string.format("%02d:%02d", minutes, seconds)
	end
end

--- Format bytes to a human-readable string
--- @param bytes? number The size in bytes
--- @return string The formatted size string
M.format_bytes = function(bytes)
	if not bytes or bytes < 0 then
		return "?.? B"
	end
	local units = { "B", "KB", "MB", "GB", "TB" }
	local unit_index = 1

	while bytes >= 1024 and unit_index < #units do
		bytes = bytes / 1024
		unit_index = unit_index + 1
	end

	return string.format("%.2f %s", bytes, units[unit_index])
end

--- Check if a string is a filename based on the mimetype
--- @param mimetype string The mimetype to check
--- @param filename string The filename to check
--- @return boolean True if the mimetype is a filename, false otherwise
M.is_filename = function(mimetype, filename)
	if not mimetype or not filename then
		return false
	end

	local mime_parts = vim.split(mimetype, "/")
	if #mime_parts ~= 2 then
		return false
	end

	-- Get the subtype
	local mime_subtype = mime_parts[2]

	-- Get the filename extension (if any)
	local filename_parts = vim.split(filename, ".", { plain = true })
	local filename_extension = filename_parts[#filename_parts]
	if #filename_parts == 1 then
		return false
	end

	-- Check if the filename is included in the mimetype
	return mime_subtype:find(filename_extension) ~= nil
end

--- Get the msgtype from a mimetype
--- @param mimetype string The mimetype to check
--- @return string The msgtype
M.get_msgtype = function(mimetype)
	vim.validate({ mimetype = { mimetype, "string" } })

	local mime_map = {
		["image"] = "m.image",
		["video"] = "m.video",
		["audio"] = "m.audio",
	}

	local mime_parts = vim.split(mimetype, "/")
	if #mime_parts ~= 2 then
		return "m.file"
	end

	local mime_type = mime_parts[1]
	return mime_map[mime_type] or "m.file"
end

--- Generates a UUID v4.
--- @return string A UUID v4 string.
M.uuid = function()
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	local uuid_str, _ = string.gsub(template, "[xy]", function(c)
		local v = (c == "x" and math.random(0, 0xf) or math.random(8, 0xb))
		return string.format("%x", v)
	end)

	return uuid_str
end

--- Get a function to set <Plug> mappings with description
--- @param plug_prefix string The prefix for the <Plug> mappings
--- @return fun(mode: string|string[], lhs: string, rhs: string, fun: function|string, opts: table|nil): nil A function to set <Plug> mappings
M.get_plug_mapping_setter = function(plug_prefix)
	--- Set a <Plug> mapping with description
	--- It also sets the internal <SID> mapping for the rhs
	--- @param mode string|string[] The mode for the mapping
	--- @param lhs string The left-hand side of the mapping
	--- @param rhs string The right-hand side of the mapping
	--- @param fun function|string The function to map to
	--- @param opts table|nil The options for the mapping
	return function(mode, lhs, rhs, fun, opts)
		-- Create a <SID> mapping for the rhs. E.g. <Plug>NeomentRoomsEnter -> <SID>Enter
		-- local sid_mapping = rhs:gsub("<Plug>" .. plug_prefix, "<SID>")
		local sid_mapping = "<SID>" .. rhs
		local plug_rhs = "<Plug>" .. plug_prefix .. rhs
		vim.keymap.set("n", sid_mapping, fun)
		if vim.fn.hasmapto(sid_mapping) == 0 then
			vim.keymap.set("n", plug_rhs, sid_mapping, { unique = true, script = true })
		end
		if vim.fn.hasmapto(plug_rhs) == 0 then
			local esc_prefix = mode == "i" and "<Esc>" or ""
			vim.keymap.set(mode, lhs, esc_prefix .. plug_rhs, opts)
		end
	end
end
--- Get the total number of normal windows in current tabpage.
--- @return integer total number of normal windows
M.win_count = function()
	return #vim.tbl_filter(function(id)
		return #vim.api.nvim_win_get_config(id).relative == 0
	end, vim.api.nvim_tabpage_list_wins(0))
end

return M
