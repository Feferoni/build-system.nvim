local path = require('plenary.path')
local bs_file = require("build-system.file")
local bs = require("build-system")
local Dev = require("build-system.dev")
local log = Dev.log

local M = {}

local get_targets = function(command_file_content, command_regex)
    local commands = {}
    for target in string.gmatch(command_file_content, command_regex) do
        table.insert(commands, target)
    end
    return commands
end

-- opts = {
    -- build_file_type = "", -- default: bs.build_file_type (Makefile)
    -- file_path = "", -- default: bs_file.find_build_file(opts)
    -- command_regex = "", -- default: "(%l-%S*):"
    -- get_commands_func = function(command_file_content, command_regex) -- default: get_targets
-- }
M.parse_command_file = function(opts)
    opts = opts or {}

    if opts.build_file_type == nil then
        opts.build_file_type = bs.build_file_type
    end

    if opts.file_path == nil then
        opts.file_path = bs_file.find_build_file(opts)
    end

    if opts.file_path == nil then
        print("Could not find build file.")
        return
    end

    if opts.command_regex == nil then
        opts.command_regex = "(%l-%S*):"
    end

    local file = io.open(opts.file_path, "r")
    if file == nil then
        print("Could not open file: " .. opts.file_path)
        return
    end

    local command_file_content = file:read("*a")

    local commands = {}
    if opts.get_commands_func then
        commands = opts.get_commands_func(command_file_content, opts.command_regex)
    else
        commands = get_targets(command_file_content, opts.command_regex)
    end

    return commands
end

M.create_output_buffer = function()
    local bufnr = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)

    if vim.fn.bufexists(bufnr) == 0 then
        print("Buffer does not exist")
        return
    end

    vim.cmd(string.format('%s split', bs.buffer_layout.split))
    vim.cmd(string.format('resize %d', bs.buffer_layout.size))

    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), bufnr)

    return bufnr
end

local set_cursor_to_end = function(bufnr)
    local current_win = vim.api.nvim_get_current_win()
    local current_line = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(current_win, { current_line, 0 })
end

M.print_to_buffer = function(bufnr, data)
    if vim.fn.bufexists(bufnr) == 0 then
        return
    end

    if data then
        for i = #data, 1, -1 do
            local line = data[i]
            if line ~= "" then
                vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { line })
            end
        end
    end

    set_cursor_to_end(bufnr)
end

M.exit_print = function(exit_code, bufnr)
    if vim.fn.bufexists(bufnr) == 0 then
        return
    end

    if exit_code ~= 0 then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "Job failed with exit code:" .. exit_code })
    else
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "Job completed successfully!" })
    end
    set_cursor_to_end(bufnr)
end

-- opts = {
    -- commands = {}, -- default: parsed commands from command file
    -- build_command = "", -- default: bs.build_command (make)
    -- ui_select = {
        -- promt = "", -- default: "Choose what to build: "
        -- kind = "", -- default: "build chooser"
        -- on_format = function(result) -- default: just returns target
        -- on_close = function() -- default: do nothing
        -- on_user_choice = function(result) -- default: run build command via jobstart and print to buffer
    -- } 
-- }
M.interactive_build = function(opts)
    opts = opts or {}

    if not opts.commands then
        local parsed_commands = M.parse_command_file(opts)
        if not parsed_commands or next(parsed_commands) == nil then
            print("No commands to select from after parsing command file")
            return
        end
        opts.commands = parsed_commands
    end

    if not opts.build_command then
        opts.build_command = bs.build_command
    end

    opts.ui_select = opts.ui_select or {}

    if opts.ui_select.promt == nil then
        opts.ui_select.promt = "Choose what to build: "
    end
    if opts.ui_select.kind == nil then
        opts.ui_select.kind = "build chooser"
    end
    if not opts.ui_select.on_format then
        opts.ui_select.on_format = function(result)
            return result
        end
    end
    if not opts.ui_select.on_close then
        opts.ui_select.on_close = function()
        end
    end

    if not opts.ui_select.on_user_choice then
        if bs_file.current_build_file == nil then
            print("No build file specified")
            return
        end
        local working_directory = tostring(path:new(bs_file.current_build_file):parent())

        opts.ui_select.on_user_choice = function(result)
            if result == nil then
                return
            end

            local command_to_run = M.build_command .. " " .. result
            print(command_to_run)

            if opts.working_directory == nil then
                print("No working directory specified")
                return
            end

            local bufnr = M.create_output_buffer()
            local _ = vim.fn.jobstart(command_to_run, {
                cwd = working_directory,
                on_stdout = function(_, data, _)
                    M.print_to_buffer(bufnr, data)
                end,
                on_stderr = function(_, data, _)
                    M.print_to_buffer(bufnr, data)
                end,
                on_exit = function(_, exit_code, _)
                    M.exit_print(exit_code, bufnr)
                end
            })
        end
    end

    vim.ui.select(opts.commands, {
        prompt = opts.ui_select.promt,
        kind = opts.ui_select.kind,
        on_format = opts.ui_select.on_format,
        on_close = opts.ui_select.on_close,
    }, opts.ui_select.on_user_choice)
end

return M
