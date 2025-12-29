-- .luacheckrc for send-to-tmux.nvim
-- Configure luacheck for Neovim plugin development

-- Global variables available in Neovim
globals = {
    "vim",           -- Neovim global API
    "jit",           -- LuaJIT
    "bit",           -- LuaJIT bit operations
    "package",       -- Lua package system
    "string",        -- Lua string library
    "table",         -- Lua table library
    "math",          -- Lua math library
    "io",            -- Lua io library
    "os",            -- Lua os library
    "debug",         -- Lua debug library
    "coroutine",     -- Lua coroutine library
    "utf8",          -- Lua utf8 library (Neovim)
}

-- Standard Lua libraries
std = "lua54"

-- Allow unused arguments in function definitions
unused_args = false

-- Allow unused second return values
unused_secondaries = false

-- Line length limit
max_line_length = 120

-- Ignore specific warnings
ignore = {
    "611", -- line contains only whitespace
    "612", -- line contains a trailing whitespace
    "613", -- trailing whitespace in a string
    "614", -- trailing whitespace in a comment
    "621", -- line is too long
}

-- Files to check
files = {
    "lua/**/*.lua",
    "plugin/**/*.lua",
}

-- Exclude patterns
exclude_files = {
    "tests/**/*.lua",
}