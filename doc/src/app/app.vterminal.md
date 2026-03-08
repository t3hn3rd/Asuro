# app.vterminal

LVGL-based multi-instance visual terminal emulator.

## Overview

`app.vterminal` implements a full graphical terminal window that runs inside the Asuro desktop environment. Each instance is fully independent: it maintains its own scrollback buffer, input line, command history, working directory, directory stack, foreground process, and background job list. All per-instance state is stored in a heap-allocated `TVTermState` record referenced through LVGL widget `user_data`.

Commands are parsed and dispatched as preemptive processes via `proc.mgr.runCommand`. A per-instance LVGL timer polls the foreground process's stdout and stderr buffers at 100 ms intervals and appends new output to the scrollback. Background jobs (launched with a trailing `&`) are tracked separately and reaped when they finish.

## Dependencies

- `driver.video.lvgl`, `driver.video`, `driver.video.windows`, `driver.video.desktop`
- `driver.hid.keyboard`
- `debug.tracer`
- `core.strings`, `core.util`, `arch.x86.util`
- `memory.heap`, `core.version`
- `io.stdio`, `driver.storage.vfs`
- `proc.mgr`, `proc.types`
- `core.ds.lists`, `core.ds.hashmap`
- `driver.storage.filedispatch`

## Constants

### TERM_W / TERM_H
`640` / `400` — Terminal window dimensions in pixels.

### MAX_TEXT
`4096` — Maximum scrollback buffer length in characters. When full, the oldest half is discarded.

### MAX_LINE
`1024` — Maximum input line length.

### HIST_SIZE
`10` — Number of command history entries.

### DRAIN_PERIOD
`100` — Milliseconds between output-drain timer polls.

## Types

### TVTermState / PVTermState

Per-instance state record allocated on the heap.

| Field | Description |
|---|---|
| `win_id` | LVGL window identifier |
| `text_label` | LVGL label widget holding the scrollback text |
| `drain_timer` | Per-instance LVGL timer for polling foreground process output |
| `text_buf` | Scrollback character buffer |
| `line_buf` | Current input line being typed |
| `hist` | Ring buffer of recent commands |
| `ForegroundPID` | PID of the currently running foreground process, or 0 |
| `fg_stdout/stderr/stdin` | I/O buffers for the foreground process |
| `TerminalPID` | PID of the terminal's own idle process |
| `cwd` | Per-terminal working directory string |
| `dir_stack` | Stack of saved working directories for `pushd`/`popd` |
| `bg_jobs` | Dynamic list of background job records |

### TBackgroundJob / PBackgroundJob

Record tracking a background process: PID, job number, command name, stdout/stderr buffers, and drain watermarks.

## Functions and Procedures

### init

```pascal
procedure init;
```

Registers the terminal application with `driver.video.desktop` under the name `Terminal`. Multiple independent instances can be launched from the desktop.

### launch (internal)

Allocates a new `TVTermState`, creates the LVGL window with a black background and green-on-black text label, registers event callbacks, creates the drain timer, spawns the terminal process, and displays the welcome prompt.

### processCommand (internal)

Parses the input line into a parameter list and dispatches to a built-in handler or `io.stdio.findCommand`. Supports background launch via trailing `&`. Falls through to `driver.storage.filedispatch` for file-based executables if no registered command matches.

## Built-in Commands

| Command | Description |
|---|---|
| `CLEAR` | Clears the scrollback buffer |
| `CD` | Changes the per-terminal working directory |
| `LS` | Lists the contents of the current directory |
| `PUSHD` | Pushes the current directory onto the stack |
| `POPD` | Pops and changes to the top directory on the stack |
| `JOBS` | Lists active background jobs |
| `FG` | Brings the first background job to the foreground |

## Notes

Ctrl+C terminates the foreground process, drains remaining output, and returns to the prompt. History navigation uses Up/Down arrow keys and wraps correctly on ring buffer boundaries. The scrollback buffer uses a half-discard strategy when full to avoid blocking I/O.
