local log = require "mongosh-nvim.log"

local M = {}

-- ----------------------------------------------------------------------------

---@alias mongo.event.CallbackSet table<function, boolean>

---@class mongo.event.Channel
---@field free_callback mongo.event.CallbackSet # callback function set
---@field binded_callback table<table, mongo.event.CallbackSet> # mapping `self` table to event callback

---@class mongo.event.Emitter
---@field name string
---@field event_type_set table<string, boolean>
---@field _channels table<string, mongo.event.Channel> # map event type to listener list.
local EventEmitter = {}
EventEmitter.__index = EventEmitter

---@param name string
---@param type_tbl table<string, string> # event type enum table
---@return mongo.event.Emitter
function EventEmitter:new(name, type_tbl)
    local obj = setmetatable({}, self)

    obj.name = name

    local type_set = {}
    for _, v in pairs(type_tbl) do
        type_set[v] = true
    end
    obj.event_type_set = type_set

    obj._channels = {}

    return obj
end

-- Gets channel of `event_type`, if such channel doesn't exists yet,
-- a new channel will be created.
---@param event_type string
---@return mongo.event.Channel
function EventEmitter:_get_channel(event_type)
    local channels = self._channels

    local chl = channels[event_type]
    if not chl then
        chl = {
            free_callback = {},
            binded_callback = {}
        }
        channels[event_type] = chl
    end

    return chl
end

-- Brodcasts event to all callbacks in channel of `event_type`.
-- Event extra arguments pass to this method call will be passed on to each
-- listener as event arguments.
---@param event_type string
---@param ... any
function EventEmitter:emit(event_type, ...)
    local chl = self:_get_channel(event_type)

    for callback in pairs(chl.free_callback) do
        callback(...)
    end

    for obj, callback_set in pairs(chl.binded_callback) do
        for callback in pairs(callback_set) do
            callback(obj, ...)
        end
    end
end

-- Registers callback into channel of `event_type`. If `obj` is passed, its
-- value will be used as first argument of event callback when event is triggered.
---@param event_type string
---@param callback function
---@param obj? table # `self` variable binded with callback
function EventEmitter:on(event_type, callback, obj)
    if not self.event_type_set[event_type] then
        log.warn(self.name .. " - invalid event: " .. event_type)
        return
    end

    local chl = self:_get_channel(event_type)
    local callback_set

    if not obj then
        callback_set = chl.free_callback
    else
        callback_set = chl.binded_callback[obj]
        if not callback_set then
            callback_set = {}
            chl.binded_callback[obj] = callback_set
        end
    end

    if not callback_set then
        log.warn(self.name .. " - failed to register listener on: " .. event_type)
        return
    end

    if callback_set[callback] then
        local listener_type = obj and "binded" or "free"
        local msg = ("%s - duplicated %s listener: %s"):format(
            self.name, listener_type, event_type
        )
        log.warn(msg)
        return
    end

    callback_set[callback] = true
end

-- Removes a listener of an object from channel of `event_type`.
---@param event_type string
---@param callback function
---@param obj? table # `self` variable binded with callback
function EventEmitter:off(event_type, callback, obj)
    local chl = self:_get_channel(event_type)

    local callback_set
    if obj then
        callback_set = chl.binded_callback[obj]
    else
        callback_set = chl.free_callback
    end

    if callback_set then
        callback_set[callback] = nil
    end
end

-- Removes listener created for given value from all channels.
-- If argument value is a function, all free listeners with that callback are
-- removed; if value is a table, all binded listeners for that object are
-- removed.
---@param value table | function
function EventEmitter:off_all(value)
    local is_free = type(value) == "function"

    for _, chl in pairs(self._channels) do
        local callback_set

        if is_free then
            callback_set = chl.free_callback
        else
            callback_set = chl.binded_callback[value]
        end

        if callback_set then
            callback_set[value] = nil
        end
    end
end

-- ----------------------------------------------------------------------------

M.EventEmitter = EventEmitter

return M
