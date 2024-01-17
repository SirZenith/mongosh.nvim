local api_constant = require "mongosh-nvim.constant.api"
local api_core = require "mongosh-nvim.api.core"
local str_util = require "mongosh-nvim.util.str"

local CoreEventType = api_constant.CoreEventType

local M = {}

-- Show name of current connected database.
---@type mongo.ui.status.BuiltComponentInfo
M.current_db = {
    default_args = {
        max_width = 20,
    },
    comp = function(args)
        local db = api_core.get_cur_db();
        if not db then
            return "mongosh.nvim"
        end

        local max_width = args.max_width
        db = str_util.truncate_msg(db, max_width)

        return "DB: " .. db
    end,
}

-- ----------------------------------------------------------------------------

return M
