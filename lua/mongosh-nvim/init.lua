local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"
local status = require "mongosh-nvim.ui.status"

local M = {}

---@param dst table
---@param src table
local function merge_tbl(dst, src)
    for k, v in pairs(src) do
        local old_v = dst[k]
        local old_v_type = type(old_v)

        if type(v) == "table" then
            if old_v_type == "table" then
                merge_tbl(old_v, v)
            else
                dst[k] = vim.deepcopy(v)
            end
        else
            dst[k] = v
        end
    end
end

function M.register_cmd()
    require "mongosh-nvim.command"
end

---@param options? table
function M.setup(options)
    if options then
        merge_tbl(config, options)
    end

    if vim.fn.executable(config.executable) == 0 then
        log.warn("mongosh executable not found")
        config.executable = nil
    end

    status.set_components(config.status_line.components)
end

return M
