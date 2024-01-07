local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local api_core = require "mongosh-nvim.api.core"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local buffer_state = require "mongosh-nvim.state.buffer"
local str_util = require "mongosh-nvim.util.str"

local BufferType = buffer_const.BufferType

local M = {}

-- refresh_buffer tries to refresh given buffer.
---@param bufnr integer
function M.refresh_buffer(bufnr)
    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)

    if mbuf then
        mbuf:refresh()
    else
        log.warn("current buffer is not refreshable")
    end
end

-- select_database selects a database among available ones.
---@param db_name string
function M.select_database(db_name)
    local full_list = mongosh_state.get_db_names()
    if #full_list == 0 then
        log.info("no available database found")
        return
    end

    local is_found = false
    for _, name in ipairs(full_list) do
        if name == db_name then
            is_found = true
            break
        end
    end

    if not is_found then
        log.warn("database is not available: " .. db_name)
        return
    end

    mongosh_state.set_cur_db(db_name)
end

-- select_database_ui lets user pick a database from name list.
function M.select_database_ui()
    local full_list = mongosh_state.get_db_names()
    if #full_list == 0 then
        log.info("no available database found")
        return
    end

    local ignore_set = {}
    for _, name in ipairs(config.connection.ignore_db_names) do
        ignore_set[name] = true
    end

    local db_names = {}
    for _, name in ipairs(full_list) do
        if not ignore_set[name] then
            db_names[#db_names + 1] = name
        end
    end

    if #db_names == 0 then
        log.info("only ignored databases are found")
        return
    end

    vim.ui.select(
        db_names,
        { prompt = "Select a database:" },
        function(db)
            mongosh_state.set_cur_db(db)
            api_core.update_collection_list()
        end
    )
end

-- select_collection selects a collection among available ones.
---@param collection_name string
function M.select_collection(collection_name)
    local full_list = mongosh_state.get_collection_names()
    if #full_list == 0 then
        log.info("no available collection found")
        return
    end

    local is_found = false
    for _, name in ipairs(full_list) do
        if name == collection_name then
            is_found = true
            break
        end
    end

    if not is_found then
        log.warn("collection is not available: " .. collection_name)
        return
    end

    mongosh_state.set_cur_collection(collection_name)
end

-- select_collection_ui_buffer creates a buffer for collection selection.
function M.select_collection_ui_buffer()
    local db_addr = mongosh_state.get_cur_db_addr()
    if not db_addr then
        log.warn("please connect to a database first")
        return
    end

    local lines = mongosh_state.get_collection_names()
    buffer_state.create_mongo_buffer(BufferType.CollectionList, lines)
end

-- select_collection_ui_list asks user to select a collection name from list.
function M.select_collection_ui_list()
    local db_addr = mongosh_state.get_cur_db_addr()
    if not db_addr then
        log.warn("please connect to a database first")
        return
    end

    local collections = mongosh_state.get_collection_names()

    vim.ui.select(
        collections,
        { prompt = "Select a collection" },
        function(collection)
            if collection == nil then return end

            local content = str_util.format(script_const.SNIPPET_QUERY, {
                collection = collection,
            })

            buffer_state.create_mongo_buffer(
                BufferType.query,
                vim.split(content, "\n", { plain = true })
            )
        end
    )
end

-- create_edit_buffer creates a new buffer with editing snippet for given document.
---@param collection string # collection name
---@param id string # `_id` of target document
function M.create_edit_buffer(collection, id)
    local query = str_util.format(script_const.TEMPLATE_FIND_ONE, {
        collection = collection,
        id = id,
    })

    api_core.do_query(query, function(err, result)
        if err then
            log.warn(err)
            return
        end

        local document = str_util.indent(result, config.indent_size)

        local snippet = str_util.format(script_const.SNIPPET_EDIT, {
            collection = collection,
            id = id,
            document = document,
        })

        local lines = vim.split(snippet, "\n", { plain = true })
        local mbuf = buffer_state.create_mongo_buffer(BufferType.Edit, lines)

        mbuf.state_args = {
            collection = collection,
            id = id,
        }
    end, "failed to update document content")
end

-- ----------------------------------------------------------------------------

---@class mongo.ExecuteBufferArgs
---@field with_range boolean

-- run_buffer_executation executes snippet in given buffer.
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
        mbuf:write_result(args)
    else
        log.warn("current buffer doesn't support Execute commnad")
    end
end

---@class mongo.RunBufferQueryArgs
---@field with_range boolean

-- run_buffer_query runs query snippet in given buffer.
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

---@class mongo.RunBufferEditArgs
---@field with_range boolean

-- run_buffer_edit runs replace snippet in given buffer
---@param bufnr integer
---@param args mongo.RunBufferEditArgs
function M.run_buffer_edit(bufnr, args)
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

return M
