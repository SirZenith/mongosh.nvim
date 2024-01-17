local api_constant = require "mongosh-nvim.constant.api"
local config = require "mongosh-nvim.config"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local util = require "mongosh-nvim.util"
local str_util = require "mongosh-nvim.util.str"
local event_util = require "mongosh-nvim.util.event"

local loop = vim.loop

local M = {}

local EventType = api_constant.CoreEventType

local emitter = event_util.EventEmitter:new("api.core", EventType)
M.emitter = emitter

-- Append flag-value pair to argument buffer list if the value is not `nil`.
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

-- Write script snippet to temporary file before running.
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

-- Return basic argument, for example authentication info, for current
-- connection.
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
    try_append_flag(args, "--authenticationDatabase", mongosh_state.get_auth_source())

    return args
end

---@class mongo.api.RunCmdResult
---@field code number
---@field signal number
---@field stdout string
---@field stderr string

---@class mongo.api.RunCmdArgs
---@field args string[]
---@field callback fun(result: mongo.api.RunCmdResult) # callback for handling evaluation result.

---@class mongo.api.RunScriptArgs
---@field script string # script snippet string.
---@field db_address? string # database address for connection.
---@field callback fun(result: mongo.api.RunCmdResult) # callback for handling evaluation result.
---@field on_process_started? fun(handle?: userdata, pid: integer)

