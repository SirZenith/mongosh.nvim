local api_core = require "mongosh-nvim.api.core"
local api_buffer = require "mongosh-nvim.api.buffer"
local api_constant = require "mongosh-nvim.constant.api"
local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local hl_const = require "mongosh-nvim.constant.highlight"
local hl_util = require "mongosh-nvim.util.highlight"

local api = vim.api

local core_emitter = api_core.emitter

local CoreEventType = api_constant.CoreEventType
local HLGroup = hl_const.HighlightGroup

local M = {}

---@class mongo.ui.SidebarWriteInfo
---@field line string
---@field hl_items mongo.highlight.HLItem[]

---@class mongo.ui.DBSideItem
---@field name string
---@field collections string[]
--
---@field expanded boolean
---@field is_loading boolean
local DBSideItem = {}
DBSideItem.__index = DBSideItem

---@param name string
---@return mongo.ui.DBSideItem
function DBSideItem:new(name)
    local obj = setmetatable({}, self)

    obj.name = name
    obj.collections = {}

    obj.expanded = false
    obj.is_loading = false

    return obj
end

function DBSideItem:toggle_expansion()
    self.expanded = not self.expanded
end

-- get_display_size returns how many lines this item should take when written
-- to buffer.
---@return integer
function DBSideItem:get_display_size()
    local sum = 1 -- name takes 1 line

    if self.expanded then
        sum = sum + #self.collections
    end

    return sum
end

---@param buffer mongo.ui.SidebarWriteInfo[]
---@return integer line_cnt
function DBSideItem:write_name(buffer)
    local symbol_map = self.expanded and config.sidebar.symbol.expanded or config.sidebar.symbol.collapsed

    local parts = {
        symbol_map.indicator,
        symbol_map.database,
        self.name
    }

    buffer[#buffer + 1] = {
        line = table.concat(parts),
        hl_items = hl_util.update_hl_items_range(parts, {
            { name = HLGroup.Normal,         st = 0, ed = 0 },
            { name = HLGroup.DatabaseSymbol, st = 0, ed = 0 },
            { name = HLGroup.DatabaseName,   st = 0, ed = 0 },
        }),
    }

    return 1
end

---@param buffer mongo.ui.SidebarWriteInfo[]
---@return integer line_cnt
function DBSideItem:write_collections(buffer)
    local sum = 0

    local symbol_map = config.sidebar.symbol.collapsed

    local indent = (" "):rep(config.sidebar.padding)

    if self.is_loading then
        local parts = {
            indent,
            config.sidebar.symbol.loading.collection,
            "loading..."
        }

        buffer[#buffer + 1] = {
            line = table.concat(parts),
            hl_items = hl_util.update_hl_items_range(parts, {
                { name = HLGroup.Normal,                  st = 0, ed = 0 },
                { name = HLGroup.CollectionLoadingSymbol, st = 0, ed = 0 },
                { name = HLGroup.CollectionLoading,       st = 0, ed = 0 },
            }),
        }

        sum = sum + 1
    else
        local symbol = symbol_map.collection
        local parts = { indent, symbol, "" }

        for _, name in ipairs(self.collections) do
            parts[3] = name

            buffer[#buffer + 1] = {
                line = table.concat(parts),
                hl_items = hl_util.update_hl_items_range(parts, {
                    { name = HLGroup.Normal,           st = 0, ed = 0 },
                    { name = HLGroup.CollectionSymbol, st = 0, ed = 0 },
                    { name = HLGroup.CollectionName,   st = 0, ed = 0 },
                })
            }

            sum = sum + 1
        end
    end

    return sum
end

---@param buffer mongo.ui.SidebarWriteInfo[]
---@return integer line_cnt
function DBSideItem:write_to_buffer(buffer)
    local sum = self:write_name(buffer)

    if self.expanded then
        sum = sum + self:write_collections(buffer)
    end

    return sum
end

-- Issue `select` with entry index inside current item. Index is 1-based, stars
-- from entry name and then collection names.
---@return { type: "database" | "collection", name: string }? selection_result
function DBSideItem:select_with_index(index)
    if index == 1 then
        return { type = "database", name = self.name }
    end

    local name = self.collections[index - 1]
    if not name then return nil end

    return { type = "collection", name = name }
end

-- ----------------------------------------------------------------------------

---@class mongo.ui.SideBarDisplayInfo
---@field preview_winnr integer # preview window number in this tabpage
---@field winnr integer # window number used by sidebar buffer

---@class mongo.ui.UIDBSidebar
---@field _bufnr? integer
---@field _databases mongo.ui.DBSideItem[]
--
---@field _item_ranges { st: integer, ed: integer }[] # display range of sidebar items, 1-base closed intervals
local UIDBSidebar = {}
UIDBSidebar.__index = UIDBSidebar

-- Mapping tabpage number to display info in this tabpage.
---@type table<integer, mongo.ui.SideBarDisplayInfo>
UIDBSidebar._display_map = {}

UIDBSidebar.winhl_map = {
    Normal = HLGroup.Normal,
}

