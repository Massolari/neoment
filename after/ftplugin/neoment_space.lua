local buffer_id = vim.api.nvim_get_current_buf()
local space_id = vim.b.space_id

-- Destroy completely the buffer when closing
vim.api.nvim_create_autocmd("BufDelete", {
	buffer = buffer_id,
	callback = function()
		vim.schedule(function()
			require("neoment.space").close(buffer_id)
		end)
	end,
})

local opts = { noremap = true, silent = true, buffer = buffer_id }
vim.keymap.set("n", "<CR>", function()
	require("neoment.space").open_room_under_cursor()
end, opts)
vim.keymap.set("n", "<localleader>f", function()
	require("neoment.rooms").pick()
end, vim.tbl_extend("error", opts, { desc = "[F]ind room" }))
vim.keymap.set("n", "<localleader>q", "<cmd>bdelete<CR>", vim.tbl_extend("error", opts, { desc = "[Q]uit room" }))
vim.keymap.set("n", "<localleader>l", function()
	require("neoment.rooms").toggle_room_list()
end, vim.tbl_extend("error", opts, { desc = "Toggle room [l]ist" }))
