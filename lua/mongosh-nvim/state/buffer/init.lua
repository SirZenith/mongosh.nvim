local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local log = require "mongosh-nvim.log"
local buffer_util = require "mongosh-nvim.util.buffer"

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
    [CreateBufferStyle.OnNeed] = function(mbuf)
        local buf = mbuf._result_bufnr
        if not buf
            or not api.nvim_buf_is_valid(buf)
            or not api.nvim_buf_is_loaded(buf)
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
            or not api.nvim_buf_is_loaded(buf)
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

-- Return result window number according to split style.
---@param split_style mongo.ResultSplitStyle
---@param bufnr integer
local function make_result_win(split_style, bufnr)
    local maker = result_win_maker_map[split_style] or result_win_maker_map[FALLBACK_RESULT_SPLIT_STYLE]
    local win = maker(bufnr)
    return win
end

-- ----------------------------------------------------------------------------

---@class mongo.BufferResultArgs
---@field type mongo.BufferType
---@field state_args? table<string, any>

---@class mongo.MongoBufferOperationModule
---@field on_enter? fun(mbuf: mongo.MongoBuffer)
---@field on_leave? fun(mbuf: mongo.MongoBuffer)
---@field content_writer? fun(mbuf: mongo.MongoBuffer, callback: fun(err: string?))
---@field result_args_generator? fun(mbuf: mongo.MongoBuffer, args: table<string, any>, callback: fun(err: string?, args: mongo.BufferResultArgs?))
---@field on_result_failed? fun(mbuf: mongo.MongoBuffer, err: string)
---@field on_result_successed? fun(mbuf: mongo.MongoBuffer, result_obj: mongo.MongoBuffer)
---@field refresher? fun(mbuf: mongo.MongoBuffer, callback: fun(err?: string))
---@field convert_type? fun(mbuf: mongo.MongoBuffer, args: table<string, any>, callback: fun(err?: string))

---@type table<mongo.BufferType, mongo.MongoBufferOperationModule>
local OPERATION_MAP = {
    [BufferType.Unknown] = require "mongosh-nvim.state.buffer.buffer_unknown",
    [BufferType.DbList] = require "mongosh-nvim.state.buffer.buffer_db_list",
    [BufferType.CollectionList] = require "mongosh-nvim.state.buffer.buffer_collection_list",
    [BufferType.Execute] = require "mongosh-nvim.state.buffer.buffer_execute",
    [BufferType.ExecuteResult] = require "mongosh-nvim.state.buffer.buffer_execute_result",
    [BufferType.Query] = require "mongosh-nvim.state.buffer.buffer_query",
    [BufferType.QueryResult] = require "mongosh-nvim.state.buffer.buffer_query_result",
    [BufferType.QueryResultCard] = require "mongosh-nvim.state.buffer.buffer_query_result_card",
    [BufferType.Edit] = require "mongosh-nvim.state.buffer.buffer_edit",
    [BufferType.EditResult] = require "mongosh-nvim.state.buffer.buffer_edit_result",
    [BufferType.Update] = require "mongosh-nvim.state.buffer.buffer_update",
    [BufferType.UpdateResult] = require "mongosh-nvim.state.buffer.buffer_update_result",
}

local FALLBACK_OP_MODEL = OPERATION_MAP[FALLBACK_BUFFER_TYPE]

-- ----------------------------------------------------------------------------

---@class mongo.MongoBuffer : mongo.MongoBufferOperationModule
--
---@field _type mongo.BufferType
---@field _is_user_buffer boolean # Whether this buffer is created by user
--
---@field _bufnr integer # buffer number of this buffer.
---@field _winnr integer # window used by this object.
---@field _dummy_lines? string[] # for dummy buffer, this will be its content.
---@field _is_destroied boolean
--
---@field _src_bufnr? integer # source buffer that create this buffer.
---@field _result_bufnr? integer # result buffer used to display executation result of this buffer.
---@field _state_args table<string, any> # state values bind with this buffer.
--
---@field create_buffer_style mongo.CreateBufferStyle
---@field create_win_style mongo.ResultSplitStyle
local MongoBuffer = {}
MongoBuffer._instance_map = {}

function MongoBuffer:__index(key)
    local value = rawget(self, key) or getmetatable(self)[key]
    if value ~= nil then return value end

    local type = rawget(self, "_type")
    local module = type and OPERATION_MAP[type]
    value = module and module[key] or FALLBACK_OP_MODEL[key]

    return value
end

-- get_buffer_obj returns buffer object of given buffer if that buffer is created
-- by this plugin, otherwise `nil` is returned.
---@param bufnr integer # buffer number
---@return mongo.MongoBuffer?
function MongoBuffer.get_buffer_obj(bufnr)
    return MongoBuffer._instance_map[bufnr]
