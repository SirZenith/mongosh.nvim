local api_core = require "mongosh-nvim.api.core"
local config = require "mongosh-nvim.config"
local buffer_const = require "mongosh-nvim.constant.buffer"
local script_const = require "mongosh-nvim.constant.mongosh_script"
local log = require "mongosh-nvim.log"
local mongosh_state = require "mongosh-nvim.state.mongosh"
local str_util = require "mongosh-nvim.util.str"
local ts_util = require "mongosh-nvim.util.tree_sitter"

local api = vim.api

local BufferType = buffer_const.BufferType
local CreateBufferStyle = buffer_const.CreateBufferStyle
local ResultSplitStyle = buffer_const.ResultSplitStyle

local M = {}

-- get_win_by_buf finds window that contains target buffer.
---@param bufnr integer
---@param is_in_current_tabpage boolean # when `true`, only looking for window in current tab
---@return integer? winnr
local function get_win_by_buf(bufnr, is_in_current_tabpage)
    local wins = is_in_current_tabpage
        and api.nvim_tabpage_list_wins(0)
        or api.nvim_list_wins()

    local win
    for _, w in ipairs(wins) do
        if api.nvim_win_get_buf(w) == bufnr then
            win = w
            break
        end
    end

    return win
end

-- read_lines_from_buf returns content of a buffer as list of string.
-- If given buffer is invalide, `nil` will be returned.
---@param bufnr integer
---@return string[]?
local function read_lines_from_buf(bufnr)
    if vim.api.nvim_buf_is_valid(bufnr) then return nil end

    local line_cnt = vim.api.nvim_buf_line_count(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line_cnt, true)
    return lines
end

-- get_visual_selection returns visual selection range in current buffer.
---@return number? row_st
---@return number? col_st
---@return number? row_ed
---@return number? col_ed
local function get_visual_selection_range()
    local unpac = unpack or table.unpack
    local _, st_r, st_c, _ = unpac(vim.fn.getpos("'<"))
    local _, ed_r, ed_c, _ = unpac(vim.fn.getpos("'>"))
    if st_r * st_c * ed_r * ed_c == 0 then return nil end
    if st_r < ed_r or (st_r == ed_r and st_c <= ed_c) then
        return st_r - 1, st_c - 1, ed_r - 1, ed_c
    else
        return ed_r - 1, ed_c - 1, st_r - 1, st_c
    end
end

-- get_visual_selection_text returns visual selected text in current buffer.
---@return string[] lines
local function get_visual_selection_text()
    local st_r, st_c, ed_r, ed_c = get_visual_selection_range()
    if not (st_r or st_c or ed_r or ed_c) then return {} end

    local lines = api.nvim_buf_get_text(0, st_r, st_c, ed_r, ed_c, {})
    return lines
end

-- ----------------------------------------------------------------------------

---@type table<mongo.BufferType, fun(mbuf: mongo.MongoBuffer)>
local buffer_option_setup_func_map = {
    -- fallback style
    [BufferType.Unknown] = function(mbuf)
        local bufnr = mbuf:get_bufnr()
        if not bufnr then return end

        local bo = vim.bo[bufnr]

        bo.bufhidden = "delete"
        bo.buflisted = false
        bo.buftype = "nofile"
    end,
    [BufferType.CollectionList] = function(mbuf)
        local bufnr = mbuf:get_bufnr()
        if not bufnr then return end

        local bo = vim.bo[bufnr]

        bo.bufhidden = "delete"
        bo.buflisted = false
        bo.buftype = "nofile"

        -- press <Cr> to select a collection
        vim.keymap.set("n", "<CR>", function()
            mbuf:write_result()
        end, { buffer = bufnr })
    end,
    [BufferType.Query] = function(mbuf)
        local bufnr = mbuf:get_bufnr()
        if not bufnr then return end

        local bo = vim.bo[bufnr]

        bo.bufhidden = "delete"
        bo.buflisted = false
        bo.buftype = "nofile"

        bo.filetype = "typescript"
    end,
    [BufferType.QueryResult] = function(mbuf)
        local bufnr = mbuf:get_bufnr()
        if not bufnr then return end

        local bo = vim.bo[bufnr]

        bo.bufhidden = "delete"
        bo.buflisted = false
        bo.buftype = "nofile"

        bo.filetype = "json"
    end,
    [BufferType.Edit] = function(mbuf)
        local bufnr = mbuf:get_bufnr()
        if not bufnr then return end

        local bo = vim.bo[bufnr]

        bo.bufhidden = "delete"
        bo.buflisted = false
        bo.buftype = "nofile"

        bo.filetype = "typescript"
    end,
    [BufferType.EditResult] = function(mbuf)
        local bufnr = mbuf:get_bufnr()
        if not bufnr then return end

        local bo = vim.bo[bufnr]

        bo.bufhidden = "delete"
        bo.buflisted = false
        bo.buftype = "nofile"

        bo.filetype = "json"
    end,
}

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
        local win = get_win_by_buf(bufnr, true)
        if not win then
            vim.cmd "botright split"
            win = api.nvim_get_current_win()
        end

        return win
    end,
    -- fallback style
    [ResultSplitStyle.Vertical] = function(bufnr)
        local win = get_win_by_buf(bufnr, true)
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

