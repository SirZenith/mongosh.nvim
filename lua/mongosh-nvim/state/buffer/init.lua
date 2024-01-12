local api_core = require "mongosh-nvim.api.core"
local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local buffer_util = require "mongosh-nvim.util.buffer"
local str_util = require "mongosh-nvim.util.str"
local ts_util = require "mongosh-nvim.util.tree_sitter"

local api = vim.api

local BufferType = buffer_const.BufferType
local CreateBufferStyle = buffer_const.CreateBufferStyle
local ResultSplitStyle = buffer_const.ResultSplitStyle

local FALLBACK_BUFFER_TYPE = BufferType.Unknown;
local FALLBACK_BUFFER_CREATION_STYLE = CreateBufferStyle.OnNeed;
local FALLBACK_RESULT_SPLIT_STYLE = ResultSplitStyle.Vertical;

local M = {}

-- ----------------------------------------------------------------------------

-- map result buffer creation sytle to buffer maker function
---@type table<mongo.CreateBufferStyle, fun(mbuf: mongo.MongoBuffer): integer>
local result_buffer_getter_map = {
    -- No matter whether old buffer exists or not, a new buffer will be created.
    [CreateBufferStyle.Always] = function()
        local buf = api.nvim_create_buf(false, false)
        return buf
    end,
    -- Only create new buffer when no old result buffer exists.
    -- fallback style
    [CreateBufferStyle.OnNeed] = function(mbuf)
        local buf = mbuf.result_bufnr
        if not buf
            or not api.nvim_buf_is_valid(buf)
        then
            buf = api.nvim_create_buf(false, false)
        end
        return buf
    end,
    -- Never create dedicated result buffer, always write result to current buffer
    [CreateBufferStyle.Never] = function(mbuf)
        local buf = mbuf:get_bufnr()
        if not buf
            or not api.nvim_buf_is_valid(buf)
        then
            buf = api.nvim_create_buf(false, false)
        end
        return buf
    end,
}

-- map result window creation style to window maker function
---@type table<mongo.ResultSplitStyle, fun(bufnr: integer): integer>
local result_win_maker_map = {
    [ResultSplitStyle.Horizontal] = function(bufnr)
        local win = buffer_util.get_win_by_buf(bufnr, true)
        if not win then
            vim.cmd "botright split"
            win = api.nvim_get_current_win()
        end

        return win
    end,
    -- fallback style
    [ResultSplitStyle.Vertical] = function(bufnr)
        local win = buffer_util.get_win_by_buf(bufnr, true)
        if not win then
            vim.cmd "rightbelow vsplit"
            win = api.nvim_get_current_win()
        end

        return win
    end,
    [ResultSplitStyle.Tab] = function()
        vim.cmd "tabnew"
        local win = api.nvim_get_current_win()

        return win
    end,
}

-- ----------------------------------------------------------------------------

---@class mongo.BufferResult
---@field type? mongo.BufferType
---@field content? string
---@field state_args? table<string, any>

---@alias mongo.ResultGenerator fun(mbuf: mongo.MongoBuffer, args: table<string, any>, callback: fun(result: mongo.BufferResult))

---@class mongo.MongoBufferOperationModule
---@field option_setup? fun(mbuf: mongo.MongoBuffer)
---@field result_generator? mongo.ResultGenerator
---@field after_write? fun(src_buf?: mongo.MongoBuffer, result_buf: mongo.MongoBuffer)
---@field refresh? fun(mbuf: mongo.MongoBuffer, callback: fun(err?: string))

---@type table<mongo.BufferType, mongo.MongoBufferOperationModule>
local operation_map = {
    [BufferType.Unknown] = require "mongosh-nvim.state.buffer.buffer_unknown",
    [BufferType.DbList] = require "mongosh-nvim.state.buffer.buffer_db_list",
    [BufferType.CollectionList] = require "mongosh-nvim.state.buffer.buffer_collection_list",
    [BufferType.Execute] = require "mongosh-nvim.state.buffer.buffer_execute",
    [BufferType.ExecuteResult] = require "mongosh-nvim.state.buffer.buffer_execute_result",
    [BufferType.Query] = require "mongosh-nvim.state.buffer.buffer_query",
    [BufferType.QueryResult] = require "mongosh-nvim.state.buffer.buffer_query_result",
    [BufferType.Edit] = require "mongosh-nvim.state.buffer.buffer_edit",
    [BufferType.EditResult] = require "mongosh-nvim.state.buffer.buffer_edit_result",
    [BufferType.Update] = require "mongosh-nvim.state.buffer.buffer_update",
    [BufferType.UpdateResult] = require "mongosh-nvim.state.buffer.buffer_update_result",
}

