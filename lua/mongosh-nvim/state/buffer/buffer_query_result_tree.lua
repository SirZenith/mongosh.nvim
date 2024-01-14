local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local config = require "mongosh-nvim.config"
local hl_const = require "mongosh-nvim.constant.highlight"
local buffer_util = require "mongosh-nvim.util.buffer"
local hl_util = require "mongosh-nvim.util.highlight"
local str_util = require "mongosh-nvim.util.str"

local ValueType = buffer_const.BSONValueType
local HLGroup = hl_const.HighlightGroup

-- ----------------------------------------------------------------------------

local cached_highlight_group = {}

-- Setup highlight group for indented keys.
local function generate_indent_hl_groups()
    for i, color in pairs(config.tree_view.indent_colors) do
        local group_name = HLGroup.TreeIndented .. "_" .. tostring(i)
        vim.api.nvim_set_hl(0, group_name, { fg = color })
        cached_highlight_group[i] = group_name
    end
end

-- Get highlight group for keys at given indent level.
---@param indent_level integer
---@return string hl_group
local function get_key_hl_by_indent_level(indent_level)
    local color_cnt = #config.tree_view.indent_colors
    if #cached_highlight_group ~= color_cnt then
        generate_indent_hl_groups()
    end

    local color_index = (indent_level % color_cnt) + 1

    return cached_highlight_group[color_index] or HLGroup.TreeNormal
end

-- ----------------------------------------------------------------------------

---@class mongo.buffer.ValueTypeMeta
---@field display_name string
---@field write? fun(value: any, builder: mongo.highlight.HighlightBuilder, indent_level: integer)

