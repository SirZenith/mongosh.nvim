local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local config = require "mongosh-nvim.config"
local hl_const = require "mongosh-nvim.constant.highlight"
local util = require "mongosh-nvim.util"
local buffer_util = require "mongosh-nvim.util.buffer"
local hl_util = require "mongosh-nvim.util.highlight"
local list_util = require "mongosh-nvim.util.list"
local str_util = require "mongosh-nvim.util.str"

local card_bson_types = require "mongosh-nvim.state.buffer.buffer_query_result_card.bson_types"
local card_util = require "mongosh-nvim.state.buffer.buffer_query_result_card.util"

local ValueType = buffer_const.BSONValueType
local NestingType = buffer_const.TreeEntryNestingType
local NESTING_TYPE_TO_VALUE_TYPE = buffer_const.NESTING_TYPE_TO_VALUE_TYPE
local HLGroup = hl_const.HighlightGroup

local COMPOSED_TYPE_IDENT_KEY = card_bson_types.COMPOSED_TYPE_IDENT_KEY
local MAX_TYPE_NAME_LEN = card_bson_types.MAX_TYPE_NAME_LEN
local SIMPLE_TYPE_MAP = card_bson_types.SIMPLE_TYPE_MAP
local VALUE_TYPE_NAME_MAP = card_bson_types.VALUE_TYPE_NAME_MAP

local get_type_display_name = card_bson_types.get_type_display_name
local get_key_hl_by_indent_level = card_util.get_key_hl_by_indent_level

-- ----------------------------------------------------------------------------

---@param indent_level integer
---@param including_type_name_width? boolean # set this to `true` for lines not preceding by value type name
---@return integer
local function get_indent_width_by_indent_level(indent_level, including_type_name_width)
    local indent_width = config.card_view.card.padding + config.card_view.indent_size * indent_level
    if including_type_name_width then
        indent_width = indent_width + MAX_TYPE_NAME_LEN
    end
    return indent_width
end

---@param indent_level integer
---@param including_type_name_width? boolean # set this to `true` for lines not preceding by value type name
---@return string
local function get_indent_str_by_indent_level(indent_level, including_type_name_width)
    local width = get_indent_width_by_indent_level(indent_level, including_type_name_width)
    return (" "):rep(width)
end

-- ----------------------------------------------------------------------------

---@class mongo.buffer.TreeHLItem
---@field name string
---@field st integer # stating column index, 0-base
---@field ed integer # ending column index, 0-base, exclusive

---@class mongo.buffer.TreeViemWriteInfo
---@field line string
---@field hl_items mongo.highlight.HLItem[]

---@class mongo.buffer.TreeViewWriteContext
---@field write_range? { [1]: integer, [2]:integer } # visible range of buffer, both values are

-- ----------------------------------------------------------------------------

---@class mongo.buffer.TreeViewItem
---@field name string | number
---@field value? any
---@field type string
---@field is_card boolean # whether this entry should be drawn as a card
--
---@field children? mongo.buffer.TreeViewItem[]
---@field child_table_type mongo.buffer.TreeEntryNestingType
---@field parent? mongo.buffer.TreeViewItem
--
---@field expanded boolean
---@field folding_level integer
---@field child_depth integer
--
---@field st_row integer # 1-base beginning row number of display range
---@field ed_row integer # 1-base ending row number of display range
--
---@field card_st_col integer # 1-base column index, recording starting point of object card
---@field card_max_content_col integer # 1-base column index, recording position of last character of longest card content line.
--
---@field display_height integer # number of lines needed to deisplay this entry in buffer
---@field write_dirty boolean # whether entry's display range has changed since last write.
---@field card_edge_dirty boolean
local TreeViewItem = {}
TreeViewItem.__index = TreeViewItem

---@param value any
---@param parent? mongo.buffer.TreeViewItem
---@return mongo.buffer.TreeViewItem
function TreeViewItem:new(value, parent)
    local obj = setmetatable({}, self)

    obj.name = 0
    obj.value = nil
    obj.type = ValueType.Unknown

    obj.children = nil
    obj.child_table_type = NestingType.None
    obj.parent = parent

    obj.expanded = false
    obj.folding_level = 0
    obj.child_depth = 0

    obj.st_row = 0
    obj.ed_row = 0

    obj.card_st_col = 0
    obj.card_max_content_col = 0

    obj.display_height = 0
    obj.write_dirty = true
    obj.card_edge_dirty = true

    obj:update_binded_value(value)

    return obj
