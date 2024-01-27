local M = {}

---@param tbl table
---@return boolean
local function check_table_is_array(tbl)
    local keys = {}
    for k in pairs(tbl) do
        if type(k) ~= "number" then
            return false
        end
        keys[#keys + 1] = k
    end

    table.sort(keys)

    for i = 1, #keys do
        if keys[i] ~= i then
            return false
        end
    end

    return true
end

---@param buffer string[]
---@param value any
---@param base_indent string
---@param indent string
local function stringify(buffer, value, base_indent, indent)
    local v_type = type(value)

    if v_type == "nil" or value == vim.NIL then
        buffer[#buffer + 1] = "null"
    elseif v_type == "number" or v_type == "boolean" then
        buffer[#buffer + 1] = tostring(value)
    elseif v_type == "string" then
        buffer[#buffer + 1] = ("%q"):format(value)
    elseif v_type == "table" then
        local is_array = check_table_is_array(value)
        if is_array then
            buffer[#buffer + 1] = "["
            local child_indent = indent .. base_indent

            for i = 1, #value do
                buffer[#buffer + 1] = "\n"
                buffer[#buffer + 1] = child_indent
                stringify(buffer, value[i], base_indent, child_indent)
                buffer[#buffer + 1] = ","
            end

            local total_cnt = #buffer
            if buffer[total_cnt] == "," then
                buffer[total_cnt] = "\n"
                buffer[total_cnt + 1] = indent
            end

            buffer[#buffer + 1] = "]"
        else
            buffer[#buffer + 1] = "{"
            local child_indent = indent .. base_indent

            for k, child in pairs(value) do
                buffer[#buffer + 1] = "\n"
                buffer[#buffer + 1] = child_indent
                buffer[#buffer + 1] = ("%q:"):format(k)
                buffer[#buffer + 1] = " "
                stringify(buffer, child, base_indent, child_indent)
                buffer[#buffer + 1] = ","
            end

            local total_cnt = #buffer
            if buffer[total_cnt] == "," then
                buffer[total_cnt] = "\n"
                buffer[total_cnt + 1] = indent
            end

            buffer[#buffer + 1] = "}"
        end
    else
        error("cannot serialize value of type " .. v_type)
    end
end

---@param value any
---@param indent? integer
---@return string
function M.stringify(value, indent)
    indent = indent or 0

    local buffer = {}
    local base_indent = (" "):rep(indent)
    stringify(buffer, value, base_indent, "")

    if indent == 0 then
        for i = 1, #buffer do
            if buffer[i] == "\n" or buffer[i] == " " then
                buffer[i] = ""
            end
        end
    end

    return table.concat(buffer)
end

return M
