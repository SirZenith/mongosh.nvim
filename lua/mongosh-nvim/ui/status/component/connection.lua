local api_constant = require "mongosh-nvim.constant.api"
local api_core = require "mongosh-nvim.api.core"
local str_util = require "mongosh-nvim.util.str"

local status_base = require "mongosh-nvim.ui.status.base"

local CoreEventType = api_constant.CoreEventType

local core_event = api_core.emitter

local M = {}

local cur_db = nil ---@type string?

-- Show name of current connected database.
---@type mongo.ui.status.BuiltComponentInfo
M.current_db = {
    default_args = {
        max_width = 20,
    },
    comp = function(args)
        if not cur_db then
            return "mongosh.nvim"
        end

        local max_width = args.max_width
        cur_db = str_util.truncate_msg(cur_db, max_width)

        return "DB: " .. cur_db
    end,
}

-- ----------------------------------------------------------------------------

status_base.register_status_line_events(core_event, {
    ---@param db string
    [CoreEventType.db_selection_update] = function(db)
        cur_db = db
    end,
})

return M