end

---@param value any
function TreeViewItem:update_binded_value(value)
    self.child_depth = 0
    self.child_table_type = NestingType.None

    self.value = nil
    self.type = ValueType.Unknown

    local value_t = type(value)
    if value_t ~= "table" then
        -- simple type
        local type = SIMPLE_TYPE_MAP[value_t] or ValueType.Unknown
        self.type = type
        self.value = type ~= ValueType.Unknown and value or nil
        self.children = nil
    else
        local type = ValueType.Unknown
        for key, type_name in pairs(COMPOSED_TYPE_IDENT_KEY) do
            if value[key] then
                type = type_name
                break
            end
        end

        if type == ValueType.Unknown then
            -- JSON array or object
            self:load_child_value(value)
        else
            -- BSON type
            self.type = type
            self.value = value
            self.children = nil
        end
    end

    self:update_expansion_state()
    self:update_card_flag()

    self:mark_display_height_dirty()
    if not self.parent then
        self:update_display_range(1)
    end
end

-- Load JSON array and object as tree structure.
function TreeViewItem:load_child_value(value)
    local old_children = self.children

    local child_map = {}
    if old_children then
        for _, child in ipairs(old_children) do
            local key = child.name

            if value[key] ~= nil then
                child_map[key] = child
            end
        end
    end

    -- merging new values
    local max_depth = 0
    for k, v in pairs(value) do
        local child = child_map[k]
        if child then
            child:update_binded_value(v)
        else
            child = TreeViewItem:new(v, self)
            child_map[k] = child
            child.name = k
        end

        local depth = child.child_depth + 1
        if depth > max_depth then
            max_depth = depth
        end
    end

    -- load new children
    local keys = {}
    for k in pairs(child_map) do
        keys[#keys + 1] = k
    end
    table.sort(keys)

    local children = {}
    for _, k in ipairs(keys) do
        children[#children + 1] = child_map[k]
    end

    self.children = children
    self.child_depth = max_depth

    -- determine value type
    local nesting_type = self:get_nested_table_type()
    local value_type = NESTING_TYPE_TO_VALUE_TYPE[nesting_type] or ValueType.Unknown

    self.type = value_type
    self.value = nil
    self.child_table_type = nesting_type
end

-- Setup expansion state for special elements after binded value gets updated.
function TreeViewItem:update_expansion_state()
    if not self.parent then
        self.expanded = true

        local children = self.children
        if children and #children == 1 then
            children[1].expanded = true
        end
    end
end

-- Set `is_card` flag for special elements
function TreeViewItem:update_card_flag()
    local children = self.children
    if not self.parent
        and self.child_table_type == NestingType.Array
        and children
    then
        for _, child in ipairs(children) do
            child.is_card = child.child_table_type == NestingType.Object
        end
    end
end

-- Compute number of lines needed to write current entry into buffer. Result will
-- be stored to field `display_height` and returned at the same time.
-- If there is non-zero value in `display_height`, this method will return that
-- value directly.
---@return integer
function TreeViewItem:get_display_height()
    local display_height = self.display_height
    if display_height > 0 then
        return display_height
    end

    local children = self.children
    if not self.expanded
        or not children
        or #children == 0
    then
        display_height = 1
    else
        display_height = 2 -- 2 lines for brackets and braces
        for _, child in ipairs(children) do
            display_height = display_height + child:get_display_height()
        end
    end

    self.display_height = display_height

    return display_height
end

function TreeViewItem:mark_display_height_dirty()
    self.display_height = 0
    self.write_dirty = true
    self.card_edge_dirty = true
end

function TreeViewItem:mark_display_height_dirty_recursive()
    self:mark_display_height_dirty()

    local children = self.children
    if not children then return end

    for _, child in ipairs(children) do
        child:mark_display_height_dirty_recursive()
    end
end

-- Update display range in a top-down maner.
---@param cur_row integer
---@return integer integer
function TreeViewItem:update_display_range(cur_row)
    self.st_row = cur_row

    local children = self.children
    if self.expanded and children then
        cur_row = cur_row + 1 -- plus one because of `[` and `{`
        for _, child in ipairs(children) do
            cur_row = child:update_display_range(cur_row)
        end
    end

    self.display_height = 0
    local new_cur_row = self.st_row + self:get_display_height()
    self.ed_row = new_cur_row - 1

    return new_cur_row
end

-- Propagate change of display height bottom-up, starting form current entry.
function TreeViewItem:display_height_changed()
    if self.expanded then
        self:mark_display_height_dirty_recursive()
    else
        self:mark_display_height_dirty()
    end

    local walker = self --[[@as mongo.buffer.TreeViewItem?]]
    while walker do
        local cur_row = walker.st_row

        walker:mark_display_height_dirty()
        cur_row = walker:update_display_range(cur_row)

        local parent = walker.parent
        local siblings = parent and parent.children --[[@as mongo.buffer.TreeViewItem[]?]]
        if siblings then
            local index = list_util.find(siblings, walker)

            if index > 0 then
                for i = index + 1, #siblings do
                    local sib = siblings[i]
                    if sib.expanded then
                        sib:mark_display_height_dirty_recursive()
                    else
                        sib:mark_display_height_dirty()
                    end
                    cur_row = sib:update_display_range(cur_row)
                end
            end
        end

        walker = parent
    end
end

---@param indent? string
function TreeViewItem:_debug_print_display_range(indent)
    indent = indent and indent .. "    " or ""
    local line = ("%s(%d, %d)"):format(indent, self.st_row, self.ed_row)
    vim.print(line)

    local children = self.children
    if children then
        for _, child in ipairs(children) do
            child:_debug_print_display_range(indent)
        end
    end
end

function TreeViewItem:toggle_expansion()
    local expanded = not self.expanded
    self.expanded = expanded
    self:display_height_changed()
end

---@param level integer
---@param max_sibling_depth integer # maximum depth among sibling entries.
---@return boolean updated
function TreeViewItem:_set_folding_level(level, max_sibling_depth)
    local cur_depth = self.child_depth

    -- Having a deeper nested sibling is equivalent to have a smaller folding
    -- level for current entry and its children.
    level = level - (max_sibling_depth - cur_depth)

    local expaneded = cur_depth > level
    local updated = self.expanded ~= expaneded

    self.expanded = expaneded
    self.folding_level = level > 0 and level or 0

    local children = self.children
    if children then
        for i = 1, #children do
            updated = children[i]:_set_folding_level(level, cur_depth - 1) or updated
        end
    end

    if updated and not self.parent then
        self:mark_display_height_dirty_recursive()
        self:update_display_range(1)
    end

    return updated
end

-- Set folding level of current entry. As folding level gets higher, the outter
-- layer of entry gets folded.
-- If expansion state changed after change of folding level, `true` will be
-- returned.
---@param level integer
---@return boolean updated
function TreeViewItem:set_folding_level(level)
    return self:_set_folding_level(level, self.child_depth)
end

-- Expand current entry and all of its children.
---@return boolean updated # `true` when expansion state changed.
function TreeViewItem:expand_all()
    local updated = not self.expanded

    self.expanded = true
    self.folding_level = 0

    local children = self.children
    if children then
        for i = 1, #children do
            updated = children[i]:expand_all() or updated
        end
    end

    if updated then
        self:mark_display_height_dirty()

        if not self.parent then
            self:update_display_range(1)
        end
    end

    return updated
end

-- Fold current entry and all of its children.
---@return boolean upated # `true` when expansion state changed.
function TreeViewItem:fold_all()
    local updated = self.expanded

    self.expanded = false
    self.folding_level = self.child_depth + 1

    local children = self.children
    if children then
        for i = 1, #children do
            updated = children[i]:fold_all() or updated
        end
    end


    if updated then
        self:mark_display_height_dirty()

        if not self.parent then
            self:update_display_range(1)
        end
    end

    return updated
end

---@return mongo.buffer.TreeEntryNestingType
function TreeViewItem:get_nested_table_type()
    local children = self.children
    if not children then return NestingType.None end

    if #children == 0 then
        return NestingType.EmptyTable
    end

    local is_numeric_indexed = true
    for i, child in ipairs(children) do
        if child.name ~= i then
            is_numeric_indexed = false
            break
        end
    end

    return is_numeric_indexed and NestingType.Array or NestingType.Object
end

-- Read current line length from builder. If line length is greater than recorded
-- max content length, update recorded value.
-- This method is supposed to be called before adding shifting builder to new
-- line and after an child entry calls its `write_to_builder` method.
---@param builder mongo.highlight.HighlightBuilder
function TreeViewItem:try_update_max_content_col(builder)
    local line_len = builder:get_cur_line_display_width()
    if self.card_max_content_col < line_len then
        self.card_max_content_col = line_len
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
function TreeViewItem:write_simple_value(builder, indent_level)
    if not self.write_dirty then return end

    local meta = VALUE_TYPE_NAME_MAP[self.type]
    local write = meta and meta.write

    if write then
        write(self.value, builder, indent_level)
    else
        builder:write(tostring(self.value), HLGroup.TreeNormal)
    end
end

---@param builder mongo.highlight.HighlightBuilder
function TreeViewItem:write_collapsed_table(builder, indent_level)
    if not self.write_dirty then return end

    local nesting_type = self.child_table_type

    local children = self.children

    local lhs, rhs = "<", ">"
    local digest
    if nesting_type == NestingType.Array then
        lhs, rhs = "[", "]"
        if children and #children > 0 then
            digest = "..."
        end
    elseif nesting_type == NestingType.Object then
        lhs, rhs = "{", "}"
        if children and #children > 0 then
            digest = "..."
        end
    elseif nesting_type == NestingType.EmptyTable then
        digest = "empty-table"
    else
        digest = "?"
    end

    local key_hl_group = get_key_hl_by_indent_level(indent_level)
    builder:write(lhs, key_hl_group)
    if digest then
        builder:write(digest, HLGroup.ValueOmited)
    end
    builder:write(rhs, key_hl_group)
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
---@param context mongo.buffer.TreeViewWriteContext
function TreeViewItem:write_array_table(builder, indent_level, context)
    -- Top level array is transparent, all elementse are exposed directly without
    -- wrapping.

    local children = self.children or {}
    local child_cnt = #children
    local indent_hl_group = get_key_hl_by_indent_level(indent_level)

    local edge_char = config.card_view.card.edge_char.left

    local is_top_level = not self.parent
    if is_top_level then
        indent_level = indent_level - 1
        builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)
        builder:write(edge_char, indent_hl_group)
    else
        builder:write("[", get_key_hl_by_indent_level(indent_level))
    end

    for i = 1, child_cnt do
        local item = children[i]

        self:try_update_max_content_col(builder)
        builder:next_line()

        local should_write = item:_check_should_write(context)
        if not should_write then
            builder:seek_line(item.ed_row)
        else
            local is_card = item.expanded and item.is_card

            builder:write(get_type_display_name(item.type), HLGroup.ValueTypeName)

            if not is_card then
                builder:write(edge_char, indent_hl_group)
                builder:write(get_indent_str_by_indent_level(indent_level + 1), indent_hl_group)
            end

            item:write_to_builder(builder, indent_level + 1, context)
            if item.card_max_content_col > self.card_max_content_col then
                self.card_max_content_col = item.card_max_content_col
            end
        end
    end

    self:try_update_max_content_col(builder)
    builder:seek_line(self.ed_row)
    builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)
    builder:write(edge_char, indent_hl_group)
    builder:write(get_indent_str_by_indent_level(indent_level), HLGroup.TreeNormal)

    if self.parent then
        builder:write("]", get_key_hl_by_indent_level(indent_level))
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
---@param context mongo.buffer.TreeViewWriteContext
function TreeViewItem:write_object_table(builder, indent_level, context)
    local is_card = self.is_card

    local edge_char = config.card_view.card.edge_char.left
    local nested_hl_group = get_key_hl_by_indent_level(indent_level + 1)
    local key_hl_group = get_key_hl_by_indent_level(indent_level)

    local children = self.children or {}
    local child_cnt = #children

    if not is_card then
        if not self.parent then
            builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)
            builder:write(edge_char, key_hl_group)
            builder:write(get_indent_str_by_indent_level(indent_level), HLGroup.TreeNormal)
        end
        builder:write(("{"), get_key_hl_by_indent_level(indent_level))
    end

    for i = 1, child_cnt do
        local item = children[i]

        self:try_update_max_content_col(builder)
        builder:next_line()
        builder:write(get_type_display_name(item.type), HLGroup.ValueTypeName)

        if is_card and self.card_st_col == 0 then
            self.card_st_col = builder:get_cur_line_display_width()
        end

        local edge_hl_group = item.child_table_type ~= NestingType.None
            and nested_hl_group
            or key_hl_group
        builder:write(edge_char, edge_hl_group)
        builder:write(get_indent_str_by_indent_level(indent_level + 1), HLGroup.TreeNormal)
        builder:write(tostring(item.name), key_hl_group)
        builder:write(": ", HLGroup.TreeNormal)
        item:write_to_builder(builder, indent_level + 1, context)

        if item.card_max_content_col > self.card_max_content_col then
            self.card_max_content_col = item.card_max_content_col
        end
    end

    self:try_update_max_content_col(builder)
    builder:next_line()
    builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)

    if not is_card then
        builder:write(edge_char, key_hl_group)
        builder:write(get_indent_str_by_indent_level(indent_level), key_hl_group)
    end

    if not is_card then
        builder:write(("}"), get_key_hl_by_indent_level(indent_level))
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
---@param context mongo.buffer.TreeViewWriteContext
function TreeViewItem:write_table_value(builder, indent_level, context)
    local nesting_type = self.child_table_type

    if not self.expanded or nesting_type == NestingType.EmptyTable then
        self:write_collapsed_table(builder, indent_level)
    elseif nesting_type == NestingType.Array then
        self:write_array_table(builder, indent_level, context)
    elseif nesting_type == NestingType.Object then
        self:write_object_table(builder, indent_level, context)
    else
        builder:write("<lua-table>", HLGroup.ValueOmited)
    end
