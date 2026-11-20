describe("room save_attachment", function()
	local room
	local buf
	local dir
	local source
	local notifications
	local original_input
	local original_select
	--- The prompts shown by `vim.ui.select`
	local select_prompts
	--- The choice `vim.ui.select` answers with
	local select_choice

	--- Run `save_attachment` answering the destination prompt with `destination`
	--- @param destination string
	local function save_to(destination)
		vim.ui.input = function(_, callback)
			callback(destination)
		end
		room.save_attachment()
	end

	--- @param path string
	--- @return string
	local function read(path)
		return table.concat(vim.fn.readfile(path, "b"), "\n")
	end

	before_each(function()
		package.loaded["neoment.room"] = nil

		dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		source = dir .. "/source"
		vim.fn.writefile({ "attachment data" }, source, "b")

		notifications = {}
		select_prompts = {}
		select_choice = nil
		original_input = vim.ui.input
		original_select = vim.ui.select
		vim.ui.select = function(_, opts, callback)
			table.insert(select_prompts, opts.prompt)
			callback(select_choice)
		end

		package.loaded["neoment.matrix"] = { client = { homeserver = "https://example.org" } }
		package.loaded["neoment.storage"] = {
			fetch_to_temp = function(_, _, callback)
				callback(require("neoment.error").ok(source))
			end,
		}
		package.loaded["neoment.config"] = {
			get = function()
				return { room = {} }
			end,
		}
		package.loaded["neoment.notify"] = {
			info = function(message)
				table.insert(notifications, message)
			end,
			error = function(message)
				table.insert(notifications, message)
			end,
		}

		room = require("neoment.room")

		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "[file: report.txt]" })
		vim.api.nvim_win_set_cursor(0, { 1, 1 })
		room._get_buffer_data(buf).line_to_message[1] = {
			id = "$event",
			content = "report.txt",
			attachment = {
				type = "file",
				url = "https://example.org/_matrix/client/v1/media/download/example.org/report",
				filename = "report.txt",
			},
		}
	end)

	after_each(function()
		vim.ui.input = original_input
		vim.ui.select = original_select
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.delete(dir, "rf")
		package.loaded["neoment.room"] = nil
		package.loaded["neoment.matrix"] = nil
		package.loaded["neoment.storage"] = nil
		package.loaded["neoment.config"] = nil
		package.loaded["neoment.notify"] = nil
	end)

	it("saves the attachment when the destination file does not exist", function()
		local destination = dir .. "/new.txt"

		save_to(destination)

		assert.equals("attachment data", read(destination))
		assert.are.same({ "Attachment saved to " .. destination }, notifications)
		assert.are.same({}, select_prompts)
	end)

	it("saves into a directory using the attachment filename", function()
		local target = dir .. "/target"
		vim.fn.mkdir(target)

		save_to(target)

		assert.equals("attachment data", read(target .. "/report.txt"))
	end)

	it("overwrites an existing file when confirmed", function()
		local destination = dir .. "/existing.txt"
		vim.fn.writefile({ "old" }, destination, "b")
		select_choice = "Yes"

		save_to(destination)

		assert.are.same({ "File exists. Overwrite?" }, select_prompts)
		assert.equals("attachment data", read(destination))
	end)

	it("saves next to an existing file when overwriting is declined", function()
		local destination = dir .. "/existing.txt"
		vim.fn.writefile({ "old" }, destination, "b")
		select_choice = "No"

		save_to(destination)

		assert.equals("old", read(destination))
		assert.equals("attachment data", read(dir .. "/existing(1).txt"))
	end)

	it("saves next to an existing file that has no extension", function()
		local destination = dir .. "/existing"
		vim.fn.writefile({ "old" }, destination, "b")
		select_choice = "No"

		save_to(destination)

		assert.equals("old", read(destination))
		assert.equals("attachment data", read(dir .. "/existing(1)"))
	end)

	it("writes nothing when the overwrite prompt is dismissed", function()
		local destination = dir .. "/existing.txt"
		vim.fn.writefile({ "old" }, destination, "b")

		save_to(destination)

		assert.equals("old", read(destination))
		assert.are.same({}, notifications)
	end)
end)