-- Get display info for given tabpage.
-- Class method
---@param tabpage integer # tabpage id
function UIDBSidebar:get_info_in_tabpage(tabpage)
    return self._display_map[tabpage]
end

-- UPdate display info for given tabpage.
---@param tabpage integer
---@param info mongo.ui.SideBarDisplayInfo? # passing `nil` means deleting record.
function UIDBSidebar:set_info_in_tabpage(tabpage, info)
    self._display_map[tabpage] = info
end

-- Create a new sidebar object with given window as preview window.
-- When collection in sidebar is selected, new query buffer will be created and
-- displayed in preview window.
---@return mongo.ui.UIDBSidebar
function UIDBSidebar:new()
    local obj = setmetatable({}, self)

    obj._databases = {}
    obj._item_ranges = {}

    obj:init_events()

    return obj
end

function UIDBSidebar:init_events()
    core_emitter:on(CoreEventType.action_connect_end, self.on_action_connect_end, self)
    core_emitter:on(CoreEventType.collection_list_update, self.on_collection_list_update, self)
end

-- Setup basic option and keybinding for sidebar buffer.
function UIDBSidebar:setup_buffer()
    local bufnr = self:get_buffer()

    local bo = vim.bo[bufnr]
    bo.buftype = "nofile"
    bo.filetype = buffer_const.DB_SIDEBAR_FILETYPE
    bo.modifiable = false

    local kset = vim.keymap.set

    kset("n", "<Cr>", function()
        self:select_under_cursor()
    end, { buffer = bufnr })

    kset("n", "<C-r>", function()
        self:update_collection_list_for_all_expanded_db()
    end)
end