end

-- Write all child object cards' edges to builder.
---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
---@param context mongo.buffer.TreeViewWriteContext
function TreeViewItem:finishing_object_cards(builder, indent_level, context)
    -- only expanded top level array entry nees to run this method
    if self.parent
        or not self.expanded
        or self.child_table_type ~= NestingType.Array
    then
        return
    end

    local children = self.children
    if not children then return end

    local child_cnt = #children
    if child_cnt == 0 then return end

    local card_config = config.card_view.card
    local min_card_width = card_config.min_content_width
    local max_card_width = min_card_width
    local max_col = MAX_TYPE_NAME_LEN + min_card_width

    for i = 1, child_cnt do
        local item = children[i]
        local card_width = item.card_max_content_col - item.card_st_col
        if card_width > max_card_width then
            max_card_width = card_width
            max_col = item.card_max_content_col
        end
    end
    if max_card_width == 0 then return end

    local padding_width = card_config.padding
    local hl_group = get_key_hl_by_indent_level(indent_level)

    local top_edge = table.concat {
        card_config.corner_char.top_left,
        card_config.edge_char.top:rep(max_card_width + padding_width),
        card_config.corner_char.top_right,
    }
    local bottom_edge = table.concat {
        card_config.corner_char.bottom_left,
        card_config.edge_char.bottom:rep(max_card_width + padding_width),
        card_config.corner_char.bottom_right,
    }

    local left_edge_len = vim.fn.strdisplaywidth(card_config.edge_char.left)

    local line_pos_cache = builder:get_cur_line()

    for i = 1, child_cnt do
        local item = children[i]
        if item.is_card
            and item.expanded
            and item.card_edge_dirty
            and item:_check_should_write_by_range(context.write_range)
        then
            item.card_edge_dirty = false
            local st, ed = item.st_row, item.ed_row

            -- top bard
            builder:seek_line(st)
            builder:write(top_edge, hl_group)

            -- edges
            for row = st + 1, ed - 1 do
                builder:seek_line(row)

                local line_len = builder:get_cur_line_display_width()
                if line_len > 0 then
                    local right_edge = table.concat {
                        (" "):rep(max_col - line_len + padding_width + left_edge_len),
                        card_config.edge_char.right,
                    }
                    builder:write(right_edge, hl_group)
                end
            end

            -- bottom bar
            builder:seek_line(ed)
            builder:write(bottom_edge, hl_group)
        end
    end

    builder:seek_line(line_pos_cache)
