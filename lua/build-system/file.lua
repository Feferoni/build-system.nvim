local Dev = require("build-system.dev")
local log = Dev.log
local path = require('plenary.path')
local scan_dir = require('plenary.scandir')

local M = {}
M.build_file_type = "Makefile"
M.project_root = vim.fn.expand("#1:p")
M.current_build_file = nil

M.find_build_file = function(opts)
    opts = opts or {}

    if opts.search_pattern == nil then
        opts.search_pattern = M.build_file_type
    end

    local project_root = path:new(M.project_root)
    local current_location = vim.fn.expand("%:p:h")
    local current_folder = path:new(current_location)
    local files = {}

    local reached_root = false;
    while not reached_root and next(files) == nil do
        if tostring(current_folder) == tostring(project_root) then
            reached_root = true
        end


        files = scan_dir.scan_dir(tostring(current_folder), opts)
        current_folder = current_folder:parent()
    end

    if next(files) == nil then
        print("Could not locate any build files.")
        return nil
    end

    local found_file = files[1]
    local on_user_choice = function(action)
        if not action then
            return
        end

        found_file = action
    end
    if #files > 1 then
        print("Found multiple build files.")
        vim.ui.select(files, {
            prompt = 'Choose a build file:',
            kind = 'build file choosing',
            format_item = function(item)
                return item
            end,
            on_close = function()
            end
        }, on_user_choice)
    end
    M.current_build_file = found_file
    return found_file
end

M.get_file_modification_epoch_time = function(file_path)
    if not file_path or file_path == "" then
        return nil
    end

    local command = "stat -c '%Y' " .. "'" .. file_path .. "'"
    local handle = io.popen(command)
    if handle == nil then
        return nil
    end

    local result = handle:read("*a")
    handle:close()

    return result:gsub("^%s*(.-)%s*$", "%1")
end

-- Returns true if the file has been modified since the given epoch time
M.cmp_file_alter_time = function(file_path, epoch_time)
    if not file_path or file_path == "" then
        return false
    end

    local file_epoch_time = M.get_file_modification_epoch_time(file_path)
    if not file_epoch_time then
        return false
    end

    return file_epoch_time > epoch_time
end

return M
