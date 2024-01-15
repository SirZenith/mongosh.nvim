local ts_util = require "mongosh-nvim.util.tree_sitter"

local api = vim.api

local M = {}

-- get_win_by_buf finds window that contains target buffer.
---@param bufnr integer
---@param is_in_current_tabpage boolean # when `true`, only looking for window in current tab
---@return integer? winnr
function M.get_win_by_buf(bufnr, is_in_current_tabpage)
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
function M.read_lines_from_buf(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr)
        or not vim.api.nvim_buf_is_loaded(bufnr)
    then
        return nil
    end

    local line_cnt = vim.api.nvim_buf_line_count(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, line_cnt, true)
    return lines
end

-- get_visual_selection returns visual selection range in current buffer.
---@return number? row_st
---@return number? col_st
---@return number? row_ed
---@return number? col_ed
function M.get_visual_selection_range()
    local unpac = unpack or table.unpack

    local st_r, st_c, ed_r, ed_c

    local cur_mode = api.nvim_get_mode().mode
    if cur_mode == "v" then
        _, st_r, st_c, _ = unpac(vim.fn.getpos("v"))
        _, ed_r, ed_c, _ = unpac(vim.fn.getpos("."))
    else
        _, st_r, st_c, _ = unpac(vim.fn.getpos("'<"))
        _, ed_r, ed_c, _ = unpac(vim.fn.getpos("'>"))
    end

    if st_r * st_c * ed_r * ed_c == 0 then return nil end
    if st_r < ed_r or (st_r == ed_r and st_c <= ed_c) then
        return st_r - 1, st_c - 1, ed_r - 1, ed_c
    else
        return ed_r - 1, ed_c - 1, st_r - 1, st_c
    end
end

-- get_visual_selection_text returns visual selected text in current buffer.
---@return string[] lines
function M.get_visual_selection_text()
    local st_r, st_c, ed_r, ed_c = M.get_visual_selection_range()
    if not (st_r or st_c or ed_r or ed_c) then return {} end

    local lines = api.nvim_buf_get_text(0, st_r, st_c, ed_r, ed_c, {})
    return lines
end

-- Get access dot path of key-value pair in visual selection.
---@param bufnr integer
---@return string?
function M.get_visual_json_dot_path(bufnr)
    local buf_lines = api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local buf_content = table.concat(buf_lines, "\n")
    local st_row, st_col, ed_row, ed_col = M.get_visual_selection_range()

    local dot_path

    if st_row and st_col and ed_row and ed_col then
        dot_path = ts_util.get_json_node_dot_path(buf_content, {
            st_row = st_row,
            st_col = st_col,
            ed_row = ed_row,
            ed_col = ed_col
        })
    end

    return dot_path
end

return M
