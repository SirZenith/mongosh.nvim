local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local str_util = require "mongosh-nvim.util.str"

local BufferType = buffer_const.BufferType
local FileType = buffer_const.FileType

---@type mongo.MongoBufferOperationModule
local M = {}

function M.on_enter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"
    bo.filetype = "typescript." .. FileType.Update
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

    local projection = { _id = false }
    local dot_path = mbuf._state_args.dot_path
    if dot_path then
        projection[dot_path] = true
    end

    local query = mbuf._state_args.query or str_util.format(
        script_const.SNIPPET_FIND_ONE,
        {
            collection = collection,
            id = id,
            projection = vim.json.encode(projection),
        }
    )

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

function M.result_args_generator(mbuf, args, callback)
    local lines = args.with_range
        and mbuf:get_visual_selection()
        or mbuf:get_lines()

    local snippet = table.concat(lines, "\n")

    callback(nil, {
        type = BufferType.UpdateResult,
        state_args = {
            snippet = snippet,
            collection = mbuf._state_args.collection,
            id = mbuf._state_args.id,
        },
    })
end

M.refresher = M.content_writer

return M
