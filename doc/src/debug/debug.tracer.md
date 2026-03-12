# debug.tracer

Ring buffer trace log for recording and inspecting recent kernel call paths.

## Overview

`debug.tracer` maintains a fixed-size circular array of `pchar` pointers representing the most recently pushed trace labels. Callers push a static string literal before a significant operation and pop it afterwards. Because no string copy is made, pointers must reference persistent memory (string literals or static constants).

The tracer is disabled immediately at kernel startup by `freeze` and re-enabled by `init` once the infrastructure is stable enough to accept trace entries. A compile-time `TRACER_ENABLE` conditional controls whether the tracing code is compiled at all; if disabled, all calls become no-ops.

A `TRACER` shell command allows runtime inspection and toggling of the trace buffer.

## Dependencies

- `core.util`, `arch.x86.util`
- `core.strings`
- `io.stdio`
- `io.syslog`

## Boot Registration

- `debug.tracer.freeze` depending on `io.syslog` — freezes the tracer ring buffer.
- `debug.tracer` depending on `io.stdio` — full tracer initialisation.

## Constants

### MAX_TRACE
`40` — Capacity of the trace ring buffer. At most 40 labels are retained; older entries are silently overwritten.

## Functions and Procedures

### init

```pascal
procedure init;
```

Zeros all trace slots, resets the `Locked` and `head` state variables, sets the tracer to ready, pushes an initial `'kmain'` entry, and registers the `TRACER` shell command via `io.stdio.registerCommand`.

### push_trace

```pascal
procedure push_trace(t_name: pchar);
```

Advances `head` (with wrap-around at `MAX_TRACE`) and stores `t_name` at the new position. Uses a simple boolean `Locked` flag to prevent re-entrant writes. Does nothing if the tracer is frozen or `TRACER_ENABLE` is false.

The pointer is stored directly; **no copy is made**. Callers must pass pointers to static/persistent data.

### pop_trace

```pascal
procedure pop_trace;
```

Currently a no-op stub. Present for symmetry with `push_trace` and potential future implementation of a proper call-depth model.

### freeze

```pascal
procedure freeze;
```

Sets the tracer to not-ready, preventing further entries until `init` is called. Called by `kmain` at the very beginning of the boot sequence before the heap is available.

### get_last_trace

```pascal
function get_last_trace: pchar;
```

Returns the pointer stored at the current `head` position — the most recently pushed trace label.

### get_trace_count

```pascal
function get_trace_count: uint32;
```

Returns `MAX_TRACE` (the ring buffer capacity). Does not reflect the number of distinct pushes made.

### get_trace_N

```pascal
function get_trace_N(idx: uint32): pchar;
```

Returns the trace entry `idx` positions before the current head (0 = most recent). Handles ring-buffer wrap-around. Returns `nil` if `idx` is out of range or `TRACER_ENABLE` is false.

### print_traces

```pascal
procedure print_traces;
```

Iterates the entire ring buffer from index 0 to `MAX_TRACE - 1` and writes each entry to `io.syslog` in the format `[TRACER] [N] <label>`. Entries that are `nil` are printed as `?????????`.

## Notes

The `TRACER` shell command supports three sub-commands:

| Sub-command | Description |
|---|---|
| `list [count]` | Prints the last `count` (default 5, max 39) trace entries to stdout. |
| `disable` | Sets the tracer to not-ready. Only works if `TRACER_ENABLE` is true. |
| `enable` | Sets the tracer to ready. Only works if `TRACER_ENABLE` is true. |

The `Locked` flag is a simple spin-lock that prevents nested `push_trace` calls from corrupting the ring buffer. It does not protect against concurrent ISR-level pushes; the tracer is not interrupt-safe by design.
