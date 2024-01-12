local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local buffer_util = require "mongosh-nvim.util.buffer"
local str_util = require "mongosh-nvim.util.str"
local ts_util = require "mongosh-nvim.util.tree_sitter"

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

    bo.filetype = "json"
end

function M.result_generator(mbuf, args, callback)
    local collection = args.collection
        or mbuf._state_args.collection
    if collection == nil then
        log.warn("collection required")
        callback {}
        return
    end

    local bufnr = mbuf:get_bufnr()
    local id = args.id
    if not id and bufnr then
        id = ts_util.find_nearest_id_in_buffer(bufnr)
    end
    if id == nil then
        log.warn("id required")
        callback {}
        return
    end

    local dot_path
    if bufnr and args.with_range then
        dot_path = buffer_util.get_visual_json_dot_path(bufnr)
    end

    local query, buffer_type

    if dot_path then
        query = str_util.format(script_const.TEMPLATE_FIND_ONE_WITH_DOT_PATH, {
            collection = collection,
            id = id,
            filter = vim.json.encode {
                [dot_path] = true,
                _id = false,
            },
        })

        buffer_type = BufferType.Update
    else
        query = str_util.format(script_const.TEMPLATE_FIND_ONE, {
            collection = collection,
            id = id,
        })

        buffer_type = BufferType.Edit
    end

    api_core.do_query(query, function(err, result)
        if err then
            log.warn(err)
            callback {}
            return
        end

        local snippet = str_util.format(script_const.SNIPPET_EDIT, {
            collection = collection,
            id = id,
            document = result,
        })

        callback {
            type = buffer_type,
            content = snippet,
            state_args = {
                collection = collection,
                id = id,
                dot_path = dot_path,
            },
        }
    end, "failed to update document content")
end

function M.refresher(mbuf, callback)
    local src_bufnr = mbuf._src_bufnr

    local src_lines = src_bufnr and buffer_util.read_lines_from_buf(src_bufnr)
    local query = src_lines
        and table.concat(src_lines)
        or mbuf._state_args.query

    if not query or #query == 0 then
        callback("no query is binded with current buffer")
        return
    end

    api_core.do_query(query, function(err, response)
        if err then
            callback(err)
            return
        end

        local lines = vim.fn.split(response, "\n")
        mbuf:set_lines(lines)

        callback()
    end)
end

return M
