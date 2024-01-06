
local config = require "mongosh-nvim.config"
local log = require "mongosh-nvim.log"

local M = {}

function M.register_cmd()
    require "mongosh-nvim.command"
end

---@param options? table
function M.setup(options)
    if options then
        vim.tbl_extend("force", config, options)
    end

    if vim.fn.executable(config.executable) then
        log.warn("mongosh executable not found")
        config.executable = nil
    end
end

return M
