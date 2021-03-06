local Cache = {}

function Cache:clean()
	self.lazy_load_paths = {}
	self.ft_paths = {}
	self.path_snippets = {}
	-- We do not clean lazy_loaded_ft!!
	--
	-- It is preserved to accomodate a workflow where the luasnip-config
	-- begins with `ls.cleanup()`, which should make it completely reloadable.
	-- This would not be the case if lazy_loaded_ft was cleaned:
	-- the autocommands for loading lazy_load-snippets will not necessarily be
	-- triggered before the next expansion occurs, at which point the snippets
	-- should be available (but won't be, because the actual load wasn't
	-- triggered).
	-- As the list is not cleaned, the snippets will be loaded when
	-- `lazy_load()` is called (where a check for already-loaded filetypes is
	-- done explicitly).
end

local function new_cache()
	-- returns the table the metatable was set on.
	return setmetatable({
		-- maps ft to list of files. Each file provides snippets for the given
		-- filetype.
		-- In snipmate:
		-- {
		--	lua = {"~/snippets/lua.snippets"},
		--	c = {"~/snippets/c.snippets", "/othersnippets/c.snippets"}
		-- }
		lazy_load_paths = {},

		-- ft -> {true, nil}.
		-- Keep track of which filetypes were already lazy_loaded to prevent
		-- duplicates.
		lazy_loaded_ft = {},

		-- key is file type, value are paths of .snippets files.
		ft_paths = {},

		path_snippets = {}, -- key is file path, value are parsed snippets in it.
	}, {
		__index = Cache,
	})
end

local M = {
	vscode = new_cache(),
	snipmate = new_cache(),
	lua = new_cache(),
}

function M.cleanup()
	M.vscode:clean()
	M.snipmate:clean()
	M.lua:clean()
end

return M
