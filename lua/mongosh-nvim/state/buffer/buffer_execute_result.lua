local api_core = require "mongosh-nvim.api.core"
local buffer_util = require "mongosh-nvim.util.buffer"

---@type mongo.MongoBufferOperationModule
local M = {}

function M.refresher(mbuf, callback)
    local src_bufnr = mbuf._src_bufnr

    local src_lines = src_bufnr and buffer_util.read_lines_from_buf(src_bufnr)
    local snippet = src_lines
        and table.concat(src_lines, "\n")
        or mbuf._state_args.src_script

    if not snippet or #snippet == 0 then
        callback("no snippet is binded with current buffer")
        return
    end

    api_core.do_execution(snippet, function(err, result)
        if err then
            callback(err)
            return
        end

        result = #result > 0 and result or "execution successed"

        local lines = vim.split(result, "\n", { plain = true })
        mbuf:set_lines(lines)

        callback()
    end)
end

return M
