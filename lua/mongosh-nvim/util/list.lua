local M = {}

-- Reverse a list in place.
---@param list any[]
function M.list_reverse(list)
    local len = #list
    local ed = len / 2
    for i = 1, ed do
        local j = len - i + 1
        list[i], list[j] = list[j], list[i]
    end
end

-- Filter list in place with condition function. Function will be called with
-- element index and value, if condition function return `false` on an element,
-- that element won't be in result list.
---@param list any[]
---@param filter fun(i: number, element: any): boolean
function M.list_filter_in_place(list, filter)
    local len = #list
    local delta = 0

    for i = 1, len do
        local element = list[i]
        if not filter(i, element) then
            list[i] = nil
            delta = delta + 1
        elseif delta > 0 then
            list[i] = nil
            local new_index = i - delta
            list[new_index] = element
        end
    end
end

-- Map list value in place. Mapper function will be called with element index
-- and value on every element, return value of mapper will replace original
-- value in place.
---@param list any[]
---@param mapper fun(i: number, element: any): any
function M.list_map_in_place(list, mapper)
    for i = 1, #list do
        list[i] = mapper(i, list[i])
    end
end

return M
