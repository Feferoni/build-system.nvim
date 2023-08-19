local Dev = require("build-system.dev")
local log = Dev.log

Build_system_config = Build_system_config or {}

local M = {}

M.build_command = "make"
M.build_file_type = "Makefile"

M.buffer_layout = {
    size = 20,
    split = "belowright"
}

M.setup = function(opts)
    opts = opts or {}

    if opts.build_file_type then
        M.build_file_type = opts.build_file_type
    end

    if opts.build_command then
        M.build_command = opts.build_command
    end

    if opts.buffer_layout then
        M.buffer_layout = opts.buffer_layout
    end
end

return M
