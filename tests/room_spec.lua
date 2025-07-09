local assert = require("luassert.assert")
local mock = require("luassert.mock")
local spy = require("luassert.spy")
local busted = require("plenary.busted")
local describe = busted.describe
local before_each = busted.before_each
local it = busted.it

local room = require("neoment.room")

describe("Room", function()
	describe("update_buffer_lines_diff", function()
		it("should not update when lines are identical", function()
			local old_lines = { "line1", "line2", "line3" }
			local new_lines = { "line1", "line2", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.spy(set_lines_spy).was_not_called()
		end)

		it("should update only changed lines in the middle", function()
			local old_lines = { "line1", "line2", "line3", "line4" }
			local new_lines = { "line1", "changed", "modified", "line4" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 1, 3, false, { "changed", "modified" })
		end)

		it("should handle lines added at the end", function()
			local old_lines = { "line1", "line2" }
			local new_lines = { "line1", "line2", "line3", "line4" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 2, 2, false, { "line3", "line4" })
		end)

		it("should handle lines removed from the end", function()
			local old_lines = { "line1", "line2", "line3", "line4" }
			local new_lines = { "line1", "line2" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 2, 4, false, {})
		end)

		it("should handle lines added at the beginning", function()
			local old_lines = { "line2", "line3" }
			local new_lines = { "line1", "line2", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 0, false, { "line1" })
		end)

		it("should handle lines removed from the beginning", function()
			local old_lines = { "line1", "line2", "line3" }
			local new_lines = { "line2", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 1, false, {})
		end)

		it("should handle complete replacement", function()
			local old_lines = { "old1", "old2", "old3" }
			local new_lines = { "new1", "new2", "new3", "new4" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 3, false, { "new1", "new2", "new3", "new4" })
		end)

		it("should handle empty old buffer", function()
			local old_lines = {}
			local new_lines = { "line1", "line2", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 0, false, { "line1", "line2", "line3" })
		end)

		it("should handle empty new buffer", function()
			local old_lines = { "line1", "line2", "line3" }
			local new_lines = {}

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 3, false, {})
		end)

		it("should handle both buffers empty", function()
			local old_lines = {}
			local new_lines = {}

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_not_called()
		end)

		it("should handle single line change", function()
			local old_lines = { "line1", "old_line", "line3" }
			local new_lines = { "line1", "new_line", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 1, 2, false, { "new_line" })
		end)

		it("should optimize when changes are at the end with same prefix", function()
			local old_lines = { "same", "same", "old1", "old2" }
			local new_lines = { "same", "same", "new1", "new2", "new3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 2, 4, false, { "new1", "new2", "new3" })
		end)

		it("should optimize when changes are at the beginning with same suffix", function()
			local old_lines = { "old1", "old2", "same", "same" }
			local new_lines = { "new1", "new2", "new3", "same", "same" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 0, 2, false, { "new1", "new2", "new3" })
		end)

		it("should handle whitespace-only changes", function()
			local old_lines = { "line1", "  line2  ", "line3" }
			local new_lines = { "line1", " line2 ", "line3" }

			local set_lines_spy = spy.on(vim.api, "nvim_buf_set_lines")

			room._update_buffer_lines_diff(1, old_lines, new_lines)

			assert.stub(set_lines_spy).was_called_with(1, 1, 2, false, { " line2 " })
		end)
	end)
end)
