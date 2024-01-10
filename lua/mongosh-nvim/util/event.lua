local log = require "mongosh-nvim.log"

local M = {}

---@class mongo.util.EventListener
---@field callback function
---@field obj table

---@alias mongo.util.EventChannel table<table, function> # mapping `self` table to event callback

---@class mongo.util.EventEmitter
---@field name string
---@field event_type_set table<string, boolean>
---@field _channels table<string, mongo.util.EventChannel> # map event type to listener list.
local EventEmitter = {}
EventEmitter.__index = EventEmitter

---@param name string
---@param type_tbl table<string, string> # event type enum table
---@return mongo.util.EventEmitter
function EventEmitter:new(name, type_tbl)
    local obj = setmetatable({}, self)

    obj.name = name

    local type_set = {}
    for _, v in ipairs(type_tbl) do
        type_set[v] = true
    end
    obj.event_type_set = type_set

    obj._channels = {}

    return obj
end

-- _get_channel gets channel of `event_type`, if such channel doesn't exists yet,
-- a new channel will be created.
---@param event_type string
---@return mongo.util.EventChannel
function EventEmitter:_get_channel(event_type)
    local channels = self._channels

    local chl = channels[event_type]
    if not chl then
        chl = {}
        channels[event_type] = chl
    end

    return chl
end

-- emit brodcasts value to all callback in channel of `event_type`.
---@param event_type string
---@param ... any
function EventEmitter:emit(event_type, ...)
    local chl = self:_get_channel(event_type)
    for obj, callback in pairs(chl) do
        callback(obj, ...)
    end
end

-- on registers callback into channel of `event_type`.
---@param event_type string
---@param obj table # `self` variable binded with callback
---@param callback function
function EventEmitter:on(event_type, obj, callback)
    if not self.event_type_set[event_type] then
        log.warn(self.name .. " - invalid event: " .. event_type)
        return
    end

    local chl = self:_get_channel(event_type)
    chl[obj] = callback
end

-- off removes listener of an object from channel of `event_type`.
---@param event_type string
---@param obj table
function EventEmitter:off(event_type, obj)
    local chl = self:_get_channel(event_type)
    chl[obj] = nil
end

-- off_all removes listener of an object from all channel.
---@param obj table
function EventEmitter:off_all(obj)
    for _, chl in pairs(self._channels) do
        chl[obj] = nil
    end
end

-- ----------------------------------------------------------------------------

M.EventEmitter = EventEmitter

return M
