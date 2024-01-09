local M = {}

-- ----------------------------------------------------------------------------

-- address last connected host
local cur_host = nil ---@type string | nil

-- name list of all available databases
local db_names = nil ---@type string[] | nil
-- name of selected database
local cur_db = nil ---@type string | nil

-- name list of all available collections
local collection_names = {} ---@type string[] | nil
-- name of selected collections
local cur_collection = nil ---@type string | nil

local username = nil ---@type string | nil
local password = nil ---@type string | nil

local api_version = nil ---@type string | nil

-- ----------------------------------------------------------------------------

-- set_host update cached last connected host address
---@param host string
function M.set_cur_host(host)
    cur_host = host
    M.reset_db_cache()
end

-- get_host returns last host address this plugin has connected to.
-- If no host is ever connected to, `nil` will be returned.
---@return string? host_addr
function M.get_cur_host()
    if not cur_host then return nil end

    return cur_host
end

-- set_db_names update cached database name list.
---@param names string[]
function M.set_db_names(names)
    db_names = {}
    for _, name in ipairs(names) do
        db_names[#db_names + 1] = name
    end
end

function M.reset_db_cache()
    db_names = nil
    M.set_cur_db(nil)
end

-- get_db_names returns all available database names in connected host.
---@return string[] db_names
function M.get_db_names()
    local results = {}
    if not db_names then return results end

    for _, name in ipairs(db_names) do
        results[#results + 1] = name
    end

    return results
end

-- set_cur_db selectes a database in current host.
-- If `nil` is passed in, database selection is cleared.
---@param name string?
function M.set_cur_db(name)
    cur_db = name
    M.reset_collection_cache()
end

-- get_cur_db returns currently selected database name.
-- If no database is selected `nil` will be returned.
---@return string? db_name
function M.get_cur_db()
    return cur_db
end

-- set_collection_names update cached collection name list.
---@param names string[]
function M.set_collection_names(names)
    collection_names = {}
    for _, name in ipairs(names) do
        collection_names[#collection_names + 1] = name
    end
end

-- get_collection_names returns all available collection names in current database.
---@return string[] collection_names
function M.get_collection_names()
    local results = {}
    if not collection_names then return results end

    for _, name in ipairs(collection_names) do
        results[#results + 1] = name
    end

    return results
end

function M.reset_collection_cache()
    collection_names = nil
    M.set_cur_collection(nil)
end

-- set_cur_collection selecte give name as collection being used.
-- If `nil` is passed in, collection selection will be cleared.
---@param name string?
function M.set_cur_collection(name)
    cur_collection = name
end

-- get_cur_collection returns currently selected collection name.
-- If no collection is ever used, `nil` will be returned.
---@return string? collection_name
function M.get_cur_collection()
    return cur_collection
end

-- set_username updates user name for current connection. If input value is `nil`
-- or empty string, this function does nothing.
---@param value? string
function M.set_username(value)
    if not value or value:len() == 0 then return end
    username = value
end

-- get_username returns user name for current connection. If no user name is used
-- for connection, `nil` will be returned.
---@return string? username
function M.get_username()
    if not username or username:len() == 0 then return end
    return username
end

-- set_password updates password for current connection. If input value is `nil`
-- or empty string, this function does nothing.
---@param value? string
function M.set_password(value)
    if not value or value:len() == 0 then return end
    password = value;
end

-- get_password returns password for current connection. If no password is used
-- for connection, `nil` will be returned.
---@return string? password
function M.get_password()
    if not password or password:len() == 0 then return end
    return password
end

-- ----------------------------------------------------------------------------

-- get_db_addr returns address of current selected database, if no database is
-- selected `nil` will be returned.
---@return string? db_addr
function M.get_cur_db_addr()
    local host = M.get_cur_host()
    if not host then return nil end

    local db = M.get_cur_db()
    if not db then return nil end

    return host .. "/" .. db
end

return M
