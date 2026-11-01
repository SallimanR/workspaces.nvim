local api = vim.api

local M = {}

---@class workspaces.Workspace
---@field name string
---@field root string
---@field tab integer
---@field bufs table<integer, true>
---@field last_file string?
---
---@class workspaces.Config
M.config = {
	root_markers = {
		".git",
		"Makefile",
		"package.json",
		"Cargo.toml",
		"pyproject.toml",
		"go.mod",
		".luarc.json",
	},
	--- only show the active workspace's buffers in :ls / :bnext / bufferline plugins
	isolate_buffers = true,
	--- wipe buffers that belong only to a workspace when it is closed
	wipe_buffers_on_close = true,
	persist_on_exit = true,
	autoload_on_startup = false,
	--- replace 'tabline' with one that shows workspace names
	tabline = false,
	--- called after a workspace is created: function(ws)
	on_open = nil,
}