-- Call mongosh executable with given arguments. Command will be evaluated
-- asynchronously.
---@param args mongo.api.RunCmdArgs
---@return userdata? handle
---@return integer pid
function M.call_mongosh(args)
    local executable = config.executable
    if not executable then
        args.callback {
            code = 1,
            signal = 0,
            stdout = "",
            stderr = "mongosh executable not found"
        }
        return nil, 0
    end

    local stdout = loop.new_pipe()
    local stderr = loop.new_pipe()

    local out_buffer = {} ---@type string[]
    local err_buffer = {} ---@type string[]

    local handle, pid
    handle, pid = loop.spawn(
        executable,
        {
            args = args.args,
            stdio = { nil, stdout, stderr }
        },
        vim.schedule_wrap(function(code, signal)
            emitter:emit(EventType.process_ended, pid)
            args.callback {
                code = code,
                signal = signal,
                stdout = table.concat(out_buffer),
                stderr = table.concat(err_buffer),
            }
        end)
    )
    emitter:emit(EventType.process_started, pid)

    loop.read_start(stdout, function(err, data)
        if err then return end

        if data then
            vim.schedule(function()
                emitter:emit(EventType.incomming_stdout, pid, data)
            end)
        end

        out_buffer[#out_buffer + 1] = data
    end)

    loop.read_start(stderr, function(err, data)
        if err then return end

        if data then
            vim.schedule(function()
                emitter:emit(EventType.incomming_stderr, pid, data)
            end)
        end

        err_buffer[#err_buffer + 1] = data
    end)

    return handle, pid
end

-- Sends script snippet to last connected database collection if no database
-- address is provided.
-- **Note**: Script content is sent to mongosh via command line directly. If snippet is too
-- long, this function might fail due to OS limitation.
---@param args mongo.api.RunScriptArgs
function M.run_raw_script(args)
    local address = args.db_address or mongosh_state.get_db_addr()
    local exe_args = M.get_connection_args();

    local handle, pid = M.call_mongosh {
        args = vim.list_extend(exe_args, {
            "--quiet",
            "--eval",
            args.script,
            address,
        }),
        callback = args.callback,
    }

    local on_process_started = args.on_process_started
    if type(on_process_started) == "function" then
        on_process_started(handle, pid)
    end
end

-- Take script snippet and run it on last connected database collection if no
-- database address is provide.
-- Before running the snippet, function will first write it to temporary file,
-- this is for avoiding limitation of maximum command line argument length.
---@param args mongo.api.RunScriptArgs
function M.run_script(args)
    local address = args.db_address or mongosh_state.get_db_addr()

    M.save_tmp_script_file(args.script, function(tmpfile_name)
        local exe_args = M.get_connection_args()

        local handle, pid = M.call_mongosh {
            args = vim.list_extend(exe_args, {
                "--quiet",
                address,
                tmpfile_name
            }),
            callback = args.callback,
        }

        local on_process_started = args.on_process_started
        if type(on_process_started) == "function" then
            on_process_started(handle, pid)
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Connecting

-- Treat every two arguments in input list as flag-value pair, and write them
-- into stored connection flag map.
-- Extra flag with no paired value is ignored.
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

-- Update stored connection raw flags with given table.
---@param args table<string, string>
function M.set_connection_flags_by_table(args)
    for flag, value in pairs(args) do
        mongosh_state.set_raw_flag(flag, value)
    end
end

-- Return a copy of stored connection raw flag map.
---@return table<string, string>
function M.get_connection_flags()
    return mongosh_state.get_raw_flag_map()
end

-- Clear all stored connection raw falgs.
function M.clear_connection_flags()
    mongosh_state.clear_all_raw_flags()
end

---@class mongo.api.ConnectArgs
---@field db_addr? string
--
---@field username? string
---@field password? string
---@field auth_source? string

-- Connect to give host, and query names of available database from it.
---@param args mongo.api.ConnectArgs
---@param callback fun(err?: string)
function M.connect(args, callback)
    local db_addr = args.db_addr or config.connection.default_db_addr
    mongosh_state.set_db_addr(db_addr)

    mongosh_state.set_username(args.username)
    mongosh_state.set_password(args.password)
    mongosh_state.set_auth_source(args.auth_source)

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

            mongosh_state.reset_all_collection_name_cache()

            callback()

            emitter:emit(EventType.connection_successed)
        end,
    }
end

-- ----------------------------------------------------------------------------
-- Script operation

-- Send given code snippet to mongosh without any preprocessing.
---@param script_snippet string
---@param callback fun(err: string?, result: string)
---@param  fallback_err_msg? string
function M.do_execution(script_snippet, callback, fallback_err_msg)
    M.run_script {
        script = script_snippet,
        callback = function(result)
            if result.code ~= 0 then
                local err = result.stderr
                if err == "" then
                    err = fallback_err_msg or "execution failed"
                end
                callback(result.stderr, "")
            else
                callback(nil, str_util.trim(result.stdout))
            end
        end,
    }
end

-- Wrap given query snippet in a query template then send it to mongosh.
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

-- Wrap given query snippet in a query template then send it to mongosh.
-- Query result contains BSON type info.
---@param query_snippet string
---@param callback fun(err: string?, result: string)
---@param  fallback_err_msg? string
function M.do_query_typed(query_snippet, callback, fallback_err_msg)
    local script_snippet = str_util.format(script_const.TEMPLATE_QUERY_TYPED, {
        query = query_snippet,
        indent = tostring(config.indent_size),
    })

    M.do_execution(script_snippet, callback, fallback_err_msg or "query failed")
end

-- Fill given edit snippet into `replaceOne` call template and send it to mongosh.
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

-- Fill given update snippet into `updateOne` call template and send it to mongosh.
---@param update_snippet string
---@param callback fun(err: string?, result: string)
---@param fallback_err_msg? string
function M.do_update_one(update_snippet, callback, fallback_err_msg)
    local script_snippet = str_util.format(script_const.TEMPLATE_UPDATE_ONE, {
        snippet = update_snippet,
        indent = tostring(config.indent_size),
    })

    M.do_execution(script_snippet, callback, fallback_err_msg or "update one failed")
end

-- ----------------------------------------------------------------------------
-- State data access

-- Set database target of current connection to `db`.
---@param db string
---@return string? err
function M.switch_to_db(db)
    local full_list = mongosh_state.get_db_names()
    if #full_list == 0 then
        return "no available database found"
    end

    local is_found = false
    for _, name in ipairs(full_list) do
        if name == db then
            is_found = true
            break
        end
    end

    if not is_found then
        return "database is not available: " .. db
    end

    emitter:emit(EventType.db_selection_update, db)
    mongosh_state.set_db(db)

    return nil
end

-- Return database address of current connection.
---@return string
function M.get_cur_db_addr()
    return mongosh_state.get_db_addr()
end

-- Return database name for current connection. If no database has been connected
-- yet, then this function returns `nil`.
---@return string?
function M.get_cur_db()
    return mongosh_state.get_db()
end

-- Return host name for current connection. If no connection have been made, then
-- this function returns `nil`.
---@return string?
function M.get_cur_host()
    return mongosh_state.get_host()
end

-- Return port number used in current connection. If no port is explictly
-- specified, `nil` will be returned.
---@return integer?
function M.get_cur_port()
    return mongosh_state.get_port()
end

-- Return names of available databases except ones that gets marked as ignored.
---@return string[] db_names
function M.get_filtered_db_list()
    local full_list = mongosh_state.get_db_names()
    if #full_list == 0 then
        return {}
    end

    local ignore_set = {}
    for _, name in ipairs(config.connection.ignore_db_names) do
        ignore_set[name] = true
    end

    local db_names = {}
    for _, name in ipairs(full_list) do
        if not ignore_set[name] then
            db_names[#db_names + 1] = name
        end
    end

    return db_names
end

-- Get list of available collection in a database.
-- If no collection list found for target database in local list, `nil` will be
-- returned.
---@param db? string # database name
---@return string[]?
function M.get_collection_names(db)
    return mongosh_state.get_collection_names(db)
end

-- Send query to specified database to get list of available collections.
---@param db string
---@param callback? fun(err?: string)
function M.update_collection_list(db, callback)
    local wrapped_callback = function(err)
        if callback then
            callback(err)
        elseif err then
            log.warn(err)
        end
    end

    local switch_err = M.switch_to_db(db)
    if switch_err then
        wrapped_callback(switch_err)
        return
    end

    M.run_raw_script {
        script = script_const.CMD_LIST_COLLECTIONS,
        callback = function(result)
            local err
            if result.code ~= 0 then
                err = "failed to get collection list\n" .. result.stderr
            else
                local collections = vim.fn.json_decode(result.stdout)
                table.sort(collections)
                mongosh_state.set_collection_names(db, collections)
            end

            emitter:emit(EventType.collection_list_update, db)
            wrapped_callback(err)
        end,
    }
end

return M
