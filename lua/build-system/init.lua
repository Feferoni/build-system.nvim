local M = {}

M.project_root = vim.fn.expand("#1:p")
M.build_file_type = "Makefile"
M.build_command = "make"
M.current_build_file = nil
M.remove_commands = {}
M.interactive_build_function = nil
-- parses a string formateted like "command_name : command1 command2"
M.build_file_regex_pattern = "([^\r\n\t]+):%s*(%S+.*)"

-- opts.source_file_function(opts, file_path) - a function that customizes what should be done with the source_file
local source_file = function(opts, file_path)
    opts = opts or {}

    if opts.source_file_function then
        opts.source_file_function(opts, file_path)
    else
        if vim.fn.filereadable(file_path) == 1 then
            local command = string.format(". %s > /dev/null && env", file_path)
            local output = vim.fn.systemlist(command)
            for _, line in ipairs(output) do
                local key, value = line:match("([^=\n]+)=([^\n]*)")
                if key and value then
                    vim.env[key] = value
                end
            end
            print("Sourcing file: " .. file_path)
        else
            print("Build-system: can't locate setup_source_file_path: " .. file_path)
        end
    end
end

-- opts.source_file - string to the file you want sourced, should be relative to the project root
-- opts.source_file_function(opts, file_path) - a function that customizes what should be done with the source_file
-- opts.remove_commands - a table with the command names that should be removed, ex:
-- { "command_name1", "command_name2", ..., "command_name_X" }
-- opts.build_file_type - a string with the name of the build file being looked for, Default: "Makefile"
-- opts.build_command - a string with the name of the build command to be used, Default: "make"
M.setup = function(opts)
    opts = opts or {}

    if opts.setup_source_file_path then
        local source_path = M.project_root .. opts.setup_source_file_path
        source_file(opts, source_path)
    end

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


M.find_build_file = function(opts)
    local plenary_sd = require('plenary.scandir')
    local plenary_path = require('plenary.path')

    opts = opts or {}
    opts.search_pattern = M.build_file_type
    local project_root = plenary_path:new(M.project_root)
    local current_folder = plenary_path:new(vim.fn.expand("%:p:h"))
    local files = {}

    local reached_root = false;
    while not reached_root and next(files) == nil do
        if tostring(current_folder) == tostring(project_root) then
            reached_root = true
        end

        files = plenary_sd.scan_dir(tostring(current_folder), opts)
        current_folder = current_folder:parent()
    end

    if next(files) == nil then
        print("Could not locate any build files.")
        M.current_build_file = nil
        return nil
    else
        if #files > 1 then
            local on_user_choice = function(action)
                if not action then
                    return
                end

                M.current_build_file = action
                print("\nChoose build file: " .. action)
            end
            print("Found multiple build files.")
            vim.ui.select(files, {
                prompt = 'Choose a build file:',
                kind = 'build file choosing',
                format_item = function(item)
                    return item
                end,
            }, on_user_choice)
        else
            print("Found build file: " .. files[1])
            M.current_build_file = files[1]
        end

        return M.current_build_file
    end
end

local clean_whitespaces = function(line)
    line = line:gsub("\t", " ")
    line = line:gsub("%s+", " ")
    line = line:match("^%s*(.-)%s*$")
    return line
end

local get_filtered_command_string = function(opts, command_string)
    local final_command_string = ""
    for sub_command in command_string:gmatch("%S+") do
        if opts.replace_commands and opts.replace_commands[sub_command] then
            sub_command = opts.replace_commands[sub_command]
        end
        final_command_string = final_command_string .. " " .. sub_command
    end
    return final_command_string
end

local is_build_file_valid = function(opts)
    if M.current_build_file then
        return true
    end
    if vim.fn.filereadable(M.current_build_file) == 1 then
        return true
    end

    M.find_build_file(opts)

    if M.current_build_file == nil or not vim.fn.filereadable(M.current_build_file) == 1 then
        print("Could not find build file.")
        return false
    end

    return true
end

