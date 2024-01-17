---@meta

---@class mongo.ui.status.ProcessMeta
---@field pid integer
---@field type mongo.api.ProcessType
---@field state mongo.api.ProcessState
--
---@field last_stdout? string
---@field stdout_dirty boolean
---@field last_stderr? string
---@field stderr_dirty boolean

---@alias mongo.ui.status.Component fun(args?: table): string

---@alias mongo.ui.status.ComponentType
---| "_current_db"
---| "_running_cnt"
---| "_process_state"
---| "_mongosh_last_output"

---@class mongo.ui.status.ComponentSpec
---@field [integer] string
---@field [string] any

---@class mongo.ui.status.BuiltComponentInfo
---@field default_args table<string, any>
---@field comp mongo.ui.status.Component

