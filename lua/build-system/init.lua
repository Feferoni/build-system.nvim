local Dev = require("build-system.dev")
local log = Dev.log

Build_system_config = Build_system_config or {}

local M = {}

M.build_command = "make"

-- opts.source_file - string to the file you want sourced, should be relative to the project root
-- opts.source_file_function(opts, file_path) - a function that customizes what should be done with the source_file
-- opts.remove_commands - a table with the command names that should be removed, ex:
-- { "command_name1", "command_name2", ..., "command_name_X" }
-- opts.build_file_type - a string with the name of the build file being looked for, Default: "Makefile"
-- opts.build_command - a string with the name of the build command to be used, Default: "make"
M.setup = function(opts)
    opts = opts or {}

    if opts.build_file_type then
        M.build_file_type = opts.build_file_type
    end

    if opts.remove_commands then
        M.remove_commands = opts.remove_commands
    end

    if opts.build_command then
        M.build_command = opts.build_command
    end

    if opts.interactive_build_function then
        M.interactive_build_function = opts.interactive_build_function
    end
end


return M
