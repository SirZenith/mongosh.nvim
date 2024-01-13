local ts_const = require "mongosh-nvim.constant.tree_sitter"

local M = {}

-- ----------------------------------------------------------------------------

-- Query declaration or assignment to variable `result`
M.QUERY_DECLARATION_RESULT = [[
[
    (variable_declarator
        name: (identifier) @ident (#eq? @ident "result")
        value: [
            (call_expression
                function: (member_expression)
            )
            (member_expression)
            (subscript_expression)
        ] @rhs
    )
    (assignment_expression
        left: (identifier) @ident (#eq? @ident "result")
        right: [
            (call_expression)
            (member_expression)
            (subscript_expression)
        ] @rhs
    )
]
]]

-- Get access to `db` in method call
M.QUERY_COLLECTION_NAME_FROM_FUNC_CALL = [[
(call_expression
    function: (member_expression
        object: (_) @object
    )
)
]]

-- Get property name immediately after `db`
M.QUERY_COLLECTION_NAME_FROM_MEMBER_ACCESSING = [[
(member_expression
    object: (identifier) @ident (#eq? @ident "db")
    property: (property_identifier) @collection_name
)
]]

-- Get indexing key immediately after `db`
M.QUERY_COLLECTION_NAME_FROM_INDEXING = [[
(subscript_expression
    object: (identifier) @ident (#eq? @ident "db")
    index: [
        (identifier)
        (string)
    ] @collection_name
)
]]

-- ----------------------------------------------------------------------------

return ts_const.wrap_with_cache(M, "typescript")
