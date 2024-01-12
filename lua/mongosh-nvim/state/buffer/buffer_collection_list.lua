local api_core = require "mongosh-nvim.api.core"
local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local buffer_util = require "mongosh-nvim.state.buffer"
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

    -- press <Cr> to select a collection
    vim.keymap.set("n", "<CR>", function()
        mbuf:write_result()
    end, { buffer = bufnr })
end

function M.result_generator(mbuf, args, callback)
    local collection = args.collection
    if not collection then
        local bufnr = mbuf:get_bufnr()
        local win = bufnr and buffer_util.get_win_by_buf(bufnr, true)
        local pos = win and api.nvim_win_get_cursor(win)

        local row = pos and pos[1]
        local lines = row and api.nvim_buf_get_lines(bufnr, row - 1, row, true)

        collection = lines and lines[1]
    end

    local content = str_util.format(script_const.SNIPPET_QUERY, {
        collection = collection,
    })

    callback {
        type = BufferType.Query,
        content = content,
    }
end

function M.after_write(src_buf)
    local bufnr = src_buf and src_buf:get_bufnr()
    if not bufnr then return end

    local win = buffer_util.get_win_by_buf(bufnr, true)
    if not win then return end

    api.nvim_win_hide(win)
end

function M.refresh(mbuf, callback)
        local collections = mongosh_state.get_collection_names()
        if not collections then return end

        mbuf:set_lines(collections)
        callback()
    end

return M
