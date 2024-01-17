local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"

local status_base = require "mongosh-nvim.ui.status.base"

local M = {}

-- ----------------------------------------------------------------------------

---@enum mongo.ui.status.StatusType
local State = {
    Inactive = 1,
    Idle = 2,
    Execute = 3,
    Query = 4,
    Edit = 5,
    DataUpdate = 6,
    Error = 7,
}

-- ----------------------------------------------------------------------------
-- Component Loading

---@type (mongo.ui.status.Component | string)[]
local active_components = {}
---@type (table | true)[]
local active_component_args = {}

-- Components are loaded on need, so that unnecessary events won't be registered.
---@type table<mongo.ui.status.ComponentType, mongo.ui.status.ComponentLoaderFunc>
local component_loader = {
    _current_db = function()
        local connection_comp = require "mongosh-nvim.ui.status.component.connection"
        return connection_comp.current_db
    end,

    _running_cnt = function()
        local process_comp = require "mongosh-nvim.ui.status.component.process"
        return process_comp.running_cnt
    end,
    _process_state = function()
        local process_comp = require "mongosh-nvim.ui.status.component.process"
        return process_comp.process_state
    end,
    _mongosh_last_output = function()
        local process_comp = require "mongosh-nvim.ui.status.component.process"
        return process_comp.mongosh_last_output
    end,
}

---@param tbl table<string, mongo.ui.status.BuiltComponentInfo>
---@param key any
---@return mongo.ui.status.BuiltComponentInfo?
local function component_lazy_loader(tbl, key)
    local comp = rawget(tbl, key)
    if type(comp) == "function" then
        return comp
    end

    local loader = component_loader[key]
    comp = loader and loader()
    if type(comp) ~= "table" then
        return
    end

    rawset(tbl, key, comp)

    return comp
end

---@type table<string, mongo.ui.status.BuiltComponentInfo>
local components = setmetatable({}, { __index = component_lazy_loader })

-- Load a component by parsing component specification value.
---@param spec any
---@return string? err
local function load_component_by_spec(spec)
    local custom_comps = config.status_line.custom_components
    local spec_t = type(spec)

    local key, user_args
    if spec_t == "string" then
        key = spec
    elseif spec_t == "table" then
        key = spec[1]
        user_args = spec
    else
        return "invalid component spec type '" .. spec_t .. "'"
    end

    if type(key) ~= "string" then
        return "can't find component name from spec value"
    end

    local custom_comp = custom_comps[key]
    local builtin_comp = M.components[key]

    local comp, args
    if type(custom_comp) == "function" then
        -- component provided by user
        comp, args = custom_comps, true
    elseif builtin_comp then
        -- built-in component
        comp = builtin_comp.comp
        args = setmetatable(user_args or {}, {
            __index = builtin_comp.default_args
        })
    elseif type(key) == "string" then
        -- no component found, use spec key as raw output.
        comp, args = key, true
    end

    if not comp or not args then
        return "invalid component '" .. tostring(spec) .. "'"
    end

    active_components[#active_components + 1] = comp
    active_component_args[#active_component_args + 1] = args
end

-- ----------------------------------------------------------------------------
-- Exported API

M.components = components

M.set_status_line_dirty = status_base.set_status_line_dirty

-- Set active components with a list of component name.
---@param comp_values (string | table)[]
function M.set_components(comp_values)
    active_components = {}
    active_component_args = {}

    local len = #comp_values
    for i = 1, len do
        local spec = comp_values[i]
        local err = load_component_by_spec(spec)
        if err then
            local msg = ("component at #%d: %s"):format(i, err)
            log.warn(msg)
        end
    end
end

-- Generate status line text, prefere using cached line if not specified.
---@param force? boolean
---@return string
function M.status(force)
    local cached = status_base.get_cached_status_line()
    if cached and not force then
        return cached
    end

    local buffer = {}
    for i, comp in ipairs(active_components) do
        local args = active_component_args[i]

        local value
        if type(comp) ~= "function" then
            value = comp
        elseif type(args) == "table" then
            value = comp(args)
        else
            value = comp()
        end

        buffer[#buffer + 1] = tostring(value)
    end

    local line = table.concat(buffer)
    status_base.set_cached_status_line(line)

    return line
end

return M