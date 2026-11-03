# workspaces.nvim

Multiple project workspaces in one Neovim instance (0.12+)

## Install (lazy.nvim)

```lua
{
  "SallimanR/workspaces.nvim",
  opts = {
    tabline = true,    -- show workspace names in the tabline
  },
  keys = {
    { "<leader>wn", "<cmd>Workspace new<cr>",     desc = "New workspace (detect root)" },
    { "<leader>ws", "<cmd>Workspace switch<cr>",  desc = "Switch workspace" },
    { "<leader>wb", "<cmd>Workspace buffers<cr>", desc = "Workspace buffers" },
    { "<leader>wc", "<cmd>Workspace close<cr>",   desc = "Close workspace" },
    { "]w", "<cmd>Workspace next<cr>", desc = "Next workspace" },
    { "[w", "<cmd>Workspace prev<cr>", desc = "Prev workspace" },
  },
}
```

## Options

```lua
{
	root_markers = {
		".git",
		"Makefile",
		"package.json",
		"Cargo.toml",
		"pyproject.toml",
		"go.mod",
		".luarc.json",
	},
	isolate_buffers = true,
	--- wipe buffers that belong only to a workspace when it is closed
	wipe_buffers_on_close = true,
	persist_on_exit = true,
	autoload_on_startup = false,
	tabline = false,
	--- called after a workspace is created: function(ws)
	on_open = nil,
}
```

## Commands
| Command | Description |
|---|---|
| `:Workspace` | pick a workspace |
| `:Workspace new [root] [name]` | create one (root defaults to the current buffer's project root, name to the dir name) |
| `:Workspace switch [name]` | switch (picker if no name) |
| `:Workspace next` / `prev` | cycle |
| `:Workspace close[!] [name]` | close; wipes buffers exclusive to it. `!` discards unsaved changes |
| `:Workspace rename [old] <new>` | rename |
| `:Workspace list` | print all |
| `:Workspace buffers` | pick among the current workspace's buffers |
| `:Workspace root` | print the active root |
| `:Workspace save` / `restore` | persist / restore (stored in `stdpath("state")/workspaces.json`) |

Command arguments are whitespace-split; for paths/names with spaces use the Lua API.
