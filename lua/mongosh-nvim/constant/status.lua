local M = {}

---@enum mongo.ui.status.OperationState
M.OperationState = {
    Idle = 2,
    Execute = 3,
    Query = 4,
    Replace = 5,
    MetaUpdate = 6,
    Connect = 7,
}

return M
