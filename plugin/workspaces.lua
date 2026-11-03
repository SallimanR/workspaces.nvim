if vim.g.loaded_workspaces then
	return
end
vim.g.loaded_workspaces = true

if vim.fn.has("nvim-0.12") == 0 then
	vim.notify("workspaces.nvim requires Neovim 0.12+", vim.log.levels.ERROR)
	return
end

local function W()
	local m = require("workspaces")
	m.setup_once()
	return m
end

---@type table<string, fun(args: string[], bang: boolean)>
local subcommands = {
	new = function(a)
		W().new({ root = a[1], name = a[2] })
	end,
	switch = function(a)
		if a[1] then
			W().switch(a[1])
		else
			W().select()
		end
	end,
	next = function()
		W().cycle(1)
	end,
	prev = function()
		W().cycle(-1)
	end,
	close = function(a, bang)
		W().close(a[1], { force = bang })
	end,
	rename = function(a)
		local m = W()
		if #a == 1 then
			local cur = m.current()
			if cur then
				m.rename(cur.name, a[1])
			end
		elseif #a == 2 then
			m.rename(a[1], a[2])
		else
			vim.notify("usage: :Workspace rename [old] <new>", vim.log.levels.WARN)
		end
	end,
	list = function()
		local m = W()
		local chunks = {}
		for _, ws in ipairs(m.list()) do
			local mark = ws == m.current() and "* " or "  "
			chunks[#chunks + 1] = {
				("%s%s  %s  (%d buffers)\n"):format(mark, ws.name, vim.fn.fnamemodify(ws.root, ":~"), #m.buffers(ws)),
			}
		end
		if #chunks == 0 then
			chunks[1] = { "no workspaces\n" }
		end
		vim.api.nvim_echo(chunks, false, {})
	end,
	buffers = function()
		W().select_buffer()
	end,
	root = function()
		print(W().root())
	end,
	save = function()
		require("workspaces.persistent_store").save(W())
	end,
	restore = function()
		require("workspaces.persistent_store").restore(W())
	end,
}

local names = vim.tbl_keys(subcommands)
table.sort(names)

vim.api.nvim_create_user_command("Workspace", function(o)
	if #o.fargs == 0 then
		return W().select()
	end
	local sub = subcommands[o.fargs[1]]
	if sub == nil and o.fargs[1] == "add" then
		sub = subcommands.new
	end
	if not sub then
		return vim.notify("[workspaces] unknown subcommand: " .. o.fargs[1], vim.log.levels.ERROR)
	end
	sub(vim.list_slice(o.fargs, 2), o.bang)
end, {
	nargs = "*",
	bang = true,
	desc = "Manage workspaces (new/switch/next/prev/close/rename/list/buffers/root/save/restore)",
	complete = function(arglead, cmdline)
		local args = vim.split(cmdline, "%s+")
		if #args <= 2 then
			return vim.tbl_filter(function(n)
				return vim.startswith(n, arglead)
			end, names)
		end
		local sub = args[2]
		if sub == "new" or sub == "add" then
			if #args == 3 then
				return vim.fn.getcompletion(arglead, "dir")
			end
		elseif sub == "switch" or sub == "close" or sub == "rename" then
			if #args == 3 then
				local res = {}
				for _, ws in ipairs(require("workspaces").list()) do
					if vim.startswith(ws.name, arglead) then
						res[#res + 1] = ws.name
					end
				end
				return res
			end
		end
		return {}
	end,
})
