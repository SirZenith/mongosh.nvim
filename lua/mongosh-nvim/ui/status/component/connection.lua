local api_constant = require "mongosh-nvim.constant.api"
local api_core = require "mongosh-nvim.api.core"
local str_util = require "mongosh-nvim.util.str"

local status_base = require "mongosh-nvim.ui.status.base"

local CoreEventType = api_constant.CoreEventType

local core_event = api_core.emitter

local M = {}

local cur_db = nil ---@type string?
local cur_host = nil ---@type string?

local FORBIDDEN_CHAR = "%$:/?#%[%]@"
local AUTH_HOST_PATT = ("[^%s]:[^%s]@(.+)"):format(FORBIDDEN_CHAR, FORBIDDEN_CHAR)

-- Show name of current connected database.
---@type mongo.ui.status.BuiltComponentInfo
M.current_db = {
    default_args = {
        max_width = 20,
    },
    comp = function(args)
        if not cur_db then
            return "<no-db>"
        end

        local max_width = args.max_width
        cur_db = str_util.truncate_msg(cur_db, max_width)

        return cur_db
    end,
}

M.current_host = {
    default_args = {
        max_width = 20,
    },
    comp = function(args)
        if not cur_host then
            return "<no-host>"
        end

        local max_width = args.max_width
        cur_host = str_util.truncate_msg(cur_host, max_width)

        return cur_host
    end,
}

-- ----------------------------------------------------------------------------

status_base.register_status_line_events(core_event, {
    [CoreEventType.connection_successed] = function()
        local host = api_core.get_cur_host();
        if not host then
            cur_host = nil
            return
        end

        local _, _, host_stem = host:find(AUTH_HOST_PATT)

        cur_host = host_stem and host_stem or host

        local port = api_core.get_cur_port()
        if port then
            cur_host = cur_host .. ":" .. tostring(port)
        end
    end,

    ---@param db string
    [CoreEventType.db_selection_update] = function(db)
        cur_db = db
    end,
})

return M