end

---@class mongo.MongoBufferCreateArgs
---@field type mongo.BufferType
---@field src_bufnr? integer
---@field result_bufnr? integer
---@field bufnr? integer
---@field is_user_buffer? boolean

---@param args mongo.MongoBufferCreateArgs
---@return mongo.MongoBuffer
function MongoBuffer:new(args)
    local obj = setmetatable({}, self)

    local bufnr = args.bufnr
    if bufnr then
        obj._is_user_buffer = args.is_user_buffer ~= false
    else
        bufnr = api.nvim_create_buf(false, true)
        obj._is_user_buffer = false
    end

    self._instance_map[bufnr] = obj

    obj._bufnr = bufnr
    obj._type = args.type
    obj._src_bufnr = args.src_bufnr
    obj._result_bufnr = args.result_bufnr
    obj._state_args = {}

    obj:init_style()
    obj:init_autocmd()
    obj:setup_buf_options()

    local on_create = config.dialog.on_create[type] or config.dialog.on_create[FALLBACK_BUFFER_TYPE]
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

    obj._is_user_buffer = false

    obj._bufnr = 0
    obj._dummy_lines = vim.deepcopy(lines)

    obj._type = type
    obj._state_args = {}

    obj:init_style()

    return obj
end

-- init_style initialize result managing style for this buffer object.
function MongoBuffer:init_style()
    local result_config = config.result_buffer
    local type = self._type

    self.create_win_style = result_config.split_style_type_map[type] or FALLBACK_RESULT_SPLIT_STYLE

    self.create_buffer_style = result_config.create_buffer_style_type_map[type] or FALLBACK_BUFFER_CREATION_STYLE

    -- Do not overwrite content of non-sketch buffer by default.
    if self._is_user_buffer
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

-- Set buffer options when mongo buffer is attached to a buffer.
function MongoBuffer:setup_buf_options()
    if not self:get_bufnr() then return end

    if not self._is_user_buffer then
        self:on_enter()
    end
end

-- Unset buffer options when mongo buffer is detach from a buffer.
function MongoBuffer:reset_buf_options()
    if not self:get_bufnr() then return end

    if not self._is_user_buffer then
        self:on_leave()
    end
end

-- destory does clean up on buffer gets unloaded
function MongoBuffer:destory()
    local bufnr = self:get_bufnr()
    if not bufnr then return end

    self._instance_map[bufnr] = nil
    self._is_destroied = true
end

-- is_valid returns `true` if a buffer is not discarded yet.
---@return boolean
function MongoBuffer:is_valid()
    if self._is_destroied then
        return false
    end

    local bufnr = self:get_bufnr()
    if bufnr then
        return vim.api.nvim_buf_is_valid(bufnr)
    else
        return self._dummy_lines ~= nil
    end
end

-- get_bufnr returns buffer number of the buffer this object is binded to.
-- Returns `nil` if this object is a dummy mongo buffer.
---@return integer? bufnr
function MongoBuffer:get_bufnr()
    local bufnr = self._bufnr
    if not bufnr then return end

    if not vim.api.nvim_buf_is_valid(bufnr)
        or not vim.api.nvim_buf_is_loaded(bufnr)
    then
        return nil
    end

    return bufnr
end

---@param split_style? mongo.ResultSplitStyle
---@param win? integer # if not `nil`, buffer will be displayed in given window.
function MongoBuffer:show(split_style, win)
    local bufnr = self:get_bufnr()
    if not bufnr then return end

    split_style = split_style or config.dialog.split_style

    win = win or make_result_win(split_style, bufnr)
    if win <= 0 then
        return "failed to get window for result buffer", nil
    end

    self._winnr = win
    api.nvim_win_set_buf(win, bufnr)
end

-- Return buffer type of this object.
function MongoBuffer:get_type()
    return self._type
end

-- change_type_to switches buffer type to given `type`.
---@param type mongo.BufferType
function MongoBuffer:change_type_to(type)
    if type == self._type then return end

    self:reset_buf_options()

    self._type = type
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
    elseif self._dummy_lines then
        lines = vim.deepcopy(self._dummy_lines) --[=[@as string[]]=]
    else
        lines = {}
    end

    return lines
end

-- set_lines writes given lines to current buffer, overwriting existing content
-- in buffer.
---@param lines string | string[]
function MongoBuffer:set_lines(lines)
    if type(lines) == "string" then
        lines = vim.split(lines, "\n", { plain = true })
    end

    local bufnr = self:get_bufnr()
    if bufnr then
        api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
    else
        self._dummy_lines = vim.deepcopy(lines)
    end
