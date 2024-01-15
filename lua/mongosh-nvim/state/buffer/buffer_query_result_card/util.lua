local config = require "mongosh-nvim.config"
local hl_const = require "mongosh-nvim.constant.highlight"

local HLGroup = hl_const.HighlightGroup

local M = {}

local cached_highlight_group = {}

-- Setup highlight group for indented keys.
local function generate_indent_hl_groups()
    for i, color in pairs(config.card_view.indent_colors) do
        local group_name = HLGroup.TreeIndented .. "_" .. tostring(i)
        vim.api.nvim_set_hl(0, group_name, { fg = color })
        cached_highlight_group[i] = group_name
    end
end

-- Get highlight group for keys at given indent level.
---@param indent_level integer
---@return string hl_group
function M.get_key_hl_by_indent_level(indent_level)
    local color_cnt = #config.card_view.indent_colors
    if #cached_highlight_group ~= color_cnt then
        generate_indent_hl_groups()
    end

    local color_index = (indent_level % color_cnt) + 1

    return cached_highlight_group[color_index] or HLGroup.TreeNormal
end



return M
