local M = {}

local constants = require("neoment.constants")

-- Define patterns for Markdown syntax
local markdown_patterns = {
	-- Bold: **text** or __text__
	{ pattern = "%*%*(.-)%*%*", replacement = "<strong>%1</strong>" },
	{ pattern = "__(.-)__", replacement = "<strong>%1</strong>" },

	-- Italic: *text* or _text_
	{ pattern = "([^_])_([^_].-)_([^_])", replacement = "%1<em>%2</em>%3" },
	{ pattern = "_([^_].-)_", replacement = "<em>%1</em>" },
	{ pattern = "%*([^%*\n]-)%*", replacement = "<em>%1</em>" },

	-- Inline code: `code`
	{ pattern = "`(.-)`", replacement = "<code>%1</code>" },
	{ pattern = "```(.-)```", replacement = "<code>%1</code>" },
	{ pattern = "```(%w+)\n(.-)\n```", replacement = '<pre><code class="language-%1">%2</code></pre>' },

	-- Unordered lists
	{ pattern = "^%s*[-%*]%s+([^\n]+)", replacement = "<li>%1</li>" },
	{ pattern = "\n%s*[-%*]%s+([^\n]+)", replacement = "\n<li>%1</li>" },

	-- Headers: # Title
	{ pattern = "^%s*#%s+([^\n]+)", replacement = "<h1>%1</h1>" },
	{ pattern = "\n%s*#%s+([^\n]+)", replacement = "\n<h1>%1</h1>" },
	{ pattern = "^%s*##%s+([^\n]+)", replacement = "<h2>%1</h2>" },
	{ pattern = "\n%s*##%s+([^\n]+)", replacement = "\n<h2>%1</h2>" },
	{ pattern = "^%s*###%s+([^\n]+)", replacement = "<h3>%1</h3>" },
	{ pattern = "\n%s*###%s+([^\n]+)", replacement = "\n<h3>%1</h3>" },
}

--- Escape HTML entities
--- @param text string Text to escape
--- @return string Escaped text
local function escape_html_content(text)
	local result = text

	result = result:gsub("&", "&amp;")
	result = result:gsub("<", "&lt;")
	result = result:gsub(">", "&gt;")

	return result
end

