local str_util = require "mongosh-nvim.util.str"

local M = {}

-- ----------------------------------------------------------------------------

-- raw flag-value pairs that gets directly prepended to command line arguments.
local raw_flag_map = {} ---@type table<string, string>

---@class mongo.DbUriData
---@field protocol? string
---@field host? string
---@field port? number
---@field db? string
---@field param? string

local db_address = {
    protocol = nil,
    host = nil,
    port = nil,
    db = nil,
    param = nil,
}

local username = nil ---@type string?
local password = nil ---@type string?

-- name list of all available databases
local db_names = nil ---@type string[]?
-- name list of all available collections
local collection_names = {} ---@type string[]?

-- parse_db_addr parses address connection URI.
---@param addr string
---@return mongo.DbUriData
local function parse_db_addr(addr)
    return {}
end

-- ----------------------------------------------------------------------------
-- Raw Flags

-- set_raw_flag sets value for a flag, set flag to value `nil` will delte this flag.
---@param flag string # flag key, e.g. --foo, -b
---@param value string?
function M.set_raw_flag(flag, value)
    raw_flag_map[flag] = value
end

-- get_raw_flag returns stored value of a given flag.
---@return string? value
function M.get_raw_flag(flag)
    return raw_flag_map[flag]
end

-- get_raw_flag returns a copy of raw flag table.
---@return table<string, string>
function M.get_raw_flag_map()
    return vim.deepcopy(raw_flag_map)
end

-- clear_all_raw_flags deletes all connection raw flag value.
function M.clear_all_raw_flags()
    raw_flag_map = {}
end

-- ----------------------------------------------------------------------------
-- Connection state

-- set_host update cached last connected host address
---@param value string
function M.set_cur_host(value)
    db_address.host = str_util.scramble(value or "")
    M.reset_db_cache()
end

-- get_host returns last host address this plugin has connected to.
-- If no host is ever connected to, `nil` will be returned.
---@return string? host_addr
function M.get_cur_host()
    local cur_host = db_address.host
    if not cur_host or cur_host:len() == 0 then return nil end
    return str_util.unscramble(cur_host)
end

-- set_cur_port sets port number for current connection.
---@param value? number
function M.set_cur_port(value)
    db_address.cur_port = value or 0
    M.reset_db_cache()
end

-- get_cur_port returns port of current connection. If no special port is specified
-- `nil` will be returned.
---@return number? port
function M.get_cur_port()
    local cur_port = db_address.port
    if not cur_port or cur_port <= 0 then return nil end
    return cur_port
end

-- set_cur_db selectes a database in current host.
-- If `nil` is passed in, database selection is cleared.
---@param value string?
function M.set_cur_db(value)
    db_address.db = value
    M.reset_collection_name_cache()
end

-- get_cur_db returns currently selected database name.
-- If no database is selected `nil` will be returned.
---@return string? db_name
function M.get_cur_db()
    return db_address.db
end

-- set_cur_db_addr set c
---@return string? db_addr
function M.set_cur_db_addr(value)
    if not value or value:len() == 0 then
        db_address = {}
        return
    end

    local data = parse_db_addr(value)
    db_address.protocol = data.protocol
    db_address.param = data.param
    M.set_cur_host(data.host)
    M.set_cur_port(data.port)
    M.set_cur_db(data.db)
end

-- get_db_addr returns address of current selected database, if no database is
-- selected `nil` will be returned.
---@return string? db_addr
function M.get_cur_db_addr()
    local buffer = {}

    local protocol = db_address.protocol
    if protocol then
        buffer[#buffer + 1] = protocol
    end

    local host = M.get_cur_host()
    if host then
        buffer[#buffer + 1] = host
    end

    local port = M.get_cur_port()
    if port and port > 0 then
        buffer[#buffer + 1] = ":" .. tostring(port)
    end

    -- any data in buffer indicates need of separator before database name.
    if #buffer > 1 then
        buffer[#buffer + 1] = "/"
    end

    local db = M.get_cur_db()
    if db then
        buffer[#buffer + 1] = db
    end

    local param = db_address.param
    if param then
        buffer[#buffer + 1] = "?" .. param
    end

    return table.concat(buffer)
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
    if not username or username:len() == 0 then return nil end
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
    if not password or password:len() == 0 then return nil end
    return str_util.unscramble(password)
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

-- reset_collection_name_cache clears collection name list cache for current database.
function M.reset_collection_name_cache()
    collection_names = nil
end

-- reset_db_cache clears cached data for connection.
function M.reset_db_cache()
    M.reset_db_name_cache()
    M.reset_collection_name_cache()
end

return M
