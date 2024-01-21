# Prerequest

Your should have `mongosh` installed on your machine. You can either have it in
your `PATH`, or config executable path in plugin setting to pointing to your
installation.

# Overview

At its core, this plugin interacts with user by commands and different types
of buffer. This plugin provides:

- Commands to run mongosh script in your buffer. Selecting buffer content with
visual mode allows running only part of buffer content.
- A sidebar for browsing available databases and collections. By selecting
collection entry in sidebar, will create a query buffer on that collection.
- A lualine component for showing connection status, like host name, database
name, number of running mongosh process, type of running operation.

This plugin talks to mongosh with buffer content, and writes operation result as
buffer content. When a new buffer should be created, and how that buffer
should be shown on screen is configurable.

On each executation, a new mongosh process is spawn for evaluation. No long
term connection is kept.

# Buffers

## Introduction

Plugin manages its operations by attaching meta info to buffers.

For example, by recognizing operation type of a buffer, one command can behave
differently, see |mongosh-nvim.cmd.edit|.

If a buffer is created by this plugin, such meta info will be attached as the
buffer gets created. For an existing buffer, once your run command on it,
corresponding meta info will then be attached to that buffer.

By default, when meta info is attached to a buffer, following key map will be
set on that buffer:

- `<A-b>`, 'build' the buffer, which means generates result buffer with
its content. On query buffer `build` means make query; on edit buffer `builde`
will write data to database, etc..
- `<A-r>`, refresh the buffer, regenerate its content with information
binded to the buffer, for example refreshing an query result buffer after some
database write operatin will run the query in buffer which created itself
again.

This key map setup is done by providing `on_create` callback in default config
for `Unknown` buffer type. Buffer config value will read `Unknown` type config
as fallback when no value is provided for that specific type.

You can set your custom callbak for buffer types of your interest of yur
interest.

Most of the time this plugin handles three types of buffer: execute, query,
 edit.

These typs of buffer can be created by user command or selecting entries in
plugin sidebar.

## Execute

By running `:Mongo execute` command on a buffer, you can set that buffer to
execute type, or you can create an empty execute buffer with
`:Mongo new execute`.

Running `:Mongo execute` command on execute buffer will run its content.

If you want to see any output for an execution, you will need to print results
to standard output yourself, for example with `print()`.

Standard output will then appear in a execution result buffer, any thing you
print to stdout, will be there. If your script does not prints anything, a
default message will be written to execution result buffer to indicate a
successful run.

- Build operation for an execute buffer is to run its content as
mongosh script.
- Refresh operation for an execution result buffer is to run content of the
buffer that created it again, and update execution result to itself. If such
buffer no longer exists, execution will use script of last successful run
cached in buffer meta.

## Edit

There are a few ways to create an edit buffer. Running `:Mongo edit` command on
user buffer, turns that buffer into an edit buffer; using build operation or
running `:Mongo edit` command in a query result buffer will create an edit
buffer for the document under your cursor; Rung `:Mongo new edit` command.

Running `:Mong edit` command on edit buffer will make write operation with its
content.

Edit buffer make its write operation by `replaceOne` call, user should provide
following variables' declaration in buffer content:

- `collection`, string value for specifying which collection to operate on.
- `id`, `_id` value of target document.
- `replacement`, new document value to use as `replaceOne` argument.

An example snippet goes like this:

```typescript
const collection = "foo"
const id = 15

// Edit your document value
const replacement = { bar: "buz" }
```

Your snippet will then be put into template code. No matter what complex
preparation you did in your snippet, template code reads only these three
variables.

Edit result buffer will display JSON output from mongosh for that `replaceOne`
call.

- Build operatin for edit buffer is to make `replaceOne` call with its content.
- Refresh operation for edit buffer is to reset its content to default snippet
with `replacement` set to value of document specifyed by `collection` and `id`
in database.
- Refresh operation for edit result buffer is to make `replaceOne` call with the
content in the buffer that created it. If such buffer no longer exists, buffer
will use script of last successful run cached in buffer meta.

## Query

Query buffer can be created by selecting a collection plugin sidebar or popup
of `:Mongo collection` command, or create with `:Mongo new query` command.

Running `:Mongo query` command on a query buffer will make query operation.

You will need to declare `result` variable in you buffer content, this variable
will be treated as output value of your snippet.

A example snippet goes like this:

```typescript
const result = db.foo.findOne({ name: /foo\d\d/ }, { name: true, value: true })
```

