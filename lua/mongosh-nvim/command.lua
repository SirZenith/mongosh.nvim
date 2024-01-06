local buffer_const = require "mongosh-nvim.constant.buffer"
local log = require "mongosh-nvim.log"
local buffer_state = require "mongosh-nvim.state.buffer"
local str_util = require "mongosh-nvim.util.str"

local api_core = require "mongosh-nvim.api.core"
local api_ui = require "mongosh-nvim.api.ui"

local cmd = vim.api.nvim_create_user_command

local BufferType = buffer_const.BufferType

---@param args string[]
---@return table<string | number, string>
local function parse_args(args)
    local parsed_args = {}
    local idx = 1
    for _, arg in ipairs(args) do
        if str_util.starts_with(arg, "--") then
            local equals_idx = arg:find("=")
            local key = ""
            local value = nil
            if equals_idx == nil then
                key = arg:sub(3)
            else
                key = arg:sub(3, equals_idx - 1)
                value = arg:sub(equals_idx + 1)
            end
            parsed_args[key] = value
        else
            parsed_args[idx] = arg
            idx = idx + 1
        end
    end
    return parsed_args
end

-- ----------------------------------------------------------------------------

cmd("MongoConnect", function(args)
    local parsed_args = parse_args(args.fargs)

    local db = parsed_args["db"] or parsed_args[1]
    local host = parsed_args["host"] or "localhost:27017"

    api_core.connect(host, function(ok)
        if not ok then return end

        if db then
            api_ui.select_database(db)
        else
            api_ui.select_database_ui()
        end
    end)
end, { nargs = "*" })

cmd("MongoDatabase", api_ui.select_database_ui, {})

cmd("MongoCollection", api_ui.select_collection_ui_buffer, {})

cmd("MongoExecute", function(args)
    local bufnr = vim.api.nvim_win_get_buf(0)
    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
        or buffer_state.wrap_with_mongo_buffer(BufferType.ExecuteResult, bufnr)

    local supported_types = {
        [BufferType.Execute] = true,
        [BufferType.Query] = true,
        [BufferType.Edit] = true,
    }

    if supported_types[mbuf.type] then
        mbuf:write_result(args)
    else
        log.warn("current buffer doesn't support Execute commnad")
    end
end, { range = true })

cmd("MongoNewQuery", api_ui.select_collection_ui_list, {})

cmd("MongoQuery", function(args)
    local bufnr = vim.api.nvim_win_get_buf(0)
    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
        or buffer_state.wrap_with_mongo_buffer(BufferType.Query, bufnr)

    if mbuf.type == BufferType.Execute then
        mbuf:change_type_to(BufferType.Query)
    end

    local supported_types = {
        [BufferType.Query] = true,
    }

    if supported_types[mbuf.type] then
        mbuf:write_result(args)
    else
        log.warn("current buffer doesn't support Query command")
    end
end, { range = true })

cmd("MongoNewEdit", function(args)
    local parsed_args = parse_args(args.fargs)
    local collection = parsed_args["collection"] or parsed_args["coll"]

    if collection == nil then
        log.warn("not collection name provided")
        return
    end

    local id = parsed_args["id"]
    if not nil then
        log.warn("no document id provided")
        return
    end

    api_ui.create_edit_buffer(collection, id)
end, { nargs = "*" })

cmd("MongoEdit", function(args)
    local bufnr = vim.api.nvim_win_get_buf(0)
    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)
        or buffer_state.wrap_with_mongo_buffer(BufferType.Edit, bufnr)

    if mbuf.type == BufferType.Execute then
        mbuf:change_type_to(BufferType.Edit)
    end

    local supported_types = {
        [BufferType.QueryResult] = true,
        [BufferType.Edit] = true,
    }

    if supported_types[mbuf.type] then
        mbuf:write_result(args)
    else
        log.warn("current buffer doesn't support Edit command")
    end
end, { range = true })

cmd("MongoRefresh", function()
    local bufnr = vim.api.nvim_win_get_buf(0)
    local mbuf = buffer_state.try_get_mongo_buffer(bufnr)

    if mbuf then
        mbuf:refresh()
    else
        log.warn("current buffer is not refreshable")
    end
end, {})
