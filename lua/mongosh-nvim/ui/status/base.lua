local M = {}

-- If cached status text is available, `status()` would uses cached content
-- instead of generating new one if not forced to generate.
local cached_status_line = nil ---@type string?

-- Mark cached status line as out of date.
function M.set_status_line_dirty()
    cached_status_line = nil
end

-- Read status line value from cache, if cache is out of date, `nil` will be
-- returned.
---@return string?
function M.get_cached_status_line()
    return cached_status_line
end

-- Update cached status line.
function M.set_cached_status_line(line)
    cached_status_line = line
end

return M
