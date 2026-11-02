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

local function notify(msg, level)
	vim.notify("[workspaces] " .. msg, level or vim.log.levels.INFO)
end

local function normalize(path)
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

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

local function tab_is_pristine(tab)
	local wins = api.nvim_tabpage_list_wins(tab)
	if #wins ~= 1 then
		return false
	end
	local b = api.nvim_win_get_buf(wins[1])
	return api.nvim_buf_get_name(b) == ""
		and vim.bo[b].buftype == ""
		and not vim.bo[b].modified
		and api.nvim_buf_line_count(b) == 1
		and api.nvim_buf_get_lines(b, 0, -1, false)[1] == ""
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

-----------------------------------------------
-- Actions
-----------------------------------------------

---@class workspaces.NewOpts
---@field root string?   defaults to the project root of the current buffer (or cwd)
---@field name string?   defaults to the root's directory name

---@param opts workspaces.NewOpts?
---@return workspaces.Workspace?
function M.new(opts)
	M.setup_once()
	opts = opts or {}
	local root = normalize(opts.root or M.detect_root())
	if vim.fn.isdirectory(root) == 0 then
		notify("not a directory: " .. root, vim.log.levels.ERROR)
		return
	end

	local name = opts.name
	if name then
		if M.find(name) then
			notify(("workspace '%s' already exists"):format(name), vim.log.levels.ERROR)
			return
		end
	else
		local base = vim.fs.basename(root)
		if base == "" then
			base = "root"
		end
		name = base
		local i = 2
		while M.find(name) do
			name = ("%s-%d"):format(base, i)
			i = i + 1
		end
	end

	-- reuse the startup tab if it is still an empty scratch tab
	local cur = api.nvim_get_current_tabpage()
	if not (#list == 0 and not M.current(cur) and tab_is_pristine(cur)) then
		vim.cmd.tabnew()
	end
	local tab = api.nvim_get_current_tabpage()
	vim.cmd.tcd({ args = { root }, magic = { file = false } })

	---@type workspaces.Workspace
	local ws = { name = name, root = root, tab = tab, bufs = {} }
	list[#list + 1] = ws
	api.nvim_tabpage_set_var(tab, "workspace", name)
	sync_listing(ws)

	fire("WorkspaceOpened", ws)
	if M.config.on_open then
		M.config.on_open(ws)
	end
	return ws
end

---@param target string|workspaces.Workspace
function M.switch(target)
	local ws = type(target) == "table" and target or M.find(target)
	if not ws or not api.nvim_tabpage_is_valid(ws.tab) then
		notify(("no workspace '%s'"):format(tostring(target)), vim.log.levels.WARN)
		return
	end
	api.nvim_set_current_tabpage(ws.tab)
end

---@param step integer  1 = next, -1 = previous
function M.cycle(step)
	if #list == 0 then
		return
	end
	local cur, idx = M.current(), 0
	for i, ws in ipairs(list) do
		if ws == cur then
			idx = i
		end
	end
	local n
	if idx == 0 then
		n = step > 0 and 1 or #list
	else
		n = ((idx - 1 + step) % #list) + 1
	end
	M.switch(list[n])
end

---@param old string
---@param new string
function M.rename(old, new)
	local ws = M.find(old)
	if not ws then
		return notify(("no workspace '%s'"):format(old), vim.log.levels.WARN)
	end
	if M.find(new) then
		return notify(("workspace '%s' already exists"):format(new), vim.log.levels.ERROR)
	end
	ws.name = new
	api.nvim_tabpage_set_var(ws.tab, "workspace", new)
	vim.cmd.redrawtabline()
end

---@class workspaces.CloseOpts
---@field force boolean?  discard unsaved changes
---@field wipe boolean?   wipe the workspace's exclusive buffers (default: config.wipe_on_close)

---@param name string?  defaults to the current workspace
---@param opts workspaces.CloseOpts?
---@return boolean
function M.close(name, opts)
	opts = opts or {}
	local ws = name and M.find(name) or M.current()
	if not ws then
		notify("no such workspace", vim.log.levels.WARN)
		return false
	end
	local wipe = opts.wipe
	if wipe == nil then
		wipe = M.config.wipe_buffers_on_close
	end

	-- buffers that only this workspace uses
	local shared = {}
	for _, o in ipairs(list) do
		if o ~= ws then
			for b in pairs(o.bufs) do
				shared[b] = true
			end
		end
	end
	local doomed = {}
	if wipe then
		local dirty = {}
		for _, b in ipairs(M.buffers(ws)) do
			if not shared[b] then
				doomed[#doomed + 1] = b
				if vim.bo[b].modified then
					dirty[#dirty + 1] = vim.fn.fnamemodify(api.nvim_buf_get_name(b), ":~:.")
				end
			end
		end
		if #dirty > 0 and not opts.force then
			notify("unsaved changes in: " .. table.concat(dirty, ", ") .. " (use ! to discard)", vim.log.levels.ERROR)
			return false
		end
	end

	for i, w in ipairs(list) do
		if w == ws then
			table.remove(list, i)
			break
		end
	end

	if #api.nvim_list_tabpages() == 1 then
		vim.cmd.tabnew() -- never close the last tab; leave a plain scratch tab behind
	end
	vim.cmd.tabclose({ args = { tostring(api.nvim_tabpage_get_number(ws.tab)) }, bang = true })

	syncing = true
	for _, b in ipairs(doomed) do
		pcall(api.nvim_buf_delete, b, { force = true })
	end
	syncing = false

	sync_listing(M.current())
	fire("WorkspaceClosed", ws)
	return true
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

--- For statuslines: `%{%v:lua.require'workspaces'.statusline()%}`
---@return string
function M.statusline()
	local ws = M.current()
	return ws and ("[" .. ws.name .. "]") or ""
end

--- Tabline that labels tabs with their workspace name.
---@return string
function M.tabline()
	local parts, cur = {}, api.nvim_get_current_tabpage()
	for i, tab in ipairs(api.nvim_list_tabpages()) do
		local ws = M.current(tab)
		local label = ws and ws.name or ("tab " .. i)
		parts[#parts + 1] = ("%s%%%dT %s %%T"):format(
			tab == cur and "%#TabLineSel#" or "%#TabLine#",
			i,
			(label:gsub("%%", "%%%%"))
		)
	end
	return table.concat(parts) .. "%#TabLineFill#"
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
