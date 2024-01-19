local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"

local status_base = require "mongosh-nvim.ui.status.base"

local M = {}

-- ----------------------------------------------------------------------------

---@alias mongo.ui.status.Component fun(args?: table): string

---@class mongo.ui.status.ComponentSpec
---@field [integer] string
---@field [string] any

---@class mongo.ui.status.BuiltComponentInfo
---@field default_args table<string, any>
---@field comp mongo.ui.status.Component

---@alias mongo.ui.status.ComponentLoaderFunc fun(): mongo.ui.status.BuiltComponentInfo

-- ----------------------------------------------------------------------------
-- Component Loading

-- Status line state cache
local last_active_state = nil ---@type boolean?
---@type (mongo.ui.status.Component | string)[]
local selected_components = {}
---@type (table | true)[]
local selected_component_args = {}

---@alias mongo.ui.status.ComponentType
---| "_current_db"
---| "_current_host"
---| "_running_cnt"
---| "_process_state"
---| "_mongosh_last_output"
---| "_operation_state"

-- Components are loaded on need, so that unnecessary events won't be registered.
---@type table<mongo.ui.status.ComponentType, mongo.ui.status.ComponentLoaderFunc>
local component_loader = {
    _current_db = function()
        local connection_comp = require "mongosh-nvim.ui.status.component.connection"
        return connection_comp.current_db
    end,
    _current_host = function()
        local connection_comp = require "mongosh-nvim.ui.status.component.connection"
        return connection_comp.current_host
    end,

    _operation_state = function()
        local operation = require "mongosh-nvim.ui.status.component.operation"
        return operation.operation_state
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

    selected_components[#selected_components + 1] = comp
    selected_component_args[#selected_component_args + 1] = args
end

-- ----------------------------------------------------------------------------
-- Exported API

M.components = components

M.set_status_line_dirty = status_base.set_status_line_dirty

-- Set active components with a list of component name.
---@param comp_values (string | table)[]
function M.set_components(comp_values)
    selected_components = {}
    selected_component_args = {}

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

-- Update state cache of status line.
---@param is_active boolean
function M.set_active_state(is_active)
    if is_active == last_active_state then return end

    last_active_state  = is_active
    status_base.set_status_line_dirty()

    local comp_cfg = config.status_line.components
    local comps = is_active and comp_cfg.active or comp_cfg.inactive
    M.set_components(comps)
end

-- Generate status line text.
---@return string
function M.get_status_line()
    local buffer = {}
    for i, comp in ipairs(selected_components) do
        local args = selected_component_args[i]

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

    return line
end

-- Generate status line text, prefere using cached line if not specified.
---@param _ table # lualine module table.
---@param is_active boolean
---@return string
function M.status(_, is_active)
    M.set_active_state(is_active)

    local cached = status_base.get_cached_status_line()
    if cached then
        return cached
    end

    local line = M.get_status_line()
    status_base.set_cached_status_line(line)

    return line
end

return M
