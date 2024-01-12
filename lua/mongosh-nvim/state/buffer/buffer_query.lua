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
    local query = table.concat(lines, "\n")

    api_core.do_query(query, function(err, response)
        if err then
            log.warn(err)
            callback {}
            return
        end

        local collection = ts_util.get_collection_name(query)

        callback {
            type = BufferType.QueryResult,
            content = response,
            state_args = {
                query = query,
                collection = collection,
            }
        }
    end)
end

return M
