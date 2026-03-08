# app.edit

Simple terminal-mode text editor with VFS file load and save support.

## Overview

`app.edit` registers the `EDIT` shell command, which opens a lightweight keyboard-driven text editor. The editor operates on an in-memory line buffer (up to 256 lines of 120 characters each) and can load and save files through the VFS layer. It renders into a terminal window using character-cell drawing primitives.

## Dependencies

- `io.syslog`, `io.stdio`, `debug.tracer`
- `driver.hid.keyboard`
- `memory.heap`
- `driver.storage.types`, `driver.storage.vfs`
- `core.strings`
- `core.util`, `arch.x86.util`

## Constants

### ED_WIDTH / ED_HEIGHT
`60` / `20` — Dimensions of the editor viewport in character columns and rows.

### MAX_LINES
`256` — Maximum number of lines that can be held in the editor buffer.

### MAX_COLS
`120` — Maximum number of characters per line.

### TEXT_ROWS
`19` — Number of rows available for text (one row is reserved for the status bar).

### TAB_SIZE
`4` — Number of spaces inserted per Tab keypress.

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `EDIT` command with `io.stdio` and initializes the colour attribute values for normal text, cursor highlight, and the status bar.

### Run (internal)

```pascal
procedure Run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. Accepts an optional file path parameter. If a path is provided it is resolved to an absolute path via `driver.storage.vfs.MakeAbsolutePath`, the buffer is reset, and the file is loaded. The editor window is then opened and the active flag set.

### SaveFile (internal)

Serializes the line buffer to a single contiguous byte array with LF newlines and writes it to the VFS. Tries `omReadWrite / wmRewrite` first for existing files, then `omWriteOnly / wmNew` for new files.

### LoadFile (internal)

Reads up to 32 KB from the VFS into a temporary buffer, then parses it into the line array splitting on LF (CR bytes are skipped).

### OnKeyPressed (internal)

Keyboard event handler. Handles Ctrl+S (save), Escape (close), Tab (insert spaces), Backspace (delete character or merge lines), Enter (split line), arrow keys (cursor movement with scroll adjustment), and printable characters (ASCII 32-126).

## Notes

The window creation and event handler registration stubs are marked `TODO` in the source. The editor is currently single-instance; attempting to open a second instance while one is active logs an error and returns. The draw routine contains stub comments in place of the actual window-drawing calls, meaning rendering is not fully connected in the current codebase state.
