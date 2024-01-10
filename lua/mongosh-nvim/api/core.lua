local config = require "mongosh-nvim.config"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local util = require "mongosh-nvim.util"
local str_util = require "mongosh-nvim.util.str"

local loop = vim.loop

local M = {}

-- try_append_flag appends flag-value pair to argument buffer list if value is
-- not `nil`.
---@param buffer string[]
---@param flag string
---@param value any
local function try_append_flag(buffer, flag, value)
    if value == nil then return end

    buffer[#buffer + 1] = flag
    buffer[#buffer + 1] = tostring(value)
end

-- ----------------------------------------------------------------------------

local cached_tmpfile_name = nil ---@type string | nil

-- save_tmp_script_file writes script snippet to temporary file before running.
---@param script string
---@param callback fun(tmpfile_name?: string)
function M.save_tmp_script_file(script, callback)
    util.save_to_tmpfile(script, cached_tmpfile_name, function(err, tmpfile_name)
        if not tmpfile_name then
            log.warn("failed to write snippet into temporary file: " .. err)
            return
        end

        cached_tmpfile_name = tmpfile_name
        callback(tmpfile_name)
    end)
end

-- get_connection_args returns basic argument, for example authentication info,
-- for current connection.
---@return string[]
function M.get_connection_args()
    local args = {}

    local raw_flag_map = mongosh_state.get_raw_flag_map()
    for flag, value in pairs(raw_flag_map) do
        args[#args + 1] = flag
        args[#args + 1] = value
    end

    try_append_flag(args, "--username", mongosh_state.get_username())
    try_append_flag(args, "--password", mongosh_state.get_password())

    return args
end

---@class mongo.RunCmdResult
---@field code number
---@field signal number
---@field stdout string
---@field stderr string

---@class mongo.RunCmdArgs
---@field args string[]
---@field callback fun(result: mongo.RunCmdResult) # callback for handling evaluation result.

---@class mongo.RunScriptArgs
---@field script string # script snippet string.
---@field db_address? string # database address for connection.
---@field callback fun(result: mongo.RunCmdResult) # callback for handling evaluation result.

-- call_mongosh calls mongosh executable with given arguments.
-- Command will be evaluated asynchronously.
---@param args mongo.RunCmdArgs
function M.call_mongosh(args)
    local executable = config.executable
    if not executable then
        args.callback {
            code = 1,
            signal = 0,
            stdout = "",
            stderr = "mongosh executable not found"
        }
        return
    end

    local stdout = loop.new_pipe()
    local stderr = loop.new_pipe()

    local out_buffer = {} ---@type string[]
    local err_buffer = {} ---@type string[]

    loop.spawn(
        executable,
        {
            args = args.args,
            stdio = { nil, stdout, stderr }
        },
        vim.schedule_wrap(function(code, signal)
            args.callback {
                code = code,
                signal = signal,
                stdout = table.concat(out_buffer),
                stderr = table.concat(err_buffer),
            }
        end)
    )

    loop.read_start(stdout, function(err, data)
        if err then return end
        out_buffer[#out_buffer + 1] = data
    end)

    loop.read_start(stderr, function(err, data)
        if err then return end
        err_buffer[#err_buffer + 1] = data
    end)
end

-- run_raw_script sends script snippet to last connected database collection if no
-- host is provided.
-- **Note**: Script content is sent to mongosh via command line directly. If snippet is too
-- long, this function might fail due to OS limitation.
---@param args mongo.RunScriptArgs
function M.run_raw_script(args)
    local address = args.db_address or mongosh_state.get_db_addr()
    local exe_args = M.get_connection_args();

    M.call_mongosh {
        args = vim.list_extend(exe_args, {
            "--quiet",
            "--eval",
            args.script,
            address,
        }),
        callback = args.callback,
    }
end

-- run_script takes script snippet and run it on last connected database collection
-- if no host is provide.
-- Before running the snippet, function will first write it to temporary file,
-- this is for avoiding limitation of maximum command line argument length.
---@param args mongo.RunScriptArgs
function M.run_script(args)
    local address = args.db_address or mongosh_state.get_db_addr()

    M.save_tmp_script_file(args.script, function(tmpfile_name)
        local exe_args = M.get_connection_args()

        M.call_mongosh {
            args = vim.list_extend(exe_args, {
                "--quiet",
                address,
                tmpfile_name
            }),
            callback = args.callback,
        }
    end)
end

-- ----------------------------------------------------------------------------

-- set_connection_flags_by_list treats every two arguments in input list as
-- flag-value pair, and sotre as raw connection flag.
-- Extra flag with no paired value takes no effect on internal flag sotrage.
---@param args string[]
function M.set_connection_flags_by_list(args)
    local len = #args

    if len == 0 then
        mongosh_state.clear_all_raw_flags()
        return
    end

    for i = 1, len, 2 do
        local flag, value = args[i], args[i + 1]
        if value ~= nil then
            mongosh_state.set_raw_flag(flag, value)
        end
    end
end

-- set_connection_flags_by_table update connection raw flags with given table.
---@param args table<string, string>
function M.set_connection_flags_by_table(args)
    for flag, value in pairs(args) do
        mongosh_state.set_raw_flag(flag, value)
    end
end

-- get_connection_flags returns a copy stored connection raw flag map.
---@return table<string, string>
function M.get_connection_flags()
    return mongosh_state.get_raw_flag_map()
end

-- clear_connection_flags clears all stored connection raw falgs.
function M.clear_connection_flags()
    mongosh_state.clear_all_raw_flags()
end

---@class mongo.ConnectArgs
---@field db_addr? string
--
---@field username? string
---@field password? string

-- connect connects to give host, and get list of available database name from host.
---@param args mongo.ConnectArgs
---@param callback fun(err?: string)
function M.connect(args, callback)
    local db_addr = args.db_addr or config.connection.default_db_addr
    mongosh_state.set_db_addr(db_addr)

    mongosh_state.set_username(args.username)
    mongosh_state.set_password(args.password)

    M.run_raw_script {
        script = script_const.CMD_LIST_DBS,
        callback = function(result)
            if result.code ~= 0 then
                callback("failed to connect to host\n" .. result.stderr)
                return
            end

            local db_names = vim.fn.json_decode(result.stdout)
            table.sort(db_names)
            mongosh_state.set_db_names(db_names)

            callback()
        end,
    }
end

-- get_collections get name list of all available collections in current data base
---@param callback fun(err?: string)
function M.update_collection_list(callback)
    M.run_raw_script {
        script = script_const.CMD_LIST_COLLECTIONS,
        callback = function(result)
            if result.code ~= 0 then
                callback("failed to get collection list\n" .. result.stderr)
                return
            end

            local collections = vim.fn.json_decode(result.stdout)
            table.sort(collections)
            mongosh_state.set_collection_names(collections)

            callback()
        end,
    }
end

-- do_execution runs a script snippet and watis for its result.
---@param script_snippet string
---@param callback fun(err: string?, result: string)
---@param  fallback_err_msg? string
function M.do_execution(script_snippet, callback, fallback_err_msg)
    M.run_script {
        script = script_snippet,
        callback = function(result)
            if result.code ~= 0 then
                local err = result.stderr
                if err:len() == 0 then
                    err = fallback_err_msg or "execution failed"
                end
                callback(result.stderr, "")
            else
                callback(nil, str_util.trim(result.stdout))
            end
        end,
    }
end

-- do_query first wraps given query snippet in a query template then executes the snippet.
---@param query_snippet string
---@param callback fun(err: string?, result: string)
---@param  fallback_err_msg? string
function M.do_query(query_snippet, callback, fallback_err_msg)
    local script_snippet = str_util.format(script_const.TEMPLATE_QUERY, {
        query = query_snippet,
        indent = tostring(config.indent_size),
    })

    M.do_execution(script_snippet, callback, fallback_err_msg or "query failed")
end

---@param edit_snippet string
---@param callback fun(err: string?, result: string)
---@param  fallback_err_msg? string
function M.do_replace(edit_snippet, callback, fallback_err_msg)
    local script_snippet = str_util.format(script_const.TEMPLATE_EDIT, {
        snippet = edit_snippet,
        indent = tostring(config.indent_size),
    })

    M.do_execution(script_snippet, callback, fallback_err_msg or "replace failed")
end

return M