end

---@param range? { [1]: integer, [2]: integer }
function TreeViewItem:_check_should_write_by_range(range)
    if not range then return true end

    if self.st_row > range[2] or self.ed_row < range[1] then
        return false
    end

    return true
end

---@param context mongo.buffer.TreeViewWriteContext
---@return boolean should_write
function TreeViewItem:_check_should_write(context)
    if not self.write_dirty then
        return false
    end

    if self.is_card
        and not self:_check_should_write_by_range(context.write_range)
    then
        return false
    end

    return true
end

-- Write tree structure into a highlight builder
---@param builder mongo.highlight.HighlightBuilder
---@param indent_level? integer
---@param context mongo.buffer.TreeViewWriteContext
function TreeViewItem:write_to_builder(builder, indent_level, context)
    indent_level = indent_level or 0
    self.card_st_col = 0
    self.card_max_content_col = 0

    builder:seek_line(self.st_row)

    if self.child_table_type == NestingType.None then
        self:write_simple_value(builder, indent_level)
    else
        self:write_table_value(builder, indent_level, context)
    end

    builder:seek_line(self.ed_row)

    self:finishing_object_cards(builder, indent_level, context)

    self.write_dirty = false
end

-- Format current tree structure with highlight and write readable form into
-- given buffer.
---@param bufnr integer
function TreeViewItem:write_to_buffer(bufnr)
    local winnr = buffer_util.get_win_by_buf(bufnr, true)
    if not winnr then return end

    local height = vim.api.nvim_win_get_height(winnr)
    local st_row = vim.api.nvim_win_call(winnr, function()
        return vim.fn.getpos("w0")[2]
    end)
    local ed_row = st_row + height - 1

    local builder = hl_util.HighlightBuilder:new()
    self:write_to_builder(builder, nil, {
        write_range = { st_row, ed_row },
    })

    builder:write_to_buffer(bufnr)

    local line_cnt = vim.api.nvim_buf_call(bufnr, function()
        return vim.fn.line("$")
    end)
    if line_cnt > self.ed_row then
        vim.api.nvim_buf_set_lines(bufnr, self.ed_row, line_cnt, true, {})
    end
