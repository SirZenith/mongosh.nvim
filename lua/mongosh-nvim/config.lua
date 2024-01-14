local buffer_const = require "mongosh-nvim.constant.buffer"

local BufferType = buffer_const.BufferType
local CreateBufferStyle = buffer_const.CreateBufferStyle
local QueryResultStyle = buffer_const.QueryResultStyle
local ResultSplitStyle = buffer_const.ResultSplitStyle

local M = {}

M = {
    -- Path to mongosh executable
    ---@type string
    executable = "mongosh",

    -- Indent space count for document representation in query result, edit snippet, etc.
    ---@type integer
    indent_size = 4,

    connection = {
        -- Default database address for connection
        ---@type string
        default_db_addr = "localhost:27017",

        -- Names in this list won't be listed in available database list.
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

                -- 'build' buffer with visual range
                vim.keymap.set("v", "<A-b>", function()
                    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
                    if mbuf then
                        mbuf:write_result {
                            with_range = true,
                        }
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
            [BufferType.QueryResultCard] = ResultSplitStyle.Tab,
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

    query = {
        -- If set to `true`, used typed JSON for query result by default.
        ---@type boolean
        use_typed_query = false,

        -- What style of view should be used to display query result.
        ---@type mongo.QueryResultStyle
        result_style = QueryResultStyle.JSON,
    },

    sidebar = {
        -- Column width of sidebar
        ---@type integer
        width = 30,

        -- Left padding size for nested content.
        ---@type integer
        padding = 4,

        -- Symbol for indication different types of list elemnt.
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

    card_view = {
        -- Right margin between right side of type name and left edge of top
        -- level object cards.
        ---@type integer
        type_name_right_margin = 0,

        -- Tree entry indent size.
        ---@type integer
        indent_size = 4,

        -- Hex cololr code used by key name and bracket in different indent level.
        -- Level 0 uses first color, level 1 uses second one, and so on.
        ---@type string[]
        indent_colors = {},

        -- Appearance setting for Object Card
        card = {
            -- Minimum card display content width event when all cards' content
            -- are shorter.
            ---@type integer
            min_content_width = 0,

            -- Padding on both left and right side of top level object card
            -- representation.
            ---@type integer
            padding = 0,

            edge_char = {
                top = "─",
                right = "│",
                bottom = "─",
                left = "│",
            },

            corner_char = {
                top_left = "┌",
                top_right = "┐",
                bottom_right = "┘",
                bottom_left = "└",
            },
        },

        keybinding = {
            -- Keys for toggle expansion state of the entry under cursor.
            ---@type string[]
            toggle_expansion = { "<CR>", "<Tab>", "za" },

            -- Keys for initiate entry field editing.
            ---@type string[]
            edit_field = { "i" },
        },
    },
}

return M