-- ----------------------------------------------------------------------------

---@class mongo.MongoBuffer
--
---@field type mongo.BufferType
---@field is_user_buffer boolean # Whether this buffer is created by user
--
---@field bufnr integer # buffer number of this buffer.
---@field dummy_lines? string[] # for dummy buffer, this will be its content.
---@field is_destroied boolean
--
---@field src_bufnr? integer # source buffer that create this buffer.
---@field result_bufnr? integer # result buffer used to display executation result of this buffer.
---@field state_args table<string, any> # state values bind with this buffer.
--
---@field create_buffer_style mongo.CreateBufferStyle #
---@field create_win_style mongo.ResultSplitStyle
local MongoBuffer = {}
MongoBuffer.__index = MongoBuffer
MongoBuffer._instance_map = {}

-- get_buffer_obj returns buffer object of given buffer if that buffer is created
-- by this plugin, otherwise `nil` is returned.
---@param bufnr integer # buffer number
---@return mongo.MongoBuffer?
function MongoBuffer.get_buffer_obj(bufnr)
    return MongoBuffer._instance_map[bufnr]
end

---@param type mongo.BufferType
---@param src_bufnr? integer
---@param result_bufnr? integer
---@param bufnr? integer # buffer number for this buffer object.
---@return mongo.MongoBuffer
function MongoBuffer:new(type, src_bufnr, result_bufnr, bufnr)
    local obj = setmetatable({}, self)

    if bufnr then
        obj.is_user_buffer = true
    else
        bufnr = api.nvim_create_buf(false, true)
        obj.is_user_buffer = false
    end

    self._instance_map[bufnr] = obj

    obj.bufnr = bufnr
    obj.type = type
    obj.src_bufnr = src_bufnr
    obj.result_bufnr = result_bufnr
    obj.state_args = {}

    obj:init_style()
    obj:init_autocmd()
    obj:setup_buf_options()

    local on_create = config.dialog.on_create[type] or config.dialog.on_create[BufferType.Unknown]
    if on_create then
        on_create(bufnr)
    end

    return obj
end

-- new_dummy creates a new mongo buffer with no actual underlying buffer.
-- With content binded with this buffer object, it can still make `write_result`
-- call, etc.
-- Dummy buffer objects are not registered to global mongo buffer map.
---@param type mongo.BufferType
---@param lines string[]
---@return mongo.MongoBuffer
function MongoBuffer:new_dummy(type, lines)
    local obj = setmetatable({}, self)

    obj.is_user_buffer = false

    obj.bufnr = 0
    obj.dummy_lines = vim.deepcopy(lines)

    obj.type = type
    obj.state_args = {}

    obj:init_style()

    return obj
end

-- init_style initialize result managing style for this buffer object.
function MongoBuffer:init_style()
    local result_config = config.result_buffer
    local type = self.type

    self.create_win_style = result_config.split_style_type_map[type] or result_config.split_style

    self.create_buffer_style = result_config.create_buffer_style_type_map[type] or result_config.create_buffer_style

    -- Do not overwrite content of non-sketch buffer by default.
    if self.is_user_buffer
        and self.create_buffer_style == CreateBufferStyle.Never
    then
        self.create_buffer_style = CreateBufferStyle.OnNeed
    end
end

-- init_autocmd setups autocommand listening for this buffer.
function MongoBuffer:init_autocmd()
    local bufnr = self:get_bufnr()
    if not bufnr then return end

    api.nvim_create_autocmd("BufUnload", {
        buffer = bufnr,
        callback = function()
            self:destory()
        end
    })
end

