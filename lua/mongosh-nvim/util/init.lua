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

---@alias mongo.util.AsyncStepFunc fun(next_step: fun())

-- do_async_steps accepts a list of step function, each of them will be call
-- with a handle function `next_step`. When step function finish its work and
-- calls `next_step`, next step function will be executed.
---@param steps mongo.util.AsyncStepFunc[]
function M.do_async_steps(steps)
    local step_index = 0

    local next_step
    next_step = function()
        step_index = step_index + 1

        local step_func = steps[step_index]
        if not step_func then return end

        step_func(next_step)
    end

    next_step()
end

return M
