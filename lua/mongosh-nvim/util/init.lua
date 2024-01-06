local loop = vim.loop

local M = {}

-- save_to_tmpfile writes content to temporary file. If tmp file name is provide,
-- this function will use that name directly instead of generates a new name.
---@param content string
---@param filename? string
---@param callback fun(err?: string, tmpfile_name: string)
function M.save_to_tmpfile(content, filename, callback)
    filename = filename or vim.fn.tempname()
    local permission = 448 -- 0o700
    local open_mode = loop.constants.O_CREAT + loop.constants.O_WRONLY + loop.constants.O_TRUNC

    loop.fs_open(filename, open_mode, permission, function(open_err, fd)
        if open_err then
            callback(nil, "")
            return
        end

        loop.fs_write(fd, content, 0, function(write_err)
            if write_err then
                callback(write_err, "")
                return
            end

            loop.fs_close(fd, function(close_err)
                if close_err then
                    callback(close_err, "")
                    return
                end

                vim.schedule(function()
                    callback(nil, filename)
                end)
            end)
        end)
    end)
end

return M
