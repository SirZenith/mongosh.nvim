local str_util = require "mongosh-nvim.util.str"
local log = require "mongosh-nvim.log"

local M = {}

-- check_is_flag_arg checks is an argument string is a flag.
-- If yes, then flag stem will be returned. Otherwise, `nil` will be returned.
-- Examples:
--
-- - foo -> `nil`
-- - -foo -> foo
-- - --foo -> foo
-- - --foo=bar -> foo=bar
-- - --this-that -> this-that
---@param s string
---@return string?
local function check_is_flag_arg(s)
    local flag_name
    if str_util.starts_with(s, "--") then
        flag_name = s:sub(3)
    elseif str_util.starts_with(s, "-") then
        flag_name = s:sub(2)
    end

    return flag_name
end

-- consume_positional_arg consumes a positional argument in argument list, returns
-- next consume index and argument value.
---@param args string[]
---@param cur_index integer
---@return integer new_index
---@return string value
local function consume_positional_arg(args, cur_index)
    return cur_index + 1, args[cur_index]
end

-- consume_flag_arg consumes a flag argument in argument list, returns next consume
-- index and key, value of the flag.
-- If current is followed by another flag immediately, then current will be of
-- value `true` indicating is precense but with no actual value.
---@return integer new_index
---@return string key
---@return string | boolean value
local function consume_flag_arg(args, cur_index, flag_stem)
    local new_index = cur_index + 1
    local eq_st, eq_ed = flag_stem:find("=")

    local key, value
    if eq_st and eq_ed then
        key = flag_stem:sub(1, eq_st - 1)
        value = flag_stem:sub(eq_ed + 1)
    else
        key = flag_stem
        value = args[new_index]

        if not value or check_is_flag_arg(value) then
            value = true
        else
            new_index = new_index + 1
        end
    end

    return new_index, key, value
end

---@alias mongo.RawParsedArgs table<string | number, string | boolean | nil>

-- parsed_args takes f-args list and translate flags and positional args into Lua
-- table.
-- Flags will be translate into key-value pairs, positional will be translated
-- into numerically-keied element in table.
-- Example:
--
-- ```lua
-- args = { "-a", "b", "-c=d", "e" }
-- parsed_args = {
--     "e",
--     a = "b",
--     c = "d",
-- }
-- ```
---@param args string[]
---@return mongo.RawParsedArgs
local function parse_fargs(args)
    local parsed_args = {}

    local consume_index = 1
    local positional_index = 1
    local total_cnt = #args

    while consume_index <= total_cnt do
        local arg = args[consume_index]
        local flag_stem = check_is_flag_arg(arg)

        if not flag_stem then
            local value
            consume_index, value = consume_positional_arg(args, consume_index)
            parsed_args[positional_index] = value
            positional_index = positional_index + 1
        else
            local key, value
            consume_index, key, value = consume_flag_arg(args, consume_index, flag_stem)
            parsed_args[key] = value
        end
    end

    return parsed_args
end

-- ----------------------------------------------------------------------------
-- Completion

