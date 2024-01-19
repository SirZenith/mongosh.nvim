local buffer_const = require "mongosh-nvim.constant.buffer"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local buffer_util = require "mongosh-nvim.util.buffer"

local api = vim.api

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
    bo.filetype = FileType.CollectionList

    -- press <Cr> to select a collection
    vim.keymap.set("n", "<CR>", function()
        mbuf:write_result()
    end, { buffer = bufnr })
end

function M.on_leave(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = ""
    bo.buflisted = true
    bo.buftype = ""

    vim.keymap.del("n", "<CR>", { buffer = bufnr })
end

function M.result_args_generator(mbuf, args, callback)
    local collection = args.collection
    if not collection then
        local bufnr = mbuf:get_bufnr()
        local win = bufnr and buffer_util.get_win_by_buf(bufnr, true)
        local pos = win and api.nvim_win_get_cursor(win)

        local row = pos and pos[1]
        local lines = row and api.nvim_buf_get_lines(bufnr, row - 1, row, true)

        collection = lines and lines[1]
    end

    callback(nil, {
        type = BufferType.Query,
        state_args = {
            collection = collection
        }
    })
end

function M.on_result_successed(mbuf, result_obj)
    local src_buf = mbuf:get_bufnr()
    if not src_buf then return end

    if result_obj:get_bufnr() == src_buf then
        return
    end

    local win = buffer_util.get_win_by_buf(src_buf, true)
    if not win then return end

    api.nvim_win_hide(win)
end

function M.refresher(mbuf, callback)
    local collections = mongosh_state.get_collection_names()
    if not collections then return end

    mbuf:set_lines(collections)

    callback()
end

return M
