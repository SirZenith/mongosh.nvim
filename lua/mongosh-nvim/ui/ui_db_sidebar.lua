local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"

local api = vim.api

local M = {}

---@class mongo.ui.DBSideItem
---@field name string
---@field collections string[]
--
---@field expanded boolean
local DBSideItem = {}
DBSideItem.__index = DBSideItem

---@param name string
---@return mongo.ui.DBSideItem
function DBSideItem:new(name)
    local obj = setmetatable({}, self)

    obj.name = name
    obj.collections = {}

    obj.expanded = false

    return obj
end

-- update_collections sets collection name list with given name array.
---@param collections string[]
function DBSideItem:update_collections(collections)
    local names = {}
    local cnt = 0

    for _, name in ipairs(collections) do
        names[#names + 1] = name
        cnt = cnt + 1
    end

    self.collections = names
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

---@param buffer string[]
---@return integer line_cnt
function DBSideItem:write_name(buffer)
    local symbol_map = self.expanded and config.sidebar.symbol.expanded or config.sidebar.symbol.collapsed

    local indicator = symbol_map.indicator
    local symbol = symbol_map.database

    buffer[#buffer + 1] = indicator .. symbol .. self.name

    return 1
end

---@param buffer string[]
---@return integer line_cnt
function DBSideItem:write_collections(buffer)
    local sum = 0

    local symbol_map = self.expanded and config.sidebar.symbol.expanded or config.sidebar.symbol.collapsed

    local indent = (" "):rep(config.sidebar.padding)
    local symbol = symbol_map.collection

    for _, name in ipairs(self.collections) do
        local line = indent .. symbol .. name
        buffer[# buffer + 1] = line
        sum = sum + 1
    end

    return sum
end

---@param buffer string[]
---@return integer line_cnt
function DBSideItem:write_to_buffer(buffer)
    local sum = self:write_name(buffer)

    if self.expanded then
        sum = sum + self:write_collections(buffer)
    end

    return sum
end

-- ----------------------------------------------------------------------------

---@class mongo.ui.UIDBSidebar
---@field bufnr? integer
---@field databases mongo.ui.DBSideItem[]
local UIDBSidebar = {}
UIDBSidebar.__index = UIDBSidebar

---@return mongo.ui.UIDBSidebar
function UIDBSidebar:new()
    local obj = setmetatable({}, self)

    obj.bufnr = nil
    obj.databases = {}

    return obj
end

-- update_databases sets database name list with given name array.
function UIDBSidebar:update_databases(databases)
    local items = {}

    for _, name in ipairs(databases) do
        items[#items + 1] = DBSideItem:new(name)
    end

    self.databases = items
end

---@return integer? bufnr
function UIDBSidebar:_get_buffer()
    local bufnr = self.bufnr
    if not bufnr or bufnr <= 0 then
        bufnr = api.nvim_create_buf(false, true)

        if bufnr <= 0 then
            log.warn("failed to create sidebar buffer")
        else
            self.bufnr = bufnr
        end
    end

    return bufnr
end

function UIDBSidebar:show()
    local bufnr = self:_get_buffer()
    if not bufnr then return end

    local bo = vim.bo[bufnr]
    bo.bufhidden = "delete"
    bo.buftype = "nofile"
    bo.modifiable = false

    vim.cmd("leftabove" .. tostring(config.sidebar.width) .. "vsplit")
    local winnr = api.nvim_get_current_win()

    api.nvim_win_set_buf(winnr, bufnr)

    self:write_to_buffer()
end

function UIDBSidebar:write_to_buffer()
    local bufnr = self:_get_buffer()
    if not bufnr then return end

    local bo = vim.bo[bufnr]
    bo.modifiable = true

    local lines = {}
    local sum = 0
    for _, item in ipairs(self.databases) do
        sum = sum + item:write_to_buffer(lines)
    end

    api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

    bo.modifiable = false
end

-- ----------------------------------------------------------------------------

M.UIDBSidebar = UIDBSidebar

return M
