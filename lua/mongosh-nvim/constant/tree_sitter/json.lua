local ts_const = require "mongosh-nvim.constant.tree_sitter"

local M = {}

-- ----------------------------------------------------------------------------

-- query `_id` field in JSON text
M.QUERY_JSON_ID_FIELD = [[
(object
    (pair
        key: (
            string (string_content) @id (#eq? @id "_id")
        )
        value: (_) @id_value
    )
) @obj
]]

-- ----------------------------------------------------------------------------

return ts_const.wrap_with_cache(M, "json")
