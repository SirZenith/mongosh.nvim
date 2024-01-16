local config = require "mongosh-nvim.config"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local buffer_const = require "mongosh-nvim.constant.buffer"
local str_util = require "mongosh-nvim.util.str"
local extract = require "mongosh-nvim.util.tree_sitter.query_collection_extraction"

local BufferType = buffer_const.BufferType
local QueryResultStyle = buffer_const.QueryResultStyle

---@type mongo.MongoBufferOperationModule
local M = {}

function M.on_enter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"
    bo.filetype = "typescript"
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
        callback "no collection name binded with this buffer"
    end

    local content = str_util.format(script_const.SNIPPET_QUERY, {
        collection = collection,
    })
    mbuf:set_lines(content)

    callback()
end

function M.result_args_generator(mbuf, args, callback)
    local lines = args.with_range
        and mbuf:get_visual_selection()
        or mbuf:get_lines()

    local snippet = table.concat(lines, "\n")
    local collection = extract.get_collection_name(snippet)

    local type = config.query.result_style == QueryResultStyle.Card
        and BufferType.QueryResultCard
        or BufferType.QueryResult

    callback(nil, {
        type = type,
        state_args = {
            is_typed = args.is_typed,
            snippet = snippet,
            collection = collection,
        }
    })
end

return M
