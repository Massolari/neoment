--- Load a module from a git repository.
--- @param module string
--- @param source string
local function load_module(module, source)
	local module_dir = vim.fs.joinpath(vim.uv.os_tmpdir(), module)
	local directory_exists = vim.fn.isdirectory(module_dir)

	if directory_exists == 0 then
		vim.fn.system({ "git", "clone", source, module_dir })
	end

	vim.opt.rtp:append(module_dir)
end

load_module("plenary.nvim", "https://github.com/nvim-lua/plenary.nvim")
vim.opt.rtp:append(".")
vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
