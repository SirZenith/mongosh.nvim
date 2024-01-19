local query_typescript = require "mongosh-nvim.constant.tree_sitter.typescript"
local base = require "mongosh-nvim.util.tree_sitter.base"

local ts = vim.treesitter

local M = {}

---@type table<string, mongo.treesitter.VisitorFunc>
local visitor_map = {
    program = function(context, node)
        local query = query_typescript.QUERY_DECLARATION_RESULT

        local rhs
        for _, captures in query:iter_matches(node, context.src) do
            local tbl = base.caps_to_table(query, captures)
            rhs = tbl.rhs
        end

        if not rhs then return end

        return base.walk_through_node(context, rhs)
    end,

    -- ------------------------------------------------------------------------

    call_expression = function(contex, node)
        local query = query_typescript.QUERY_COLLECTION_NAME_FROM_FUNC_CALL

        local tbl
        for _, cap in query:iter_matches(node, contex.src) do
            tbl = base.caps_to_table(query, cap)
            break
        end

        local obj = tbl and tbl.object
        if not obj then return end

        return base.walk_through_node(contex, obj)
    end,
    member_expression = function(context, node)
        local query = query_typescript.QUERY_COLLECTION_NAME_FROM_MEMBER_ACCESSING

        local tbl
        for _, cap in query:iter_matches(node, context.src) do
            tbl = base.caps_to_table(query, cap)
            break
        end

        local coll_node = tbl and tbl.collection_name
        if not coll_node then return end

        return base.walk_through_node(context, coll_node)
    end,
    subscript_expression = function(context, node)
        local query = query_typescript.QUERY_COLLECTION_NAME_FROM_INDEXING

        local tbl
        for _, cap in query:iter_matches(node, context.src) do
            tbl = base.caps_to_table(query, cap)
            break
        end

        local coll_node = tbl and tbl.collection_name
        if not coll_node then return end

        return base.walk_through_node(context, coll_node)
    end,

    -- ------------------------------------------------------------------------

    identifier = function(context, node)
        local ident_name = ts.get_node_text(node, context.src)
        local query_str = ([[
            [
                (variable_declarator
                    name: (identifier) @ident (#eq? @ident "%s")
                    value: (string) @value
                )
                (assignment_expression
                    left: (identifier) @ident (#eq? @ident "%s")
                    right: (string) @value
                )
            ] @expr
        ]]):format(ident_name, ident_name)
        local query = vim.treesitter.query.parse("typescript", query_str)

        local target
        for _, cap in query:iter_matches(context.root, context.src) do
            local tbl = base.caps_to_table(query, cap)
            local value = tbl.value

            local expr = tbl.expr
            if expr:type() == "assignment_expression" then
                target = value
            elseif expr:parent():parent() == context.root then
                -- only top-level declarations are take in count.
                target = value
            end
        end

        if not target then return end

        return base.walk_through_node(context, target)
    end,
    property_identifier = function(context, node)
        return ts.get_node_text(node, context.src)
    end,
    string = function(context, node)
        local child = node:named_child(0)
        if not child then return end

        return ts.get_node_text(child, context.src)
    end,
}

-- Extract collection name from query snippet. Following forms are supported:
--
-- - `result` variable is defined by string literal key indexing to `db`.
-- - `result` variable is defined by dot access to `db`.
-- - `result` variable is defined by indexing `db` with another variable, and
--   that vairable is last asigned by a string literal.
---@param src string # query snippet source code
---@return string? collection_name
function M.get_collection_name(src)
    local parser = vim.treesitter.get_string_parser(src, "typescript")
    local tree = parser:parse()[1]
    local root = tree:root()

    local collection_name = base.walk_through_node({
        root = root,
        src = src,
        visitor_map = visitor_map,
        visited = {},
    }, root)

    return collection_name
end

return M