-- Setup window option before displying sidebar buffer in that window.
---@param winnr integer
function UIDBSidebar:setup_window(winnr)
    local wo = vim.wo[winnr]
    wo.signcolumn = "yes"
    wo.number = false
    wo.relativenumber = false

    local winhl_buffer = {}
    for k, v in pairs(self.winhl_map) do
        winhl_buffer[#winhl_buffer + 1] = k .. ":" .. v
    end
    wo.winhl = table.concat(winhl_buffer, ",")

    local bufnr = self:get_buffer()
    api.nvim_win_set_buf(winnr, bufnr)
    api.nvim_win_set_width(winnr, config.sidebar.width)
end

-- Set database name list with given name array.
function UIDBSidebar:update_databases(databases)
    local items = {}

    local old_item_map = {} ---@type table<string, mongo.ui.DBSideItem>
    for _, item in ipairs(self._databases) do
        old_item_map[item.name] = item
    end

    for _, name in ipairs(databases) do
        local item = old_item_map[name] or DBSideItem:new(name)
        items[#items + 1] = item
    end

    self._databases = items
end

-- Get buffer number used by sidebar object, a new buffer is created if no validr
-- buffer is currently being in use.
---@return integer bufnr
function UIDBSidebar:get_buffer()
    local bufnr = self._bufnr
    if not bufnr
        or not api.nvim_buf_is_valid(bufnr)
    then
        bufnr = api.nvim_create_buf(false, true)
        self._bufnr = bufnr
        self:setup_buffer()
    end

    return bufnr
end

-- Get preview window number in current tabpage.
---@return integer? winnr
function UIDBSidebar:get_preview_win()
    local tabpage = api.nvim_get_current_tabpage()
    local info = self:get_info_in_tabpage(tabpage)
    if not info then return end

    local preview_winnr = info.preview_winnr

    if not preview_winnr
        or not api.nvim_win_is_valid(preview_winnr)
    then
        vim.cmd "rightbelow vsplit"
        preview_winnr = api.nvim_get_current_win()

        local wo = vim.wo[preview_winnr]
        wo.winhl = ""

        local winnr = info.winnr
        api.nvim_win_set_width(winnr, config.sidebar.width)
        api.nvim_set_current_win(winnr)

        info.preview_winnr = preview_winnr
    end

    return preview_winnr
end

-- Make vertical split on the left, and writes database list to it.
---@param tabpage integer # tabpage id
---@param preview_winnr integer # preview window number
function UIDBSidebar:show(tabpage, preview_winnr)
    local db_names = api_core.get_filtered_db_list()
    self:update_databases(db_names)

    local info = self:get_info_in_tabpage(tabpage)

    local winnr = info and info.winnr
    local bufnr = self:get_buffer()

    if winnr and api.nvim_win_is_valid(info.winnr) then
        api.nvim_win_set_buf(info.winnr, bufnr)
        return
    end

    vim.cmd "leftabove vsplit"
    winnr = api.nvim_get_current_win()
    self:setup_window(winnr)

    self:write_to_buffer()

    self:set_info_in_tabpage(tabpage, {
        preview_winnr = preview_winnr,
        winnr = winnr,
    })
end

-- Hide sidebar in givn tabpage
---@param tabpage integer
function UIDBSidebar:hide(tabpage)
    local info = self:get_info_in_tabpage(tabpage)
    local winnr = info and info.winnr

    if winnr and api.nvim_win_is_valid(winnr) then
        api.nvim_win_hide(winnr)
    end

    self:set_info_in_tabpage(tabpage, nil)
end

-- Check sidebar window is still valid in given window.
---@param tabpage integer
---@return boolean
function UIDBSidebar:is_valid_in_tabpage(tabpage)
    local info = self:get_info_in_tabpage(tabpage)
    local winnr = info and info.winnr

    return winnr ~= nil and api.nvim_win_is_valid(winnr)
end

function UIDBSidebar:on_action_connect_end()
    local db_names = api_core.get_filtered_db_list()
    self:update_databases(db_names)
    self:write_to_buffer()
end

---@param db string
function UIDBSidebar:on_collection_list_update(db)
    local target
    for _, item in ipairs(self._databases) do
        if item.name == db then
            target = item
            break
        end
    end

    if not target then return end

    target.is_loading = false

    local names = api_core.get_collection_names(db)
    if names then
        target.collections = names
    end

    self:write_to_buffer()
end

-- Update content of sidebar buffer
function UIDBSidebar:write_to_buffer()
    local bufnr = self:get_buffer()
    if not bufnr then return end

    local ranges = {}
    local write_infos = {} ---@type mongo.ui.SidebarWriteInfo[]

    local db_addr = api_core.get_cur_db_addr()
    local host_parts = { config.sidebar.symbol.collapsed.host, db_addr }
    write_infos[#write_infos + 1] = {
        line = table.concat(host_parts),
        hl_items = hl_util.update_hl_items_range(host_parts, {
            { name = HLGroup.HostSymbol, st = 0, ed = 0 },
            { name = HLGroup.HostName,   st = 0, ed = 0 },
        })
    }

    local sum = #write_infos
    for _, item in ipairs(self._databases) do
        local line_cnt = item:write_to_buffer(write_infos)
        local range = { st = sum + 1, ed = sum + line_cnt }
        ranges[#ranges + 1] = range

        sum = sum + line_cnt
    end

    self._item_ranges = ranges

    local lines = {}
    local hl_lines = {}
    for _, info in ipairs(write_infos) do
        lines[#lines + 1] = info.line
        hl_lines[#hl_lines + 1] = info.hl_items
    end

    local bo = vim.bo[bufnr]
    bo.modifiable = true

    api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    hl_util.add_hl_to_buffer(bufnr, 0, hl_lines)

    bo.modifiable = false
end

-- Issue `select` movement with current cursor postion
function UIDBSidebar:select_under_cursor()
    local tabpage = api.nvim_get_current_tabpage()
    local info = self:get_info_in_tabpage(tabpage)
    if not info then return end

    local winnr = api.nvim_get_current_win()
    if winnr ~= info.winnr then return end

    local pos = api.nvim_win_get_cursor(winnr)
    local row = pos[1]

    local target_index, entry_index
    for i, range in ipairs(self._item_ranges) do
        if row >= range.st and row <= range.ed then
            target_index = i
            entry_index = row - range.st + 1
            break
        end
    end

    if not target_index or not entry_index then return end

    local target_item = self._databases[target_index]
    local result = target_item:select_with_index(entry_index)
    if not result then
        return
    end

    if result.type == "database" then
        self:on_select_database(target_item)
    elseif result.type == "collection" then
        self:on_select_collection(target_item, result.name)
    end
end

---@param item mongo.ui.DBSideItem
function UIDBSidebar:on_select_database(item)
    item:toggle_expansion()
    if not item.expanded then
        self:write_to_buffer()
        return
    end

    local names = api_core.get_collection_names(item.name)
    if names then
        api_core.switch_to_db(item.name)

        item.collections = names
        self:write_to_buffer()
        return
    end

    local was_loading = item.is_loading;
    item.is_loading = true

    self:write_to_buffer()

    if not was_loading then
        api_core.update_collection_list(item.name)
    end
end

---@param item mongo.ui.DBSideItem
---@param collection string
function UIDBSidebar:on_select_collection(item, collection)
    local preview_winnr = self:get_preview_win()
    api_buffer.create_query_buffer(item.name, collection, preview_winnr)
    self:write_to_buffer()
end

function UIDBSidebar:update_collection_list_for_all_expanded_db()
    for _, item in ipairs(self._databases) do
        if item.expanded and not item.is_loading then
            item.is_loading = true
            api_core.update_collection_list(item.name)
        end
    end
    self:write_to_buffer()
end

-- ----------------------------------------------------------------------------

local db_sidebar = UIDBSidebar:new()

function M.show()
    local tabpage = api.nvim_get_current_tabpage()
    local preview_winnr = api.nvim_get_current_win()
    db_sidebar:show(tabpage, preview_winnr)
end

function M.hide()
    local tabpage = api.nvim_get_current_tabpage()
    db_sidebar:hide(tabpage)
end

function M.toggle()
    local tabpage = api.nvim_get_current_tabpage()
    local is_valid = db_sidebar:is_valid_in_tabpage(tabpage)

    if is_valid then
        M.hide()
    else
        M.show()
    end
end

return M
