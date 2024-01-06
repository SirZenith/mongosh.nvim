local buffer_const = require "mongosh-nvim.constant.buffer"

local M = {}

M = {
    -- path to mongosh executable
    ---@type string
    executable = "mongosh",

    -- indent space count for document representation in query result, edit snippet, etc.
    ---@type integer
    indent_size = 4,

    connection = {
        -- default host address for connection.
        ---@type string
        default_host = "localhost:27017",

        -- names in this list won't be listed in available database list.
        ---@type string[]
        ignore_db_names = {
            "admin",
            "config",
            "local",
        },
    },

    dialog = {
        -- When a snippe buffer for query, editing, etc. needs to be shown, how
        -- this plugin would create a window for it.
        ---@type mongo.ResultSplitStyle
        split_style = buffer_const.ResultSplitStyle.Tab,
    },

    result_buffer = {
        -- How this plugin would create a new result window.
        -- This will be default value for new buffer.
        ---@type mongo.ResultSplitStyle
        split_style = buffer_const.ResultSplitStyle.Vertical,

        -- When this plugin should create a new result buffer.
        -- This will be default value for new buffer.
        ---@type mongo.CreateBufferStyle
        create_buffer_style = buffer_const.CreateBufferStyle.OnNeed,
    },
}

return M
