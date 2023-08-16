local path = require('plenary.path')
local bs_file = require("build-system.file")
local Dev = require("build-system.dev")
local log = Dev.log

local M = {}

M.build_command = "make"

local get_targets = function(command_file_content)
    local commands = {}
    for target in string.gmatch(command_file_content, "(%l-%S*):") do
        table.insert(commands, target)
    end
    return commands
end

M.parse_command_file = function(opts)
    opts = opts or {}

    local file_path = bs_file.find_build_file(opts)
    if file_path == nil then
        print("Could not find build file.")
        return
    end

    local file = io.open(file_path, "r")
    if file == nil then
        print("Could not open file: " .. file_path)
        return
    end

    local command_file_content = file:read("*a")

    local commands = {}
    if opts.get_commands_func then
        commands = opts.get_commands_func(command_file_content)
    else
        commands = get_targets(command_file_content)
    end

    return commands
end

M.create_output_buffer = function()
    local bufnr = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)

    return bufnr
end

M.use_output_buffer = function(bufnr)
    if vim.fn.bufexists(bufnr) == 0 then
        print("Buffer does not exist")
        return
    end

    vim.cmd('belowright split')
    -- TODO: make the size a option
    vim.cmd('resize 15')
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), bufnr)

    -- Delete the default empty line from the new buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})
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
        opts.build_command = M.build_command
    end

    local bufnr = M.create_output_buffer()

    if not opts.user_choice_stdout then
        opts.user_choice_stdout = function(_, data, _)
            M.print_to_buffer(bufnr, data)
        end
    end

    if not opts.user_choice_stderr then
        opts.user_choice_stderr = function(_, data, _)
            M.print_to_buffer(bufnr, data)
        end
    end

    if not opts.user_choice_exit then
        opts.user_choice_exit = function(_, exit_code, _)
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
    end

    if not opts.working_directory then
        if bs_file.current_build_file == nil then
            print("No build file specified")
            return
        end
        opts.working_directory = tostring(path:new(bs_file.current_build_file):parent())
    end

    if not opts.on_user_choice then
        opts.on_user_choice = function(result)
            if result == nil then
                return
            end

            local command_to_run = M.build_command .. " " .. result
            print(command_to_run)

            if opts.working_directory == nil then
                if vim.fn.bufexists(bufnr) == 1 then
                    vim.api.nvim_del_buf(bufnr, {})
                end
                print("No working directory specified")
                return
            end
            M.use_output_buffer(bufnr)
            local _ = vim.fn.jobstart(command_to_run, {
                cwd = opts.working_directory,
                on_stdout = opts.user_choice_stdout,
                on_stderr = opts.user_choice_stderr,
                on_exit = opts.user_choice_exit,
            })
        end
    end


    if not opts.ui_select_format then
        opts.ui_select_format = function(result)
            return result
        end
    end

    if not opts.ui_on_close then
        opts.ui_on_close = function()
        end
    end

    vim.ui.select(opts.commands, {
        prompt = 'Choose what to build: ',
        kind = 'build chooser',
        on_format = opts.ui_select_format,
        on_close = opts.ui_on_close,
    }, opts.on_user_choice)
end

return M
