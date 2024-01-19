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
    action_connect_end = "action_connect_end",             -- fun()
    action_connect_start = "action_connect_start",         -- fun()
    action_execute_end = "action_execute_end",             -- fun()
    action_execute_start = "action_execute_start",         -- fun()
    action_replace_end = "action_replace_end",             -- fun()
    action_replace_start = "action_replace_start",         -- fun()
    action_query_end = "action_query_end",                 -- fun()
    action_query_start = "action_query_start",             -- fun()
    action_meta_update_end = "action_meta_update_end",     -- fun()
    action_meta_update_start = "action_meta_update_start", -- fun()
    collection_list_update = "collection_list_update",     -- fun(db: string)
    db_selection_update = "db_selection_update",           -- fun(db: string)
    incomming_stdout = "incomming_stdout",                 -- fun(pid: number, out: string)
    incomming_stderr = "incomming_stderr",                 -- fun(pid: number, out: string)
    process_started = "process_started",                   -- fun(pid: number)
    process_ended = "process_ended",                       -- fun(pid: number)
    update_process_type = "update_process_type"            -- fun(pid: number, type: monog.api.ProcessType)
}

return M
