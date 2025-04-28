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

return M
