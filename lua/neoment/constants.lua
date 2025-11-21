local M = {}

M.MENTION_REGEX = "(@[a-zA-Z0-9_-]+:[^%s]+)"

M.ns_id = vim.api.nvim_create_namespace("neoment_highlight")

return M