---@class mongo.BufferResult
---@field type? mongo.BufferType
---@field content? string
---@field state_args? table<string, any>

---@alias mongo.ResultGenerator fun(mbuf: mongo.MongoBuffer, args: table<string, any>, callback: fun(result: mongo.BufferResult))

-- map buffer type to result generator functoin, types doesn't get mapped to a
-- generator cannot make result buffer.
---@type table<mongo.BufferType, mongo.ResultGenerator>
local result_generator_map = {
    [BufferType.CollectionList] = function(mbuf, args, callback)
        local collection = args.collection
        if not collection then
            local bufnr = mbuf:get_bufnr()
            local win = bufnr and get_win_by_buf(bufnr, true)
            local pos = win and api.nvim_win_get_cursor(win)

            local row = pos and pos[1]
            local lines = row and api.nvim_buf_get_lines(bufnr, row - 1, row, true)

            collection = lines and lines[1]
        end

        local content = str_util.format(script_const.SNIPPET_QUERY, {
            collection = collection,
        })

        callback {
            type = BufferType.Query,
            content = content,
        }
    end,
    [BufferType.Execute] = function(mbuf, args, callback)
        local lines = args.with_range
            and mbuf:get_visual_selection()
            or mbuf:get_lines()
        local snippet = table.concat(lines, "\n")

        api_core.do_execution(snippet, function(err, result)
            if err then
                log.warn(err)
                callback {}
                return
            end

            result = #result > 0 and result or "execution successed"

            callback {
                type = BufferType.ExecuteResult,
                content = result,
                state_args = {
                    src_script = snippet,
                }
            }
        end)
    end,
    [BufferType.Query] = function(mbuf, args, callback)
        local lines = args.with_range
            and mbuf:get_visual_selection()
            or mbuf:get_lines()
        local query = table.concat(lines, "\n")

        api_core.do_query(query, function(err, response)
            if err then
                log.warn(err)
                callback {}
                return
            end

            local collection = ts_util.get_collection_name(query)

            callback {
                type = BufferType.QueryResult,
                content = response,
                state_args = {
                    query = query,
                    collection = collection,
                }
            }
        end)
    end,
    [BufferType.QueryResult] = function(mbuf, args, callback)
        local collection = args.collection
            or mbuf.state_args.collection
            or mongosh_state.get_cur_collection()
        if collection == nil then
            log.warn("collection required")
            callback {}
            return
        end

        local bufnr = mbuf:get_bufnr()
        local id = args.id
        if not id and bufnr then
            id = ts_util.find_nearest_id_in_buffer(bufnr)
            id = id and str_util.unquote(id)
        end
        if id == nil then
            log.warn("id required")
            callback {}
            return
        end

        local query = str_util.format(script_const.TEMPLATE_FIND_ONE, {
            collection = collection,
            id = id,
        })

        api_core.do_query(query, function(err, result)
            if err then
                log.warn(err)
                callback {}
                return
            end

            local document = str_util.indent(result, config.indent_size)
            -- document = document:sub(4) -- remove indent at the beginning

            local snippet = str_util.format(script_const.SNIPPET_EDIT, {
                collection = collection,
                id = id,
                document = document,
            })

            callback {
                type = BufferType.Edit,
                content = snippet,
                state_args = {
                    collection = collection,
                    id = id,
                },
            }
        end, "failed to update document content")
    end,
    [BufferType.Edit] = function(mbuf, args, callback)
        local lines = args.with_range
            and mbuf:get_visual_selection()
            or mbuf:get_lines()
        local snippet = table.concat(lines, "\n")

        api_core.do_replace(snippet, function(err, result)
            if err then
                log.warn(err)
                callback {}
                return
            end

            result = #result > 0 and result or "execution successed"
            callback {
                type = BufferType.EditResult,
                content = result,
                state_args = {
                    collection = mbuf.state_args.collection,
                    id = mbuf.state_args.id,
                },
            }
        end)
    end,
}

-- map buffer type to clean up function which gets called after writing result.
-- If source buffer share the same buffer with result buffer, `src_buf` in function
-- argument will be `nil`.
---@type table<mongo.BufferType, fun(src_buf?: mongo.MongoBuffer, result_buf: mongo.MongoBuffer)>
local after_write_result_map = {
    [BufferType.CollectionList] = function(src_buf)
        local bufnr = src_buf and src_buf:get_bufnr()
        if not bufnr then return end

        local win = get_win_by_buf(bufnr, true)
        if not win then return end

        api.nvim_win_hide(win)
    end
}

