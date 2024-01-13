local log = require "mongosh-nvim.log"

---@type mongo.MongoBufferOperationModule
local M = {}

function M.content_writer(mbuf, callback)
    callback("current type doesn't support content generation: " .. mbuf:get_type())
end

function M.option_setter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"
end

function M.result_args_generator(_, _, callback)
    callback "current buffer doesn't generate result"
end

function M.on_result_failed(_, err)
    log.warn(err)
end

function M.on_result_successed()
end

function M.refresher(callback)
    callback "current buffer doesn't support refreshing"
end

return M
