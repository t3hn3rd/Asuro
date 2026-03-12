# proc.mgr

Preemptive process manager providing process creation, scheduling, messaging, resource binding, and reaping.

## Overview

`proc.mgr` is the core process management unit for the Asuro kernel. It maintains a doubly-linked list (`PDList`) of `PProcessContext` pointers and implements:

- **Process creation** — allocates a `TProcessContext`, builds a fake interrupt frame on a newly-allocated 8 KiB stack so the first context switch `IRET`s into `process_trampoline`, and marks the process as `psReady`.
- **Round-robin scheduler** — `scheduler_pick_next` is called from the context-switch ISR. It reaps finished processes, checks the current process's remaining quantum, and scans the process list for the next `psReady` process. Falls back to the idle process if none is found.
- **System messaging** — `sendMessage` writes a `TProcessSysMsg` into the target process's `PendingMsg` field and wakes awaiting or suspended processes as appropriate.
- **Resource binding** — `bindResource`/`unbindResource`/`unbindAllResources` manage a per-process list of `TResourceBinding` records, each carrying a handle and a `TResourceCleanup` callback invoked on unbind or reap.
- **Legacy command wrapper** — `runCommand` wraps a `TCommandMethod` as a process by routing through `legacy_entry`, enabling terminal commands to run as proper preemptive processes.

A dedicated idle process (PID 0, name `'Idle'`) is created at `init` time. It runs on the kernel's original stack, is never reaped, and is selected by the scheduler whenever no other process is runnable.

Three shell commands are exposed: `PS` (process list), `KILL` (immediate state transition to `psFinished`), and `TERMINATE` (graceful `smTerminate` message).

## Dependencies

- `arch.x86.bda`
- `driver.storage.fdtable`
- `core.ds.lists`
- `memory.heap`
- `proc.types`
- `core.rand`
- `io.stdio`, `io.syslog`
- `core.strings`, `core.util`, `arch.x86.util`
- `debug.tracer`

## Boot Registration

Registered with `boot.mgr` as `proc.mgr`, depending on glob `driver.storage.fs*` (waits for all matching entries).

## Variables

| Variable | Type | Description |
|---|---|---|
| `CurrentProcess` | `PProcessContext` | The process currently executing; never nil — at minimum the idle process. |
| `IdleProcess` | `PProcessContext` | PID 0 idle process. Unkillable; runs the kernel's original HLT loop. |
| `Processes` | `PDList` | Process table containing `uint32`-sized slots, each holding a `PProcessContext`. |
| `SchedulerIndex` | `uint32` | Round-robin cursor into the process list. |

## Functions and Procedures

### init

```pascal
procedure init;
```

Creates the process table DList, allocates and initializes the idle process (PID 0, priority 0, quantum 1), sets `CurrentProcess` to the idle process, and registers the `PS`, `KILL`, and `TERMINATE` shell commands.

### create

```pascal
function create(name: pchar;
                entry: TProcessEntryPoint;
                localData: void;
                priority: uint8): PProcessContext;
```

Allocates and fully initializes a new process context. Assigns a random PID via `rand32`, copies `name` (truncated to 31 characters), allocates an 8 KiB kernel stack, and builds the initial stack frame:

- 3-word IRET frame: EFLAGS (`$0202`, IF=1), CS (`$08`), EIP → `process_trampoline`.
- 8-register POPAD frame (all zero).
- 4 segment registers pushed as 32-bit values: DS, ES, FS, GS = `$10`.

`SavedESP` is set to the bottom of this frame. `localData` is stored in `ctx^.Local`. A `PDList` resource list and a per-process FD table are allocated. The working directory is initialized to `'/'`. The context is appended to `Processes` and transitioned to `psReady`.

### findByID / findByName

```pascal
function findByID(pid: uint32): PProcessContext;
function findByName(name: pchar): PProcessContext;
```

Linear search through the process table. `findByName` uses `stringEquals` (case-sensitive). Both return `nil` if not found.

### sendMessage

```pascal
procedure sendMessage(pid: uint32; msg: TProcessSysMsg; data: void);
```

Sets `PendingMsg` and `MsgData` on the target process. If the process is `psAwaiting`, transitions it to `psReady`. If suspended and receiving `smResume`, transitions it to `psReady`.

### terminate

```pascal
procedure terminate(pid: uint32);
```

Sends `smTerminate` to the process. The process is responsible for checking `PendingMsg` and exiting gracefully. PID 0 is silently ignored.

### kill

```pascal
procedure kill(pid: uint32);
```

