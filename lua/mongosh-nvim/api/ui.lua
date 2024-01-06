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

---@class mongo.RunExecutionArgs
---@field script? string # query snippet, if `nil`, query snippet will be read from current buffer
---@field with_range boolean # when read query from current buffer, use visual selected text

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

return M