-- flag_completion is a simple completion function for command flags.
---@param flag_list string[] # e.g. { "-a", "--bar" }
---@param arg_lead string
---@param cmd_line string
---@return string[]
local function flag_completion(flag_list, arg_lead, cmd_line, _)
    local result = {}

    for _, flag in ipairs(flag_list) do
        local is_picked = false

        if arg_lead == "-" then
            is_picked = flag:sub(1, 1) == "-" and flag:sub(1, 2) ~= "--"
        elseif arg_lead == "--" then
            is_picked = flag:sub(1, 2) == "--"
        else
            is_picked = str_util.starts_with(flag, arg_lead)
            is_picked = is_picked and cmd_line:find(flag) == nil
        end

        if is_picked then
            result[#result + 1] = flag
        end
    end

    return result
end

---@param arg_list mongo.CommandArg[]
---@return fun(arg_lead: string, cmd_line, string, cursor_pos: integer): string[]
local function flag_completor_maker(arg_list)
    local flag_list = {}
    for _, arg in ipairs(arg_list) do
        local is_flag = arg.is_flag
        local long = arg.name
        local short = arg.short

        if is_flag and long then
            flag_list[#flag_list + 1] = "--" .. long
        end

        if is_flag and short then
            flag_list[#flag_list + 1] = "-" .. short
        end
    end

    return function(arg_lead, cmd_line, cursor_pos)
        return flag_completion(flag_list, arg_lead, cmd_line, cursor_pos)
    end
end

-- ----------------------------------------------------------------------------

---@alias mongo.CommandArgType
---| "number"
---| "string"
---| "boolean"

---@type table<mongo.CommandArgType, fun(value: string | boolean): any | nil>
local arg_value_converter_map = {
    number = function(value)
        return type(value) == "string" and tonumber(value) or 0
    end,
    string = function(value)
        return type(value) == "string" and value or ""
    end,
    boolean = function(value)
        if not value then return false end

        if type(value) == "string" then
            if value == "0"
                or value:len() == 0
                or value:lower() == "false"
            then
                return false
            end
        end

        return true
    end,
}

---@class mongo.CommandArg
---@field name string
---@field short? string
---@field is_flag? boolean # indicating an argument is used as flag
---@field is_list? boolean # indicating a positional argument matches multiple value, and implies type `string[]`, can't be used with `is_flag`.
---@field type? mongo.CommandArgType
---@field default? any
---@field required? boolean

---@alias mongo.CommandActionCallback fun(args: table<string, any>, orig_args: table, unused_args: mongo.RawParsedArgs)

---@class mongo.Command
---@field name string
---@field range boolean # Does the command support range.
---@field buffer? number # If `buffer` has non `nil` value, command will be local to buffer.
---@field no_unused_warning? boolean # if `ture`, unused argument warnning will be ignored
--
---@field action mongo.CommandActionCallback
---@field arg_list mongo.CommandArg[]
local Command = {}
Command.__index = Command

---@return mongo.Command
function Command:new(args)
    local obj = setmetatable({}, self)

    obj.name = args.name or ""
    obj.range = args.range or false
    obj.no_unused_warning = args.no_unused_warning

    obj.action = args.action or function() end

    local arg_list = args.arg_list
    obj.arg_list = arg_list and vim.deepcopy(args.arg_list) or {}

    return obj
end

-- _extract_arg takes value out of parsed argument table.
-- This function modifies `raw_parsed`, argument key extracted will be removed
-- from `raw_parsed`.
---@param raw_parsed table<string | number, string | boolean | nil>
---@param arg_spec mongo.CommandArg
---@return string? err
---@return any value
---@return integer new_pos_index
function Command:_extract_arg(raw_parsed, arg_spec, cur_pos_index)
    local err

    local is_flag = arg_spec.is_flag
    local value
    if is_flag then
        local long = arg_spec.name
        if long then
            value = raw_parsed[long]
            raw_parsed[long] = nil
        end

        local short = arg_spec.short
        if short then
            value = value or raw_parsed[short]
            raw_parsed[short] = nil
        end
    elseif arg_spec.is_list then
        value = {}
        cur_pos_index = cur_pos_index + 1
        local end_pos = #raw_parsed

        for i = cur_pos_index, end_pos do
            value[#value + 1] = raw_parsed[i]
            raw_parsed[i] = nil
        end

        cur_pos_index = end_pos
    else
        cur_pos_index = cur_pos_index + 1
        value = raw_parsed[cur_pos_index]
        raw_parsed[cur_pos_index] = nil
    end

    -- check required
    if arg_spec.required and value == nil then
        if is_flag then
            err = "flag `" .. arg_spec.name .. "` is required"
        else
            err = ("positional argument #%d `%s` is required"):format(
                cur_pos_index, arg_spec.name
            )
        end
    end

    if type(value) == "table" then
        -- pass
    elseif value ~= nil then
        local arg_type = arg_spec.type or "string"
        local converter = arg_value_converter_map[arg_type]
        value = converter and converter(value) or value
    else
        value = arg_spec.default
    end

    return err, value, cur_pos_index
end

-- _check_unused_args is used after _extract_arg to generate prompt message for
-- all unused arguments left in `raw_parsed`.
---@param raw_parsed table<string | number, string | boolean | nil>
---@return string? msg
function Command:_check_unused_args(raw_parsed)
    local positional_list = {} ---@type number[]
    local flag_list = {} ---@type string[]

    for key in pairs(raw_parsed) do
        local key_t = type(key)
        if key_t == "string" then
            flag_list[#flag_list + 1] = key
        elseif key_t == "number" then
            positional_list[#positional_list + 1] = key
        end
    end

    local msg = {}

    if #positional_list > 0 then
        table.sort(positional_list)
        msg[#msg + 1] = "Unused positional argument(s): #" .. table.concat(positional_list, ", #")
    end

    if #flag_list > 0 then
        table.sort(flag_list)
        msg[#msg + 1] = "Unused flag(s): " .. table.concat(flag_list, ", ")
    end

    return #msg > 0 and table.concat(msg, "\n") or nil
end

-- _make_command_callback generates a uesr command callback with command's
-- argument list and action.
function Command:_make_command_callback()
    return function(args)
        local raw_parsed = parse_fargs(args.fargs)
        local parsed_args = {}

        local pos_index, err = 0, nil
        for _, arg in ipairs(self.arg_list) do
            local value
            err, value, pos_index = self:_extract_arg(raw_parsed, arg, pos_index)

            if err then break end

            local key = arg.name:gsub("%-", "_")
            parsed_args[key] = value
        end

        if err then
            log.warn(err)
            return
        end

        local unused_args = raw_parsed
        if not self.no_unused_warning then
            local unused_value_msg = self:_check_unused_args(unused_args)
            if unused_value_msg then
                log.info(unused_value_msg)
            end
        end

        self.action(parsed_args, args, unused_args)
    end
end

function Command:register()
    if self.name:len() == 0 then return end

    local flag_cnt, pos_cnt = 0, 0
    for _, arg in ipairs(self.arg_list) do
        if arg.is_flag then
            flag_cnt = flag_cnt + 1
        else
            pos_cnt = pos_cnt + 1
        end
    end

    local arg_cnt = flag_cnt + pos_cnt
    local nargs
    if flag_cnt > 0 then
        nargs = "*"
    elseif pos_cnt > 1 then
        nargs = "*"
    elseif pos_cnt == 1 then
        nargs = "1"
    end

    local options = {
        range = self.range,
        nargs = nargs,
        complete = arg_cnt > 0 and flag_completor_maker(self.arg_list) or nil,
    }

    local callback = self:_make_command_callback()

    local buffer = self.buffer
    if buffer then
        vim.api.nvim_buf_create_user_command(buffer, self.name, callback, options)
    else
        vim.api.nvim_create_user_command(self.name, callback, options)
    end
end

-- ----------------------------------------------------------------------------

---@class mongo.CommandCreationArg
---@field name string
---@field range? boolean
---@field buffer? number
---@field no_unused_warning? boolean
--
---@field arg_list? mongo.CommandArg[]
---@field action mongo.CommandActionCallback

---@param args mongo.CommandCreationArg
---@return mongo.Command
function M.new_cmd(args)
    return Command:new(args)
end

---@param args mongo.CommandCreationArg
function M.register_cmd(args)
    local cmd = M.new_cmd(args)
    cmd:register()
end

return M
