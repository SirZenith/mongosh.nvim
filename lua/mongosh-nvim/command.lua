local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local log = require "mongosh-nvim.log"
local buffer_state = require "mongosh-nvim.state.buffer"
local util = require "mongosh-nvim.util"
local cmd_util = require "mongosh-nvim.util.command"

local api_buffer = require "mongosh-nvim.api.buffer"
local api_core = require "mongosh-nvim.api.core"
local api_ui = require "mongosh-nvim.api.ui"

local BufferType = buffer_const.BufferType
local ResultSplitStyle = buffer_const.ResultSplitStyle

---@return boolean
local function check_db_selected()
    return api_core.get_cur_db() ~= nil
end

---@param supported_types mongo.buffer.BufferType[]
---@return fun(): boolean available_checker
local function buffer_type_checker(supported_types)
    local type_set = {}
    for _, type in ipairs(supported_types) do
        type_set[type] = true
    end

    return function()
        local bufnr = vim.api.nvim_win_get_buf(0)

        local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
        if not mbuf then return false end

        local type = mbuf:get_type()
        return type_set[type]
    end
end

local cmd_mongo = cmd_util.new_cmd {
    name = "Mongo",
    range = true,
}

-- ----------------------------------------------------------------------------
-- Connecting

cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "connect",
    no_unused_warning = true,
    arg_list = {
        { name = "db-addr",                       is_flag = true },
        { name = "with-auth",                     is_flag = true, type = "boolean" },

        -- Basic
        { name = "host",                          is_flag = true, is_dummy = true },
        { name = "port",                          is_flag = true, is_dummy = true },

        -- Authentication
        { name = "authenticationMechanism",       is_flag = true, is_dummy = true },
        { name = "awsIamSessionToken",            is_flag = true, is_dummy = true },
        { name = "gssapiServiceName",             is_flag = true, is_dummy = true },
        { name = "sspiHostnameCanonicalization",  is_flag = true, is_dummy = true },
        { name = "sspiRealmOverride",             is_flag = true, is_dummy = true },

        -- TLS
        { name = "tls",                           is_flag = true, is_dummy = true },
        { name = "tlsCertificateKeyFile",         is_flag = true, is_dummy = true },
        { name = "tlsCertificateKeyFilePassword", is_flag = true, is_dummy = true },
        { name = "tlsCAFile",                     is_flag = true, is_dummy = true },
        { name = "tlsAllowInvalidHostnames",      is_flag = true, is_dummy = true },
        { name = "tlsAllowInvalidCertificates",   is_flag = true, is_dummy = true },
        { name = "tlsCertificateSelector",        is_flag = true, is_dummy = true },
        { name = "tlsCRLFile",                    is_flag = true, is_dummy = true },
        { name = "tlsDisabledProtocols",          is_flag = true, is_dummy = true },
        { name = "tlsUseSystemCA",                is_flag = true, is_dummy = true },
        { name = "tlsFIPSMode",                   is_flag = true, is_dummy = true },

        -- API version
        { name = "apiVersion",                    is_flag = true, is_dummy = true },
        { name = "apiStrict",                     is_flag = true, is_dummy = true },
        { name = "apiDeprecationErrors",          is_flag = true, is_dummy = true },

        -- FLE
        { name = "awsAccessKeyId",                is_flag = true, is_dummy = true },
        { name = "awsSecretAccessKey",            is_flag = true, is_dummy = true },
        { name = "awsSessionToken",               is_flag = true, is_dummy = true },
        { name = "keyVaultNamespace",             is_flag = true, is_dummy = true },
        { name = "kmsURL",                        is_flag = true, is_dummy = true },
    },
    action = function(args, _, unused_args)
        -- update raw connection flags
        api_core.clear_connection_flags()
        local raw_flags = {}
        for key, value in pairs(unused_args) do
            local flag
            if type(key) == "string" and type(value) == "string" then
                local len = key:len()
                if len == 0 then
                    -- pass
                elseif len == 1 then
                    flag = "-" .. key
                else
                    flag = "--" .. key
                end
            end

            if flag then
                raw_flags[flag] = value
            end
        end
        api_core.set_connection_flags_by_table(raw_flags)

        -- try connecting
        ---@type mongo.api.ConnectArgs
        local connect_args = {
            db_addr = args.db_addr,

            username = "",
            password = "",
            auth_source = "",
        }

        util.do_async_steps {
            -- user name input
            function(next_step)
                if not args.with_auth then
                    next_step()
                    return
                end

                vim.ui.input({ prompt = "User Name: " }, function(input)
                    connect_args.username = input or ""
                    next_step()
                end)
            end,

            -- password input
            function(next_step)
                if not args.with_auth then
                    next_step()
                    return
                end

                local input = vim.fn.inputsecret("Password: ")
                connect_args.password = input or ""
                next_step()
            end,

            -- authentication source database input
            function(next_step)
                if not args.with_auth then
                    next_step()
                    return
                end

                vim.ui.input({ prompt = "Auth Source DB: " }, function(input)
                    connect_args.auth_source = input or ""
                    next_step()
                end)
            end,

            -- connecting
            function(next_step)
                api_core.connect(connect_args, function(err)
                    if err then
                        log.warn(err)
                        next_step()
                        return
                    end

                    if config.dialog.split_style == ResultSplitStyle.Tab then
                        vim.cmd "tabnew"
                    end

                    api_ui.show_db_sidebar()

                    next_step()
                end)
            end,
        }
    end,
}

cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "database",
    action = api_ui.select_database_ui,
}

cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "collection",
    available_checker = check_db_selected,
    action = api_ui.select_collection_ui_list,
}

-- ----------------------------------------------------------------------------
-- Action

cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "execute",
    range = true,
    action = function(_, orig_args)
        api_buffer.run_buffer_executation(
            vim.api.nvim_win_get_buf(0),
            {
                with_range = orig_args.range ~= 0,
            }
        )
    end,
}

cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "query",
    range = true,
    arg_list = {
        { name = "typed", type = "boolean", is_flag = true },
    },
    action = function(args, orig_args)
        api_buffer.run_buffer_query(
            vim.api.nvim_win_get_buf(0),
            {
                is_typed = args.typed,
                with_range = orig_args.range ~= 0,
            }
        )
    end,
}

cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "edit",
    range = true,
    available_checker = check_db_selected,
    action = function(_, orig_args)
        api_buffer.run_buffer_edit(
            vim.api.nvim_win_get_buf(0),
            {
                with_range = orig_args.range ~= 0,
            }
        )
    end,
}

cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "refresh",
    action = function()
        local bufnr = vim.api.nvim_win_get_buf(0)
        api_buffer.refresh_buffer(bufnr)
    end,
}

-- ----------------------------------------------------------------------------
-- `new` Buffer

local cmd_mongo_new = cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "new"
}

cmd_util.new_cmd {
    parent = cmd_mongo_new,
    name = "execute",
    action = function()
        api_buffer.create_execute_buffer()
    end,
}

cmd_util.new_cmd {
    parent = cmd_mongo_new,
    name = "query",
    available_checker = check_db_selected,
    action = api_ui.select_collection_ui_list,
}

cmd_util.new_cmd {
    parent = cmd_mongo_new,
    name = "edit",
    arg_list = {
        { name = "collection", is_flag = true, short = "c",    required = true },
        { name = "id",         is_flag = true, required = true },
    },
    available_checker = check_db_selected,
    action = function(args)
        local collection = args.collection or ""
        local id = args.id or ""

        api_buffer.create_edit_buffer(collection, id)
    end,
}

-- ----------------------------------------------------------------------------
-- Sidebar

local cmd_mongo_sidebar = cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "sidebar",
    action = api_ui.toggle_db_sidebar,
}

cmd_util.new_cmd {
    parent = cmd_mongo_sidebar,
    name = "show",
    action = api_ui.show_db_sidebar,
}

cmd_util.new_cmd {
    parent = cmd_mongo_sidebar,
    name = "hide",
    action = api_ui.hide_db_sidebar,
}

cmd_util.new_cmd {
    parent = cmd_mongo_sidebar,
    name = "toggle",
    action = api_ui.toggle_db_sidebar,
}

-- ----------------------------------------------------------------------------
-- Conversion

local cmd_mongo_convert = cmd_util.new_cmd {
    parent = cmd_mongo,
    name = "convert",
    available_checker = function()
        local bufnr = vim.api.nvim_win_get_buf(0)
        local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
        return mbuf ~= nil
    end,
}

cmd_util.new_cmd {
    parent = cmd_mongo_convert,
    name = "card-result",
    arg_list = {
        { name = "persist", type = "boolean", is_flag = true },
    },
    available_checker = buffer_type_checker { BufferType.QueryResult },
    action = function(args)
        if args.persist then
            config.query.result_style = BufferType.QueryResultCard
        end

        api_buffer.buffer_convert(
            vim.api.nvim_win_get_buf(0),
            BufferType.QueryResultCard
        )
    end,
}

cmd_util.new_cmd {
    parent = cmd_mongo_convert,
    name = "json-result",
    arg_list = {
        { name = "persist", type = "boolean", is_flag = true },
    },
    available_checker = buffer_type_checker { BufferType.QueryResultCard },
    action = function(args)
        if args.persist then
            config.query.result_style = BufferType.QueryResult
        end

        api_buffer.buffer_convert(
            vim.api.nvim_win_get_buf(0),
            BufferType.QueryResult
        )
    end,
}

-- ----------------------------------------------------------------------------

cmd_mongo:register()
