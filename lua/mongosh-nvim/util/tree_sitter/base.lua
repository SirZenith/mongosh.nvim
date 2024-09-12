local log = require "mongosh-nvim.log"

local M = {}

-- caps_to_table converts query captures into Lua table
---@return table<string, TSNode>
function M.caps_to_table(query, captures)
    local tbl = {}

    for index, node in ipairs(captures) do
        local name = query.captures[index]
        -- QUESTION: assigning simply `node` was always fine until neovim 0.10.1
        -- is there any breaking change made to treesitter API?
        tbl[name] = type(node) == "table" and node[1] or node
    end

    return tbl
end

---@alias mongo.treesitter.VisitorFunc fun(contex: mongo.treesitter.WalkThroughContext, node: TSNode): string?

---@class mongo.treesitter.WalkThroughContext
---@field root TSNode
---@field src string
---@field visitor_map table<string, mongo.treesitter.VisitorFunc>
---@field visited? table<string, boolean>

---@param contex mongo.treesitter.WalkThroughContext
---@param node TSNode
---@return string?
function M.walk_through_node(contex, node)
    local type = node:type()

    local visited = contex.visited
    if visited then
        if visited[type] then
            log.warn("repeated visit on: " .. type)
            return
        else
            contex.visited[type] = true
        end
    end

    local visitor = contex.visitor_map[type]
    if not visitor then
        vim.notify("no handler for " .. type)
        return
    end

    return visitor(contex, node)
end

return M
