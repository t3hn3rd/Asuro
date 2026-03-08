# app.notepad

Graphical text editor application with full file management and text selection.

## Overview

`app.notepad` provides a windowed GUI text editor built on LVGL. It is registered with the desktop environment and launched from the application launcher. The editor supports opening, saving, and creating new documents via an integrated file picker dialog. Text selection is implemented manually on top of LVGL's textarea widget using a selection anchor and direct label selection API calls.

The application runs as a desktop program and creates an associated process entry visible in `PS`.

## Dependencies

- `driver.video.desktop`, `driver.video.lvgl`, `driver.video`, `driver.video.windows`
- `app.filepicker`
- `driver.hid.keyboard`
- `memory.heap`
- `driver.storage.types`, `driver.storage.vfs`
- `core.strings`, `io.syslog`, `debug.tracer`
- `core.util`, `arch.x86.util`
- `proc.mgr`, `proc.types`

## Constants

### WIN_W / WIN_H
`700` / `500` — Window dimensions in pixels.

### TOOLBAR_H / STATUSBAR_H
`40` / `24` — Heights of the toolbar and status bar in pixels.

### FILE_BUF_SIZE
`65536` — Maximum file read/write buffer size (64 KB).

### LV_NO_SEL
`$FFFF` — Sentinel returned by LVGL when no text selection is active.

### LV_EVT_STOP_OFF / LV_EVT_STOP_BIT
`24` / `2` — Byte offset and bitmask used to set the `stop_processing` flag in an `lv_event_t` struct, preventing LVGL's default textarea key handler from also processing a key event.

## Types

### TNotepadState / PNotepadState

Per-instance state record allocated on the heap.

| Field | Type | Description |
|---|---|---|
| `win_id` | `uint32` | LVGL window identifier |
| `pid` | `uint32` | Process ID of the associated notepad process |
| `ta` | `Plv_obj` | LVGL textarea widget |
| `status_label` | `Plv_obj` | Status bar label showing line, column, and filename |
| `dirty_label` | `Plv_obj` | Dirty-flag indicator label |
| `currentPath` | `pchar` | Heap-allocated path of the open file, or `nil` for untitled |
| `isDirty` | `boolean` | Whether the document has unsaved changes |
| `sel_anchor` | `sint32` | Byte offset of the selection anchor; `-1` means no selection |

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the application with `driver.video.desktop` under the name `Notepad`.

### launch (internal)

Creates the LVGL window, toolbar (New, Open, Save, Save As buttons), main textarea, and status bar. Registers keyboard event callbacks and spawns the notepad process.

### saveFile (internal)

Writes the textarea content to `currentPath` via VFS. Opens for read-write rewrite first; falls back to write-only new for new files. Shows an error message box on failure.

### loadFile (internal)

Reads a file from VFS into the textarea. Resets dirty state and selection anchor after loading.

### performNew (internal)

Clears the textarea, resets `currentPath` to `nil`, and updates the status bar.

### updateStatusBar (internal)

Computes the 1-based line and column from the current cursor byte offset and updates the status label text.

### buildSplicedString (internal)

Returns a new heap-allocated string with a range `[from_idx, to_idx)` replaced by an optional insertion string. Used for selection deletion and text replacement.

### applyIndent (internal)

Applies or removes 4-space indentation from every line overlapping a selection range. Returns a new heap-allocated string.

## Notes

Only one Notepad window may be open at a time. Closing with unsaved changes shows a discard confirmation dialog. The Shift+Arrow selection mechanism uses `lv_label_set_text_selection_start/end` directly rather than LVGL's built-in selection, because user key callbacks fire before the default widget handler, allowing `stopEvent` to suppress unwanted default behaviour.
