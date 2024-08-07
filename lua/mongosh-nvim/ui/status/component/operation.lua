local api_core = require "mongosh-nvim.api.core"
local api_constant = require "mongosh-nvim.constant.api"
local status_const = require "mongosh-nvim.constant.status"
local log = require "mongosh-nvim.log"
local anim_util = require "mongosh-nvim.util.anim"

local status_base = require "mongosh-nvim.ui.status.base"

local CoreEventType = api_constant.CoreEventType
local OperationState = status_const.OperationState
local core_event = api_core.emitter
local CharAnimation = anim_util.CharAnimation

local loop = vim.uv or vim.loop

local M = {}


local STATE_PRIORITY_LIST = {
    OperationState.Connect,
    OperationState.MetaUpdate,
    OperationState.Replace,
    OperationState.Query,
    OperationState.Execute,
    OperationState.Idle,
}

-- Recording active process count of a state.
local state_activation_record = {} ---@type table<mongo.ui.status.OperationState, integer>
local last_used_state = nil ---@type mongo.ui.status.OperationState?

local anim = CharAnimation:new()
local old_frame_time = nil ---@type integer?
local timer_anim = nil

-- Setting flag of given state on or off.
---@param state mongo.ui.status.OperationState
---@param on boolean
local function set_state_flag(state, on)
    local old_cnt = state_activation_record[state] or 0
    local delta = on and 1 or -1
    local new_cnt = old_cnt + delta

    state_activation_record[state] = new_cnt > 0 and new_cnt or nil

    status_base.set_status_line_dirty()
end

local function get_cur_state()
    local target = OperationState.Idle

    for _, state in ipairs(STATE_PRIORITY_LIST) do
        if state_activation_record[state] then
            target = state
            break
        end
    end

    return target;
end

-- Start or stop animation timer.
---@param frame_time integer # time in second, value less then or equal to 0 will stop the timer.
local function try_set_anim_timer(frame_time)
    if frame_time == old_frame_time then
        return
    end

    old_frame_time = frame_time

    if timer_anim then
        timer_anim:stop()
    else
        timer_anim = loop.new_timer()
    end

    if frame_time <= 0 then
        return
    end

    if not timer_anim then
        log.warn "failed to create animation timer"
        return
    end

    timer_anim:start(0, frame_time * 1000, status_base.set_status_line_dirty)
end

---@type mongo.ui.status.BuiltComponentInfo
M.operation_state = {
    default_args = {
        ---@type table<mongo.ui.status.OperationState, string[] | string>
        symbol = {
            [OperationState.Idle] = " ",
            [OperationState.Execute] = { " ", " " },
            [OperationState.Query] = { "󰮗 ", "󰈞 " },
            [OperationState.Replace] = { " ", "󰏫 " },
            [OperationState.MetaUpdate] = { " ", " " },
            [OperationState.Connect] = { " ", " ", " ", "󰢹 ", " ", "󰢹 " },
        },
        frame_time = 0.1,
    },
    comp = function(args)
        local new_state = get_cur_state()

        if last_used_state ~= new_state then
            local frames = args.symbol[new_state]
            local frame_t = type(frames)
            if frame_t == "string" then
                frames = { frames }
            elseif frame_t ~= "table" then
                frames = {}
            end

            anim:set_frames(frames)
            anim.frame_time = args.frame_time
        end

        last_used_state = new_state
        local result = anim:yield()

        local frame_time = anim:get_frame_cnt() > 1 and anim.frame_time or 0
        try_set_anim_timer(frame_time)

        return result
    end,
}

-- ----------------------------------------------------------------------------

status_base.register_status_line_events(core_event, {
    [CoreEventType.action_connect_start] = function()
        set_state_flag(OperationState.Connect, true)
    end,
    [CoreEventType.action_connect_end] = function()
        set_state_flag(OperationState.Connect, false)
    end,
    [CoreEventType.action_execute_start] = function()
        set_state_flag(OperationState.Execute, true)
    end,
    [CoreEventType.action_execute_end] = function()
        set_state_flag(OperationState.Execute, false)
    end,
    [CoreEventType.action_replace_start] = function()
        set_state_flag(OperationState.Replace, true)
    end,
    [CoreEventType.action_replace_end] = function()
        set_state_flag(OperationState.Replace, false)
    end,
    [CoreEventType.action_query_start] = function()
        set_state_flag(OperationState.Query, true)
    end,
    [CoreEventType.action_query_end] = function()
        set_state_flag(OperationState.Query, false)
    end,
    [CoreEventType.action_meta_update_start] = function()
        set_state_flag(OperationState.MetaUpdate, true)
    end,
    [CoreEventType.action_meta_update_end] = function()
        set_state_flag(OperationState.MetaUpdate, false)
    end,
})

return M
