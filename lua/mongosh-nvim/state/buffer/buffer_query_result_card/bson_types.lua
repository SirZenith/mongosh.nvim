local buffer_const = require "mongosh-nvim.constant.buffer"
local config = require "mongosh-nvim.config"
local hl_const = require "mongosh-nvim.constant.highlight"
local str_util = require "mongosh-nvim.util.str"

local card_util = require "mongosh-nvim.state.buffer.buffer_query_result_card.util"

local ValueType = buffer_const.BSONValueType
local HLGroup = hl_const.HighlightGroup

local get_key_hl_by_indent_level = card_util.get_key_hl_by_indent_level

local M = {}

---@class mongo.buffer.ValueTypeMeta
---@field display_name string
---@field write? fun(value: any, builder: mongo.highlight.HighlightBuilder, indent_level: integer)
---@field edit_type? string # edit input value type description
---@field edit_default_value? fun(value: any): string # default value used in input box.
---@field edit? fun(value: string): string?, string? # edit input value converter, returns error message and serialized JSON text for value.

---@param value string
---@param int_key string
---@param float_key string
---@returns string? err
---@returns string? json_str
local function int_value_serialize(value, int_key, float_key)
    local num = tonumber(value)
    if not num then
        return "invalid number string", nil
    end

    local key = int_key
    if num ~= math.floor(num) then
        key = float_key
    end

    return nil, ("{ %s: %q }"):format(key, value)
end

