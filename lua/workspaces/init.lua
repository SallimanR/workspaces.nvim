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
local syncing = false -- guards our own 'buflisted' changes from re-triggering autocmds
local did_setup = false

-----------------------------------------------
-- Helpers
-----------------------------------------------

local function fire(event, ws)
	api.nvim_exec_autocmds("User", {
		pattern = event,
		modeline = false,
		data = { name = ws.name, root = ws.root, tab = ws.tab },
	})
end

local function is_file_buf(buf)
	return api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" and api.nvim_buf_get_name(buf) ~= ""
end

local function prune()
	for i = #list, 1, -1 do
		if not api.nvim_tabpage_is_valid(list[i].tab) then
			local ws = table.remove(list, i)
			fire("WorkspaceClosed", ws)
		end
	end
end

--- Make 'buflisted' reflect ownership so :ls/:bnext only show the active workspace.
---@param ws workspaces.Workspace?
local function sync_listing(ws)
	if not M.config.isolate_buffers then
		return
	end
	local owned = {}
	for _, w in ipairs(list) do
		for b in pairs(w.bufs) do
			owned[b] = true
		end
	end
	syncing = true
	for _, b in ipairs(api.nvim_list_bufs()) do
		if is_file_buf(b) and owned[b] then
			local show = ws == nil or ws.bufs[b] == true
			if vim.bo[b].buflisted ~= show then
				vim.bo[b].buflisted = show
			end
		end
	end
	syncing = false
end

local function claim(buf)
	local ws = M.current()
	if not ws or not is_file_buf(buf) then
		return
	end
	ws.bufs[buf] = true
	ws.last_file = api.nvim_buf_get_name(buf)
	if M.config.isolate_buffers and not vim.bo[buf].buflisted then
		syncing = true
		vim.bo[buf].buflisted = true
		syncing = false
	end
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

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function M.setup_once()
	if not did_setup then
		M.setup()
	end
end

---@param opts workspaces.Config?
function M.setup(opts)
	did_setup = true
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	local group = api.nvim_create_augroup("workspaces", { clear = true })
	local function au(event, cb)
		api.nvim_create_autocmd(event, { group = group, callback = cb })
	end

	au("TabClosed", prune)

	au("TabEnter", function()
		local ws = M.current()
		sync_listing(ws)
		if ws then
			fire("WorkspaceSwitched", ws)
		end
	end)

	au({ "BufAdd", "BufEnter" }, function(a)
		if not syncing then
			claim(a.buf)
		end
	end)

	au({ "BufDelete", "BufWipeout" }, function(a)
		if syncing then
			return
		end
		for _, ws in ipairs(list) do
			ws.bufs[a.buf] = nil
		end
	end)

	if M.config.tabline then
		vim.o.showtabline = 2
		vim.o.tabline = "%!v:lua.require'workspaces'.tabline()"
	end
end

return M
