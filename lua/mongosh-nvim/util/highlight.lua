local api = vim.api

local M = {}

---@class mongo.highlight.HLItem
---@field name string # higlight group name
---@field st integer # stating column index, 0-base
---@field ed integer # ending column index, 0-base, exclusive

-- Update range of highlight items by matching text segment. Operation will
-- happen in place, the same highlight item list will be returned
---@param text_segments string[]
---@param hl_items mongo.highlight.HLItem[]
---@return mongo.highlight.HLItem[] hl_items
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
---@param hl_lines mongo.highlight.HLItem[][] # each item is a list of highlight item on the same line.
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
---@field _max_visited_line integer # maximum line number this builder has ever put its write head on.
local HighlightBuilder = {}
HighlightBuilder.__index = HighlightBuilder
M.HighlightBuilder = HighlightBuilder

---@return mongo.highlight.HighlightBuilder
function HighlightBuilder:new()
    local obj = setmetatable({}, self)

    obj._cur_line = 0
    obj._lines = {}
    obj._max_visited_line = 0

    obj:next_line()

    return obj
end

-- Current writing position.
function HighlightBuilder:get_cur_line()
    return self._cur_line
end

-- Update value of max visited line if current line is greater.
function HighlightBuilder:_try_update_max_visited()
    local cur_line = self._cur_line

    if cur_line > self._max_visited_line then
        self._max_visited_line = cur_line
    end
end

-- Set writing position to given `line_num`.
---@param line_num integer
function HighlightBuilder:seek_line(line_num)
    if line_num < 1 then
        line_num = 1
    end

    self._cur_line = line_num
    self:_try_update_max_visited()
end

-- Shifting to next line. A new line will be appended to builder if there's not
-- already one.
function HighlightBuilder:next_line()
    self._cur_line = self._cur_line + 1
    self:_try_update_max_visited()
end

-- Get byte length of current line.
---@return integer
function HighlightBuilder:get_cur_line_len()
    local line = self._lines[self._cur_line]
    if not line then return 0 end

    local sum = 0
    for _, part in ipairs(line.parts) do
        sum = sum + part:len()
    end
    return sum
end

-- Get display width of current line.
---@return integer
function HighlightBuilder:get_cur_line_display_width()
    local line = self._lines[self._cur_line]
    if not line then return 0 end

    local sum = 0
    for _, part in ipairs(line.parts) do
        sum = sum + vim.fn.strdisplaywidth(part)
    end
    return sum
end

-- Write one segment with given highlight group into builder.
---@param content string
---@param hl_group string
function HighlightBuilder:write(content, hl_group)
    vim.validate {
        content = { content, "s" },
        hl_group = { hl_group, "s" },
    }

    local cur_line = self._cur_line
    local line = self._lines[cur_line]
    if not line then
        line = { parts = {}, hl_groups = {} }
        self._lines[cur_line] = line
    end

    local parts = line.parts
    parts[#parts + 1] = content

    local hl_groups = line.hl_groups
    hl_groups[#hl_groups + 1] = hl_group
end

---@param line_num integer # 1-base index of line
---@return string line
---@return mongo.highlight.HLItem[] hl_line
function HighlightBuilder:build_line(line_num)
    local line = self._lines[line_num]
    if not line then
        return "", {}
    end

    local parts = line.parts
    local hl_groups = line.hl_groups

    assert(#parts == #hl_groups, "unequal parts and highlight groups count")

    local sum = 0
    local hl_items = {}
    for i, hl_group in ipairs(hl_groups) do
        local ed = sum + parts[i]:len()
        hl_items[#hl_items + 1] = { name = hl_group, st = sum, ed = ed }
        sum = ed
    end

    return table.concat(parts), hl_items
end

-- Genrate text lines and highlight infomation of each line with builder content.
-- This method asumes content in builder is continous.
---@return string[] lines
---@return mongo.highlight.HLItem[][]
function HighlightBuilder:build()
    local str_lines = {} ---@type string[]
    local hl_lines = {} ---@type mongo.highlight.HighlightBuilder[][]

    for i = 1, #self._lines do
        local line, hl_line = self:build_line(i)
        str_lines[#str_lines + 1] = line
        hl_line[#hl_line + 1] = hl_line
    end

    return str_lines, hl_lines
end

---@param bufnr integer
---@param st_row integer
---@param lines string[]
---@param hl_lines mongo.highlight.HLItem[]
function HighlightBuilder:_write_chunk_to_buffer(bufnr, st_row, lines, hl_lines)
    local st = st_row - 1
    local ed = st + #lines

    local cur_line_cnt = api.nvim_buf_call(bufnr, function()
        return vim.fn.line("$")
    end)

    if ed > cur_line_cnt then
        local place_holder = {}
        for _ = cur_line_cnt + 1, ed do
            place_holder[#place_holder + 1] = ""
        end

        vim.api.nvim_buf_set_lines(bufnr, cur_line_cnt, cur_line_cnt, true, place_holder)
    end

    vim.api.nvim_buf_set_lines(bufnr, st, ed, true, lines)
    M.add_hl_to_buffer(bufnr, st, hl_lines)
end

-- Write highlighted lines to buffer. Builder content doesn't need to be continous.
-- Gaps are ignored, and no operation will be done to that line.
---@param bufnr integer
function HighlightBuilder:write_to_buffer(bufnr)
    local lines = self._lines

    local cur_st = 0
    local processed_lines = {}
    local processed_hl_lines = {}

    for i = 1, self._max_visited_line do
        local line = lines[i]

        if line and #line.parts > 0 then
            if cur_st <= 0 then
                cur_st = i
            end
            local result_line, hl_line = self:build_line(i)
            processed_lines[#processed_lines + 1] = result_line
            processed_hl_lines[#processed_hl_lines + 1] = hl_line
        elseif cur_st > 0 then
            self:_write_chunk_to_buffer(bufnr, cur_st, processed_lines, processed_hl_lines)
            cur_st = 0
            processed_lines = {}
            processed_hl_lines = {}
        end
    end

    if cur_st > 0 then
        self:_write_chunk_to_buffer(bufnr, cur_st, processed_lines, processed_hl_lines)
    end
end

-- ----------------------------------------------------------------------------

return M