---@type table<mongo.BSONValueType, mongo.buffer.ValueTypeMeta>
local VALUE_TYPE_NAME_MAP = {
    -- ------------------------------------------------------------------------
    -- plain value
    [ValueType.Unknown] = {
        display_name = "???",
        write = function(_, builder)
            builder:write("---", HLGroup.ValueUnknown)
        end,
    },
    [ValueType.Boolean] = {
        display_name = "bool",
        write = function(value, builder)
            builder:write(tostring(value), HLGroup.ValueBoolean)
        end
    },
    [ValueType.Null] = {
        display_name = "null",
        write = function(_, builder)
            -- vim.NIL
            builder:write("null", HLGroup.ValueNull)
        end
    },
    [ValueType.Number] = {
        display_name = "num",
        write = function(value, builder)
            builder:write(tostring(value), HLGroup.ValueNumber)
        end
    },
    [ValueType.String] = {
        display_name = "str",
        write = function(value, builder)
            local quoted = ("%q"):format(value)
            builder:write(quoted, HLGroup.ValueString)
        end
    },
    -- ------------------------------------------------------------------------
    -- BSON value
    [ValueType.Array] = {
        display_name = "arr",
    },
    [ValueType.Binary] = {
        display_name = "bin",
        write = function(_, builder, indent_level)
            local hl_group = get_key_hl_by_indent_level(indent_level)
            builder:write("bin", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write("...", HLGroup.ValueOmited)
            builder:write(")", hl_group)
        end
    },
    [ValueType.Code] = {
        display_name = "code",
        write = function(_, builder, indent_level)
            local hl_group = get_key_hl_by_indent_level(indent_level)

            builder:write("code", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write("...", HLGroup.ValueOmited)
            builder:write(")", hl_group)
        end
    },
    [ValueType.Date] = {
        display_name = "date",
        write = function(value, builder, indent_level)
            vim.print(value)
            local hl_group = get_key_hl_by_indent_level(indent_level)
            local date_value = value["$date"]
            date_value = date_value["$numberLong"] or date_value

            builder:write("date", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write(date_value, HLGroup.ValueString)
            builder:write(")", hl_group)
        end
    },
    [ValueType.Decimal] = {
        display_name = "i128",
        write = function(value, builder)
            builder:write(value["$numberDecimal"], HLGroup.ValueNumber)
        end,
    },
    [ValueType.Int32] = {
        display_name = "i32",
        write = function(value, builder)
            builder:write(value["$numberInt"], HLGroup.ValueNumber)
        end,
    },
    [ValueType.Int64] = {
        display_name = "i64",
        write = function(value, builder)
            builder:write(value["$numberLong"], HLGroup.ValueNumber)
        end,
    },
    [ValueType.MaxKey] = {
        display_name = "kMax",
        write = function(value, builder, indent_level)
            local hl_group = get_key_hl_by_indent_level(indent_level)
            local key = value["$maxKey"]

            builder:write("maxKey", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write(tostring(key), HLGroup.ValueNumber)
            builder:write(")", hl_group)
        end,
    },
    [ValueType.MinKey] = {
        display_name = "kMin",
        write = function(value, builder, indent_level)
            local hl_group = get_key_hl_by_indent_level(indent_level)
            local key = value["$minKey"]

            builder:write("minKey", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write(tostring(key), HLGroup.ValueNumber)
            builder:write(")", hl_group)
        end,
    },
    [ValueType.Object] = {
        display_name = "obj",
    },
    [ValueType.Regex] = {
        display_name = "re",
        write = function(value, builder)
            local pattern = value["$regularExpression"].pattern
            builder:write("/" .. pattern .. "/", HLGroup.ValueRegex)
        end,
    },
    [ValueType.Timestamp] = {
        display_name = "ts",
        write = function(value, builder, indent_level)
            local time = value["$timestamp"].t
            local hl_group = get_key_hl_by_indent_level(indent_level)

            builder:write("time", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write(tostring(time), HLGroup.ValueNumber)
            builder:write(")", hl_group)
        end,
    },
}

local MAX_TYPE_NAME_LEN = 0
for _, meta in pairs(VALUE_TYPE_NAME_MAP) do
    local len = meta.display_name:len()
    if len > MAX_TYPE_NAME_LEN then
        MAX_TYPE_NAME_LEN = len
    end
end

---@type table<string, mongo.BSONValueType>
local COMPOSED_TYPE_IDENT_KEY = {
    ["$binary"] = ValueType.Binary,
    ["$code"] = ValueType.Code,
    ["$date"] = ValueType.Date,
    ["$numberDecimal"] = ValueType.Decimal,
    ["$numberInt"] = ValueType.Int32,
    ["$numberLong"] = ValueType.Int64,
    ["$maxKey"] = ValueType.MaxKey,
    ["$minKey"] = ValueType.MinKey,
    ["$regularExpression"] = ValueType.Regex,
    ["$timestamp"] = ValueType.Timestamp,
}

---@tyep table<string, mongo.BSONValueType>
local SIMPLE_TYPE_MAP = {
    userdata = ValueType.Null,
    boolean = ValueType.Boolean,
    number = ValueType.Numberst,
    string = ValueType.String,
}

---@param indent_level integer
---@param including_type_name_width? boolean # set this to `true` for lines not preceding by value type name
---@return string
local function get_indent_str_by_indent_level(indent_level, including_type_name_width)
    local indent_width = config.tree_view.type_name_padding + config.tree_view.indent_size * indent_level
    if including_type_name_width then
        indent_width = indent_width + MAX_TYPE_NAME_LEN
    end
    return (" "):rep(indent_width)
end

-- ----------------------------------------------------------------------------

---@class mongo.buffer.TreeHLItem
---@field name string
---@field st integer # stating column index, 0-base
---@field ed integer # ending column index, 0-base, exclusive

---@class mongo.buffer.TreeViemWriteInfo
---@field line string
---@field hl_items mongo.higlight.HLItem[]

---@alias mongo.buffer.TreeNestingType
---| "object"
---| "array"
---| "none"

---@param type string
---@return string
local function get_type_display_name(type)
    local type_name = type
    local meta = VALUE_TYPE_NAME_MAP[type_name]
    type_name = meta and meta.display_name or type_name
    type_name = type_name and str_util.format_len(type_name, MAX_TYPE_NAME_LEN) or " - "
    return type_name
end

-- ----------------------------------------------------------------------------

---@class mongo.buffer.TreeViewItem
---@field value? any
---@field type string
--
---@field is_top_level boolean # whether current item is tree view root
---@field children? table<number | string, mongo.buffer.TreeViewItem>
---@field child_table_type mongo.buffer.TreeNestingType
--
---@field expanded boolean
---@field st_row integer # 1-base beginning row number of display range
---@field ed_row integer # 1-base ending row number of display range
local TreeViewItem = {}
TreeViewItem.__index = TreeViewItem

---@param value any
---@return mongo.buffer.TreeViewItem
function TreeViewItem:new(value)
    local obj = setmetatable({}, self)

    self.expanded = false
    self.st_row = 0
    self.ed_row = 0

    obj:update_binded_value(value)

    return obj
end

---@param value any
function TreeViewItem:update_binded_value(value)
    self.child_table_type = "none"

    self.value = value
    self.type = ValueType.Unknown

    local value_t = type(value)
    if value_t ~= "table" then
        -- simple type
        self.type = SIMPLE_TYPE_MAP[value_t] or ValueType.Unknown
        if self.type == ValueType.Unknown then
            self.value = nil
        end
    else
        -- BSON type
        for key, type_name in pairs(COMPOSED_TYPE_IDENT_KEY) do
            if value[key] then
                self.type = type_name
                break
            end
        end

        if self.type == ValueType.Unknown then
            -- array or object value
            local children = self.children
            if not children then
                children = {}
                self.children = children
            end

            for k, v in pairs(value) do
                local child = children[k]
                if child then
                    child:update_binded_value(v)
                else
                    children[k] = TreeViewItem:new(v)
                end
            end

            self.value = nil
            self.child_table_type = self:get_nested_table_type()

            if self.child_table_type == "array" then
                self.type = ValueType.Array
            elseif self.child_table_type == "object" then
                self.type = ValueType.Object
            end
        end
    end
end

function TreeViewItem:toggle_expansion()
    self.expanded = not self.expanded
end

---@return mongo.buffer.TreeNestingType
function TreeViewItem:get_nested_table_type()
    local children = self.children
    if not children then return "none" end

    local cnt = 0
    for _ in pairs(children) do
        cnt = cnt + 1
    end

    if cnt == 0 then
        return "none"
    end

    local continous = true
    for i = 1, cnt do
        if children[i] == nil then
            continous = false
            break
        end
    end

    return continous and "array" or "object"
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
function TreeViewItem:write_simple_value(builder, indent_level)
    local meta = VALUE_TYPE_NAME_MAP[self.type]
    local write = meta and meta.write

    if write then
        write(self.value, builder, indent_level)
    else
        builder:write(tostring(self.value), HLGroup.TreeNormal)
    end
end

---@param builder mongo.highlight.HighlightBuilder
function TreeViewItem:write_collapsed_table(builder, indent_level)
    local nesting_type = self.child_table_type

    local lhs, rhs, digest = "<", ">", "?"
    if nesting_type == "array" then
        lhs, rhs, digest = "[", "]", "..."
    elseif nesting_type == "object" then
        lhs, rhs, digest = "{", "}", "..."
    end

    local key_hl_group = get_key_hl_by_indent_level(indent_level)
    builder:write(lhs, key_hl_group)
    builder:write(digest, HLGroup.ValueOmited)
    builder:write(rhs, key_hl_group)
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
function TreeViewItem:write_array_table(builder, indent_level)
    if self.is_top_level then
        indent_level = indent_level - 1
    else
        builder:write("[", get_key_hl_by_indent_level(indent_level))
        builder:new_line()
    end

    local indent_hl_group = get_key_hl_by_indent_level(indent_level)
    local dirty = false
    for i, item in ipairs(self.children) do
        dirty = true
        if i > 1 then
            builder:new_line()
        end

        local starting_edge = "│"
        local indent = get_indent_str_by_indent_level(indent_level + 1)
        if item.is_top_level and item.child_table_type ~= "none" then
            starting_edge = "┌"
            indent = ("─"):rep(indent:len())
        end

        builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)

        builder:write(starting_edge, indent_hl_group)
        builder:write(indent, indent_hl_group)
        item:write_to_builder(builder, indent_level + 1)
    end

    if not self.is_top_level then
        if dirty then
            builder:new_line()
            builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)
            builder:write("│", indent_hl_group)
            builder:write(get_indent_str_by_indent_level(indent_level), HLGroup.TreeNormal)
        end

        builder:write("]", get_key_hl_by_indent_level(indent_level))
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
function TreeViewItem:write_object_table(builder, indent_level)
    if self.is_top_level then
        builder:write(("─"):rep(25), get_key_hl_by_indent_level(indent_level))
    else
        builder:write(("{"), get_key_hl_by_indent_level(indent_level))
    end

    local indent_hl_group = get_key_hl_by_indent_level(indent_level)

    local dirty = false
    for key, item in pairs(self.children) do
        dirty = true
        builder:new_line()

        builder:write(get_type_display_name(item.type), HLGroup.ValueTypeName)
        builder:write("│", indent_hl_group)
        builder:write(get_indent_str_by_indent_level(indent_level + 1), HLGroup.TreeNormal)
        builder:write(tostring(key), indent_hl_group)
        builder:write(": ", HLGroup.TreeNormal)
        item:write_to_builder(builder, indent_level + 1)
    end

    if dirty then
        local ending_edge = "│"
        local indent = get_indent_str_by_indent_level(indent_level)
        if self.is_top_level then
            ending_edge = "└"
            indent = ("─"):rep(indent:len())
        end
        builder:new_line()
        builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)
        builder:write(ending_edge, indent_hl_group)
        builder:write(indent, indent_hl_group)
    end

    if self.is_top_level then
        builder:write(("─"):rep(25), get_key_hl_by_indent_level(indent_level))
    else
        builder:write(("}"), get_key_hl_by_indent_level(indent_level))
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
function TreeViewItem:write_table_value(builder, indent_level)
    local nesting_type = self.child_table_type

    if not self.expanded then
        self:write_collapsed_table(builder, indent_level)
    elseif nesting_type == "array" then
        self:write_array_table(builder, indent_level)
    elseif nesting_type == "object" then
        self:write_object_table(builder, indent_level)
    else
        builder:write("<lua-table>", HLGroup.ValueOmited)
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level? integer
function TreeViewItem:write_to_builder(builder, indent_level)
    indent_level = indent_level or 0

    self.st_row = builder:get_line_cnt()

    if self.children then
        self:write_table_value(builder, indent_level)
    else
        self:write_simple_value(builder, indent_level)
    end

    self.ed_row = builder:get_line_cnt()
end

---@param bufnr integer
function TreeViewItem:write_to_buffer(bufnr)
    local builder = hl_util.HighlightBuilder:new()
    self:write_to_builder(builder)

    local lines, hl_lines = builder:build()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    hl_util.add_hl_to_buffer(bufnr, 0, hl_lines)
end

---@parat_row integer # line number of cursor line, 1-base
---@return boolean updated
function TreeViewItem:on_selected(at_row)
    if at_row < self.st_row or at_row > self.ed_row then
        return false
    end

    local updated = false

    local children = self.children
    if children and self.expanded then
        for _, item in pairs(children) do
            updated = item:on_selected(at_row)

            if updated then
                break
            end
        end
    end

    if not updated and at_row == self.st_row then
        self:toggle_expansion()
        updated = true
    end

    return updated
end

-- ----------------------------------------------------------------------------

---@type mongo.MongoBufferOperationModule
local M = {}

---@param mbuf mongo.MongoBuffer
local function update_tree_view(mbuf, typed_json)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local tree_item = mbuf._state_args.tree_item ---@type mongo.buffer.TreeViewItem?
    if not tree_item then
        tree_item = TreeViewItem:new()
        mbuf._state_args.tree_item = tree_item

        tree_item.is_top_level = true
    end

    local value = vim.json.decode(typed_json)
    tree_item:update_binded_value(value)
    tree_item:write_to_buffer(bufnr)
end

function M.content_writer(mbuf, callback)
    local src_bufnr = mbuf._src_bufnr

    local src_lines = src_bufnr and buffer_util.read_lines_from_buf(src_bufnr)
    local snippet = src_lines
        and table.concat(src_lines)
        or mbuf._state_args.snippet

    if not snippet or snippet == "" then
        callback("no query is binded with current buffer")
        return
    end

    api_core.do_query_typed(snippet, function(err, response)
        if err then
            callback(err)
            return
        end

        update_tree_view(mbuf, response)

        callback()
    end)
end

function M.option_setter(mbuf)
    local bufnr = mbuf:get_bufnr()
    if not bufnr then return end

    local bo = vim.bo[bufnr]

    bo.bufhidden = "delete"
    bo.buflisted = false
    bo.buftype = "nofile"

    -- press <Cr> to select a collection
    vim.keymap.set("n", "<CR>", function()
        if not vim.api.nvim_buf_is_valid(bufnr)
            or not vim.api.nvim_buf_is_loaded(bufnr)
        then
            return
        end

        local tree_item = mbuf._state_args.tree_item ---@type mongo.buffer.TreeViewItem?
        if not tree_item then return end

        local pos = vim.api.nvim_win_get_cursor(0)
        local updated = tree_item:on_selected(pos[1])

        if updated then
            tree_item:write_to_buffer(bufnr)
        end
    end, { buffer = bufnr })
end

M.refresher = M.content_writer

return M
