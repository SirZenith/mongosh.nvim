local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local log = require "mongosh-nvim.log"
local buffer_state = require "mongosh-nvim.state.buffer"

local BufferType = buffer_const.BufferType

local M = {}

-- ----------------------------------------------------------------------------

-- Try to refresh given buffer.
---@param bufnr integer
function M.refresh_buffer(bufnr)
    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)

    if mbuf then
        mbuf:refresh()
    else
        log.warn("current buffer is not refreshable")
    end
end

-- ----------------------------------------------------------------------------

-- Create a new query buffer for given collection name.
---@param db string # database name
---@param collection string # collection name
---@param win? integer # if not `nil`, buffer will be displayed in given window.
function M.create_query_buffer(db, collection, win)
    local err = api_core.switch_to_db(db)
    if err then
        log.warn(err)
        return
    end

    local mbuf = buffer_state.create_dummy_mongo_buffer(BufferType.CollectionList, {})
    mbuf:write_result {
        win = win,
        collection = collection,
    }
end

-- Create a new buffer with editing snippet for given document.
---@param collection string # collection name
---@param id string # `_id` of target document
---@param win? integer # if not `nil`, buffer will be displayed in given window.
function M.create_edit_buffer(collection, id, win)
    local mbuf = buffer_state.create_dummy_mongo_buffer(BufferType.QueryResult, {})
    mbuf:write_result {
        win = win,
        collection = collection,
        id = id,
    }
end

-- ----------------------------------------------------------------------------

---@class mongo.ExecuteBufferArgs
---@field with_range boolean

-- Execute snippet in given buffer.
---@param bufnr integer
---@param args mongo.ExecuteBufferArgs
function M.run_buffer_executation(bufnr, args)
    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
        or buffer_state.wrap_with_mongo_buffer(BufferType.Execute, bufnr)

    local supported_types = {
        [BufferType.Execute] = true,
        [BufferType.Query] = true,
        [BufferType.Edit] = true,
    }

    if supported_types[mbuf.type] then
        mbuf:change_type_to(BufferType.Execute)
        mbuf:write_result(args)
    else
        log.warn("current buffer doesn't support Execute commnad")
    end
end

-- Execute given snippet and show result in buffer.
---@param lines string[]
---@param args mongo.ExecuteBufferArgs
function M.run_executation_lines(lines, args)
    local mbuf = buffer_state.create_dummy_mongo_buffer(BufferType.Execute, lines)
    mbuf:write_result(args)
end

---@class mongo.RunBufferQueryArgs
---@field with_range boolean

-- Run query snippet in given buffer.
---@param bufnr integer
---@param args mongo.RunBufferQueryArgs
function M.run_buffer_query(bufnr, args)
    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
        or buffer_state.wrap_with_mongo_buffer(BufferType.Query, bufnr)

    if mbuf.type == BufferType.Execute then
        mbuf:change_type_to(BufferType.Query)
    end

    local supported_types = {
        [BufferType.Query] = true,
    }

    if supported_types[mbuf.type] then
        mbuf:write_result(args)
    else
        log.warn("current buffer doesn't support Query command")
    end
end

-- Run given query and show result in buffer.
---@param lines string[]
---@param args mongo.RunBufferQueryArgs
function M.run_query_lines(lines, args)
    local mbuf = buffer_state.create_dummy_mongo_buffer(BufferType.Query, lines)
    mbuf:write_result(args)
end

---@class mongo.RunBufferEditArgs
---@field with_range boolean

-- Run replace snippet in given buffer
---@param bufnr integer
---@param args mongo.RunBufferEditArgs
function M.run_buffer_edit(bufnr, args)
    local db = api_core.get_cur_db()
    if not db then
        log.warn("you need to first connect to a database to do edit")
        return
    end

    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
        or buffer_state.wrap_with_mongo_buffer(BufferType.Edit, bufnr)

    if mbuf.type == BufferType.Execute then
        mbuf:change_type_to(BufferType.Edit)
    end

    local supported_types = {
        [BufferType.QueryResult] = true,
        [BufferType.Edit] = true,
    }

    if supported_types[mbuf.type] then
        mbuf:write_result(args)
    else
        log.warn("current buffer doesn't support Edit command")
    end
end

-- Run given replace snippet and show result in buffer.
---@param lines string[]
---@param args mongo.RunBufferEditArgs
function M.run_edit_lines(lines, args)
    local mbuf = buffer_state.create_dummy_mongo_buffer(BufferType.Edit, lines)
    mbuf:write_result(args)
end

-- ----------------------------------------------------------------------------

return M