end

-- Tries to get lines from source buffer.
---@return string[]?
function MongoBuffer:get_src_buf_lines()
    local src_bufnr = self._src_bufnr
    if not src_bufnr then return nil end

    local src_lines = src_bufnr and buffer_util.read_lines_from_buf(src_bufnr)
    return src_lines
end

-- get_visual_selection returns visual selected text in current buffer.
---@return string[]
function MongoBuffer:get_visual_selection()
    local bufnr = self:get_bufnr()
    if not bufnr then return {} end

    local cur_bufnr = api.nvim_win_get_buf(0)
    if bufnr ~= cur_bufnr then return {} end

    return buffer_util.get_visual_selection_text()
end

-- Set buffer state argument to reference a table.
---@param state_args table<string, any>
function MongoBuffer:set_state_args(state_args)
    self._state_args = state_args
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

-- make_result_buffer_obj creates a mongo buffer object for writing result.
---@param type mongo.BufferType
---@param bufnr? integer
---@return string? err
---@return mongo.MongoBuffer?
function MongoBuffer:make_result_buffer_obj(type, bufnr)
    bufnr = bufnr or self:make_result_buffer()
    if bufnr <= 0 then
        return "failed to create new buffer", nil
    end

    local cur_buf = self:get_bufnr()
    local is_buf_reuse = bufnr == cur_buf

    local src_buf
    if is_buf_reuse then
        self:reset_buf_options()
    else
        src_buf = cur_buf
    end

    local buf_obj = MongoBuffer.get_buffer_obj(bufnr)
    if buf_obj and buf_obj:get_type() == type then
        buf_obj._src_bufnr = src_buf
    else
        buf_obj = MongoBuffer:new {
            type = type,
            src_bufnr = src_buf,
            bufnr = bufnr,
            is_user_buffer = bufnr == cur_buf and self._is_user_buffer,
        }
    end

    return nil, buf_obj
end

-- Try to make buffer and window, then write result to result buffer.
---@param args? table<string, any>
function MongoBuffer:write_result(args)
    args = args or {}
    local target_win = args.win

    self:result_args_generator(args, function(result_err, result_args)
        if result_err or not result_args then
            log.warn(result_err or "failed to genrate arguments for writing result")
            return
        end

        local buf_err, buf_obj = self:make_result_buffer_obj(result_args.type)
        if buf_err or not buf_obj then
            log.warn(buf_err or "faled to create result buffer object")
            return
        end

        local result_buf = buf_obj:get_bufnr()
        local src_buf = self:get_bufnr()
        self._result_bufnr = result_buf ~= src_buf and result_buf or nil

        buf_obj._state_args = vim.tbl_extend(
            "force", buf_obj._state_args, result_args.state_args
        )
        buf_obj:content_writer(function(err)
            if err then
                self:on_result_failed(err)
            else
                buf_obj:show(self.create_win_style, target_win)
                self:on_result_successed(buf_obj)
            end
        end)
    end)
end

-- refresh tries to regenerate buffer content.
function MongoBuffer:refresh()
    self:refresher(function(err)
        if err then
            log.warn(err)
        else
            log.info("buffer refreshed")
        end
    end)
end

-- Convert current buffer into another type
function MongoBuffer:convert(args)
    self:convert_type(args, function(err)
        if err then
            log.warn(err)
            return
        end
    end)
end

-- ----------------------------------------------------------------------------

-- Make a new mongo buffer without showing it on screen.
---@param type mongo.BufferType
---@param lines string[]
---@return mongo.MongoBuffer
function M.create_mongo_buffer(type, lines)
    local mbuf = MongoBuffer:new { type = type }

    mbuf:set_lines(lines)

    return mbuf
end

-- Make a new dummy mongo buffer with given content.
---@param type mongo.BufferType
---@param lines string[]
---@return mongo.MongoBuffer
function M.create_dummy_mongo_buffer(type, lines)
    return MongoBuffer:new_dummy(type, lines)
end

-- Create a MongoBuffer object for given buffer.
---@param type mongo.BufferType
---@param bufnr integer
---@return mongo.MongoBuffer
function M.wrap_with_mongo_buffer(type, bufnr)
    local mbuf = MongoBuffer:new {
        type = type,
        bufnr = bufnr,
    }
    return mbuf
end

-- Look up mongo buffer object for given buffer number.
-- Returns such object if found, otherwise returns `nil`.
---@param bufnr integer
---@return mongo.MongoBuffer?
function M.try_get_mongo_buffer(bufnr)
    return MongoBuffer.get_buffer_obj(bufnr)
end

return M
