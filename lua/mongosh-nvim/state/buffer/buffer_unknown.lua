local buffer_const = require "mongosh-nvim.constant.buffer"
local log = require "mongosh-nvim.log"

local FileType = buffer_const.FileType

---@type mongo.buffer.MongoBufferOperationModule
local M = {}

function M.on_enter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"
    bo.filetype = FileType.Unknown
end

function M.on_leave(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = ""
    bo.buflisted = true
    bo.buftype = ""
end

function M.content_writer(mbuf, callback)
    callback("current type doesn't support content generation: " .. mbuf:get_type())
end

function M.result_args_generator(_, _, callback)
    callback "current buffer doesn't generate result"
end

function M.on_result_failed(_, err)
    log.warn(err)
end

function M.on_result_successed()
end

function M.refresher(_, callback)
    callback "current buffer doesn't support refreshing"
end

function M.convert_type(_, _, callback)
    callback "not supported conversion"
end

return M
