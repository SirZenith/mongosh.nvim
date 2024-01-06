M = {}

-- tirm white space on both ends of string.
---@param s string
function M.trim(s)
    return s:match("^%s*(.-)%s*$")
end

local QUOTES = { "'", "\"", "`" }

-- unquote removes one pair of quotes surrounding given string.
---@param s string
---@return string
function M.unquote(s)
    local len = s:len()
    if len <= 1 then
        return s
    end

    local first = s:sub(1, 1)
    local last = s:sub(len, len)

    local result = s
    for _, quote in ipairs(QUOTES) do
        if first == quote and last == quote then
            result = s:sub(2, len - 1)
        end
    end

    return result
end

-- str_startswith checks if `s` is starts with ``
---@param s string
---@param prefix string
function M.starts_with(s, prefix)
    return s:sub(1, prefix:len()) == prefix
end

---@param s string
---@param n integer
function M.indent(s, n)
    local indent = (" "):rep(n)

    local lines = vim.fn.split(s, "\n")
    for i, line in ipairs(lines) do
        lines[i] = indent .. line
    end

    return vim.fn.join(lines, "\n")
end

-- str_format makes new string from template by replacing each `${}` slot in
-- template string with translation provided in args.
--
-- ```lua
-- local result = M.str_format("Hello ${name}", { name = "World" })
-- assert(result, "Hello World")
-- ```
---@param template string
---@param args table<string, string>
---@return string
function M.format(template, args)
    local result = template:gsub("${(%w+)}", args)
    return result
end

return M
