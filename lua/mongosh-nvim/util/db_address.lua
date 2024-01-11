local str_util = require "mongosh-nvim.util.str"

local M = {}

---@class mongo.DbAddressData
---@field _protocol? string
---@field _host? string
---@field _port? number
---@field _db? string
---@field _param? string
local DbAddressData = {}
DbAddressData.__index = DbAddressData
M.DbAddressData = DbAddressData

-- new creates a new database address object.
---@return mongo.DbAddressData
function DbAddressData:new()
    local obj = setmetatable({}, self)
    return obj
end

-- parse_db_addr parses database address and makes new DbAddressData.
---@param addr string
function DbAddressData:parse_addr(addr)
    local proto_st, proto_ed = addr:find("://")
    if proto_st then
        self:set_protocol(addr:sub(1, proto_st - 1))
    end

    local stem = proto_ed and addr:sub(proto_ed + 1) or addr
    local parts = vim.split(stem, "/", { plain = true })

    local part_cnt = #parts
    local host_stem, db_stem, param_stem
    if part_cnt == 0 then
        -- pass
    elseif part_cnt > 2 then
        host_stem, db_stem, param_stem = parts[1], parts[2], parts[2]
    elseif part_cnt == 2 then
        host_stem, db_stem, param_stem = parts[1], parts[2], parts[2]
    elseif parts[1]:find(":") then
        host_stem = parts[1]
    else
        db_stem = parts[1]
    end

    local host, port
    if host_stem then
        local index = host_stem:find(":")
        if index then
            host = host_stem:sub(1, index - 1)
            port = tonumber(host_stem:sub(index + 1))
        else
            host = host_stem
        end
    end
    self:set_host(host)
    self:set_port(port)

    local db
    if db_stem then
        local index = db_stem:find("%?")
        if index then
            db = db_stem:sub(1, index - 1)
        else
            db = db_stem
        end
    end
    self:set_db(db)

    local param
    if param_stem then
        local index = param_stem:find("%?")
        if index then
            param = param_stem:sub(index - 1)
        end
    end
    self:set_param(param)
end

-- to_db_addr generates database address string with address data.
function DbAddressData:to_db_addr()
    local buffer = {}

    local protocol = self:get_protocol()
    if protocol then
        buffer[#buffer + 1] = protocol .. "://"
    end

    local host = self:get_host()
    if host then
        buffer[#buffer + 1] = host
    end

    local port = self:get_port()
    if port then
        buffer[#buffer + 1] = ":" .. tostring(port)
    end

    -- any data in buffer indicates need of separator before database name.
    if #buffer > 1 then
        buffer[#buffer + 1] = "/"
    end

    local db = self:get_db()
    if db then
        buffer[#buffer + 1] = db
    end

    local param = self:get_param()
    if param then
        buffer[#buffer + 1] = "?" .. param
    end

    return table.concat(buffer)
end

-- ----------------------------------------------------------------------------

-- set_protocol sets protocol of database address.
---@param value string?
function DbAddressData:set_protocol(value)
    self._protocol = value
end

---@return string? protocol # protocol of database address
function DbAddressData:get_protocol()
    return self._protocol
end

-- set_host sets host value of a database address.
---@param value string
function DbAddressData:set_host(value)
    self._host = str_util.scramble(value or "")
end

---@return string? host # host value of database address.
function DbAddressData:get_host()
    local host = self._host
    if not host or host:len() == 0 then return nil end

    return str_util.unscramble(host)
end

-- set_port sets port number of database address.
---@param value? number
function DbAddressData:set_port(value)
    self._port = value or 0
end

---@return number? port # port number of database address.
function DbAddressData:get_port()
    local cur_port = self._port
    if not cur_port or cur_port <= 0 then return nil end

    return cur_port
end

-- set_db sets database name for database address.
---@param value string?
function DbAddressData:set_db(value)
    self._db = value
end

---@return string? db_name # database name of database address.
function DbAddressData:get_db()
    return self._db
end

-- set_param sets URI parameter query string for database address
---@param value? string
function DbAddressData:set_param(value)
    self._param = str_util.scramble(value or "")
end

---@return string? param # parameter query string for database address.
function DbAddressData:get_param()
    local param = self._param
    if not param or param:len() == 0 then return nil end

    return str_util.unscramble(param)
end

return M
