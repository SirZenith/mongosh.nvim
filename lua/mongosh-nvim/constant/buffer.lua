local M = {}

---@enum mongo.buffer.BufferType
M.BufferType = {
    Unknown = "unknown",
    DbList = "db_list",
    CollectionList = "collection_list",
    Execute = "execute",
    ExecuteResult = "execute_result",
    Query = "query",
    QueryResult = "query_result",
    QueryResultCard = "query_result_card",
    Edit = "edit",
    EditResult = "edit_result",
    Update = "update",
    UpdateResult = "update_result",
}

---@enum mongo.buffer.FileType
M.FileType = {
    Unknown = "MongoshNvimUnknown",
    DbList = "MongoshNvimDbList",
    CollectionList = "MongoshNvimCollectionList",
    Execute = "MongoshNvimExecute",
    ExecuteResult = "MongoshNvimExecuteResult",
    Query = "MongoshNvimQuery",
    QueryResult = "MongoshNvimQueryResult",
    QueryResultCard = "MongoshNvimQueryResultCard",
    Edit = "MongoshNvimEdit",
    EditResult = "MongoshNvimEditResult",
    Update = "MongoshNvimUpdate",
    UpdateResult = "MongoshNvimUpdateResult",
}

---@enum mongo.buffer.ResultSplitStyle
M.ResultSplitStyle = {
    Tab = "tab",
    Horizontal = "horizontal",
    Vertical = "vertical",
}

---@enum mongo.buffer.CreateBufferStyle
M.CreateBufferStyle = {
    Always = "always",
    OnNeed = "on_need",
    Never = "never",
}

---@enum mongo.buffer.QueryResultStyle
M.QueryResultStyle = {
    JSON = "json",
    Card = "card",
}

M.DB_SIDEBAR_FILETYPE = "MongoshNvimDBSideBar"

---@enum mongo.buffer.TreeEntryNestingType
M.TreeEntryNestingType = {
    Object = "object",
    Array = "array",
    EmptyTable = "empty_table",
    None = "none",
}

---@enum mongo.buffer.BSONValueType
M.BSONValueType = {
    -- ------------------------------------------------------------------------
    -- plain value
    Unknown   = "unknown",
    Boolean   = "boolean",
    Null      = "null",
    Number    = "number",
    String    = "string",
    -- ------------------------------------------------------------------------
    -- BSON value
    Array     = "array",
    Binary    = "binary",    -- { $binary: { base64: string, subType: string } }
    Code      = "code",      -- { $code: string, $scope: object }
    Date      = "date",      -- { $date: string }
    Decimal   = "decimal",   -- { $numberDecimal: string }
    Double    = "double",    -- { $numberDouble: string }
    Int32     = "int32",     -- { $numberInt: string }
    Int64     = "int64",     -- { $numberLong: string }
    MaxKey    = "max_key",   -- { $maxKey: integer }
    MinKey    = "min_key",   -- { $minKey: integer }
    Object    = "object",
    ObjectID  = "object_id", -- { $oid: string }
    Regex     = "regex",     -- { $regularExpression: { pattern: string, options: string } }
    Timestamp = "timestamp", -- { $timestamp: { t: integer, i: integer } }
}

return M
