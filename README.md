# mongosh.nvim

This plugin is inspired by [jrop/mongo.nvim](https://github.com/jrop/mongo.nvim).

---

This is a frontend for mongosh. It provides your the ability to send script to
mongosh and inspect executation result in NeoVim.

You can:

- List available databases and collections on a host.
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

```lua
require "mongosh-nvim".setup {
    -- your config here
}
```

Default config value and introduction of each option can be found [here](https://github.com/SirZenith/mongosh.nvim/blob/main/lua/mongosh-nvim/config.lua).

## Usage

Check out `:help mongosh-nvim` for documentation.

Overview video:

[![usage overview](https://i.ytimg.com/vi/lnBtr-dtoAk/maxresdefault.jpg)](https://www.youtube.com/watch?v=lnBtr-dtoAk)
