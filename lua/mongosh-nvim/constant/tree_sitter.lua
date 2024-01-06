local M = {}

-- query collection name in `db["<name>"]`
M.QUERY_COLLECTION_NAME_IN_QUERY = [[
(call_expression
    function: (member_expression
        object: (
            (_) @mbr (#match? @mbr "^db(\\[|\\.)")
        )
        ;
        property: (_) @fn)
) @call
]]

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

return M
