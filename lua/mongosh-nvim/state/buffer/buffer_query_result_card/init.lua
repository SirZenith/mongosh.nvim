local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"
local util = require "mongosh-nvim.util"
local buffer_util = require "mongosh-nvim.util.buffer"

local TreeViewItem = require "mongosh-nvim.state.buffer.buffer_query_result_card.tree_view_item"

local BufferType = buffer_const.BufferType
local FileType = buffer_const.FileType

-- ----------------------------------------------------------------------------

---@type mongo.buffer.MongoBufferOperationModule
local M = {}

---@param bufnr integer
---@param tree_item mongo.buffer.TreeViewItem
local function update_tree_to_buffer(bufnr, tree_item)
    local bo = vim.bo[bufnr]
    bo.modifiable = true
    tree_item:write_to_buffer(bufnr)
    bo.modifiable = false
end

---@param mbuf mongo.buffer.MongoBuffer
---@return integer? bufnr
---@return mongo.buffer.TreeViewItem?
local function try_get_tree_item(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return nil, nil end

    local tree_item = mbuf._state_args.tree_item ---@type mongo.buffer.TreeViewItem?

    return bufnr, tree_item
end

---@param mbuf mongo.buffer.MongoBuffer
---@param callback fun(err?: string)
local function update_tree_view(mbuf, typed_json, callback)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local tree_item = mbuf._state_args.tree_item ---@type mongo.buffer.TreeViewItem?
    if not tree_item then
        tree_item = TreeViewItem:new()
        mbuf._state_args.tree_item = tree_item
    end

    local ok, value = pcall(vim.json.decode, typed_json)
    if not ok then
        callback("JSON decode error: " .. tostring(value))
        return
    end

    tree_item:update_binded_value(ok and value or {})
    update_tree_to_buffer(bufnr, tree_item)

    callback()
end

---@param mbuf mongo.buffer.MongoBuffer
local function toggle_entry_expansion(mbuf)
    local bufnr, tree_item = try_get_tree_item(mbuf)
    if not bufnr or not tree_item then return end

    local bo = vim.bo[bufnr]
    bo.modifiable = true
    tree_item:select_with_cursor_pos(bufnr)
    bo.modifiable = false
end

---@param mbuf mongo.buffer.MongoBuffer
local function try_edit_field(mbuf)
    local collection = mbuf._state_args.collection
    if not collection then
        log.warn "no collection binded with current buffer"
    end

    local bufnr, tree_item = try_get_tree_item(mbuf)
    if not bufnr or not tree_item then return end

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

---@param mbuf mongo.buffer.MongoBuffer
---@param offset integer
local function change_folding_level(mbuf, offset)
    local bufnr, tree_item = try_get_tree_item(mbuf)
    if not bufnr or not tree_item then
        return
    end

    local level = tree_item.folding_level + offset

    if tree_item:set_folding_level(level) then
        update_tree_to_buffer(bufnr, tree_item)
    end
end

---@param mbuf mongo.buffer.MongoBuffer
local function fold_all(mbuf)
    local bufnr, tree_item = try_get_tree_item(mbuf)
    if not bufnr or not tree_item then
        return
    end

    if tree_item:fold_all() then
        update_tree_to_buffer(bufnr, tree_item)
    end
end

---@param mbuf mongo.buffer.MongoBuffer
local function expand_all(mbuf)
    local bufnr, tree_item = try_get_tree_item(mbuf)
    if not bufnr or not tree_item then
        return
    end

    if tree_item:expand_all() then
        update_tree_to_buffer(bufnr, tree_item)
    end
end

---@param mbuf mongo.buffer.MongoBuffer
local function setup_events(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local options = { buffer = bufnr }
    local key_cfg = config.card_view.keybinding

    -- toggle entry expansion
    local toggle_callback = function() toggle_entry_expansion(mbuf) end
    for _, key in ipairs(key_cfg.toggle_expansion) do
        vim.keymap.set("n", key, toggle_callback, options)
    end

    -- editing field
    local edit_callback = function() try_edit_field(mbuf) end
    for _, key in ipairs(key_cfg.edit_field) do
        vim.keymap.set("n", key, edit_callback, options)
    end

    -- folding operation
    local fold_key = key_cfg.folding
    local fold_mapping = {
        [fold_key.fold_less] = function()
            change_folding_level(mbuf, -1)
        end,
        [fold_key.fold_more] = function()
            change_folding_level(mbuf, 1)
        end,
        [fold_key.expand_all] = function()
            expand_all(mbuf)
        end,
        [fold_key.fold_all] = function()
            fold_all(mbuf)
        end,
    }
    for key, callback in pairs(fold_mapping) do
        vim.keymap.set("n", key, callback, options)
    end

    -- refresh content on move
    local old_pos = 0
    vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = bufnr,
        callback = function()
            local _, tree_item = try_get_tree_item(mbuf)
            if not tree_item then return end

            local winnr = buffer_util.get_win_by_buf(bufnr, true)
            if not winnr then return end

            local st_row = vim.api.nvim_win_call(winnr, function()
                return vim.fn.getpos("w0")[2]
            end)

            if st_row == old_pos then
                return
            end

            old_pos = st_row
            update_tree_to_buffer(bufnr, tree_item)
        end
    })
