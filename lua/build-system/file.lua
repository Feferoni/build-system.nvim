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

return M