--- Convert Markdown to HTML
--- @param markdown_text string Markdown text to convert
--- @return string HTML text
M.to_html = function(markdown_text)
	if not markdown_text or markdown_text == "" then
		return ""
	end

	local html = markdown_text

	-- Process Markdown blockquotes before other patterns
	-- Identify consecutive lines of blockquotes to group them into a single blockquote

	--- @type string[]
	local lines = {}
	local in_blockquote = false
	local blockquote_content = ""

	for line in vim.gsplit(html, "\n", { plain = true }) do
		if line:match("^%s*>%s([^!]*)") then
			local content = line:gsub("^%s*>%s*(.*)", "%1")
			content = escape_html_content(content)
			if in_blockquote then
				blockquote_content = blockquote_content .. "\n" .. content
			else
				in_blockquote = true
				blockquote_content = content
			end
		elseif line:match("%s*>!.-<!") then
			-- Inline spoiler
			local new_line = line:gsub(">!%s*(.-)<!", function(spoiler_content)
				return "<span data-mx-spoiler>" .. escape_html_content(spoiler_content) .. "</span>"
			end)
			table.insert(lines, new_line)
		elseif line:match("^%s*>!.*") then
			-- Spoiler block
			local content = line:gsub("^%s*>!%s*(.*)", "%1")
			content = escape_html_content(content)
			table.insert(lines, "<span data-mx-spoiler>" .. content .. "</span>")
		else
			if in_blockquote then
				table.insert(lines, "<blockquote>" .. blockquote_content .. "</blockquote>")
				in_blockquote = false
				blockquote_content = ""
			end
			table.insert(lines, escape_html_content(line))
		end
	end

	if in_blockquote then
		table.insert(lines, "<blockquote>" .. blockquote_content .. "</blockquote>")
	end

	html = table.concat(lines, "\n")

	local preserved_blocks = {}
	local preserved_count = 0

	-- Handle blockquotes with specified language
	html = html:gsub("```(%w+)\n(.-)\n```", function(lang, code)
		preserved_count = preserved_count + 1
		local placeholder = "{{CODEBLOCK" .. preserved_count .. "}}"
		preserved_blocks[placeholder] = '<pre><code class="language-' .. lang .. '">' .. code .. "</code></pre>"
		return placeholder
	end)

	-- Handle code blocks without specified language
	html = html:gsub("```(.-)```", function(code)
		preserved_count = preserved_count + 1
		local placeholder = "{{CODEBLOCK" .. preserved_count .. "}}"
		preserved_blocks[placeholder] = "<pre><code>" .. code .. "</code></pre>"
		return placeholder
	end)

	-- Handle inline code
	html = html:gsub("`(.-)`", function(code)
		preserved_count = preserved_count + 1
		local placeholder = "{{INLINECODE" .. preserved_count .. "}}"
		preserved_blocks[placeholder] = "<code>" .. code .. "</code>"
		return placeholder
	end)

	-- Handle mentions
	html = html:gsub(constants.MENTION_REGEX, function(mention)
		preserved_count = preserved_count + 1
		local placeholder = "{{MENTION" .. preserved_count .. "}}"
		preserved_blocks[placeholder] = mention
		return placeholder
	end)

	-- First, preserve link content but process markdown within link text
	local link_placeholders = {}
	local link_count = 0

	-- Process links first and store them as placeholders
	html = html:gsub("%[(.-)%]%((.-)%)", function(text, url)
		link_count = link_count + 1
		local placeholder = "LINKPLACEHOLDER" .. link_count .. "LINKPLACEHOLDER"

		-- Process markdown patterns within the link text (but not the URL)
		local processed_text = text
		for _, pattern in ipairs(markdown_patterns) do
			processed_text = processed_text:gsub(pattern.pattern, pattern.replacement)
		end

		link_placeholders[placeholder] = '<a href="' .. url .. '">' .. processed_text .. "</a>"
		return placeholder
	end)
	-- Apply other patterns (excluding links since they're already processed)
	for _, pattern in ipairs(markdown_patterns) do
		html = html:gsub(pattern.pattern, pattern.replacement)
	end

	-- Restore link placeholders
	for placeholder, link in pairs(link_placeholders) do
		html = html:gsub(placeholder, link)
	end

	-- Convert line breaks to <br /> tags (except in code blocks)
	html = html:gsub("\n", "<br />")

	-- Restaurar os blocos de código
	for placeholder, code_block in pairs(preserved_blocks) do
		html = html:gsub(placeholder, code_block)
	end

	-- Processar listas não ordenadas para adicionar <ul> tags
	html = html:gsub("(<li>.-</li>)%s*(<li>)", "%1%2") -- juntar itens adjacentes
	html = html:gsub("(<li>.*</li>)", "<ul>%1</ul>") -- envolver com <ul>
	-- html = html:gsub("<ul>.-(<ul>.-</ul>).-</ul>", "%1") -- remover aninhamentos extras

	-- Linebreaks
	html = html:gsub("\\n", "<br />")

	return html
end

--- Convert HTML to Markdown
--- @param html string HTML text to convert
--- @return string Markdown text
M.from_html = function(html)
	if not html or html == "" then
		return ""
	end

	local markdown = html

	-- Replace
	markdown = markdown:gsub("&#39;", "'")
	markdown = markdown:gsub("&#x27;", "'")
	markdown = markdown:gsub("&#27;", '"')

	-- Replace common HTML entities
	markdown = markdown:gsub("&lt;", "<")
	markdown = markdown:gsub("&gt;", ">")
	markdown = markdown:gsub("&amp;", "&")
	markdown = markdown:gsub("&quot;", '"')

	-- Paragraphs
	markdown = markdown:gsub("<p>(.-)</p>", "%1\n")

	-- Line breaks
	markdown = markdown:gsub("<br>", "\n")
	markdown = markdown:gsub("<br/>", "\n")
	markdown = markdown:gsub("<br />", "\n")

	-- Capture code blocks
	local preserved_code_blocks = {}
	local preserved_count = 0
	local function preserve(text)
		preserved_count = preserved_count + 1
		local placeholder = "{{CODEBLOCK" .. preserved_count .. "}}"
		preserved_code_blocks[placeholder] = text
		return placeholder
	end

	-- Code blocks with language
	markdown = markdown:gsub([[<pre><code class=["']language%-([^"']+)["']>(.-)</code></pre>]], function(lang, code)
		return preserve("\n```" .. lang .. "\n" .. code .. "\n```\n")
	end)

	-- Code blocks without language
	markdown = markdown:gsub("<pre><code>(.-)</code></pre>", function(code)
		return preserve("\n```\n" .. code .. "\n```\n")
	end)

	-- Code blocks with language (inline/fallback)
	markdown = markdown:gsub([[<code class=["']language%-([^"]+)["']>(.-)</code>]], function(lang, code)
		return preserve("\n```" .. lang .. "\n" .. code .. "\n```\n")
	end)

	-- Inline code
	markdown = markdown:gsub("<code>(.-)</code>", function(code)
		return preserve("`" .. code .. "`")
	end)

	-- Strip Matrix reply blocks as we support rich replies
	markdown = markdown:gsub("<mx%-reply>%s*<blockquote>(.-)</blockquote>%s*</mx%-reply>", "")

	-- Apply our own forwarded header
	markdown = markdown:gsub("<p data%-mx%-forwarded%-notice>(.-)</p>", "_↪️ Forwarded:_\n\n")

	-- Convert Matrix <span data-mx-spoiler> spoiler blocks to markdown
	-- markdown = markdown:gsub("<span data%-mx%-spoiler>(.-)</span>", "[Spoiler](<%1>)")
	-- markdown = markdown:gsub('<span data%-mx%-spoiler="([^"]*)">(.-)</span>', "[Spoiler for %1](<%2>)")
	markdown = markdown:gsub("<span data%-mx%-spoiler>(.-)</span>", function(spoiler)
		-- Check if there are whitespaces in the content
		if spoiler:match("%s") then
			spoiler = string.format("<%s>", spoiler)
		end
		return string.format("[Spoiler](%s)", spoiler)
	end)
	markdown = markdown:gsub('<span data%-mx%-spoiler="([^"]*)">(.-)</span>', function(description, spoiler)
		-- Check if there are whitespaces in the content
		if spoiler:match("%s") then
			spoiler = string.format("<%s>", spoiler)
		end
		return string.format("[Spoiler for %s](%s)", description, spoiler)
	end)

	-- Convert HTML blockquote to markdown
	markdown = markdown:gsub("<blockquote.->(.-)</blockquote>", function(content)
		-- Adiciona o caractere '>' em cada linha da citação
		local quoted = ""
		for line in content:gmatch("([^\n]+)") do
			quoted = quoted .. "┃ " .. line .. "\n"
		end
		return quoted
	end)

	-- Handle tags with data-md attribute
	markdown = markdown:gsub(
		[[<(%w+)%s+data%-md=["'](.-)["']>(.-)</(%w+)>]],
		function(tag_open, md_value, content, tag_close)
			if tag_open ~= tag_close then
				return content -- Open tag and close tag do not match, return only the content
			end

			-- Remove any \ characters from the md_value
			md_value = md_value:gsub("\\", "")

			-- Use the data-md value as a delimiter for the content
			if md_value ~= "" then
				return md_value .. content .. md_value
			else
				-- If data-md is empty, return the content without formatting
				return content
			end
		end
	)

	-- Bold
	markdown = markdown:gsub("<strong>(.-)</strong>", "**%1**")
	markdown = markdown:gsub("<b>(.-)</b>", "**%1**")

	-- Italic
	markdown = markdown:gsub("<em>(.-)</em>", "_%1_")
	markdown = markdown:gsub("<i>(.-)</i>", "_%1_")



	-- Headers
	markdown = markdown:gsub("<h1>(.-)</h1>", "# %1")
	markdown = markdown:gsub("<h2>(.-)</h2>", "## %1")
	markdown = markdown:gsub("<h3>(.-)</h3>", "### %1")

	-- Links
	markdown = markdown:gsub([[<a href=["'](.-)["']>(.-)</a>]], "[%2](%1)")

	-- Lists
	markdown = markdown:gsub("<li>(.-)</li>", "- %1")
	markdown = markdown:gsub("<ul>(.-)</ul>", "%1")

	-- Clean up any remaining HTML tags
	markdown = markdown:gsub("<[^>]+>(.-)</[^>]+>", "%1")

	-- Restore code blocks
	for placeholder, code in pairs(preserved_code_blocks) do
		markdown = markdown:gsub(placeholder, code)
	end

	return markdown
end

return M