end

-- Try to toggle expansion state of an entry at row number `at_row`.
-- If an entry do gets toggled, this function returns `true`.
---@parat_row integer # line number of cursor line, 1-base
---@return boolean updated
function TreeViewItem:on_selected(at_row)
    if at_row < self.st_row or at_row > self.ed_row then
        return false
    end

    local children = self.children
    if not children or #children == 0 then
        return false
    end

    if at_row == self.st_row then
        self:toggle_expansion()
        return true
    end

    local updated = false
    if children and self.expanded then
        for _, item in ipairs(children) do
            updated = item:on_selected(at_row)
            if updated then break end
        end
    end

    return updated
end

-- Try to toggle expansion state of the entry under cursor.
---@param bufnr integer
function TreeViewItem:select_with_cursor_pos(bufnr)
    local pos = vim.api.nvim_win_get_cursor(0)
    local updated = self:on_selected(pos[1])

    if updated then
        self:write_to_buffer(bufnr)
    end
end

-- Try to find top most `_id` field of the entry under cursor.
-- If such field is found, value of `_id` field and the Object entry containing
-- that field will be returned.
---@param row? integer # 1-base row index, default to cursor row
---@return any?
---@return mongo.buffer.TreeViewItem?
function TreeViewItem:find_id_field_by_row_num(row)
    if not row then
        row = vim.api.nvim_win_get_cursor(0)[1]
    end

    if row < self.st_row or row > self.ed_row then
        return nil, nil
    end

    local children = self.children
    if not children then return nil, nil end

    local value, target
    local nesting_type = self.child_table_type
    if nesting_type == NestingType.Object then
        -- Searching stops at outter most layer of object entry. `_id` field
        -- nested field value of object should be ignored.
        local item
        for _, child in ipairs(children) do
            if child.name == "_id" then
                item = child
                break
            end
        end

        if item then
            value = item.value
            target = self
        end
    elseif nesting_type == NestingType.Array then
        for _, item in ipairs(children) do
            value, target = item:find_id_field_by_row_num()
            if value ~= nil and target ~= nil then
                break
            end
        end
    end

    return value, target
