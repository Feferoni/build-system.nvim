local path = require('plenary.path')
local bs_file = require("build-system.file")
local bs = require("build-system")

local M = {}

M.parse_make_file = function(file_path)
    file_path = file_path or bs_file.find_build_file("Makefile")

    if not file_path or file_path == nil then
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
    local command_regex = "(%l-%S*):"
    for target in string.gmatch(command_file_content, command_regex) do
        if target ~= "" and target ~= ".PHONY" then
            table.insert(commands, target)
        end
    end
    return commands
end

local set_cursor_to_end = function(bufnr)
    local current_win = vim.api.nvim_get_current_win()
    local current_line = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(current_win, { current_line, 0 })
end

local write_to_buf = function(bufnr, text, should_cursor_move)
    if vim.fn.bufexists(bufnr) == 0 then
        return
    end

    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { text })

    if should_cursor_move then
        set_cursor_to_end(bufnr)
    end
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
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false,
        { "-- build system buffer --" })

    return bufnr
end

M.print_to_buffer = function(bufnr, data)
    if not data then
        return
    end

    for i = #data, 1, -1 do
        local line = data[i]
        if line ~= "" then
            write_to_buf(bufnr, line, true)
        end
    end
end

M.exit_print = function(exit_code, bufnr, command)
    local output = "Job finish: \"" .. command .. "\""

    if exit_code ~= 0 then
        output = output .. " failed with exit code: " .. exit_code
    else
        output = output .. " completed sucessfully!"
    end

    write_to_buf(bufnr, output, true)
end

M.interactive_make_build = function()
    local parsed_commands = M.parse_make_file()
    if not parsed_commands or next(parsed_commands) == nil then
        print("No commands to select from after parsing command file")
        return
    end

    local on_format = function(result)
        return result
    end

    if bs_file.last_used_build_file == nil then
        print("No build file specified")
        return
    end
    local working_directory = tostring(path:new(bs_file.last_used_build_file):parent())

    local on_user_choice = function(result)
        if result == nil then
            return
        end

        print(result)

        local command_to_run = "make " .. result

        if working_directory == nil then
            print("No working directory specified")
            return
        end

        local bufnr = M.create_output_buffer()
        M.jobstart(bufnr, command_to_run, working_directory)
    end

    vim.ui.select(parsed_commands, {
        prompt = "Choose: ",
        on_format = on_format,
    }, on_user_choice)
end

M.jobstart = function(bufnr, command_to_run, working_directory)
    write_to_buf(bufnr, "Job start: \"" .. command_to_run .. "\"", true)
    local _ = vim.fn.jobstart(command_to_run, {
        cwd = working_directory,
        on_stdout = function(_, data, _)
            M.print_to_buffer(bufnr, data)
        end,
        on_stderr = function(_, data, _)
            M.print_to_buffer(bufnr, data)
        end,
        on_exit = function(_, exit_code, _)
            M.exit_print(exit_code, bufnr, command_to_run)
        end
    })
end

return M