Collection name used in query buffer will be extracted and save to query result
buffer's meta info for further operation in query result buffer.

Currently only following types of extraction are supported:

- `const result = db.foo.find({})`, collection given by dot access to `db`.
- `const result = db['foo'].find({})`, collection given subscripting to `db`.
- `const coll = 'foo'; const result  = db[coll]`, collection name declare by
  string literal and stored in variable, and use that variablein subscripting
  to `db`.

All these extractions need the right hand side of your `result` declaration to
be direct access to `db` global variable.

Query result buffer now supports two different display style: JSON and card.

JSON style show your query result as plain JSON, card view shows result with
cards, and uses customizable highlight for elements.

Card view draws its content lazyly, when you make a huge query, result will not
be written buffer until they are visible in window.

Highlight groups used in card view are:

- `MongoshTreeNormal`, for normal text in card view.
- `MongoshValueTypeName`, for name of data type.
- `MongoshValueBoolean`, for boolean literal.
- `MongoshValueNull`, for `null` literal.
- `MongoshValueNumber`, for numberic literal.
- `MongoshValueString`, for string literal.
- `MongoshValueObject`, for representation of some BSON type value, e.g. binary,.
- `MongoshValueOmited`, for some elements like ellipsis.
- `MongoshValueRegex`, for regular expression literal.
- `MongoshValueUnknown`, for unrecognized value.

Card view provides some fold operation, default key maps are:

- pressing `<Tab>` or `<Cr>` at the beginning of and entry will toggle its
  expasnion.
- `zr`, lower fold level by one.
- `zm`, increase fold level by one.
- `zR`, expand all.
- `zM`, fold all.

JSON view and card view provides different editing support.

Your can either create an edit buffer from query result by running `:Mongo edit`
or by its build operation, these two way have the same effect.

Without visual selection, edit buffer created by JSON view will be a edit buffer
for document under cursor; with visual selection, it will create a update buffer
for selected field(s) only.

Card view, with or without visual selection, will only create update buffer for
field under cursor.

Additionally, when pressing `i` in card view, an input box will show up and
allows you to make quick edit to field under your cursor with input value. Key
used to trigger a quick edit is configurable.

- Build operation for query buffer is to run query with its content.
- Build operation for JSON view query result, when with visual selection a
  update buffer will be created for selected field(s); when without visual
  selection, an edit buffer will be created for the document under cursor.
- Refreh operation for query buffer is to rerun the query in the buffer that
  created this result buffer, if such buffer no longer exists, script used in
  last successful run will be used.

# Commands

This plugin provides one user command `:Mongo` as entrance, each of its
subcommand provides one actual functionality.

For commands that take flag argument, enter `-` will give you completion of
all short flags, and `--` will give you all long flags.

## Connection

`:Mongo connect`

: sets connection arguments for latter execution.

  This command is almost transparent to mongosh, which means most flags you
provide to this command will be passed to mongosh as is. And all flags
supported by mongosh can be passed to this command. (Note: though not all
mongosh flags are listed in completion of this command, they are still
supported and will finally be passed to mongosh calls.)

  There are several extra flags provided by this command:

  - `db-addr`, database address used for connection, value takes one of
following forms:

    - database name: `foo`
    - host address and database name: `localhost/foo`
    - host address with port and database name: `localhost:27017/foo`
    - any valid connection URI string: `mongosh://localhost:27017/foo`

  Value of this flag will be used as first positional argument to mongosh
calls. Everything mongosh supports for this argument also works here.

  - `with-auth`, a boolean flag, presence of this flag indicates `true`.
  When sets to `true`, plugin will ask user input for authentication
information, including user name, password, authentication source
database. If any of these three is not needed, just leave input box
blank and press enter.

  You can also provides user name and password via `--username` and
`--password` flag if you don't mind your password gets recorded in input
history.

  Normally speaking, everyone who can reads memory of running program on
your machine can do many other horrible things to your system, so this
plugin assumes storing connection information in memory to be safe.

  With that being said, this plugin still remaps string connection info with a
shuffeled ASCII list, texts gets recovered only when they are read, used.
This makes connection information not directly readable when your memory
gets dumped.

`:Mongo database`

: List all available databases on current host

You can pick one from them as target of latter operation.

`:Mongo collection`

: List all available collections

Picked name will be used to create a new query buffer.

## Action

`:Mongo execute`

: Run content in current buffer with mongosh.

Command support range argument. With visual selection, only selected part will
be executed.

Standard out put of executation will be display in result buffer.

