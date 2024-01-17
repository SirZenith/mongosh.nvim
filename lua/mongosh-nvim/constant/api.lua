local M = {}

---@enum mongo.api.ProcessType
M.ProcessType = {
    Unknown = 1,
    MetaUpdate = 2,
    Execute = 3,
    Query = 4,
    Edit = 5,
}

---@enum mongo.api.ProcessState
M.ProcessState = {
    Unknown = 1,
    Running = 2,
    Error = 3,
    Exit = 4,
}

---@enum mongo.api.CoreEventType
M.CoreEventType = {
    connection_successed = "connection_successed",     -- fun()
    collection_list_update = "collection_list_update", -- fun(db: string)
    db_selection_update = "db_selection_update",       -- fun(db: string)
    incomming_stdout = "incomming_stdout",             -- fun(pid: number, out: string)
    incomming_stderr = "incomming_stderr",             -- fun(pid: number, out: string)
    process_started = "process_started",               -- fun(pid: number)
    process_ended = "process_ended",                   -- fun(pid: number)
    update_process_type = "update_process_type"        -- fun(pid: number, type: monog.api.ProcessType)
}

return M
