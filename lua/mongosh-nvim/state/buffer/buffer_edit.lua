local api_core = require "mongosh-nvim.api.core"
local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local str_util = require "mongosh-nvim.util.str"
local ts_util = require "mongosh-nvim.util.tree_sitter"

local api = vim.api

local BufferType = buffer_const.BufferType
local CreateBufferStyle = buffer_const.CreateBufferStyle
local ResultSplitStyle = buffer_const.ResultSplitStyle

---@type mongo.MongoBufferOperationModule
local M = {}

function M.option_setup(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"

    bo.filetype = "typescript"
end

function M.result_generator(mbuf, args, callback)
    local lines = args.with_range
        and mbuf:get_visual_selection()
        or mbuf:get_lines()
    local snippet = table.concat(lines, "\n")

    api_core.do_replace(snippet, function(err, result)
        if err then
            log.warn(err)
            callback {}
            return
        end

        result = #result > 0 and result or "execution successed"
        callback {
            type = BufferType.EditResult,
            content = result,
            state_args = {
                collection = mbuf.state_args.collection,
                id = mbuf.state_args.id,
            },
        }
    end)
end

function M.refresh(mbuf, callback)
    local collection = mbuf.state_args.collection
    if not collection then
        callback("no collection name is binded with current buffer")
        return
    end

    local id = mbuf.state_args.id
    if not id then
        callback("no document id is binded with current buffer")
        return
    end

    local query = str_util.format(script_const.TEMPLATE_FIND_ONE, {
        collection = collection,
        id = id,
    })

    api_core.do_query(query, function(err, result)
        if err then
            callback(err)
            return
        end

        local document = str_util.indent(result, config.indent_size)

        local snippet = str_util.format(script_const.SNIPPET_EDIT, {
            collection = collection,
            id = id,
            document = document,
        })

        local lines = vim.split(snippet, "\n", { plain = true })
        mbuf:set_lines(lines)
    end, "failed to update document content")
end

return M
