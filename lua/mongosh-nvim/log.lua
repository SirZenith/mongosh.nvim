local M = {}

---@return string
local function pad_num(value)
    if value < 0 or value >= 10 then
        return tostring(value)
    else
        return "0" .. tostring(value)
    end
end

---@param msg string
---@param level? integer # vim.log.levels value
function M.log(msg, level)
    local date = os.date("*t", os.time())
    local prefix = ("[mongo.nvim %s:%s:%s] - "):format(
        pad_num(date.hour), pad_num(date.min), pad_num(date.sec)
    )

    vim.notify(prefix .. msg, level)
end

function M.error(msg)
    M.log(msg, vim.log.levels.ERROR)
end

function M.warn(msg)
    M.log(msg, vim.log.levels.WARN)
end

function M.info(msg)
    M.log(msg, vim.log.levels.INFO)
end

function M.debug(msg)
    M.log(msg, vim.log.levels.DEBUG)
end

function M.trace(msg)
    M.log(msg, vim.log.levels.TRACE)
end

return M
