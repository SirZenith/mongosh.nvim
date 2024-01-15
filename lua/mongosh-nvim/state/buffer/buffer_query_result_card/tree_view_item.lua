local api_core = require "mongosh-nvim.api.core"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local config = require "mongosh-nvim.config"
local hl_const = require "mongosh-nvim.constant.highlight"
local util = require "mongosh-nvim.util"
local hl_util = require "mongosh-nvim.util.highlight"
local list_util = require "mongosh-nvim.util.list"
local str_util = require "mongosh-nvim.util.str"

local card_bson_types = require "mongosh-nvim.state.buffer.buffer_query_result_card.bson_types"
local card_util = require "mongosh-nvim.state.buffer.buffer_query_result_card.util"

local ValueType = buffer_const.BSONValueType
local NestingType = buffer_const.TreeEntryNestingType
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
---@field hl_items mongo.higlight.HLItem[]

-- ----------------------------------------------------------------------------

---@class mongo.buffer.TreeViewItem
---@field name string | number
---@field value? any
---@field type string
--
---@field is_top_level boolean # whether current item is tree view root
---@field children? table<number | string, mongo.buffer.TreeViewItem>
---@field child_table_type mongo.TreeEntryNestingType
---@field parent? mongo.buffer.TreeViewItem
--
---@field expanded boolean
---@field st_row integer # 1-base beginning row number of display range
---@field ed_row integer # 1-base ending row number of display range
--
---@field card_st_col integer # 1-base column index, recording starting point of object card
---@field card_max_content_col integer # 1-base column index, recording position of last character of longest card content line.
---@field obj_key_show_order? (string | number)[] # display order of object field used during last write.
local TreeViewItem = {}
TreeViewItem.__index = TreeViewItem

---@param value any
---@return mongo.buffer.TreeViewItem
function TreeViewItem:new(value)
    local obj = setmetatable({}, self)

    self.expanded = false
    self.st_row = 0
    self.ed_row = 0
    self.card_st_col = 0
    self.card_max_content_col = 0

    obj:update_binded_value(value)

    return obj
end

---@param value any
function TreeViewItem:update_binded_value(value)
    self.child_table_type = NestingType.None

    self.value = value
    self.type = ValueType.Unknown

    local value_t = type(value)
    if value_t ~= "table" then
        -- simple type
        self.type = SIMPLE_TYPE_MAP[value_t] or ValueType.Unknown
        if self.type == ValueType.Unknown then
            self.value = nil
        end
    else
        -- BSON type
        for key, type_name in pairs(COMPOSED_TYPE_IDENT_KEY) do
            if value[key] then
                self.type = type_name
                break
            end
        end

        if self.type == ValueType.Unknown then
            -- array or object value
            local children = self.children
            if not children then
                children = {}
                self.children = children
            end

            -- update children value
            for k, v in pairs(value) do
                local child = children[k]
                if child then
                    child:update_binded_value(v)
                else
                    child = TreeViewItem:new(v)
                    children[k] = child
                    child.name = k
                    child.parent = self
                end
            end

            -- remove deleted children
            for k in pairs(children) do
                if value[k] == nil then
                    children[k] = nil
                end
            end

            self.value = nil
            self.child_table_type = self:get_nested_table_type()

            if self.child_table_type == NestingType.Array then
                self.type = ValueType.Array
            elseif self.child_table_type == NestingType.Object then
                self.type = ValueType.Object
            end
        end
    end

    if self.is_top_level
        and self.child_table_type == NestingType.Array
    then
        self.expanded = true

        local children = self.children
        if children and #children == 1 then
            children[1].expanded = true
        end
    end
end

function TreeViewItem:toggle_expansion()
    self.expanded = not self.expanded
end

---@return mongo.TreeEntryNestingType
function TreeViewItem:get_nested_table_type()
    local children = self.children
    if not children then return NestingType.None end

    local cnt = 0
    for _ in pairs(children) do
        cnt = cnt + 1
    end

    if cnt == 0 then
        return NestingType.EmptyTable
    end

    local continous = true
    for i = 1, cnt do
        if children[i] == nil then
            continous = false
            break
        end
    end

    return continous and NestingType.Array or NestingType.Object
