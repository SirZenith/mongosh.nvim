local str_util = require "mongosh-nvim.util.str"
local db_addr_util = require "mongosh-nvim.util.db_address"

local DbAddressData = db_addr_util.DbAddressData

local M = {}

-- ----------------------------------------------------------------------------

-- raw flag-value pairs that gets directly prepended to command line arguments.
local raw_flag_map = {} ---@type table<string, string>

local username = nil ---@type string?
local password = nil ---@type string?
local auth_source = nil ---@type string?

local addr_data = DbAddressData:new()

-- name list of all available databases
local db_names = nil ---@type string[]?
-- map database name to collection name list of all available collections
local collection_name_cache = {} ---@type table<string, string[]>

-- ----------------------------------------------------------------------------
-- Raw Flags

-- set_raw_flag sets value for a flag, set flag to value `nil` will delte this flag.
---@param flag string # flag key, e.g. --foo, -b
---@param value string?
function M.set_raw_flag(flag, value)
    raw_flag_map[flag] = value and str_util.scramble(value) or nil
end

-- get_raw_flag returns stored value of a given flag.
---@return string? value
function M.get_raw_flag(flag)
    local value = raw_flag_map[flag]
    return value and str_util.unscramble(value)
end

-- get_raw_flag returns a copy of raw flag table.
---@return table<string, string>
function M.get_raw_flag_map()
    local copy = {}
    for flag in pairs(raw_flag_map) do
        copy[flag] = M.get_raw_flag(flag)
    end
    return copy
end

-- clear_all_raw_flags deletes all connection raw flag value.
function M.clear_all_raw_flags()
    raw_flag_map = {}
end

-- ----------------------------------------------------------------------------
-- Connection state

-- set_db_addr sets database address for current connection.
---@return string? db_addr
function M.set_db_addr(value)
    addr_data:parse_addr(value or "")
end

---@return string db_addr # database address of current connection.
function M.get_db_addr()
    return addr_data:to_db_addr()
end

-- set_host set host value for current connection.
---@param value string
function M.set_host(value)
    addr_data:set_host(value)
end

---@return string? host_addr # host value of current connection.
function M.get_host()
    return addr_data:get_host()
end

-- set_port sets port number for current connection.
---@param value? number
function M.set_port(value)
    addr_data:set_port(value)
end

-- get_port returns port of current connection. If no special port is specified
-- `nil` will be returned.
---@return number? port
function M.get_port()
    return addr_data:get_port()
end

-- set_cur_db selectes a database in current host.
-- If `nil` is passed in, database selection is cleared.
---@param value string?
function M.set_db(value)
    addr_data:set_db(value)
end

-- get_db returns currently selected database name.
-- If no database is selected `nil` will be returned.
---@return string? db_name
function M.get_db()
    return addr_data:get_db()
end

-- ----------------------------------------------------------------------------
-- Authentication

-- set_username updates user name for current connection. If input value is `nil`
-- or empty string, this function does nothing.
---@param value? string
function M.set_username(value)
    username = str_util.scramble(value or "")
end

-- get_username returns user name for current connection. If no user name is used
-- for connection, `nil` will be returned.
---@return string? username
function M.get_username()
    if not username or username == "" then return nil end
    return str_util.unscramble(username)
end

-- set_password updates password for current connection. If input value is `nil`
-- or empty string, this function does nothing.
---@param value? string
function M.set_password(value)
    password = str_util.scramble(value or "");
end

-- get_password returns password for current connection. If no password is used
-- for connection, `nil` will be returned.
---@return string? password
function M.get_password()
    if not password or password == "" then return nil end
    return str_util.unscramble(password)
end

-- Set authentication source database for connection connection.
---@param value? string
function M.set_auth_source(value)
    auth_source = value
end

-- Get authentication database for current connection.
function M.get_auth_source()
    if not auth_source or auth_source == "" then return nil end
    return auth_source
end

-- ----------------------------------------------------------------------------
-- Cached Values

-- set_db_names update cached database name list.
---@param names string[]
function M.set_db_names(names)
    db_names = {}
    for _, name in ipairs(names) do
        db_names[#db_names + 1] = name
    end
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

-- reset_db_name_cache clears cached database name list for current connection.
function M.reset_db_name_cache()
    db_names = nil
end

-- set_collection_names update cached collection name list.
---@param db string # database name, default value is database name of current connection.
---@param names string[]
function M.set_collection_names(db, names)
    local collections = {}
    for _, name in ipairs(names) do
        collections[#collections + 1] = name
    end

    collection_name_cache[db] = collections
end

-- Return all available collection names in current database.
---@param db? string # database name, default value is database name of current connection.
---@return string[]? collection_names
function M.get_collection_names(db)
    db = db or M.get_db()
    if not db then return nil end

    local names = collection_name_cache[db]
    if not names then return nil end

    local results = {}
    for _, name in ipairs(names) do
        results[#results + 1] = name
    end

    return results
end

-- reset_collection_name_cache clears collection name list cache for current database.
---@param db string # database name
function M.reset_collection_name_cache(db)
    collection_name_cache[db] = nil
end

-- Clear cached collection name list for all database
function M.reset_all_collection_name_cache()
    collection_name_cache = {}
end

-- reset_db_cache clears cached data for connection.
function M.reset_db_cache()
    M.reset_db_name_cache()
    collection_name_cache = {}
end

return M