end

---@param mbuf mongo.buffer.MongoBuffer
local function clear_buffer_keybinding(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local options = { buffer = bufnr }
    local key_cfg = config.card_view.keybinding

    -- toggle entry expansion
    for _, key in ipairs(key_cfg.toggle_expansion) do
        vim.keymap.del("n", key, options)
    end

    -- editing field
    for _, key in ipairs(key_cfg.edit_field) do
        vim.keymap.del("n", key, options)
    end

    -- folding operation
    local fold_key = key_cfg.folding
    local fold_mapping = {
        fold_key.fold_less,
        fold_key.fold_more,
        fold_key.expand_all,
        fold_key.fold_all,
    }
    for _, key in ipairs(fold_mapping) do
        vim.keymap.del("n", key, options)
    end
end

function M.on_enter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"
    bo.filetype = FileType.QueryResultCard
    bo.modifiable = false

    setup_events(mbuf)
end

function M.on_show(mbuf)
    local bufnr, tree_item = try_get_tree_item(mbuf)
    if not bufnr or not tree_item then
        return
    end

    local winnr = buffer_util.get_win_by_buf(bufnr, true)
    if winnr then
        local wo = vim.wo[winnr]
        wo.number = false
        wo.relativenumber = false
    end

    update_tree_to_buffer(bufnr, tree_item)
end

function M.on_leave(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = ""
    bo.buflisted = true
    bo.buftype = ""
    bo.modifiable = true

    clear_buffer_keybinding(mbuf)
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

    api_core.do_query_typed(snippet, function(err, response)
        if err then
            callback(err)
            return
        end

        update_tree_view(mbuf, response, callback)
    end)
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

    local row = vim.api.nvim_win_get_cursor(0)[1]
    local err, info = tree_item:find_edit_target(row)
    if err or not info then
        callback(err or "no field found under cursor")
        return
    end

    local err_path
    for _, segment in ipairs(info.dot_path) do
        if type(segment) ~= "string" then
            err_path = "editing array element is not supported"
        elseif type(segment) == "string" and segment:sub(1, 1) == "$" then
            err_path = "unrecognized field name " .. segment
        end

        if err_path then break end
    end
    if err_path then
        callback(err_path)
        return
    end

    local dot_path = table.concat(info.dot_path, ".")

    callback(nil, {
        type = BufferType.Update,
        state_args = {
            collection = collection,
            id = vim.json.encode(info.id),
            dot_path = dot_path,
        }
    })
end

M.refresher = M.content_writer

function M.convert_type(mbuf, args, callback)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local to_type = args.to_type
    if to_type ~= BufferType.QueryResult then
        callback "not supported conversion"
        return
    end

    mbuf:change_type_to(BufferType.QueryResult)
    mbuf:content_writer(callback)
end

return M