Directly sets the process state to `psFinished` with exit code `$FFFFFFFF`. The process is reaped on the next scheduler cycle. PID 0 is silently ignored.

### proc_yield

```pascal
procedure proc_yield;
```

Forces preemption by setting `TicksUsed := Quantum` then halting with `HLT`. The next timer interrupt will reschedule.

### proc_sleep_ms

```pascal
procedure proc_sleep_ms(ms: uint32);
```

Yields repeatedly until approximately `ms` milliseconds have elapsed, measured by comparing the BDA 1024 Hz tick counter with overflow handling.

### proc_await

```pascal
procedure proc_await;
```

Busy-waits on `HLT` while `CurrentProcess^.State = psAwaiting`. The caller must set `psAwaiting` before calling. An ISR or another process must set the state to something other than `psAwaiting` to unblock.

### proc_suspend

```pascal
procedure proc_suspend;
```

Sets `CurrentProcess^.State := psSuspended` and halts. The process does not execute again until `smResume` is delivered via `sendMessage`.

### proc_exit

```pascal
procedure proc_exit(exitCode: uint32);
```

Sets the exit code, transitions the process to `psFinished`, and enters an infinite `HLT` loop awaiting reaping.

### bindResource / unbindResource / unbindResourceNoCleanup / unbindAllResources

```pascal
procedure bindResource(ctx: PProcessContext; kind: TResourceKind; handle: void; cleanup: TResourceCleanup);
procedure unbindResource(ctx: PProcessContext; handle: void);
procedure unbindResourceNoCleanup(ctx: PProcessContext; handle: void);
procedure unbindAllResources(ctx: PProcessContext);
```

Manage per-process resource bindings. `bindResource` appends a `TResourceBinding` to the process's resource DList. `unbindResource` calls the cleanup callback before removing the binding. `unbindResourceNoCleanup` removes without calling cleanup. `unbindAllResources` detaches the DList, iterates in reverse calling all cleanup callbacks, then frees the list.

### runCommand

```pascal
function runCommand(name: pchar; method: TCommandMethod; params: PParamList;
                    stdin_buf, stdout_buf, stderr_buf: POutBuf): PProcessContext;
```

Creates a priority-1 process with `legacy_entry` as the entry point, storing `method` in `Local` and `params` in `MsgData`. Attaches the provided I/O buffers. Returns the new context, or `nil` if creation fails.

### processCount / getProcessByIndex

```pascal
function processCount: uint32;
function getProcessByIndex(idx: uint32): PProcessContext;
```

Query the process table size and retrieve a context by table index.

### scheduler_pick_next

```pascal
function scheduler_pick_next: PProcessContext;
```

Called from the context-switch ISR. Steps:

1. Calls `reapFinished` to free terminated processes.
2. If `CurrentProcess` is still running and has remaining quantum, returns it.
3. Transitions the current process from `psRunning` to `psReady` and resets `TicksUsed`.
4. Scans from `SchedulerIndex` in round-robin order, skipping PID 0 and non-ready processes.
5. Returns the first `psReady` process found, or `IdleProcess` if none.

### reapFinished

```pascal
procedure reapFinished;
```

Iterates the process table in reverse (to handle index shifting safely). For each process in `psFinished` or `psError` state (excluding `CurrentProcess` and PID 0): notifies the parent via `smChildExited`, frees the FD table, frees the working directory, calls `unbindAllResources`, frees the stack, removes the slot from the DList, and frees the context.

### terminal_command_ps

```pascal
procedure terminal_command_ps(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Prints a formatted table of all processes: PID (hex), name, state, and priority.

### terminal_command_kill / terminal_command_terminate

```pascal
procedure terminal_command_kill(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
procedure terminal_command_terminate(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Shell commands accepting a hex PID argument. `KILL` calls `kill`; `TERMINATE` calls `terminate`.

## Notes

The fake stack frame built by `create` uses the `process_trampoline` procedure as the EIP target. On the first IRET, the trampoline calls `CurrentProcess^.EntryPoint(CurrentProcess)`. When the entry point returns, the trampoline sets `psFinished` and halts, waiting for `reapFinished` to reclaim the context.

`unbindAllResources` detaches `ctx^.Resources` to `nil` before iterating, so cleanup callbacks that call back into the resource system will see an empty list and not cause double-frees.

Process IDs are generated by `core.rand.rand32` and are not guaranteed to be unique, though collisions are unlikely in practice. PID 0 is reserved for the idle process and bypasses kill/terminate guards.
