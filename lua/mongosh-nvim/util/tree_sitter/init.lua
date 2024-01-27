local list_util = require "mongosh-nvim.util.list"

local base = require "mongosh-nvim.util.tree_sitter.base"
local query_json = require "mongosh-nvim.constant.tree_sitter.json"

local ts = vim.treesitter

local M = {}

-- find_nearest_id_in_buffer tries to find `_id` field value of document around cursor.
---@param bufid integer
function M.find_nearest_id_in_buffer(bufid)
    local parser = ts.get_parser(bufid, "json")
    local tree = parser:parse()[1]

    local query = query_json.QUERY_JSON_ID_FIELD

    local pos = vim.fn.getpos(".")
    local line = pos[2] - 1
    local col = pos[3] - 1

    for _, captures in query:iter_matches(tree:root(), bufid) do
        local tab = base.caps_to_table(query, captures)
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
-- If covered key itself has no parent key, then `nil` will be returned.
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
---@return string[]?
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

    if #chain == 0 then
        return nil
    end

    return chain
end

return M
