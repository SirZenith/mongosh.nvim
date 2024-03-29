local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"

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
    bo.filetype = "json." .. FileType.UpdateResult
end

function M.on_leave(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = ""
    bo.buflisted = true
    bo.buftype = ""
    bo.filetype = ""
end

function M.content_writer(mbuf, callback)
    local snippet = mbuf._state_args.snippet
    if not snippet then
        local src_lines = mbuf:get_src_buf_lines()
        snippet = src_lines and table.concat(src_lines, "\n")
    end

    if not snippet or snippet == "" then
        callback "no snippet is binded with current buffer"
        return
    end

    api_core.do_update_one(snippet, function(err, result)
        if err then
            callback(err)
            return
        end

        result = #result > 0 and result or "execution successed"

        mbuf:set_lines(result)

        callback()
    end)
end

M.refresher = M.content_writer

return M