function MongoBuffer:setup_buf_options()
    if not self:get_bufnr() then return end

    if self.is_user_buffer then return end

    local module = operation_map[self.type]
    local setter = module.option_setup
    if not setter then
        setter = operation_map[FALLBACK_BUFFER_TYPE].option_setup
    end

    if setter then
        setter(self)
    end
end

-- destory does clean up on buffer gets unloaded
function MongoBuffer:destory()
    local bufnr = self:get_bufnr()
    if not bufnr then return end

    self._instance_map[bufnr] = nil
    self.is_destroied = true
end

-- is_valid returns `true` if a buffer is not discarded yet.
---@return boolean
function MongoBuffer:is_valid()
    if self.is_destroied then
        return false
    end

    local bufnr = self:get_bufnr()
    if bufnr then
        return vim.api.nvim_buf_is_valid(bufnr)
    else
        return self.dummy_lines ~= nil
    end
end

-- get_bufnr returns buffer number of the buffer this object is binded to.
-- Returns `nil` if this object is a dummy mongo buffer.
---@return integer? bufnr
function MongoBuffer:get_bufnr()
    return self.bufnr > 0 and self.bufnr or nil
end

---@param win? integer # if not `nil`, buffer will be displayed in given window.
function MongoBuffer:show(win)
    local bufnr = self:get_bufnr()
    if not bufnr then return end

    win = win or get_win_by_buf(bufnr, true)
    if win then return end

    local cmd = "vsplit"
    local style = config.dialog.split_style
    if style == ResultSplitStyle.Horizontal then
        cmd = "botright split"
    elseif style == ResultSplitStyle.Vertical then
        cmd = "rightbelow vsplit"
    elseif style == ResultSplitStyle.Tab then
        cmd = "tabnew"
    end

    vim.cmd(cmd)
    win = api.nvim_get_current_win()

    api.nvim_win_set_buf(win, bufnr)
end

-- change_type_to switches buffer type to given `type`.
---@param type mongo.BufferType
function MongoBuffer:change_type_to(type)
    self.type = type

    self:init_style()
    self:setup_buf_options()
end

-- get_lines returns content of current buffer in an array of text lines.
---@return string[] lines
function MongoBuffer:get_lines()
    local bufnr = self:get_bufnr()

    local lines
    if bufnr then
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, vim.api.nvim_buf_line_count(bufnr), true)
    elseif self.dummy_lines then
        lines = vim.deepcopy(self.dummy_lines) --[=[@as string[]]=]
    else
        lines = {}
    end

    return lines
end

-- set_lines writes given lines to current buffer, overwriting existing content
-- in buffer.
---@param lines string[]
function MongoBuffer:set_lines(lines)
    local bufnr = self:get_bufnr()
    if bufnr then
        api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    else
        self.dummy_lines = vim.deepcopy(lines)
    end
end

-- get_visual_selection returns visual selected text in current buffer.
---@return string[]
function MongoBuffer:get_visual_selection()
    local bufnr = self:get_bufnr()
    if not bufnr then return {} end

    local cur_bufnr = api.nvim_win_get_buf(0)
    if bufnr ~= cur_bufnr then return {} end

    return get_visual_selection_text()
end

-- make_result_buffer returns buffer number of the buffer which write result to according to buffer
-- managing style of current buffer.
function MongoBuffer:make_result_buffer()
    local maker = result_buffer_getter_map[self.create_buffer_style]
    if not maker then
        local style = CreateBufferStyle.OnNeed
        maker = result_buffer_getter_map[style]
    end

    local buf = maker(self)

    return buf
end

-- make_result_win returns window number to
function MongoBuffer:make_result_win(bufnr)
    local maker = result_win_maker_map[self.create_win_style]
    if not maker then
        local style = ResultSplitStyle.Vertical
        maker = result_win_maker_map[style]
    end

    local win = maker(bufnr)

    return win
end