---@type table<mongo.BSONValueType, mongo.buffer.ValueTypeMeta>
M.VALUE_TYPE_NAME_MAP = {
    -- ------------------------------------------------------------------------
    -- plain value
    [ValueType.Unknown] = {
        display_name = "???",
        write = function(_, builder)
            builder:write("---", HLGroup.ValueUnknown)
        end,
        edit_type = "raw JSON",
        edit = function(value)
            return nil, value
        end,
    },
    [ValueType.Boolean] = {
        display_name = "bool",
        write = function(value, builder)
            builder:write(tostring(value), HLGroup.ValueBoolean)
        end,
        edit_type = "boolean",
        edit_default_value = function(value)
            return value and "true" or "false"
        end,
        edit = function(value)
            value = value:lower()
            if value == "true" then
                return nil, value
            elseif value == "false" then
                return nil, value
            end
            return "invalid bool string", nil
        end,
    },
    [ValueType.Null] = {
        display_name = "null",
        write = function(_, builder)
            -- vim.NIL
            builder:write("null", HLGroup.ValueNull)
        end,
        edit_type = "raw JSON",
        edit_default_value = function()
            return "null"
        end,
        edit = function(value)
            return nil, value
        end,
    },
    [ValueType.Number] = {
        display_name = "num",
        write = function(value, builder)
            builder:write(tostring(value), HLGroup.ValueNumber)
        end,
        edit_type = "number",
        edit_default_value = function(value)
            return tostring(value)
        end,
        edit = function(value)
            local num = tonumber(value)
            if not num then
                return "invalid number string", nil
            end
            return nil, value
        end,
    },
    [ValueType.String] = {
        display_name = "str",
        write = function(value, builder)
            local quoted = ("%q"):format(value)
            builder:write(quoted, HLGroup.ValueString)
        end,
        edit_type = "string",
        edit_default_value = function(value)
            return value
        end,
        edit = function(value)
            return nil, vim.json.encode(value)
        end,
    },
    -- ------------------------------------------------------------------------
    -- BSON value
    [ValueType.Array] = {
        display_name = "arr",
        edit_type = "raw JSON",
        edit = function(value)
            return nil, value
        end,
    },
    [ValueType.Binary] = {
        display_name = "bin",
        write = function(_, builder, indent_level)
            local hl_group = get_key_hl_by_indent_level(indent_level)
            builder:write("bin", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write("...", HLGroup.ValueOmited)
            builder:write(")", hl_group)
        end,
    },
    [ValueType.Code] = {
        display_name = "code",
        write = function(_, builder, indent_level)
            local hl_group = get_key_hl_by_indent_level(indent_level)

            builder:write("code", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write("...", HLGroup.ValueOmited)
            builder:write(")", hl_group)
        end,
    },
    [ValueType.Date] = {
        display_name = "date",
        write = function(value, builder, indent_level)
            local hl_group = get_key_hl_by_indent_level(indent_level)
            local date_value = value["$date"]
            date_value = date_value["$numberLong"] or date_value

            builder:write("date", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write(date_value, HLGroup.ValueString)
            builder:write(")", hl_group)
        end,
        edit_type = "date string",
        edit = function(value)
            return nil, ("{ $date: %q }"):format(value)
        end,
    },
    [ValueType.Decimal] = {
        display_name = "i128",
        write = function(value, builder)
            builder:write(value["$numberDecimal"], HLGroup.ValueNumber)
        end,
        edit_type = "number",
        edit_default_value = function(value)
            return value["$numberDecimal"]
        end,
        edit = function(value)
            return int_value_serialize(value, "$numberDecimal", "$numberDouble")
        end,
    },
    [ValueType.Double] = {
        display_name = "f64",
        write = function(value, builder)
            builder:write(value["$numberDouble"], HLGroup.ValueNumber)
        end,
        edit_type = "number",
        edit_default_value = function(value)
            return value["$numberDouble"]
        end,
        edit = function(value)
            local num = tonumber(value)
            if not num then
                return "invalid number string", nil
            end
            return nil, ("{ $numberDouble: %q }"):format(value)
        end,
    },
    [ValueType.Int32] = {
        display_name = "i32",
        write = function(value, builder)
            builder:write(value["$numberInt"], HLGroup.ValueNumber)
        end,
        edit_type = "number",
        edit_default_value = function(value)
            return value["$numberInt"]
        end,
        edit = function(value)
            return int_value_serialize(value, "$numberInt", "$numberDouble")
        end,
    },
    [ValueType.Int64] = {
        display_name = "i64",
        write = function(value, builder)
            builder:write(value["$numberLong"], HLGroup.ValueNumber)
        end,
        edit_type = "number",
        edit_default_value = function(value)
            return value["$numberLong"]
        end,
        edit = function(value)
            return int_value_serialize(value, "$numberLong", "$numberDouble")
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
        edit_type = "number",
        edit_default_value = function(value)
            return tostring(value["$maxKey"])
        end,
        edit = function(value)
            local num = tonumber(value)
            if not num then
                return "invalid number string", nil
            end
            return nil, ("{ $maxKey: %d }"):format(value)
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
        edit_type = "number",
        edit_default_value = function(value)
            return tostring(value["$maxKey"])
        end,
        edit = function(value)
            local num = tonumber(value)
            if not num then
                return "invalid number string", nil
            end
            return nil, ("{ $minKey: %d }"):format(value)
        end,
    },
    [ValueType.Object] = {
        display_name = "obj",
        edit_type = "raw JSON",
        edit = function(value)
            return nil, value
        end,
    },
    [ValueType.ObjectID] = {
        display_name = "oid",
        write = function(value, builder, indent_level)
            local hl_group = get_key_hl_by_indent_level(indent_level)
            local id = ("%q"):format(value["$oid"])

            builder:write("ObjectID", HLGroup.ValueObject)
            builder:write("(", hl_group)
            builder:write(id, HLGroup.ValueString)
            builder:write(")", hl_group)
        end,
    },
    [ValueType.Regex] = {
        display_name = "regx",
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

M.MAX_TYPE_NAME_LEN = 0
for _, meta in pairs(M.VALUE_TYPE_NAME_MAP) do
    local len = meta.display_name:len()
    if len > M.MAX_TYPE_NAME_LEN then
        M.MAX_TYPE_NAME_LEN = len
    end
end

---@type table<string, mongo.BSONValueType>
M.COMPOSED_TYPE_IDENT_KEY = {
    ["$binary"] = ValueType.Binary,
    ["$code"] = ValueType.Code,
    ["$date"] = ValueType.Date,
    ["$numberDecimal"] = ValueType.Decimal,
    ["$numberDouble"] = ValueType.Double,
    ["$numberInt"] = ValueType.Int32,
    ["$numberLong"] = ValueType.Int64,
    ["$maxKey"] = ValueType.MaxKey,
    ["$minKey"] = ValueType.MinKey,
    ["$oid"] = ValueType.ObjectID,
    ["$regularExpression"] = ValueType.Regex,
    ["$timestamp"] = ValueType.Timestamp,
}

---@tyep table<string, mongo.BSONValueType>
M.SIMPLE_TYPE_MAP = {
    userdata = ValueType.Null,
    boolean = ValueType.Boolean,
    number = ValueType.Numberst,
    string = ValueType.String,
}

---@param value_type string
---@return string
function M.get_type_display_name(value_type)
    local type_name = value_type
    local meta = M.VALUE_TYPE_NAME_MAP[type_name]
    type_name = meta and meta.display_name or type_name
    type_name = type_name and str_util.format_len(type_name, M.MAX_TYPE_NAME_LEN) or " - "

    local margin_width = config.card_view.type_name_right_margin
    if type(margin_width) == "number" and margin_width > 0 then
        type_name = type_name .. (" "):rep(margin_width)
    end

    return type_name
end

return M
