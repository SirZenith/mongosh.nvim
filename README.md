# mongosh.nvim

<b>Notice</b>: still in early stage of development, might be breaking change.

---

This is a frontend for mongosh. It provides your the ability to send script to
mongosh and inspect executation result in NeoVim.

You can:

- Connect to database with authentication.
- List available databases and collections for current connection.
- Execute script in buffer.
- Make query by buffer content.
- Edit document by buffer content.
- Refresh result buffer after some data operations.

Following option can be customized:

- Executable path of `mongsh`.
- Indent size for JSON result.
- How result window splits current view.
- Action on new buffer gets created by plugin, you can set keymap in new buffer
or do other things of your interest.

## Installation

To use this plugin, you need to have `mongosh` executable on your machine.

Then, install this plugin with plugin manager of your choice.

## Configuration

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

Default config value and introduction of each option can be found [here](https://github.com/SirZenith/mongosh.nvim/blob/main/lua/mongosh-nvim/config.lua).

## Usage

Check out `:help mongosh-nvim` for documentation.

Basically, this plugin provides command `:Mongo` as entrance, and several
subcommands that actually do something.

Screen shot (click to jump to video):

[![screen shot](./img/screen_shot.png)](https://youtu.be/t8gPMM5TuyI)

## Thanks

This plugin is inspired by [jrop/mongo.nvim](https://github.com/jrop/mongo.nvim).
