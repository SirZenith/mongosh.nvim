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
---@param start_index integer
---@return mongo.RawParsedArgs
local function parse_fargs(args, start_index)
    local parsed_args = {}

    local consume_index = start_index
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
---@field is_dummy? boolean # indicating an argument does not consume command line text, only serve as completion item.
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
---@field available_checker? fun(): boolean
---@field arg_list mongo.CommandArg[]
---@field _subcommands table<string, mongo.Command>
local Command = {}
Command.__index = Command

---@return mongo.Command
function Command:new(args)
    local obj = setmetatable({}, self)

    obj.name = args.name or ""
    obj.range = args.range or false
    obj.no_unused_warning = args.no_unused_warning

    obj.action = args.action
    obj.available_checker = args.available_checker

    local arg_list = args.arg_list
    obj.arg_list = arg_list and vim.deepcopy(args.arg_list) or {}

    obj._subcommands = {}

    return obj
end

-- add_sub_cmd adds all commands in list as subcommand.
---@param commands mongo.Command[]
function Command:add_sub_cmd(commands)
    for _, cmd in ipairs(commands) do
        local name = cmd.name

        local old_cmd = self:_get_sub_cmd(name)
        if old_cmd then
            log.warn("duplicated command name: " .. name)
        else
            self._subcommands[name] = cmd
        end
    end
end

-- _get_sub_cmd searchs subcommand with given name.
---@param name string
---@return mongo.Command?
function Command:_get_sub_cmd(name)
    return self._subcommands[name]
end

-- _redirect_to_sub_cmd_by_args searchs for proper subcommand to handle input
-- arugment list.
-- Returns target subcommand and index to first unhandled argument left in list.
---@param cur_index integer # index of first unhandled argument
---@return mongo.Command
---@return integer new_index
function Command:_redirect_to_sub_cmd_by_args(args, cur_index)
    local first_arg = args[cur_index]
    if not first_arg or check_is_flag_arg(first_arg) then
        return self, cur_index
    end

    local subcmd = self:_get_sub_cmd(first_arg)
    if not subcmd then
        return self, cur_index
    end

    return subcmd:_redirect_to_sub_cmd_by_args(args, cur_index + 1)
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
    if arg_spec.is_dummy then
        -- ignored
    elseif is_flag then
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
    if not arg_spec.is_dummy and arg_spec.required and value == nil then
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

-- _parse_args converts list of string into argument table suitable for calling
-- command action.
---@param args string[] # argument list
---@param cur_index integer # index of first unhandled argument
---@return string? err
---@return table<string, any> parsed_args
---@return mongo.RawParsedArgs unused_args
function Command:_parse_args(args, cur_index)
    local raw_parsed = parse_fargs(args, cur_index)
    local parsed_args = {}

    local pos_index, err = 0, nil
    for _, arg in ipairs(self.arg_list) do
        local value
        err, value, pos_index = self:_extract_arg(raw_parsed, arg, pos_index)

        if err then break end

        local key = arg.name:gsub("%-", "_")
        parsed_args[key] = value
    end

    local unused_args = raw_parsed

    if err then
        return err, parsed_args, unused_args
    end

    if not self.no_unused_warning then
        local unused_value_msg = self:_check_unused_args(unused_args)
        if unused_value_msg then
            log.info(unused_value_msg)
        end
    end

    return nil, parsed_args, unused_args
end

-- _run_as_user_command can be used in user command callback, takes user commnd
-- argument table, runs command action.
---@param args table
function Command:_run_as_user_command(args)
    local fargs = args.fargs
    local cmd, cur_index = self:_redirect_to_sub_cmd_by_args(fargs, 1)

    local action = cmd.action
    if type(action) ~= "function" then return end

    local err, parsed_args, unused_args = cmd:_parse_args(fargs, cur_index)
    if err then
        log.warn(err)
    else
        action(parsed_args, args, unused_args)
    end
end

---@param arg_lead string
---@return string[]
function Command:_complete_subcmd(arg_lead)
    local result = {}

    for name, cmd in pairs(self._subcommands) do
        local is_match = arg_lead:len() == 0 or str_util.starts_with(name, arg_lead)
        local is_available = not cmd.available_checker or cmd.available_checker()

        if is_match and is_available then
            result[#result + 1] = name
        end
    end

    table.sort(result)

    return result
end

---@param arg_lead string
---@param cmd_line string
---@return string[]
function Command:_complete_flags(arg_lead, cmd_line)
    local result = {}

    local is_long_flag = arg_lead:sub(1, 2) == "--"
    local is_short_flag = not is_long_flag and arg_lead:sub(1, 1) == "-"
    if not is_long_flag and not is_short_flag then
        return result
    end

    for _, arg in ipairs(self.arg_list) do
        local flag
        if not arg.is_flag then
            -- pass
        elseif is_long_flag then
            flag = "--" .. arg.name
        else
            flag = arg.short and "-" .. arg.short
        end

        local is_picked = flag ~= nil
            and str_util.starts_with(flag, arg_lead)
            and cmd_line:find(flag) == nil

        if is_picked then
            result[#result + 1] = flag
        end
    end

    table.sort(result)

    return result
end

---@param arg_lead string
---@param cmd_line string
---@return string[]
function Command:_cmd_completion(arg_lead, cmd_line)
    local parts = vim.split(cmd_line, "%s")
    local cmd = self:_redirect_to_sub_cmd_by_args(parts, 2)

    local result = {}

    vim.list_extend(result, cmd:_complete_subcmd(arg_lead))

    vim.list_extend(result, cmd:_complete_flags(arg_lead, cmd_line))

    return result
end

-- _get_cmd_narg returns command-nargs value of current command.
---@return string | number
function Command:_get_cmd_nargs()
    local subcmd_empty = true
    for _ in pairs(self._subcommands) do
        subcmd_empty = false
        break
    end

    if not subcmd_empty then
        return "*"
    end

    local flag_cnt, pos_cnt = 0, 0
    local has_required_positional = false
    for _, arg in ipairs(self.arg_list) do
        if arg.is_flag then
            flag_cnt = flag_cnt + 1
        else
            pos_cnt = pos_cnt + 1

            if arg.required then
                has_required_positional = true
            end
        end
    end

    local nargs
    if flag_cnt + pos_cnt == 0 then
        nargs = 0
    elseif flag_cnt > 0 then
        nargs = "*"
    elseif pos_cnt > 1 then
        nargs = "*"
    elseif pos_cnt == 1 then
        nargs = has_required_positional and 1 or "?"
    end

    return nargs
end

function Command:register()
    if self.name:len() == 0 then return end

    local nargs = self:_get_cmd_nargs()
    local complete
    if nargs and nargs ~= 0 then
        complete = function(arg_lead, cmd_line)
            return self:_cmd_completion(arg_lead, cmd_line)
        end
    end

    local options = {
        range = self.range,
        nargs = nargs,
        complete = complete,
    }

    local callback = function(args)
        self:_run_as_user_command(args)
    end

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
---@field action? mongo.CommandActionCallback
---@field available_checker? fun(): boolean
--
---@field parent? mongo.Command

---@param args mongo.CommandCreationArg
---@return mongo.Command
function M.new_cmd(args)
    local cmd = Command:new(args)

    local parent = args.parent
    if parent then
        parent:add_sub_cmd { cmd }
    end

    return cmd
end

---@param args mongo.CommandCreationArg
function M.register_cmd(args)
    local cmd = M.new_cmd(args)
    cmd:register()
end

return M
