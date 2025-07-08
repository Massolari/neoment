local stub = require("luassert.stub")
local spy = require("luassert.spy")
local match = require("luassert.match")
local assert = require("luassert.assert")
local busted = require("plenary.busted")
local describe = busted.describe
local before_each = busted.before_each
local after_each = busted.after_each
local it = busted.it

local markdown = require("neoment.markdown")

describe("Markdown", function()
	it("should convert bold text to HTML", function()
		local input = "**bold** __text__"
		local expected_output = "<strong>bold</strong> <strong>text</strong>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert italic text to HTML", function()
		local input = "this is an *italic* _text_"
		local expected_output = "this is an <em>italic</em> <em>text</em>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert inline code with single backticks to HTML", function()
		local input = "`inline code`"
		local expected_output = "<code>inline code</code>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert inline code with triple backticks to HTML", function()
		local input = "```inline code```"
		local expected_output = "<pre><code>inline code</code></pre>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert code blocks with language to HTML", function()
		local input = "```lua\nprint('Hello, World!')\n```"
		local expected_output = "<pre><code class=\"language-lua\">print('Hello, World!')</code></pre>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert unordered lists with dash to HTML", function()
		local input = "- Item 1\n- Item 2\n- Item 3"
		local expected_output = "<ul><li>Item 1</li><br /><li>Item 2</li><br /><li>Item 3</li></ul>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert unordered lists with asterisk to HTML", function()
		local input = "* Item 1\n* Item 2\n* Item 3"
		local expected_output = "<ul><li>Item 1</li><br /><li>Item 2</li><br /><li>Item 3</li></ul>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert links to HTML", function()
		local input = "[Matrix](https://matrix.org)"
		local expected_output = '<a href="https://matrix.org">Matrix</a>'
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert headers to HTML", function()
		local input = "# Header 1\n## Header 2\n### Header 3"
		local expected_output = "<h1>Header 1</h1><br /><h2>Header 2</h2><br /><h3>Header 3</h3>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should convert spoilers to HTML", function()
		local input = ">! This is a spoiler <! >! Another spoiler <!"
		local expected_output =
			"<span data-mx-spoiler>This is a spoiler </span> <span data-mx-spoiler>Another spoiler </span>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should keep empty lines", function()
		local input = "This is a line.\n\nThis is another line."
		local expected_output = "This is a line.<br /><br />This is another line."
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	it("should keep empty lines in code blocks", function()
		local input = "```\nThis is a line.\n\nThis is another line.\n```"
		local expected_output = "<pre><code>\nThis is a line.\n\nThis is another line.\n</code></pre>"
		local result = markdown.to_html(input)
		assert.are.same(expected_output, result)
	end)

	describe("from_html", function()
		it("should convert bold HTML tags to Markdown", function()
			local input = "<strong>bold text</strong> and <b>more bold</b>"
			local expected_output = "**bold text** and **more bold**"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert italic HTML tags to Markdown", function()
			local input = "<em>italic text</em> and <i>more italic</i>"
			local expected_output = "_italic text_ and _more italic_"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert inline code HTML to Markdown", function()
			local input = "<code>inline code</code>"
			local expected_output = "`inline code`"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert code blocks without language to Markdown", function()
			local input = "<pre><code>code block</code></pre>"
			local expected_output = "```\ncode block\n```\n"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert code blocks with language to Markdown", function()
			local input = '<pre><code class="language-lua">print("Hello")</code></pre>'
			local expected_output = '```lua\nprint("Hello")\n```\n'
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert headers to Markdown", function()
			local input = "<h1>Header 1</h1><h2>Header 2</h2><h3>Header 3</h3>"
			local expected_output = "# Header 1## Header 2### Header 3"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert links to Markdown", function()
			local input = '<a href="https://matrix.org">Matrix</a>'
			local expected_output = "[Matrix](https://matrix.org)"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert list items to Markdown", function()
			local input = "<ul><li>Item 1</li><li>Item 2</li><li>Item 3</li></ul>"
			local expected_output = "- Item 1- Item 2- Item 3"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert line breaks to newlines", function()
			local input = "Line 1<br>Line 2<br/>Line 3<br />Line 4"
			local expected_output = "Line 1\nLine 2\nLine 3\nLine 4"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert paragraphs to double newlines", function()
			local input = "<p>Paragraph 1</p><p>Paragraph 2</p>"
			local expected_output = "Paragraph 1\n\nParagraph 2\n\n"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert HTML entities to their characters", function()
			local input = "&lt;tag&gt; &amp; &quot;quotes&quot;"
			local expected_output = '<tag> & "quotes"'
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert spoiler spans to Markdown links", function()
			local input = "<span data-mx-spoiler>This is a spoiler</span>"
			local expected_output = "[Spoiler](<This is a spoiler>)"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert spoiler spans with description to Markdown", function()
			local input = '<span data-mx-spoiler="ending">The character dies</span>'
			local expected_output = "[Spoiler for ending](<The character dies>)"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should convert blockquotes to quoted text", function()
			local input = "<blockquote>This is a quote\nWith multiple lines</blockquote>"
			local expected_output = "┃ This is a quote\n┃ With multiple lines\n"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should remove Matrix reply blocks", function()
			local input = "<mx-reply><blockquote>Original message</blockquote></mx-reply>Reply content"
			local expected_output = "Reply content"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should handle data-md attributes", function()
			local input = '<em data-md="_">italic text</em>'
			local expected_output = "_italic text_"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should handle empty input", function()
			local input = ""
			local expected_output = ""
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should handle nil input", function()
			local input = nil
			local expected_output = ""
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should clean up remaining HTML tags", function()
			local input = "<div>content</div><span>more content</span>"
			local expected_output = "contentmore content"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should handle complex mixed HTML", function()
			local input =
				'<p>This is <strong>bold</strong> and <em>italic</em> text with <code>code</code> and a <a href="https://example.com">link</a>.</p>'
			local expected_output = "This is **bold** and _italic_ text with `code` and a [link](https://example.com).\n\n"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should preserve multiple newlines", function()
			local input = "Line 1\n\n\nLine 2\n\n\n\nLine 3"
			local expected_output = "Line 1\n\n\nLine 2\n\n\n\nLine 3"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)

		it("should preserve multiple line breaks from HTML", function()
			local input = "Line 1<br /><br /><br />Line 2<br /><br /><br /><br />Line 3"
			local expected_output = "Line 1\n\n\nLine 2\n\n\n\nLine 3"
			local result = markdown.from_html(input)
			assert.are.same(expected_output, result)
		end)
	end)
end)
