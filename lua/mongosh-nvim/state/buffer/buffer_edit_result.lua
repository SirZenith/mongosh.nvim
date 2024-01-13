local api_core = require "mongosh-nvim.api.core"
local util = require "mongosh-nvim.util"

---@type mongo.MongoBufferOperationModule
local M = {}

function M.content_writer(mbuf, callback)
    local src_lines = mbuf:get_src_buf_lines()
    local snippet = src_lines
        and table.concat(src_lines)
        or mbuf._state_args.snippet

    if not snippet or snippet == "" then
        callback "no snippet is binded with current buffer"
        return
    end

    api_core.do_replace(snippet, function(err, result)
        if err then
            callback(err)
            return
        end

        if result == "" then
            result = util.get_time_str() .. " - " .. "execution successed"
        end

        mbuf:set_lines(result)

        callback()
    end)
end

function M.option_setter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"

    bo.filetype = "json"
end

M.refresher = M.content_writer

return M
