local M = {}

---@class mongo.anim.CharAnimation
---@field frame_time integer
---@field _frames? string[]
---@field _frame_cnt integer
--
---@field _last_yielded_index integer # frame index of last yield.
---@field _last_update integer? # time of last frame yielding.
local CharAnimation = {}
CharAnimation.__index = CharAnimation

---@return mongo.anim.CharAnimation
function CharAnimation:new()
    local obj = setmetatable({}, self)

    obj.frame_time = 0.1
    obj._frames = nil
    obj._frame_cnt = 0

    obj._last_yielded_index = 0
    obj._last_update = nil

    return obj
end

-- Reset animation play head to start position.
function CharAnimation:reset()
    self._last_yielded_index = 0
    self._last_update = nil
end

-- Set frame character list.
---@param frames string[]
function CharAnimation:set_frames(frames)
    self._frames = vim.deepcopy(frames)
    self._frame_cnt = #self._frames
    self:reset()
end

---@return integer
function CharAnimation:get_frame_cnt()
    return #self._frames
end

---@return string # character used in this frame.
function CharAnimation:yield()
    local frames = self._frames
    if not frames then return "" end

    local frame_cnt = self._frame_cnt
    if frame_cnt == 0 then return "" end

    if frame_cnt == 1 then
        return frames[1] or ""
    end

    local now = os.clock()
    local last_time = self._last_update or now
    self._last_update = now

    local delta = math.floor((now - last_time) / self.frame_time)
    local index = (self._last_yielded_index + delta) % frame_cnt
    if index == 0 then
        index = frame_cnt
    end

    self._last_yielded_index = index
    local frame = frames[index] or ""

    return frame
end

-- ----------------------------------------------------------------------------

M.CharAnimation = CharAnimation

return M
