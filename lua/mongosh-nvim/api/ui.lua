local log = require "mongosh-nvim.log"
local api_core = require "mongosh-nvim.api.core"
local api_buffer = require "mongosh-nvim.api.buffer"
local mongosh_state = require "mongosh-nvim.state.mongosh"

local ui_db_sidebar = require "mongosh-nvim.ui.ui_db_sidebar"

local M = {}

-- ----------------------------------------------------------------------------

-- Ask user to pick a database from name list.
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
            api_core.switch_to_db(db)
            api_core.update_collection_list(db)
        end
    )
end

-- Show database selection UI if no valid database is selected right now.
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

-- Ask user to select a collection name from list.
function M.select_collection_ui_list()
    local db = api_core.get_cur_db()
    if not db then
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
            api_buffer.create_query_buffer(db, collection)
        end
    )
end

-- ----------------------------------------------------------------------------

-- Toggle database side bar.
function M.toggle_db_sidebar()
    ui_db_sidebar.toggle()
end

-- Show database side bar.
function M.show_db_sidebar()
    ui_db_sidebar.show()
end

-- Hide database side bar.
function M.hide_db_sidebar()
    ui_db_sidebar.hide()
end

-- ----------------------------------------------------------------------------

return M
