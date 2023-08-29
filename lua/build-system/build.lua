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

    -- vim.cmd("term") -- open terminal
    vim.cmd("term zsh -i") -- open terminal
    vim.cmd("norm G") -- scroll to bottom
    local channel_id = vim.b.terminal_job_id
    vim.cmd('wincmd p') -- go back to previous window

    return channel_id
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

        local command_to_run = "make " .. result

        if working_directory == nil then
            print("No working directory specified")
            return
        end

        local channel_id = M.create_output_buffer()
        M.send_commands_to_channel(channel_id, working_directory, command_to_run)
    end

    vim.ui.select(parsed_commands, {
        prompt = "Choose: ",
        on_format = on_format,
    }, on_user_choice)
end

M.send_commands_to_channel = function(channel_id, working_directory, command_to_run)
    vim.api.nvim_chan_send(channel_id, "cd " .. working_directory .. "\n")
    vim.api.nvim_chan_send(channel_id, command_to_run .. "\n")
    vim.api.nvim_chan_send(channel_id, "echo $SHELL\n")
end

return M

