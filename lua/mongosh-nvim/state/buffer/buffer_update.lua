local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local str_util = require "mongosh-nvim.util.str"

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

function M.refresher(mbuf, callback)
    local collection = mbuf._state_args.collection
    if not collection then
        callback("no collection name is binded with current buffer")
        return
    end

    local id = mbuf._state_args.id
    if not id then
        callback("no document id is binded with current buffer")
        return
    end

    local args = { _id = false }
    local dot_path = mbuf._state_args.dot_path
    if dot_path then
        args[dot_path] = true
    end

    local query = str_util.format(script_const.TEMPLATE_FIND_ONE_WITH_DOT_PATH, {
        collection = collection,
        id = id,
        filter = vim.json.encode(args),
    })

    api_core.do_query(query, function(err, result)
        if err then
            callback(err)
            return
        end

        local snippet = str_util.format(script_const.SNIPPET_EDIT, {
            collection = collection,
            id = id,
            document = result,
        })

        local lines = vim.split(snippet, "\n", { plain = true })
        mbuf:set_lines(lines)

        callback()
    end, "failed to update document content")
end

return M
