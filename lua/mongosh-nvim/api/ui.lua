local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local log = require "mongosh-nvim.log"
local api_core = require "mongosh-nvim.api.core"
local api_buffer = require "mongosh-nvim.api.buffer"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local buffer_state = require "mongosh-nvim.state.buffer"

local ui_db_sidebar = require "mongosh-nvim.ui.ui_db_sidebar"

local BufferType = buffer_const.BufferType

local M = {}

-- ----------------------------------------------------------------------------

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

    mongosh_state.set_db(db_name)
end

-- select_database_ui lets user pick a database from name list.
function M.select_database_ui()
    local db_names = api_core.get_filtered_db_list()

    if #db_names == 0 then
        log.info("not connected to host or all available databases are mark ignored")
        return
    end

    vim.ui.select(
        db_names,
        { prompt = "Select a database:" },
        function(db)
            if db == "" then return end
            mongosh_state.set_db(db)
            api_core.update_collection_list(db)
        end
    )
end

-- try_select_database_ui shows database selection UI if no valid database is
-- selected right now.
function M.try_select_database_ui()
    local db = mongosh_state.get_db()

    local full_list = mongosh_state.get_db_names()
    local is_found = false
    for _, name in ipairs(full_list) do
        if name == db then
            is_found = true
            break
        end
    end

    if not is_found then
        M.select_database_ui()
    elseif db then
        api_core.update_collection_list(db)
    end
end

-- select_collection_ui_buffer creates a buffer for collection selection.
function M.select_collection_ui_buffer()
    if not mongosh_state.get_db() then
        log.warn("please connect to a database first")
        return
    end

    local lines = mongosh_state.get_collection_names()
    if not lines then
        log.warn("no collection found in current database")
        return
    end

    buffer_state.create_mongo_buffer(BufferType.CollectionList, lines)
end

-- select_collection_ui_list asks user to select a collection name from list.
function M.select_collection_ui_list()
    if not mongosh_state.get_db() then
        log.warn("please connect to a database first")
        return
    end

    local collections = mongosh_state.get_collection_names()
    if not collections then
        log.warn("no collection found in current database")
        return
    end

    vim.ui.select(
        collections,
        { prompt = "Select a collection" },
        function(collection)
            if collection == nil then return end
            api_buffer.create_query_buffer(collection)
        end
    )
end

-- Toggle database side bar.
function M.toggle_db_sidebar()
    ui_db_sidebar.toggle()
end

function M.show_db_sidebar()
    ui_db_sidebar.show()
end

function M.hide_db_sidebar()
    ui_db_sidebar.hide()
end

-- ----------------------------------------------------------------------------

return M
