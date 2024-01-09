local config = require "mongosh-nvim.config"
local cmd_util = require "mongosh-nvim.util.command"

local api_core = require "mongosh-nvim.api.core"
local api_ui = require "mongosh-nvim.api.ui"

-- ----------------------------------------------------------------------------

cmd_util.register_cmd {
    name = "MongoConnect",
    arg_list = {
        { name = "host",        is_flag = true },
        { name = "port",        is_flag = true },
        { name = "db",          is_flag = true },
        { name = "with-auth",   is_flag = true },
        { name = "api-version", is_flag = true },
    },
    action = function(args)
        local db = args.db

        ---@type mongo.ConnectArgs
        local connect_args = {
            host = args.host or config.connection.default_host,
            port = args.port,

            username = "",
            password = "",

            api_version = args.api_version,
        }

        api_core.connect(connect_args, function(ok)
            if not ok then return end

            if db then
                api_ui.select_database(db)
            else
                api_ui.select_database_ui()
            end
        end)
    end,
}

cmd_util.register_cmd {
    name = "MongoDatabase",
    action = api_ui.select_database_ui,
}

cmd_util.register_cmd {
    name = "MongoCollection",
    action = api_ui.select_collection_ui_buffer,
}

cmd_util.register_cmd {
    name = "MongoExecute",
    range = true,
    action = function(_, orig_args)
        api_ui.run_buffer_executation(
            vim.api.nvim_win_get_buf(0),
            {
                with_range = orig_args.range ~= 0,
            }
        )
    end,
}

cmd_util.register_cmd {
    name = "MongoNewQuery",
    action = api_ui.select_collection_ui_list,
}

cmd_util.register_cmd {
    name = "MongoQuery",
    range = true,
    action = function(_, orig_args)
        api_ui.run_buffer_query(
            vim.api.nvim_win_get_buf(0),
            {
                with_range = orig_args.range ~= 0,
            }
        )
    end,
}

cmd_util.register_cmd {
    name = "MongoNewEdit",
    arg_list = {
        { name = "collection", is_flag = true, short = "c",    required = true },
        { name = "id",         is_flag = true, required = true },
    },
    action = function(args)
        local collection = args.collection or ""
        local id = args.id or ""

        api_ui.create_edit_buffer(collection, id)
    end,
}

cmd_util.register_cmd {
    name = "MongoEdit",
    range = true,
    action = function(args)
        api_ui.run_buffer_edit(
            vim.api.nvim_win_get_buf(0),
            {
                with_range = args.range ~= 0,
            }
        )
    end,
}

cmd_util.register_cmd {
    name = "MongoRefresh",
    action = function()
        local bufnr = vim.api.nvim_win_get_buf(0)
        api_ui.refresh_buffer(bufnr)
    end,
}
