local api = vim.api

local M = {}

---@class mongo.higlight.HLItem
---@field name string # higlight group name
---@field st integer # stating column index, 0-base
---@field ed integer # ending column index, 0-base, exclusive

-- Update range of highlight items by matching text segment. Operation will
-- happen in place, the same highlight item list will be returned
---@param text_segments string[]
---@param hl_items mongo.higlight.HLItem[]
---@return mongo.higlight.HLItem[] hl_items
function M.update_hl_items_range(text_segments, hl_items)
    local pos = 0
    for i, item in ipairs(hl_items) do
        local text = text_segments[i]
        item.st = pos

        pos = pos + text:len()
        item.ed = pos
    end

    return hl_items
end

-- Write lines of highlight item to specified buffer.
---@param bufnr integer
---@param st_line integer # starting line number, 0-index
---@param hl_lines mongo.higlight.HLItem[][] # each item is a list of highlight item on the same line.
function M.add_hl_to_buffer(bufnr, st_line, hl_lines)
    local add_hl = api.nvim_buf_add_highlight

    for i, line in ipairs(hl_lines) do
        local line_num = st_line + i - 1

        for _, item in ipairs(line) do
            add_hl(bufnr, 0, item.name, line_num, item.st, item.ed)
        end
    end
end

-- ----------------------------------------------------------------------------

---@class mongo.highlight.HighlightedLine
---@field parts string[]
---@field hl_groups string[]

-- HighlightBuilder, utility class for making highlighted content in buffer.
---@class mongo.highlight.HighlightBuilder
---@field _cur_line integer
---@field _lines mongo.highlight.HighlightedLine[]
local HighlightBuilder = {}
HighlightBuilder.__index = HighlightBuilder
M.HighlightBuilder = HighlightBuilder

---@return mongo.highlight.HighlightBuilder
function HighlightBuilder:new()
    local obj = setmetatable({}, self)

    obj._cur_line = 0
    obj._lines = {}

    obj:new_line()

    return obj
end

---@return integer
function HighlightBuilder:get_line_cnt()
    return self._cur_line
end

-- Shifting to next line.
function HighlightBuilder:new_line()
    local cur_line = self._cur_line + 1
    self._cur_line = cur_line

    self._lines[cur_line] = { parts = {}, hl_groups = {} }
end

-- Write one segment with given highlight group into builder.
---@param content string
---@param hl_group string
function HighlightBuilder:write(content, hl_group)
    vim.validate {
        content = { content, "s" },
        hl_group = { hl_group, "s" },
    }

    local line = self._lines[self._cur_line]

    local parts = line.parts
    parts[#parts + 1] = content

    local hl_groups = line.hl_groups
    hl_groups[#hl_groups + 1] = hl_group
end

-- Genrate text lines and highlight infomation of each line with builder content.
---@return string[] lines
---@return mongo.highlight.HighlightBuilder[][]
function HighlightBuilder:build()
    local str_lines = {} ---@type string[]
    local hl_lines = {} ---@type mongo.highlight.HighlightBuilder[][]

    for _, line in ipairs(self._lines) do
        local parts = line.parts
        local hl_groups = line.hl_groups

        assert(#parts == #hl_groups, "unequal parts and highlight groups count")

        str_lines[#str_lines + 1] = table.concat(parts)

        local sum = 0
        local hl_items = {}
        for i, hl_group in ipairs(hl_groups) do
            local ed = sum + parts[i]:len()
            hl_items[#hl_items + 1] = { name = hl_group, st = sum, ed = ed }
            sum = ed
        end

        hl_lines[#hl_lines + 1] = hl_items
    end

    return str_lines, hl_lines
end

-- ----------------------------------------------------------------------------

return M
