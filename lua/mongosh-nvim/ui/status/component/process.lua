local api_core = require "mongosh-nvim.api.core"
local api_constant = require "mongosh-nvim.constant.api"
local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"
local str_util = require "mongosh-nvim.util.str"

local status_base = require "mongosh-nvim.ui.status.base"

local CoreEventType = api_constant.CoreEventType
local ProcessType = api_constant.ProcessType
local ProcessState = api_constant.ProcessState
local core_event = api_core.emitter

local M = {}

-- Amount of running process.
local running_cnt = 0 ---@type integer

-- Last PID that changed state by event callback.
local last_active_pid = 0 ---@type integer
-- mapping PID to its meta file
---@type table<integer, mongo.ui.status.ProcessMeta>
local process_meta_map = {}

-- Create new meta data for specified process. Existing meta data will be
-- overwritten.
-- New meta data will be returned after creation.
---@param pid integer
---@return mongo.ui.status.ProcessMeta
local function new_process_meta(pid)
    ---@type mongo.ui.status.ProcessMeta
    local meta = {
        pid = pid,
        type = ProcessType.Unknown,
        state = ProcessType.Unknown,
        stdout_dirty = false,
        stderr_dirty = false,
    }
    process_meta_map[pid] = meta

    return meta
end

-- Remove meta data of given process from record
---@param pid integer
local function remove_process_meta(pid)
    process_meta_map[pid] = nil
end

-- Find meta data for given process in record, if no matching meta data is found
-- `nil` will be returned.
---@param pid integer
---@return mongo.ui.status.ProcessMeta?
local function get_process_meta(pid)
    local meta = process_meta_map[pid]
    return meta
end

-- Find meta data for given process in record, if no matching meta data is found
-- a new one will be created.
---@param pid integer
---@return mongo.ui.status.ProcessMeta
local function get_or_create_process_meta(pid)
    local meta = process_meta_map[pid]
    if not meta then
        meta = new_process_meta(pid)
    end

    return meta
end

-- ----------------------------------------------------------------------------

-- Show number of running process, if no process is running, " " will be
-- returned.
---@type mongo.ui.status.BuiltComponentInfo
M.running_cnt = {
    default_args = {},
    comp = function()
        if running_cnt <= 0 then
            return " "
        end
        return tostring(running_cnt)
    end,
}

---@type mongo.ui.status.BuiltComponentInfo
M.process_state = {
    default_args = {
        state_symbol = {
            [ProcessState.Unknown] = "➖",
            [ProcessState.Running] = "🟢",
            [ProcessState.Error] = "🔴",
            [ProcessState.Exit] = "⚪",
        }
    },
    comp = function(args)
        local sign

        local meta = get_process_meta(last_active_pid)
        if meta then
            sign = args.state_symbol[meta.state]
        end

        if not sign then
            sign = args.state_symbol[ProcessState.Unknown]
            local width = vim.fn.strdisplaywidth(sign)
            sign = (" "):rep(width)
        end

        return sign
    end
}

---@type mongo.ui.status.BuiltComponentInfo
M.mongosh_last_output = {
    default_args = {
        max_width = 15,
    },
    comp = function(args)
        local meta = get_process_meta(last_active_pid)
        if not meta then
            return ""
        end

        local out
        if meta.stderr_dirty then
            -- stderr takes higher priority
            meta.stderr_dirty = false
            out = meta.last_stderr or ""
        elseif meta.stdout_dirty then
            meta.stdout_dirty = false
            out = meta.last_stdout or ""
        end

        out = str_util.truncate_msg(out or "", args.max_width)

        return out
    end
}

-- ----------------------------------------------------------------------------

---@type table<mongo.api.CoreEventType, function>
local event_map = {
    ---@type fun(pid: integer)
    [CoreEventType.process_started] = function(pid)
        running_cnt = running_cnt + 1
        last_active_pid = pid

        local meta = get_or_create_process_meta(pid)
        meta.state = ProcessState.Running
    end,

    ---@type fun(pid: integer)
    [CoreEventType.process_ended] = function(pid)
        running_cnt = running_cnt - 1
        last_active_pid = pid
        remove_process_meta(pid)
    end,

    ---@type fun(pid: integer, out: string)
    [CoreEventType.incomming_stdout] = function(pid, out)
        last_active_pid = pid
        local meta = get_or_create_process_meta(pid)
        meta.state = ProcessState.Running
        meta.stdout_dirty = true
        meta.last_stdout = out
    end,

    ---@type fun(pid: integer, out: string)
    [CoreEventType.incomming_stderr] = function(pid, out)
        last_active_pid = pid
        local meta = get_or_create_process_meta(pid)
        meta.state = ProcessState.Error
        meta.stderr_dirty = true
        meta.last_stderr = out
    end,

    ---@type fun(pid: integer, type: mongo.api.ProcessType)
    [CoreEventType.update_process_type] = function(pid, type)
        last_active_pid = pid
        local meta = get_or_create_process_meta(pid)
        meta.type = type
    end,
}

for event, handler in pairs(event_map) do
    core_event:on(event, function(...)
        status_base.set_status_line_dirty()
        handler(...)
    end)
end

return M
