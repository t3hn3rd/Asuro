# app.filepicker

Reusable LVGL file picker dialog for open and save operations.

## Overview

`app.filepicker` provides a modal file picker widget that can be embedded by any application needing VFS file selection. It presents a two-pane layout with a bookmarks sidebar and a scrollable file list. Directories and files are displayed separately, both sorted alphabetically. The caller supplies a callback that receives the selected path as a heap-allocated string (which the caller must `kfree`) or `nil` on cancellation.

The picker is built on a full-screen semi-transparent backdrop that blocks interaction with the application behind it. Destroying the backdrop tears down the entire picker tree in one LVGL call.

## Dependencies

- `core.ds.hashmap`, `memory.heap`
- `driver.video.lvgl`
- `driver.storage.types`, `driver.storage.vfs`
- `core.strings`, `io.syslog`, `debug.tracer`
- `core.util`, `arch.x86.util`

## Constants

### FP_FILTER_ALL
`nil` — Pass as the `filter` parameter to show all file types.

## Types

### TPickerCallback

```pascal
TPickerCallback = procedure(path: pchar; userdata: pointer); cdecl;
```

Callback invoked when the user confirms a selection or cancels. `path` is a `kalloc`'d absolute path string that the caller must `kfree`, or `nil` if the user cancelled.

### TPicker / PPicker (internal)

State record holding all LVGL widget references, current directory, navigation history (up to 16 entries), callback pointer, and picker mode flags.

## Functions and Procedures

### show_open

```pascal
procedure show_open(title: pchar; start_dir: pchar; filter: pchar;
                    cb: TPickerCallback; userdata: pointer);
```

Creates and displays an open-mode file picker. `title` is shown in the dialog header. `start_dir` is the initial directory. `filter` restricts visible files to a specific extension (e.g. `'.txt'`), or pass `FP_FILTER_ALL` for no restriction. `cb` is called with the chosen path on confirm or `nil` on cancel. `userdata` is passed through to the callback unchanged.

### show_save

```pascal
procedure show_save(title: pchar; start_dir: pchar; initial_name: pchar;
                    filter: pchar; cb: TPickerCallback; userdata: pointer);
```

Creates and displays a save-mode file picker. In addition to the open-mode features, a filename entry bar is shown below the file list. If the user selects an existing file a two-click overwrite confirmation is required before the callback is invoked. `initial_name` pre-fills the filename bar.

## Notes

Navigation history is capped at 16 entries. Entry names stored in LVGL widget `user_data` are `stringCopy`'d and freed by `free_list_items` before any list repopulation or picker close. Bookmark button paths are similarly managed by `free_bkmk_items`. The picker uses a deferred-refresh timer to avoid re-entering LVGL event handlers during directory population.
