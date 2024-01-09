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
-- - --this-that -> this_that
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
---@return integer new_index
---@return string key
---@return string value
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
        new_index = new_index + 1
    end

    return new_index, key, value
end

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
---@return table<string | number, string | nil>
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

-- validate_required_args checks if all required arguments have non-nil value.
---@param spec_list (string | nil)[][]
---@return string? err
local function validate_required_args(spec_list)
    local err

    for _, spec in ipairs(spec_list) do
        local value = spec[1]
        local msg = spec[2]
        if value == nil then
            err = msg
                and msg .. " is required"
                or "required value is missing"
            break
        end
    end

    return err
end

-- flag_completion is a simple completion function for command flags.
---@param flag_list string[] # e.g. { "-a", "--bar" }
---@param arg_lead string
---@return string[]
local function flag_completion(flag_list, arg_lead, _, _)
    local result = {}

    for _, flag in ipairs(flag_list) do
        local is_picked = false

        if arg_lead == "-" then
            is_picked = flag:sub(1, 1) == "-" and flag:sub(1, 2) ~= "--"
        elseif arg_lead == "--" then
            is_picked = flag:sub(1, 2) == "--"
        else
            is_picked = str_util.starts_with(flag, arg_lead)
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

---@class mongo.CommandArg
---@field name string
---@field short? string
---@field is_flag? boolean
---@field default? string
---@field required? boolean

---@alias mongo.CommandActionCallback fun(args: table<string, string | nil>, orig_args: table)

---@class mongo.Command
---@field name string
---@field range boolean # Does the command support range.
---@field buffer? number # If `buffer` has non `nil` value, command will be local to buffer.
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

    obj.action = args.action or function() end

    local arg_list = args.arg_list
    obj.arg_list = arg_list and vim.deepcopy(args.arg_list) or {}

    return obj
end

---@param raw_parsed table<string | number, string | nil>
---@param arg_spec mongo.CommandArg
---@return string? err
---@return string? value
---@return integer new_pos_index
function Command:_extract_arg(raw_parsed, arg_spec, cur_pos_index)
    local err
    local value = arg_spec.default

    local is_flag = arg_spec.is_flag
    if is_flag then
        value = raw_parsed[arg_spec.name] or raw_parsed[arg_spec.short] or value
    else
        cur_pos_index = cur_pos_index + 1
        value = raw_parsed[cur_pos_index] or value
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

    return err, value, cur_pos_index
end

function Command:make_command_callback()
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

        self.action(parsed_args, args)
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

    local callback = self:make_command_callback()

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
