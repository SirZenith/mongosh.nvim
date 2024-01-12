local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local log = require "mongosh-nvim.log"

local BufferType = buffer_const.BufferType

---@type mongo.MongoBufferOperationModule
local M = {}

function M.option_setter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"

    bo.filetype = "typescript"

    vim.print("update buffer")
end

function M.result_generator(mbuf, args, callback)
    local lines = args.with_range
        and mbuf:get_visual_selection()
        or mbuf:get_lines()
    local snippet = table.concat(lines, "\n")

    api_core.do_update_one(snippet, function(err, result)
        if err then
            log.warn(err)
            callback {}
            return
        end

        result = #result > 0 and result or "execution successed"
        callback {
            type = BufferType.UpdateResult,
            content = result,
            state_args = {
                collection = mbuf._state_args.collection,
                id = mbuf._state_args.id,
            },
        }
    end)
end

return M
