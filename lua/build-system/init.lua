local M = {}

M.root_dir = vim.fn.expand("#1:p")
M.build_file_type = "Makefile"
M.current_build_file = "/home/feferoni/tmp/source/test/test/bin/Makefile"
M.remove_commands = {}
-- parses a string formateted like "command_name : command1 command2"
M.build_file_regex_pattern = "([^\r\n\t]+):%s*(%S+.*)"

local source_file = function(file_path)
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

M.setup = function(opts)
    opts = opts or {}

    if opts.setup_source_file_path then
        local source_path = M.root_dir .. opts.setup_source_file_path
        source_file(source_path)
    end

    if opts.build_file_type then
        M.build_file_type = opts.build_file_type
    end

    if opts.remove_commands then
        M.remove_commands = opts.remove_commands
    end
end


M.find_build_file = function(opts)
    local plenary_sd = require('plenary.scandir')
    local plenary_path = require('plenary.path')

    opts = opts or {}
    opts.search_pattern = M.build_file_type
    local root_dir = plenary_path:new(M.root_dir)
    local current_folder = plenary_path:new(vim.fn.expand("%:p:h"))
    local files = {}

    local reached_root = false;
    while not reached_root and next(files) == nil do
        if tostring(current_folder) == tostring(root_dir) then
            reached_root = true
        end

        files = plenary_sd.scan_dir(tostring(current_folder), opts)
        current_folder = current_folder:parent()
    end

    if next(files) == nil then
        print("Could not locate any build files.")
        return ""
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

-- opts.command_file_filter_function: function that takes the lines and filters the lines before regex is being run on them
-- opts.replace_commands: a table with key = sub_command that you want to replace, value what you want to replace the sub_command with
-- opts.add_commands: a table with the key = command that you want to add to, value = sub_commands you want to increase with
-- / char in the command line instructs the function to count the next row as a continuation of the command on the next line
M.parse_command_file = function(opts)
    if not M.current_build_file then
        print("No build file set")
        return
    end

    if not vim.fn.filereadable(M.current_build_file) == 1 then
        print("Build file set is not valid: " .. M.current_build_file)
    end

    opts = opts or {}

    local lines = io.open(M.current_build_file, "r"):read("*a")

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

-- opts.build_function decides what to do with the build command
M.interactive_build = function(opts)
    opts = opts or {}

    local commands = M.parse_command_file(opts)
    if not commands or next(commands) == nil then
        print("No commands to select from after parsing command file: " .. M.current_build_file)
        return
    end

    local on_user_choice = function(result_table)
        if not result_table then
            return
        end

        local command, command_string = next(result_table)
        print(command .. ": " .. command_string)
    end

    if opts.build_function then
        on_user_choice = opts.build_function
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
