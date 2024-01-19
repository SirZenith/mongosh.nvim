local api_core = require "mongosh-nvim.api.core"
local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local buffer_util = require "mongosh-nvim.util.buffer"
local ts_util = require "mongosh-nvim.util.tree_sitter"

local BufferType = buffer_const.BufferType
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
    bo.filetype = "json." .. FileType.QueryResult
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
    local src_lines = mbuf:get_src_buf_lines()
    local snippet = src_lines
        and table.concat(src_lines, "\n")
        or mbuf._state_args.snippet

    if not snippet or snippet == "" then
        callback("no query is binded with current buffer")
        return
    end

    local is_type = mbuf._state_args.is_typed
    if is_type == nil then
        is_type = config.query.use_typed_query or false
    end

    local do_query = is_type
        and api_core.do_query_typed
        or api_core.do_query

    do_query(snippet, function(err, response)
        if err then
            callback(err)
            return
        end

        mbuf:set_lines(response)

        callback()
    end)
end

function M.result_args_generator(mbuf, args, callback)
    local collection = args.collection or mbuf._state_args.collection
    if collection == nil then
        callback "collection required"
        return
    end

    local bufnr = mbuf:get_bufnr()
    local id = args.id
    if not id and bufnr then
        id = ts_util.find_nearest_id_in_buffer(bufnr)
    end
    if id == nil then
        callback "id required"
        return
    end

    local dot_path
    if bufnr and args.with_range then
        dot_path = buffer_util.get_visual_json_dot_path(bufnr)
    end

    callback(nil, {
        type = dot_path and BufferType.Update or BufferType.Edit,
        state_args = {
            collection = collection,
            id = id,
            dot_path = dot_path,
        }
    })
end

M.refresher = M.content_writer

function M.convert_type(mbuf, args, callback)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local to_type = args.to_type
    if to_type ~= BufferType.QueryResultCard then
        callback "not supported conversion"
        return
    end

    mbuf:change_type_to(BufferType.QueryResultCard)
    mbuf:content_writer(callback)
end

return M
