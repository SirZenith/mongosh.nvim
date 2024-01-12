local ts_const = require "mongosh-nvim.constant.tree_sitter"
local list_util = require "mongosh-nvim.util.list"

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
            txt = txt:sub(5)           -- trim leading 'db[' (and quote)
            txt = txt:sub(1, #txt - 2) -- trim trailing '"]' or "']"
        elseif prefix == "db." then
            txt = txt:sub(4)           -- trim leading 'db.'
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

-- Take JSON source text and range of target node as input. Find smallest key-
-- value pair covering given range, and find accessing key path to that key from
-- root of document.
-- For example, with source text:
-- ```json
-- [
--     {
--         "user": {
--             "foo": {
--                 "bar": "buz"
--             }
--         }
--     }
-- ]
-- ```
-- and seelction range covers `ar": "buz"`.
-- This function will first find key value pair `"foo": { ... }`, and returns
-- access key path `user.foo`
---@param json_text string
---@param target_range { st_row: number, st_col: number, ed_row: number, ed_col: number } # all index are 0-base, column end is exclusive
function M.get_json_node_dot_path(json_text, target_range)
    ---@type LanguageTree
    local parser = ts.get_string_parser(json_text, "json")
    local tree = parser:parse()[1]
    local root = tree:root()

    local cur_node = root:descendant_for_range(
        target_range.st_row,
        target_range.st_col,
        target_range.ed_row,
        target_range.ed_col
    )

    local chain = {} ---@type TSNode[]
    repeat
        table.insert(chain, cur_node)
        cur_node = cur_node:parent()
    until not cur_node

    list_util.list_reverse(chain)
    list_util.list_filter_in_place(chain, function(_, node)
        return node:type() == "pair"
    end)
    list_util.list_map_in_place(chain, function(_, node)
        local key_node = node:field("key")[1]
        local key_type = key_node:type()

        local target = key_node
        if key_type == "string" then
            target = key_node:named_child(0)
        end

        local text = ts.get_node_text(target, json_text)

        return text
    end)

    local node_path = table.concat(chain, ".")

    return node_path
end

return M
