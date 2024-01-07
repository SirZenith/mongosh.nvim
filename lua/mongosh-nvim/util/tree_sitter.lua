local ts_const = require "mongosh-nvim.constant.tree_sitter"

local ts = vim.treesitter

local M = {}

-- caps_to_table converts query captures into Lua table
---@return table<string, TSNode>
local function caps_to_table(query, captures)
    local tbl = {}

    for index, node in ipairs(captures) do
        local name = query.captures[index]
        tbl[name] = node
    end

    return tbl
end

-- get_collection_name extracts collection name used in simple query snippet.
---@param src string # query snippet source code
---@return string? collection_name
function M.get_collection_name(src)
    local parser = ts.get_string_parser(src, "typescript")
    local tree = parser:parse()[1]
    local query = ts.query.parse("typescript", ts_const.QUERY_COLLECTION_NAME_IN_QUERY)

    local result

    for _, captures in query:iter_matches(tree:root(), src) do
        local tbl = caps_to_table(query, captures)
        if result then
            -- multiple collection name found, not supported
            result = nil
            break
        end

        local txt = ts.get_node_text(tbl.mbr, src)
        local prefix = txt:sub(1, 3)

        if prefix == "db[" then
            txt = txt:sub(5) -- trim leading 'db[' (and quote)
            txt = txt:sub(1, #txt - 2) -- trim trailing '"]' or "']"
        elseif prefix == "db." then
            txt = txt:sub(4) -- trim leading 'db.'
        end

        result = txt
    end

    return result
end

-- find_nearest_id_in_buffer tries to find `_id` field value of document around cursor.
---@param bufid integer
function M.find_nearest_id_in_buffer(bufid)
    local parser = ts.get_parser(bufid)
    local tree = parser:parse()[1]

    local query = ts.query.parse("json", ts_const.QUERY_JSON_ID_FIELD)

    local pos = vim.fn.getpos(".")
    local line = pos[2] - 1
    local col = pos[3] - 1

    for _, captures in query:iter_matches(tree:root(), bufid) do
        local tab = caps_to_table(query, captures)
        if ts.is_in_node_range(tab.obj, line, col) then
            local node_text = ts.get_node_text(tab.id_value, bufid)
            -- node_text could be a JSON object, so let's remove newlines:
            node_text = vim.fn.json_encode(vim.fn.json_decode(node_text))
            return node_text
        end
    end
end

return M
