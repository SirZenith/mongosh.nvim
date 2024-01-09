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

-- ----------------------------------------------------------------------------
-- Scrambling

-- a map from normal text to scrambled text.
local char_map = nil ---@type table<string, string> | nil
-- a map from scrambled text to normal text
local char_inverse_map = nil ---@type table<string, string> | nil

---@return table<string, string> scramble_map
---@return table<string, string> inverse_map
local function generate_char_map()
    local scramble_map, inverse_map = {}, {}

    local len = 256

    local index_list = {}
    for i = 1, len do
        index_list[i] = i
    end

    for i = len, 2, -1 do
        local j = math.random(i)
        index_list[i], index_list[j] = index_list[j], index_list[i]
    end

    for i = 1, len do
        local char = string.char(i - 1)
        local mapped = string.char(index_list[i] - 1)
        scramble_map[char] = mapped
        inverse_map[mapped] = char
    end

    return scramble_map, inverse_map
end

---@return table<string, string> scramble_map
---@return table<string, string> inverse_map
local function get_char_map_pair()
    if not char_map or not char_inverse_map then
        char_map, char_inverse_map = generate_char_map()
    end

    return char_map, char_inverse_map
end

-- scramble mapped plain text by shuffeled ASCII list, so that its not directly
-- readable when memory gets dumpped.
---@param s string
---@return string
function M.scramble(s)
    local scramble_map = get_char_map_pair()
    local value = s:gsub(".", scramble_map)
    return value
end

-- unscramble translates a scrambled text into original plain text.
---@param s string
---@return string
function M.unscramble(s)
    local _, inverse_map = get_char_map_pair()
    local value = s:gsub(".", inverse_map)
    return value
end

-- ----------------------------------------------------------------------------

return M
