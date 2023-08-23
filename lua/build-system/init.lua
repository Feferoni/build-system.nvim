local Dev = require("build-system.dev")
local log = Dev.log

Build_system_config = Build_system_config or {}

local M = {}

M.buffer_layout = {
    size = 20,
    split = "belowright"
}

M.setup = function(opts)
    opts = opts or {}

    if opts.buffer_layout then
        M.buffer_layout = opts.buffer_layout
    end
end

return M
