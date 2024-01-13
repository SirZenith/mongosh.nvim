local M = {}

---@param tbl table<string, string>
---@param lang string
---@return table<string, Query>
function M.wrap_with_cache(tbl, lang)
    local cached_query = {}

    return setmetatable({}, {
        __index = function(_, key)
            local src = rawget(tbl, key)
            if not src then return nil end

            local query = cached_query[key]
            if not query then
                query = vim.treesitter.query.parse(lang, src)
                cached_query[key] = query
            end

            return query
        end,
        __newindex = function()
            error("you cannot write into query cache module")
        end,
    })
end

return M