end

-- Locate a field inside current entry at given row number.
---@param row integer # 1-base row index.
---@return mongo.buffer.TreeViewItem?
function TreeViewItem:get_field_by_row_num(row)
    if self.child_table_type == NestingType.None then
        return nil
    end

    if row < self.st_row or row > self.ed_row then
        return nil
    end

    if not self.expanded and row == self.st_row then
        return self
    end

    local target

    local children = self.children
    if not children then return nil end

    local total_cnt = #children

    for i = 1, total_cnt do
        local child = children[i]
        if child.st_row > row then
            break
        end

        if child.child_table_type == NestingType.None then
            if row == child.st_row then
                target = child
            end
        else
            target = child:get_field_by_row_num(row)
        end

        if target then
            break
        end
    end

    if not target and row == self.st_row then
        target = self
    end

    return target
end

---@class mongo.buffer.TreeEditTarget
---@field id any
---@field field mongo.buffer.TreeViewItem
---@field dot_path (string | number)[]
---@field meta mongo.buffer.ValueTypeMeta

---@param row integer
---@return string? err
---@return mongo.buffer.TreeEditTarget?
function TreeViewItem:find_edit_target(row)
    if not row then
        row = vim.api.nvim_win_get_cursor(0)[1]
    end

    local id, item = self:find_id_field_by_row_num(row)
    if id == nil or not item then
        return "no `_id` field found in current entry", nil
    end

    if not item.expanded then
        return "can't not edit collapsed entry", nil
    end

    local field = item:get_field_by_row_num(row)
    if not field then
        return "no field found under cursor", nil
    end

    local meta = VALUE_TYPE_NAME_MAP[field.type]
    if not meta then
        return "unrecognized type: " .. field.type, nil
    end

    local segments = {}
    local walker = field
    local path_err
    repeat
        segments[#segments + 1] = walker.name
        walker = walker.parent
    until path_err or walker == item or not walker

    if path_err then
        return path_err, nil
    end

    list_util.list_reverse(segments)

    return nil, {
        field = field,
        id = id,
        dot_path = segments,
        meta = meta,
    }
end

-- Issue an edti to the entry at specified row number.
---@param row? integer # 1-base row index, default to cursor row.
---@param collection string
---@param callback fun(err?: string)
function TreeViewItem:try_update_entry_value(row, collection, callback)
    if not row then
        row = vim.api.nvim_win_get_cursor(0)[1]
    end
    local find_err, info = self:find_edit_target(row)
    if find_err or not info then
        callback(find_err or "can't find target field under cursor")
        return
    end

    -- dot path validation
    local err_path
    for _, segment in ipairs(info.dot_path) do
        if type(segment) ~= "string" then
            err_path = "editing array element is not supported"
        elseif type(segment) == "string" and segment:sub(1, 1) == "$" then
            err_path = "unrecognized field name " .. segment
        end

        if err_path then break end
    end
    if err_path then
        callback(err_path)
        return
    end

    local meta = info.meta
    local edit_handler = meta.edit
    if not edit_handler then
        callback("current field type doesn't support editing: " .. info.field.type)
        return
    end

    local dot_path = table.concat(info.dot_path, ".")

    util.do_async_steps {
        function(next_step)
            local prompt = "Edit"
            if meta.edit_type then
                prompt = prompt .. " (type: " .. meta.edit_type .. ")"
            end
            local default
            if meta.edit_default_value then
                default = meta.edit_default_value(info.field.value)
            end
            vim.ui.input({ prompt = prompt .. ": ", default = default }, next_step)
        end,
        function(_, value_str)
            if not value_str then
                callback "edit abort"
                return
            end

            local err_value, value_json = edit_handler(value_str)
            if err_value or not value_json then
                callback(err_value or "invalid input value")
                return
            end

            local snippet = str_util.format(script_const.TEMPLATE_UPDATE_FIELD_VALUE, {
                collection = collection,
                id = vim.json.encode(info.id),
                dot_path = dot_path,
                value = value_json
            })

            api_core.do_update_one(snippet, function(err, result)
                if err then
                    callback(err)
                    return
                end

                result = #result > 0 and result or "execution successed"

                callback()
            end)
        end
    }
end

return TreeViewItem
