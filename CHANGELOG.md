# Change Log

## [0.3.0] - 2024-01-27

Result display style change. Add status line component for indicating operation
state. Some user experience improvements.

## Added

- lualine.nvim status line component for showing operation status of plugin in
real time.
- Card view for displaying query result, this allows user to do huge query by
drawing query result in buffer lazily.

## Changed

- When expanding database entry in sidbar, connection that database automatically
- Sidebar expansion is preserved after get cloesd.
- Each type of buffer now gets an unique file type.

## Fixed

- User config doesn't actually get merged into default config, is not fixed.

## [0.2.0] - 2024-01-11

User interface and some API change. UI interaction and plugin command are changed
massively.

### Added

- Database list sidebar. user can open sidebar for browsing available database
in current connection.

  By pressing enter on a list entry, one can expand a database entry to show all
collections in it, or create a new qery buffer on a collection.
- Allow user specifying result buffer creation style and window splitting style
for individual buffer type.

### Changed

- Plugin command is changed to subcommand style. Both subcommands and command
flags gets completion. Main command of this plugin is `:Mongo`

### Fixed

- Selecting a item in collection lilst buffer gives and error, and failed to
create new query buffer, is now fixed.
- Running `:Mongo edit` on a query result buffer failed to create edit buffer,
is now fixed.