end

-- Read current line length from builder. If line length is greater than recorded
-- max content length, update recorded value.
-- This method is supposed to be called before adding shifting builder to new
-- line and after an child entry calls its `write_to_builder` method.
---@param builder mongo.highlight.HighlightBuilder
function TreeViewItem:try_update_max_content_col(builder)
    local line_len = builder:get_cur_line_len()
    if self.card_max_content_col < line_len then
        self.card_max_content_col = line_len
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
function TreeViewItem:write_simple_value(builder, indent_level)
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
        if children then
            for _ in pairs(children) do
                digest = "..."
                break
            end
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
function TreeViewItem:write_array_table(builder, indent_level)
    -- Top level array is transparent, all elementse are exposed directly without
    -- wrapping.

    local is_top_level = self.is_top_level
    if is_top_level then
        indent_level = indent_level - 1
    else
        builder:write("[", get_key_hl_by_indent_level(indent_level))
    end

    local children = self.children or {}
    local child_cnt = #children
    local indent_hl_group = get_key_hl_by_indent_level(indent_level)

    local edge_char = config.card_view.card.edge_char.left

    for i = 1, child_cnt do
        local item = children[i]

        self:try_update_max_content_col(builder)
        builder:new_line()

        local is_card = is_top_level
            and item.expanded
            and item.child_table_type == NestingType.Object

        builder:write(get_type_display_name(item.type), HLGroup.ValueTypeName)

        if not is_card then
            builder:write(edge_char, indent_hl_group)
            builder:write(get_indent_str_by_indent_level(indent_level + 1), indent_hl_group)
        end

        item:write_to_builder(builder, indent_level + 1, is_card)
        if item.card_max_content_col > self.card_max_content_col then
            self.card_max_content_col = item.card_max_content_col
        end
    end

    if not self.is_top_level then
        if child_cnt > 0 then
            self:try_update_max_content_col(builder)
            builder:new_line()
            builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)
            builder:write(edge_char, indent_hl_group)
            builder:write(get_indent_str_by_indent_level(indent_level), HLGroup.TreeNormal)
        end

        builder:write("]", get_key_hl_by_indent_level(indent_level))
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
---@param is_card boolean
function TreeViewItem:write_object_table(builder, indent_level, is_card)
    is_card = is_card or false

    local edge_char = config.card_view.card.edge_char.left
    local nested_hl_group = get_key_hl_by_indent_level(indent_level + 1)
    local key_hl_group = get_key_hl_by_indent_level(indent_level)

    local children = self.children or {}
    local keys = {}
    if children then
        for k in pairs(self.children) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
    end
    self.obj_key_show_order = keys

    local child_cnt = #keys

    if not is_card then
        if self.is_top_level then
            builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)
            builder:write(edge_char, key_hl_group)
            builder:write(get_indent_str_by_indent_level(indent_level), HLGroup.TreeNormal)
        end
        builder:write(("{"), get_key_hl_by_indent_level(indent_level))
    end

    for i = 1, child_cnt do
        local key = keys[i]
        local item = children[key]

        self:try_update_max_content_col(builder)
        builder:new_line()
        builder:write(get_type_display_name(item.type), HLGroup.ValueTypeName)

        if is_card and self.card_st_col == 0 then
            self.card_st_col = builder:get_cur_line_len()
        end

        local edge_hl_group = item.child_table_type ~= NestingType.None
            and nested_hl_group
            or key_hl_group
        builder:write(edge_char, edge_hl_group)
        builder:write(get_indent_str_by_indent_level(indent_level + 1), HLGroup.TreeNormal)
        builder:write(tostring(key), key_hl_group)
        builder:write(": ", HLGroup.TreeNormal)
        item:write_to_builder(builder, indent_level + 1)

        if item.card_max_content_col > self.card_max_content_col then
            self.card_max_content_col = item.card_max_content_col
        end
    end

    if child_cnt > 0 then
        self:try_update_max_content_col(builder)
        builder:new_line()
        builder:write((" "):rep(MAX_TYPE_NAME_LEN), HLGroup.TreeNormal)

        if not is_card then
            builder:write(edge_char, key_hl_group)
            builder:write(get_indent_str_by_indent_level(indent_level), key_hl_group)
        end
    end

    if not is_card then
        builder:write(("}"), get_key_hl_by_indent_level(indent_level))
    end
