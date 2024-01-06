local M = {}

---@param msg string
---@param level? integer | string # vim.log.levels value
function M.log(msg, level)
    vim.notify("[mongo.nvim] - " .. msg, level)
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
