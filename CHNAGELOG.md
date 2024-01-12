# Change Log

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
