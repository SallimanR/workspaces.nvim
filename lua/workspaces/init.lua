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

local list = {}

-----------------------------------------------
-- Helpers
-----------------------------------------------

local function is_file_buf(buf)
	return api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and api.nvim_buf_get_name(buf) ~= ""
end

-----------------------------------------------
-- Queries
-----------------------------------------------

---@return workspaces.Workspace[]
function M.list()
	return vim.list_slice(list)
end

---@param name string
---@return workspaces.Workspace?
function M.find(name)
	for _, ws in ipairs(list) do
		if ws.name == name then
			return ws
		end
	end
end

---@param tab integer?
---@return workspaces.Workspace?
function M.current(tab)
	tab = tab or api.nvim_get_current_tabpage()
	for _, ws in ipairs(list) do
		if ws.tab == tab then
			return ws
		end
	end
end

---@return string
function M.root()
	local ws = M.current()
	return ws and ws.root or vim.fn.getcwd()
end

--- Sorted list of valid file buffers owned by a workspace.
---@param ws workspaces.Workspace?
---@return integer[]
function M.buffers(ws)
	ws = ws or M.current()
	if not ws then
		return {}
	end
	local res = {}
	for b in pairs(ws.bufs) do
		if is_file_buf(b) then
			res[#res + 1] = b
		end
	end
	table.sort(res)
	return res
end

---@return string
function M.detect_root()
	local root = vim.fs.root(0, M.config.root_markers)
	return root or vim.fn.getcwd()
end