-- opts.command_file_filter_function(lines) - function that takes the lines and filters the lines before regex is being run on them
-- lines - a string with the content of the command file
-- opts.replace_commands: a table with key = sub_command that you want to replace, value what you want to replace the sub_command with
-- opts.add_commands: a table with the key = command that you want to add to, value = sub_commands you want to increase with
-- / char in the command line instructs the function to count the next row as a continuation of the command on the next line
M.parse_command_file = function(opts)
    opts = opts or {}

    if not is_build_file_valid(opts) then
        return
    end

    local file = io.open(M.current_build_file, "r")
    if file == nil then
        print("Could not open file: " .. M.current_build_file)
        return
    end

    local lines = file:read("*a")

    if opts.command_file_filter_function then
        lines = opts.command_file_filter_function(lines)
    end

    local parse_line = function(line)
        local command, command_string, _ = line:match(M.build_file_regex_pattern)
        if command and command_string then
            command = command:gsub("%s", "")
            return command, command_string
        else
            return nil, nil
        end
    end

    local result = {}
    local prevCommand = nil
    for line in lines:gmatch("[^\r\n]+") do
        line = clean_whitespaces(line)
        local stripped_line, command_continuation = line:match("([^\r\n]-)(/)")
        if stripped_line and command_continuation then
            if prevCommand then
                result[prevCommand] = clean_whitespaces(result[prevCommand] .. " " .. stripped_line)
            else
                local command, command_string = parse_line(stripped_line)
                if command and command_string then
                    result[command] = command_string
                    prevCommand = command
                end
            end
        else
            if prevCommand then
                result[prevCommand] = clean_whitespaces(result[prevCommand] .. " " .. line)
            else
                local command, command_string = parse_line(line)
                if command and command_string then
                    result[command] = command_string
                end
            end
            prevCommand = nil
        end
    end

    for _, removed_command in pairs(M.remove_commands) do
        for command, _ in pairs(result) do
            if removed_command == command then
                result[command] = nil
                break
            end
        end
    end

    local final_result = {}
    local i = 1;

    for command, command_string in pairs(result) do
        if opts.add_commands and opts.add_commands[command] then
            local modified_command = {}
            modified_command[command .. "_modified"] = get_filtered_command_string(opts,
                command_string .. " " .. opts.add_commands[command])
            final_result[i] = modified_command
            i = i + 1
            opts.add_commands[command] = nil
        end
        local final_command = {}
        final_command[command] = get_filtered_command_string(opts, command_string)
        final_result[i] = final_command
        i = i + 1
    end

    if opts.add_commands then
        for command, command_string in pairs(opts.add_commands) do
            local final_command = {}
            final_command[command] = get_filtered_command_string(opts, command_string)
            final_result[i] = final_command
            i = i + 1
        end
    end

    return final_result
end

M.create_output_buffer = function()
    -- Create a new buffer that's not listed
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Set up the buffer to be a scratch buffer
    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)

    -- Create a new horizontal split and set the newly created buffer to the active window
    vim.cmd('belowright split')
    vim.cmd('resize 10')
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), bufnr)

    -- Delete the default empty line from the new buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})

    return bufnr
end

M.print_to_buffer = function(bufnr, data, first_line)
    if data then
        for _, line in ipairs(data) do
            if line ~= "" then
                if first_line then
                    -- Remove the initial empty line and set the flag to false
                    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { line })
                    first_line = false
                else
                    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { line })
                end
            end
        end
    end
    return first_line
end

-- M.interactive_build_function decides what to do with the build command, if both this and option is passed, the option is used
-- opts.interactive_build_function decides what to do with the build command, format for result_table passed to it:
--  {                                                                                                                                                                                                                                                                                                                                                                                           command4 = " clang++"                                                                                                                                                                                                                                                                                                                                                                   }                                                                                                                                                                                                                                                                                                                                                                                         {                                                                                                                                                                                                                                                                                                                                                                                           command5 = " clang++ clangcommand3"                                                                                                                                                                                                                                                                                                                                                     }
--      command_name = " command1 command2 command3"
--  }
M.interactive_build = function(opts)
    opts = opts or {}

    local commands = M.parse_command_file(opts)
    if not commands or next(commands) == nil then
        print("No commands to select from after parsing command file: " .. M.current_build_file)
        return
    end

    local on_user_choice = function(result_table)
        if not result_table or next(result_table) == nil then
            return
        end
        local command, _ = next(result_table)
        local bash_command = M.build_command .. " " .. command
        local bufnr = M.create_output_buffer()
        local working_directory = tostring(require('plenary.path'):new(M.current_build_file):parent())

        local first_line = true
        local _ = vim.fn.jobstart(bash_command, {
            cwd = working_directory,
            on_stdout = function(_, data, _)
                first_line = M.print_to_buffer(bufnr, data, first_line)
            end,
            on_stderr = function(_, data, _)
                first_line = M.print_to_buffer(bufnr, data, first_line)
            end,
            on_exit = function(_, exit_code, _)
                if exit_code ~= 0 then
                    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "Job failed with exit code:" .. exit_code })
                else
                    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "Job completed successfully!" })
                end
            end,
        })
    end

    if M.interactive_build_function then
        on_user_choice = M.interactive_build_function
    end

    if opts.interactive_build_function then
        on_user_choice = opts.interactive_build_function
    end

    vim.ui.select(commands, {
        prompt = 'Choose what to build: ',
        kind = 'build chooser',
        format_item = function(result_table)
            local command, command_string = next(result_table)
            return command .. " : " .. command_string
        end,
    }, on_user_choice)
end

return M