-- map buffer type to buffer refreshing function
---@type table<mongo.BufferType, fun(mbuf: mongo.MongoBuffer, callback: fun(err?: string))>
local buffer_refresher_map = {
    [BufferType.CollectionList] = function(mbuf, callback)
        local collections = mongosh_state.get_collection_names()
        mbuf:set_lines(collections)
        callback()
    end,
    [BufferType.ExecuteResult] = function(mbuf, callback)
        local src_bufnr = mbuf.src_bufnr

        local src_lines = src_bufnr and read_lines_from_buf(src_bufnr)
        local snippet = src_lines
            and table.concat(src_lines, "\n")
            or mbuf.state_args.src_script

        if not snippet or #snippet == 0 then
            callback("no snippet is binded with current buffer")
            return
        end

        api_core.do_execution(snippet, function(err, result)
            if err then
                callback(err)
                return
            end

            result = #result > 0 and result or "execution successed"

            local lines = vim.split(result, "\n", { plain = true })
            mbuf:set_lines(lines)
        end)
    end,
    [BufferType.QueryResult] = function(mbuf, callback)
        local src_bufnr = mbuf.src_bufnr

        local src_lines = src_bufnr and read_lines_from_buf(src_bufnr)
        local query = src_lines
            and table.concat(src_lines)
            or mbuf.state_args.query

        if not query or #query == 0 then
            callback("no query is binded with current buffer")
            return
        end

        api_core.do_query(query, function(err, response)
            if err then
                callback(err)
                return
            end

            local lines = vim.fn.split(response, "\n")
            mbuf:set_lines(lines)
        end)
    end,
    [BufferType.Edit] = function(mbuf, callback)
        local collection = mbuf.state_args.collection
        if not collection then
            callback("no collection name is binded with current buffer")
            return
        end

        local id = mbuf.state_args.id
        if not id then
            callback("no document id is binded with current buffer")
            return
        end

        local query = str_util.format(script_const.TEMPLATE_FIND_ONE, {
            collection = collection,
            id = id,
        })

        api_core.do_query(query, function(err, result)
            if err then
                callback(err)
                return
            end

            local document = str_util.indent(result, config.indent_size)

            local snippet = str_util.format(script_const.SNIPPET_EDIT, {
                collection = collection,
                id = id,
                document = document,
            })

            local lines = vim.split(snippet, "\n", { plain = true })
            mbuf:set_lines(lines)
        end, "failed to update document content")
    end,
}

-- ----------------------------------------------------------------------------

---@class mongo.MongoBuffer
--
---@field type mongo.BufferType
---@field is_user_buffer boolean # Whether this buffer is created by user
--
---@field bufnr integer # buffer number of this buffer.
---@field dummy_lines? string[] # for dummy buffer, this will be its content.
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
    self.create_win_style = config.result_buffer.split_style

    self.create_buffer_style = config.result_buffer.create_buffer_style
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

    api.nvim_create_autocmd(
        { "BufUnload" },
        {
            buffer = bufnr,
            callback = function()
                if api.nvim_get_current_buf() ~= bufnr then
                    return
                end

                self:destory()
            end
        }
    )
end

function MongoBuffer:setup_buf_options()
    if not self:get_bufnr() then return end

    if self.is_user_buffer then return end

    local setter = buffer_option_setup_func_map[self.type]
    if not setter then
        local type = BufferType.Unknown
        setter = buffer_option_setup_func_map[type]
    end

    setter(self)
end

-- destory does clean up on buffer gets unloaded
function MongoBuffer:destory()
    local bufnr = self:get_bufnr()
    if not bufnr then return end

    self._instance_map[bufnr] = nil
end

-- get_bufnr returns buffer number of the buffer this object is binded to.
-- Returns `nil` if this object is a dummy mongo buffer.
---@return integer? bufnr
function MongoBuffer:get_bufnr()
    return self.bufnr > 0 and self.bufnr or nil
end

function MongoBuffer:show()
    local bufnr = self:get_bufnr()
    if not bufnr then return end

    local win = get_win_by_buf(bufnr, true)
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
---@return string? err
---@return mongo.MongoBuffer?
function MongoBuffer:make_result_buffer_obj()
    local buf = self:make_result_buffer()
    if buf <= 0 then
        return "failed to create new buffer", nil
    end

    local win = self:make_result_win(buf)
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
    local result_gen = self:get_result_generator()
    if not result_gen then
        log.error("not resul generator found for buffer type: " .. self.type)
        return
    end

    result_gen(self, args or {}, function(result)
        if not result.type then
            log.warn("failed to generate result")
            return
        end

        local err, buf_obj = self:make_result_buffer_obj()
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

        buf_obj.type = result.type

        local content = result.content
        local lines = content
            and vim.split(content, "\n", { plain = true })
            or {}
        buf_obj:set_lines(lines)

        buf_obj.state_args = result.state_args

        buf_obj:setup_buf_options()

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
        end
    end)
end

-- ----------------------------------------------------------------------------

-- create_mongo_buffer makes a new mongo buffer and show it on screen
---@param type mongo.BufferType
---@param lines string[]
---@return mongo.MongoBuffer
function M.create_mongo_buffer(type, lines)
    local mbuf = MongoBuffer:new(type)

    mbuf:set_lines(lines)
    mbuf:show()

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
