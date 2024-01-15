local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"
local buffer_util = require "mongosh-nvim.util.buffer"
local util = require "mongosh-nvim.util"

local TreeViewItem = require "mongosh-nvim.state.buffer.buffer_query_result_card.tree_view_item"

local BufferType = buffer_const.BufferType

-- ----------------------------------------------------------------------------

---@type mongo.MongoBufferOperationModule
local M = {}

---@param mbuf mongo.MongoBuffer
local function update_tree_view(mbuf, typed_json)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local tree_item = mbuf._state_args.tree_item ---@type mongo.buffer.TreeViewItem?
    if not tree_item then
        tree_item = TreeViewItem:new()
        mbuf._state_args.tree_item = tree_item

        tree_item.is_top_level = true
    end

    local value = vim.json.decode(typed_json)
    tree_item:update_binded_value(value)

    local bo = vim.bo[bufnr]
    bo.modifiable = true
    tree_item:write_to_buffer(bufnr)
    bo.modifiable = false
end

---@param mbuf mongo.MongoBuffer
local function toggle_entry_expansion(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local tree_item = mbuf._state_args.tree_item ---@type mongo.buffer.TreeViewItem?
    if not tree_item then return end

    local bo = vim.bo[bufnr]
    bo.modifiable = true
    tree_item:select_with_cursor_pos(bufnr)
    bo.modifiable = false
end

---@param mbuf mongo.MongoBuffer
local function try_edit_field(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local collection = mbuf._state_args.collection
    if not collection then
        log.warn "no collection binded with current buffer"
    end

    local tree_item = mbuf._state_args.tree_item ---@type mongo.buffer.TreeViewItem?
    if not tree_item then return end

    util.do_async_steps {
        function(next_step)
            tree_item:try_update_entry_value(nil, collection, function(err)
                if err then
                    log.warn(err)
                else
                    log.info "value edited"
                    next_step()
                end
            end)
        end,
        function()
            M.refresher(mbuf, function(err)
                if err then
                    log.warn(err)
                end
            end)
        end
    }
end

---@param mbuf mongo.MongoBuffer
local function set_up_buffer_keybinding(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local key_cfg = config.card_view.keybinding

    -- toggle entry expansion
    local toggle_callback = function() toggle_entry_expansion(mbuf) end
    for _, key in ipairs(key_cfg.toggle_expansion) do
        vim.keymap.set("n", key, toggle_callback, { buffer = bufnr })
    end

    -- editing field
    local edit_callback = function() try_edit_field(mbuf) end
    for _, key in ipairs(key_cfg.edit_field) do
        vim.keymap.set("n", key, edit_callback, { buffer = bufnr })
    end
end

function M.content_writer(mbuf, callback)
    local src_bufnr = mbuf._src_bufnr

    local src_lines = src_bufnr and buffer_util.read_lines_from_buf(src_bufnr)
    local snippet = src_lines
        and table.concat(src_lines)
        or mbuf._state_args.snippet

    if not snippet or snippet == "" then
        callback("no query is binded with current buffer")
        return
    end

    api_core.do_query_typed(snippet, function(err, response)
        if err then
            callback(err)
            return
        end

        update_tree_view(mbuf, response)

        callback()
    end)
end

function M.option_setter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"
    bo.modifiable = false

    set_up_buffer_keybinding(mbuf)
end

function M.result_args_generator(mbuf, args, callback)
    local tree_item = mbuf._state_args.tree_item ---@type mongo.buffer.TreeViewItem
    if not tree_item then
        callback "no card view tree binded with this buffer"
        return
    end

    local collection = args.collection or mbuf._state_args.collection
    if collection == nil then
        callback "no collection name binded with this buffer"
        return
    end

    local id = tree_item:find_id_field_by_row_num()
    if id == nil then
        callback "no `_id` field found under cursor"
        return
    end

    callback(nil, {
        type = BufferType.Edit,
        state_args = {
            collection = collection,
            id = vim.json.encode(id),
            -- dot_path = dot_path,
        }
    })
end

M.refresher = M.content_writer

function M.convert_type(mbuf, args, callback)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local to_type = args.to_type
    if to_type == "card" then
        callback "current buffer is already card view"
        return
    end

    local err, new_buf = mbuf:make_result_buffer_obj(BufferType.QueryResult, bufnr)
    if err or not new_buf then
        callback(err or "failed to convert to new buffer")
        return
    end

    local bo = vim.bo[bufnr]
    bo.modifiable = true

    new_buf._state_args = mbuf._state_args
    new_buf:show(nil, mbuf._winnr)
    new_buf:setup_buf_options()
    new_buf:content_writer(callback)
end

return M