Please note that you need to print out all information of your interest in your
script snippet yourself, or else there will only be default content in result
buffer.

`:Mongo query`

: Run query in current buffer.

Command support range argument. With visual selection, only selected part will
be executed. For more detail see [Buffers](#buffers)

Query result will be written to buffer.

Query snippet should define `result` variable that has database cursor value,
such as `const result = db.collection.find()` method.

Query buffer created by this plugin will have example snippet as their initial
content.

Available flags are:

- `typed`, boolean flag, when `true`, JSON query result will contains value type
  information.

`:Mongo edit`

: Run edit snippet in current buffer.

Command support range argument. With visual selection, only selected part will
be executed.

Final behavior varies according to the type of current buffer.

- In query result buffer, a new edit buffer with collection name of that
query, and id of the nearest document to cursor will be created.
- With edit buffer, create and run a replace snippet with current buffer
content. Executation result will be written to another buffer.

A replace snippet for edit buffer should define following variables:

- `collection`, string value for collection name.
- `id`, target document's `_id` value.
- `replacement`, new document value to use as `replaceOne` argument

Replace snippet will be merge into a template with `replaceOne` call into
the collection of your choice.

Executation result of a replace snippet will be written to result buffer
as JSON text.

`:Mongo refresh`

: Regenerates content of current buffer according to its type.

For example, running this command in a query result buffer will run its
query again, and query result will again be written to that buffer.

## Creation

`:Mongo new execute`

: Create a empty mongosh script sketch buffer.

`:Mongo new query`

: Create a new query buffer with user selection.

List all available collections in current database, the one you pick will be
used in buffer creation.

`:Mongo new edit`

: Create new edit buffer with given collection name, document id.

Available flags:

  - `collection`, `c`, target collection name.
  - `id`, document's `_id` field value.

## Sidebar

`:Mongo sidebar`

: Toggle database list sidebar

The same as `:Mongo sidebar toggle`.

`:Mongo sidebar show`

: Show database list sidebar,

If a sidebar is already created in current tabpage, then nothing happends.

`:Mongo sidebar hide`

: Hide database list sidebar in current tabpage.

`:Mongo sidebar toggle`

: Toggle database list sidebar in current tabpage.

## Conversion

`:Mongo convert card-result`

: Convert JSON query result to card view.

Available flags are:

- `persisit`, also use card view for latter query.

`:Mongo convert json-result`

: Convert card view query result to JSON view.

Available flags are:

- `persisit`, also use JSON view for latter query.

# Configuration

All available config options and default config value are list at
<https://github.com/SirZenith/mongosh.nvim/blob/main/lua/mongosh-nvim/config.lua>

All config fields are commented, you can check that file for documentation on
configuration options.

User config table can be passed to plugin as follow:

```lua
require "mongosh-nvim".setup {
    -- your config here
    executable = "/usr/local/bin/mongosh"
    connection = {
        default_db_addr = "192.168.1.10:10001"
    }
}
```

User config will be merge into default config. Options that not provided by
user will use default value.

# Database List Sidebar

User can use database list sidebar to browse available database on host, and
collection names in a database.

By expanding a database entry or selecting a collection entry, target database
of current connection will automatically switch to corresponding database.

Additionally, selecting a collection by pressing enter will create a query
buffer on that collection.

`sidebar` section in configuration file modifies the looking of sidebar
elements.

For example icon for each type of list entry. To display icon in default
config you need to install one of Nerd Fonts. For more information about Nerd
Fonts check https://www.nerdfonts.com/ .

Sidebar uses highlight groups to bring colors to list elements. You will to
setup highlight style by yourself. For example, following code set foreground
color of database name in list to cyan:

```lua
vim.api.nvim_set_hl(0, "MongoshDatabaseName", { fg = "#30E2FF" })
```

Supported highlight groups are:

- `MongoshNormal`, window background and color of normal text.

- `MongoshHostName`, color of host name.
- `MongoshHostSymbol`, color of host address icon.

- `MongoshDatabaseName`, color of database name.
- `MongoshDatabaseSymbol`, color of database type icon.

- `MongoshCollectionName`, color of collection name.
- `MongoshCollectionSymbol`, color of collection type icon.

- `MongoshCollectionLoading`, color of loading place holder text.
- `MongoshCollectionLoadingSymbol`, color of loading indicator.

# Status Line

Plugin provides a [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)
component for displaying plugin state in status line.

Status line information is composed by child components, by default, on active
window, mongosh.nvim shows names of current host, database currently connected
to, operation state of plugin, and number of running mongosh process; on
inactive window, only database name and operation state are shown.

Each component is a function that returns string, you can provide your own
component in plugin config if you like.

Enabled components are given by a list of component specification. `spec` is
either a string or a table.

When `spec` is given by string, plugin will first treat it as component name,
and try to find custom component or built-in component with that name, if a
custom component has the same name as built-in one, custom component is prefered.

If no component's name matches given string, then this string is used as literal,
and will be concatenate directly to other parts.

When `spec` is table, plugin will used `spec[1]` as component name. If not
component is found using that name, this `spec` will be ignored.

When mathing component is found, `spec` will be passed to component function as
argument every time component gets invoked.

For example, you can have following status line setting:

```lua
require "mongosh-nvim".setup {
    status_line = {
        components = {
            -- components used in status line active window
            active = {
                -- this will show something like "localhost:27017/foo"
                "_current_host", "/", "_current_db",
            },
            -- components used in inactive window
            inactive = {
                { -- the same built-in component but shorter.
                    "_current_host",
                    max_width = 10,
                }
            },
        },
    },
}
```

## Custom Component

Status line content is generated lazyly, once there is cached value, plugin
won't generates another string, the same value is reused when lualine does
refreshing.

If you want to write your own component, you must tell plugin when the cached
should be out of date. You do that by call `set_status_line_dirty()` with
autocommand, keybindding, events, etc..

An example component for showing time used for connection:

```lua
local api_constant = require "mongosh-nvim.constant.api"
local api_core = require "mongosh-nvim.api.core"
local status_base = require "mongosh-nvim.ui.status.base"

local CoreEventType = api_constant.CoreEventType
local core_event = api_core.emitter

local time_cache = 0

-- component function
local function connection_clock(args)
    if time_cache <= 0 then return "" end

    local format = args and args.format or "%d"
    local duration = os.clock() - time_cache

    return format:format(duration)
end

-- registering events
core_event:on(CoreEventType.action_connect_end, function()
    time_cache = 0
    status_base.set_status_line_dirty()
end)
core_event:on(CoreEventType.action_connect_start, function()
    time_cache = os.clock()
    status_base.set_status_line_dirty()
end)
```

You can register and enable component implementation above like this:

```lua
require "mongosh-nvim".setup {
    status_line = {
        components = {
            active = {
                {
                    "connection_clock",
                    format = "Connecting: %d",
                }
            },
        },
        custom_components = {
            connection_clock = connection_clock,
        },
    },
}
```

## Built-in

Plugin provides some built-in component, this section list their names and
argument they supports along with default value of each arguments, in form of
component specification.

All built-in component names start with a `_`.

- `_current_db`, shows database used for current connection.

```lua
{
    "_current_db",
    max_width = 20, -- max display width of database name
}
```

- `_current_host`, shows host name currently connected to.

```lua
{
    "_current_host",
    max_width = 20, -- max display width of host name
}
```

- `_operation_state`, shows plugin runnig state. Each state is mapped string or
  a list of string. When string list is used, each string in list will be used
  as animation freame when plugin is in that state.

```lua
local status_const = require "mongosh-nvim.constant.status"
local OperationState = status_const.OperationState

{
    "_operation_state",
    symbol = {
        [OperationState.Idle] = " ",
        [OperationState.Execute] = { " ", " " },
        [OperationState.Query] = { "󰮗 ", "󰈞 " },
        [OperationState.Replace] = { " ", "󰏫 " },
        [OperationState.MetaUpdate] = { " ", " " },
        [OperationState.Connect] = { " ", " ", " ", "󰢹 ", " ", "󰢹 " },
    },
    frame_time = 0.1, -- second for each animation frame
}
```

- `_running_cnt`, takes no argument, shows number of running mongosh process.
- `_process_state`, shows simple symbol for indicating state of mongosh process
  spawn by plugin.

```lua
local api_constant = require "mongosh-nvim.constant.api"
local ProcessState = api_constant.ProcessState

{
    "_process_state",
    state_symbol = {
        [ProcessState.Unknown] = "➖",
        [ProcessState.Running] = "🟢",
        [ProcessState.Error] = "🔴",
        [ProcessState.Exit] = "⚪",
    }
}
```

- `_mongosh_last_output`, shows last stdout or stderr output received from
  mongosh process.

```lua
{
    "_mongosh_last_output",
    max_width = 15, -- max display width of message
}
```
