local buffer_const = require "mongosh-nvim.constant.buffer"

local BufferType = buffer_const.BufferType
local CreateBufferStyle = buffer_const.CreateBufferStyle
local ResultSplitStyle = buffer_const.ResultSplitStyle

local M = {}

M = {
    -- path to mongosh executable
    ---@type string
    executable = "mongosh",

    -- indent space count for document representation in query result, edit snippet, etc.
    ---@type integer
    indent_size = 4,

    connection = {
        -- default database address for connection
        ---@type string
        default_db_addr = "localhost:27017",

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
        split_style = ResultSplitStyle.Tab,

        -- Map for function to be call when a mongo buffer of certain type is
        -- created.
        -- This can be used to create custom keymap in new buffer.
        ---@type table<mongo.BufferType, fun(bufnr: integer)>
        on_create = {
            -- fallback operation for all buffer type with no on-create function.
            [BufferType.Unknown] = function(bufnr)
                local buffer_state = require "mongosh-nvim.state.buffer"

                -- 'build' buffer
                vim.keymap.set("n", "<A-b>", function()
                    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
                    if mbuf then
                        mbuf:write_result {}
                    end
                end, { buffer = bufnr })

                -- refresh buffer
                vim.keymap.set("n", "<A-r>", function()
                    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
                    if mbuf then
                        mbuf:refresh()
                    end
                end, { buffer = bufnr })
            end,
        },
    },

    result_buffer = {
        -- How this plugin would create a new result window.
        -- This will be default value for new buffer.
        ---@type mongo.ResultSplitStyle
        split_style = ResultSplitStyle.Vertical,

        -- Type-wise result window split style setting. Mongo buffers prefers
        -- using value in this map to do initialization if style for its type is
        -- found here.
        ---@type table<mongo.ResultSplitStyle, mongo.ResultSplitStyle>
        split_style_type_map = {
            [BufferType.QueryResult] = ResultSplitStyle.Tab,
        },

        -- When this plugin should create a new result buffer.
        -- This will be default value for new buffer.
        ---@type mongo.CreateBufferStyle
        create_buffer_style = CreateBufferStyle.OnNeed,

        -- Type-wise result buffer creation strategy. Mongo bufferrs prefers
        -- using value in this map to do initialization if style for its type is
        -- found here
        ---@type table<mongo.BufferType, mongo.CreateBufferStyle>
        create_buffer_style_type_map = {},
    },

    sidebar = {
        -- column width of sidebar
        ---@type integer
        width = 30,

        -- left padding size for nested content.
        ---@type integer
        padding = 4,

        symbol = {
            loading = {
                collection = " ",
            },
            expanded = {
                indicator = " ",
                host = "󰇄 ",
                database = " ",
                collection = "󱔘 ",
            },
            collapsed = {
                indicator = " ",
                host = "󰇄 ",
                database = " ",
                collection = "󱔗 ",
            },
        },
    },
}

return M