end

---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
---@param is_card boolean
function TreeViewItem:write_table_value(builder, indent_level, is_card)
    local nesting_type = self.child_table_type

    if not self.expanded or nesting_type == NestingType.EmptyTable then
        self:write_collapsed_table(builder, indent_level)
    elseif nesting_type == NestingType.Array then
        self:write_array_table(builder, indent_level)
    elseif nesting_type == NestingType.Object then
        self:write_object_table(builder, indent_level, is_card)
    else
        builder:write("<lua-table>", HLGroup.ValueOmited)
    end
end

-- Write all child object cards' edges to builder.
---@param builder mongo.highlight.HighlightBuilder
---@param indent_level integer
function TreeViewItem:finishing_object_cards(builder, indent_level)
    if self.child_table_type ~= NestingType.Array then
        return
    end

    local line_pos_cache = builder:get_line_cnt()

    local children = self.children
    if not children then return end

    local child_cnt = #children
    if child_cnt == 0 then
        return
    end

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

    local left_edge_len = card_config.edge_char.left:len()

    for i = 1, child_cnt do
        local item = children[i]
        if item.expanded
            and item.child_table_type == NestingType.Object
        then
            local st, ed = item.st_row, item.ed_row

            builder:seek_line(st)
            builder:write(top_edge, hl_group)

            for row = st + 1, ed - 1 do
                builder:seek_line(row)

                local line_len = builder:get_cur_line_len()
                local right_edge = table.concat {
                    (" "):rep(max_col - line_len + padding_width + left_edge_len),
                    card_config.edge_char.right,
                }
                builder:write(right_edge, hl_group)
            end

            builder:seek_line(ed)
            builder:write(bottom_edge, hl_group)
        end
    end

    builder:seek_line(line_pos_cache)
end

-- Write tree structure into a highlight builder
---@param builder mongo.highlight.HighlightBuilder
---@param indent_level? integer
---@param is_card? boolean
function TreeViewItem:write_to_builder(builder, indent_level, is_card)
    indent_level = indent_level or 0
    is_card = is_card or false

    self.st_row = builder:get_line_cnt()
    self.card_st_col = 0
    self.card_max_content_col = 0
    self.obj_key_show_order = nil

    if self.child_table_type == NestingType.None then
        self:write_simple_value(builder, indent_level)
    else
        self:write_table_value(builder, indent_level, is_card)
    end

    self.ed_row = builder:get_line_cnt()

    if self.is_top_level and self.expanded then
        self:finishing_object_cards(builder, indent_level)
    end
end

-- Format current tree structure with highlight and write readable form into
-- given buffer.
---@param bufnr integer
function TreeViewItem:write_to_buffer(bufnr)
    local builder = hl_util.HighlightBuilder:new()
    self:write_to_builder(builder)

    local lines, hl_lines = builder:build()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    hl_util.add_hl_to_buffer(bufnr, 0, hl_lines)
end

-- Try to toggle expansion state of an entry at row number `at_row`.
-- If an entry do gets toggled, this function returns `true`.
---@parat_row integer # line number of cursor line, 1-base
---@return boolean updated
function TreeViewItem:on_selected(at_row)
    if at_row < self.st_row or at_row > self.ed_row then
        return false
    end

    local updated = false

    local children = self.children
    if children and self.expanded then
        for _, item in pairs(children) do
            updated = item:on_selected(at_row)

            if updated then
                break
            end
        end
    end

    if not updated and at_row == self.st_row then
        self:toggle_expansion()
        updated = true
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
        local item = children._id
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

    local ordered_keys = self.obj_key_show_order
    local total_cnt = ordered_keys and #ordered_keys or #children

    for i = 1, total_cnt do
        local key = ordered_keys and ordered_keys[i] or i

        local child = children[key]
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

    local ordered_keys = item.obj_key_show_order
    if not ordered_keys then
        return "curent entry lacks field display order infomation", nil
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

            vim.print(value_json)

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
