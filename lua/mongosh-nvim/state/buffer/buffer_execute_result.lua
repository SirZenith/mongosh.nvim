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

function M.refresh(mbuf, callback)
    local src_bufnr = mbuf.src_bufnr

    local src_lines = src_bufnr and read_lines_from_buf(src_bufnr)
    local snippet = src_lines
        and table.concat(src_lines, "\n")
        or mbuf.state_args.src_script

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
    end)
end

return M
