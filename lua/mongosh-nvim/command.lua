local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"
local str_util = require "mongosh-nvim.util.str"

local api_core = require "mongosh-nvim.api.core"
local api_ui = require "mongosh-nvim.api.ui"

local cmd = vim.api.nvim_create_user_command

-- check_is_flag_arg checks is an argument string is a flag.
-- If yes, then flag stem will be returned. Otherwise, `nil` will be returned.
-- Examples:
--
-- - foo -> `nil`
-- - -foo -> foo
-- - --foo -> foo
-- - --foo=bar -> foo=bar
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
---@return table<string | number, string>
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

-- flag_completion is a simple completion function for command flags.
---@param flag_list string[] # e.g. { "-a", "--bar" }
---@param arg_lead string
---@return string[]
local function flag_completion(flag_list, arg_lead, _, _)
    local result = {}

    for _, flag in ipairs(flag_list) do
        if str_util.starts_with(flag, arg_lead) then
            result[#result + 1] = flag
        end
    end

    return result
end

---@param flag_name_list string[] # e.g. { "a", "bar" }
---@return fun(arg_lead: string, cmd_line, string, cursor_pos: integer): string[]
local function flag_completor_maker(flag_name_list)
    local flag_list = {}
    for _, name in ipairs(flag_name_list) do
        flag_list[#flag_list + 1] = "-" .. name
        flag_list[#flag_list + 1] = "--" .. name
    end

    return function(arg_lead, cmd_line, cursor_pos)
        return flag_completion(flag_list, arg_lead, cmd_line, cursor_pos)
    end
end

-- ----------------------------------------------------------------------------

cmd("MongoConnect", function(args)
    local parsed_args = parse_fargs(args.fargs)

    local host = parsed_args.host or config.connection.default_host
    local db = parsed_args.db or parsed_args[1]

    api_core.connect(host, function(ok)
        if not ok then return end

        if db then
            api_ui.select_database(db)
        else
            api_ui.select_database_ui()
        end
    end)
end, {
    nargs = "*",
    complete = flag_completor_maker { "host", "db" },
})

cmd("MongoDatabase", api_ui.select_database_ui, {})

cmd("MongoCollection", api_ui.select_collection_ui_buffer, {})

cmd("MongoExecute", function(args)
    api_ui.run_buffer_executation(
        vim.api.nvim_win_get_buf(0),
        {
            with_range = args.range ~= 0,
        }
    )
end, { range = true })

cmd("MongoNewQuery", api_ui.select_collection_ui_list, {})

cmd("MongoQuery", function(args)
    api_ui.run_buffer_query(
        vim.api.nvim_win_get_buf(0),
        {
            with_range = args.range ~= 0,
        }
    )
end, { range = true })

cmd("MongoNewEdit", function(args)
    local parsed_args = parse_fargs(args.fargs)

    local collection = parsed_args.collection or parsed_args.coll
    local id = parsed_args.id

    if collection == nil then
        log.warn("not collection name provided")
        return
    end

    if not nil then
        log.warn("no document id provided")
        return
    end

    api_ui.create_edit_buffer(collection, id)
end, {
    nargs = "*",
    complete = flag_completor_maker { "collection", "coll", "id" },
})

cmd("MongoEdit", function(args)
    api_ui.run_buffer_edit(
        vim.api.nvim_win_get_buf(0),
        {
            with_range = args.range ~= 0,
        }
    )
end, { range = true })

cmd("MongoRefresh", function()
    local bufnr = vim.api.nvim_win_get_buf(0)
    api_ui.refresh_buffer(bufnr)
end, {})
