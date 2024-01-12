local log = require "mongosh-nvim.log"

---@type mongo.MongoBufferOperationModule
local M = {}

function M.option_setter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"
end

function M.result_generator()
    log.info("current buffer doesn't generate result")
end

function M.after_write_handler()
end

function M.refresher()
    log.info("current buffer doesn't support refreshing")
end

return M