-- make_result_buffer_obj creates a mongo buffer object for writing result.
---@param win? integer # if not `nil`, buffer will be displayed in given window.
---@return string? err
---@return mongo.MongoBuffer?
function MongoBuffer:make_result_buffer_obj(win)
    local buf = self:make_result_buffer()
    if buf <= 0 then
        return "failed to create new buffer", nil
    end

    win = win or self:make_result_win(buf)
    if win <= 0 then
        return "failed to get window for result buffer", nil
    end

    api.nvim_win_set_buf(win, buf)

    local cur_buf = self:get_bufnr()

    -- it's possible buf_obj here is `self`, make sure following setup override
    -- all necessary field in buf_obj
    local buf_obj = self.get_buffer_obj(buf)
    if not buf_obj then
        buf_obj = MongoBuffer:new(BufferType.Unknown, nil, nil, buf)
        buf_obj.is_user_buffer = buf == cur_buf and self.is_user_buffer
    end

    buf_obj.src_bufnr = buf ~= cur_buf and cur_buf or nil
    buf_obj.result_bufnr = nil

    return nil, buf_obj
end

-- get_result_generator rerturns result generation function for current buffer.
-- If `nil` is returned, then current buffer is not capabale of generating result.
---@return mongo.ResultGenerator?
function MongoBuffer:get_result_generator()
    local type = self.type
    return result_generator_map[type]
end

-- write_result trys to make buffer and window and write result to them.
---@param args? table<string, any>
function MongoBuffer:write_result(args)
    args = args or {}

    local result_gen = self:get_result_generator()
    if not result_gen then
        log.error("not resul generator found for buffer type: " .. self.type)
        return
    end

    result_gen(self, args, function(result)
        if not result.type then
            log.warn("failed to generate result")
            return
        end

        local err, buf_obj = self:make_result_buffer_obj(args.win)
        if err then
            log.warn(err)
            return
        elseif not buf_obj then
            log.warn("failed to create result buffer object")
            return
        end

        local new_buf = buf_obj:get_bufnr()
        local no_buf_reuse = new_buf ~= self:get_bufnr()
        local src_buf_type = self.type

        -- update steate

        buf_obj:change_type_to(result.type)

        local content = result.content
        local lines = content
            and vim.split(content, "\n", { plain = true })
            or {}
        buf_obj:set_lines(lines)

        buf_obj.state_args = result.state_args

        self.result_bufnr = no_buf_reuse and new_buf or nil

        -- after write clean up

        local after_write = after_write_result_map[src_buf_type]
        if after_write then
            local src_buf = no_buf_reuse and self or nil
            after_write(src_buf, buf_obj)
        end
    end)
end

-- refresh tries to regenerate buffer content.
function MongoBuffer:refresh()
    local refresher = buffer_refresher_map[self.type]
    if not refresher then
        log.warn("current buffer doesn't support refreshing")
        return
    end

    refresher(self, function(err)
        if err then
            log.warn(err)
        else
            log.info("buffer refreshed")
        end
    end)
end

-- ----------------------------------------------------------------------------

-- create_mongo_buffer makes a new mongo buffer and show it on screen
---@param type mongo.BufferType
---@param lines string[]
---@param win? integer # if not `nil`, buffer will be displayed in given window.
---@return mongo.MongoBuffer
function M.create_mongo_buffer(type, lines, win)
    local mbuf = MongoBuffer:new(type)

    mbuf:set_lines(lines)
    mbuf:show(win)

    return mbuf
end

-- create_dummy_mongo_buffer makes a new dummy mongo buffer with given content.
---@param type mongo.BufferType
---@param lines string[]
---@return mongo.MongoBuffer
function M.create_dummy_mongo_buffer(type, lines)
    return MongoBuffer:new_dummy(type, lines)
end

-- wrap_with_mongo_buffer creates a MongoBuffer object for given buffer.
---@param type mongo.BufferType
---@param bufnr integer
---@return mongo.MongoBuffer
function M.wrap_with_mongo_buffer(type, bufnr)
    local mbuf = MongoBuffer:new(type, nil, nil, bufnr)
    return mbuf
end

-- try_get_mongo_buffer looks up mongo buffer object for given buffer number.
-- Returns such object if found, otherwise returns `nil`.
---@param bufnr integer
---@return mongo.MongoBuffer?
function M.try_get_mongo_buffer(bufnr)
    return MongoBuffer.get_buffer_obj(bufnr)
end

return M
