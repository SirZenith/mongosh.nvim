local M = {}

---@enum mongo.BufferType
M.BufferType = {
    Unknown = "unknown",
    DbList = "db_list",
    CollectionList = "collection_list",
    Execute = "execute",
    ExecuteResult = "execute_result",
    Query = "query",
    QueryResult = "query_result",
    Edit = "edit",
    EditResult = "edit_result",
    Update = "update",
    UpdateResult = "update_result",
}

---@enum mongo.ResultSplitStyle
M.ResultSplitStyle = {
    Tab = "tab",
    Horizontal = "horizontal",
    Vertical = "vertical",
}

---@enum mongo.CreateBufferStyle
M.CreateBufferStyle = {
    Always = "always",
    OnNeed = "on_need",
    Never = "never",
}

M.DB_SIDEBAR_FILETYPE = "mongosh-nvim-db-sidebar"

return M
