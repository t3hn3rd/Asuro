# Process Management — Architecture Plan

## Overview
A **preemptive** process management system for the Asuro kernel. Processes execute on the kernel's main thread (replacing the idle HLT loop). The 1024 Hz timer interrupt (IRQ0) preempts the running process, dispatches all existing kernel hooks (graphics, USB, network, BIOS tick, etc.) as normal, then the scheduler decides whether to resume the same process or context-switch to another. When no process is runnable, the CPU idles via HLT. This lays the groundwork for running WASM VM instances as first-class processes.

### Key Principle: Timer Hooks Are Untouched
All existing `TMR_0_ISR` hooks (`bios_data_area.tick_update`, `graphicsrefresh`, `usbhotplug`, TCP timers, etc.) continue to be dispatched **identically** on every IRQ0. The context switch happens **after** hooks have run, not instead of them.

## Design Decisions
| Decision | Choice | Rationale |
|---|---|---|
| Scheduling model | **Preemptive** (timer-driven context switch) | Main thread is wasted on HLT; preemption gives true concurrency; processes can run real code between interrupts |
| Context switch mechanism | IRQ0 saves/restores per-process kernel stack (ESP swap) | Single-stack-swap is the simplest correct approach for ring-0; no TSS task-switching needed |
| Per-process stack | 8 KB `kalloc`'d kernel stack per process | Large enough for nested calls + interrupt frames; small enough for many processes |
| Idle task | The original `kernel.yield()` HLT loop | When no process is runnable, scheduler returns the idle ESP; IRET resumes the HLT loop |
| Timer hooks | Unchanged — dispatched every IRQ0 before scheduling | Zero impact on existing hook-based subsystems (graphics, USB, network, BIOS) |
| Timer source | 1024 Hz TMR_0_ISR via IRQ0 (ISR_32) | Proven; all hooks already registered here |
| Process table | DList of `PProcessContext` pointers | Dynamic, contiguous; matches TCP/TCB pattern; avoids static array bloat |
| Process IDs | `rand32()` | Already used for TCP ISN; simple, collision-unlikely for ≤65535 processes |
| StdIO model | Per-process `POutBuf` triple | Extends existing stdio pattern; vterminal already knows how to render `POutBuf` |
| Resource bindings | Per-process hook DList | Allows sockets, timers, etc. to be bound to a process and cleaned up on destroy |
| Backwards compat | Legacy commands wrapped as processes | Existing `TCommandMethod` callbacks run as a process entry point, finish in one quantum |
| Re-entrancy guard | CLI/STI spinlocks on `kalloc`/`kfree` and shared state | Prevents heap corruption when process is preempted mid-allocation |
| Unit location | `src/processmanager.pas` + `src/contextswitcher.pas` | processmanager owns the table & API; contextswitcher owns the assembly stub |

## Data Structures (new `src/include/proctypes.pas`)

### Process State Enum
```pascal
TProcessState = (
    psCreated,      { Allocated, stack prepared, not yet scheduled }
    psRunning,      { Currently executing on the main thread }
    psReady,        { Runnable but not the current process }
    psSuspended,    { Paused — will not be scheduled }
    psAwaiting,     { Blocked on I/O or event — will not be scheduled }
    psFinishing,    { Marked for cleanup — destroy runs next schedule }
    psFinished,     { Terminal state — safe to reap }
    psError         { Unrecoverable error — safe to reap }
);
```

### System Message Enum
```pascal
TProcessSysMsg = (
    smNone,         { No message }
    smTerminate,    { Graceful shutdown requested }
    smKill,         { Immediate forced shutdown }
    smSuspend,      { Pause execution }
    smResume,       { Resume from suspended }
    smInput,        { New data available on stdin }
    smChildExited,  { A child process has exited }
    smCustom        { User-defined message (payload in MsgData) }
);
```

### Process Entry Point
```pascal
{ Every process is a procedure that receives its own context pointer.
  When this procedure returns, the process is automatically moved to psFinished. }
TProcessEntryPoint = procedure(ctx : PProcessContext);
```

### Resource Binding
```pascal
TResourceKind = (
    rkSocket,       { TCP/UDP socket }
    rkTimer,        { A timer hook }
    rkFileHandle,   { VFS file descriptor }
    rkCustom        { Arbitrary pointer }
);

PResourceBinding = ^TResourceBinding;
TResourceBinding = record
    Kind    : TResourceKind;
    Handle  : void;           { The resource pointer (PTCPSocket, etc.) }
    Cleanup : pointer;        { Optional cleanup procedure(handle: void) }
end;
```

### Process Context
```pascal
const
    PROCESS_STACK_SIZE = 8192;  { 8 KB per-process kernel stack }

PProcessContext = ^TProcessContext;
TProcessContext = record
    { Identity }
    ProcessID   : uint32;           { Unique ID via rand32() }
    Name        : array[0..31] of char; { Human-readable name }
    ParentID    : uint32;           { PID of parent (0 = kernel) }

    { State }
    State       : TProcessState;
    ExitCode    : uint32;

    { StdIO — per-process I/O buffers }
    StdIn       : POutBuf;          { Input buffer (written to by terminal/parent) }
    StdOut      : POutBuf;          { Output buffer (read by terminal for display) }
    StdErr      : POutBuf;          { Error buffer (read by terminal for display) }

    { Entry point }
    EntryPoint  : TProcessEntryPoint; { The procedure that IS the process }

    { Context switch state }
    SavedESP    : uint32;           { Saved stack pointer (set by context switch) }
    StackBase   : pointer;          { Base of kalloc'd stack (for kfree on reap) }
    StackTop    : uint32;           { Top of stack (StackBase + PROCESS_STACK_SIZE) }

    { Scheduling }
    Priority    : uint8;            { 1 = low, 255 = high; affects quantum length }
    Quantum     : uint16;           { Ticks before preemption (derived from Priority) }
    TicksUsed   : uint16;           { Ticks consumed this quantum }

    { System messages }
    PendingMsg  : TProcessSysMsg;   { Next message to deliver }
    MsgData     : void;             { Optional message payload }

    { Resource bindings }
    Resources   : void;             { PDList of TResourceBinding }

    { User-defined state }
    Local       : void;             { Arbitrary pointer (PWASMContext, etc.) }
end;
```

## Process Lifecycle

```
    processmanager.create()
           │
           ▼
     ┌─────────────┐
     │  psCreated   │  Context + stack allocated, fake interrupt frame pushed,
     └──────┬───────┘  added to process table as psReady
            │
            │  Scheduler selects this process → context switch
            │  IRET "returns" into process_trampoline → calls EntryPoint(ctx)
            ▼
     ┌─────────────┐
     │  psRunning   │◄──────────────────────┐
     └──────┬───────┘                       │
            │  Process code executes on      │
            │  the main thread; preempted    │
            │  by IRQ0 every quantum         │
            │                                │
            ├─ process calls proc_yield()    │
            │  → state set to psAwaiting ────┤  (resumed when smResume/smInput received)
            │                                │
            ├─ process calls proc_suspend()  │
            │  → state set to psSuspended ───┘  (resumed via smResume)
            │
            │  Process returns from EntryPoint (or calls proc_exit)
            │  → trampoline sets state to psFinished
            ▼
     ┌─────────────┐
     │  psFinished  │  Reaped by processmanager.reap():
     └─────────────┘  unbindAllResources, kfree stack, kfree context
```

### Lifecycle Rules
1. **A process is a procedure.** `EntryPoint(ctx)` runs as actual code on the main thread. When it returns, the process is done.
2. **Preemption is transparent.** The process does not need to yield or tick — IRQ0 preempts it automatically and the scheduler may switch to another process.
3. **The process can cooperate** by calling `proc_yield()` (release remaining quantum), `proc_await()` (block until event), or `proc_suspend()` (pause until explicit resume).
4. **External actors** send system messages via `processmanager.sendMessage()`. Messages are delivered as a flag check — the process can poll `ctx^.PendingMsg` or ignore it.
5. **smKill** is the exception: the process manager forcibly moves state to `psFinished` and reaps on the next scheduling pass (the process code is abandoned, stack freed).
6. **smTerminate** sets a flag the process should poll. Well-behaved processes check `ctx^.PendingMsg` periodically and return cleanly.

## Context Switcher (`contextswitcher.pas`)

The heart of the preemptive model. This unit replaces the generic `ISR_32` (IRQ0) handler with a custom assembly stub that performs the context switch.

### How It Works

**Current flow (unchanged for hooks):**
```
IRQ0 fires → CPU pushes EFLAGS, CS, EIP onto current stack
           → Enters ISR_32 handler
           → TMR_0_ISR hooks are dispatched (graphics, USB, BIOS tick, TCP, etc.)
```

**New flow (added after hooks):**
```
           → Save current ESP into CurrentProcess^.SavedESP
           → Call scheduler.pickNext() → returns PProcessContext (or nil for idle)
           → Load new process's SavedESP into ESP
           → EOI ($20 → port $20)
           → POPAD + POP segment regs + IRET
           → CPU resumes executing the new (or same) process
```

### Assembly Stub (pseudocode)
```nasm
context_switch_isr:
    ; --- Save interrupted process's registers ---
    pushad                          ; EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI
    push ds
    push es
    push fs
    push gs

    mov ax, $10                     ; Kernel data segment
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; --- Save current ESP ---
    mov eax, [current_process]      ; PProcessContext pointer (or nil if idle)
    test eax, eax
    jz .skip_save
    mov [eax + SavedESP_offset], esp
.skip_save:

    ; --- Dispatch all TMR_0_ISR hooks (unchanged) ---
    call tmr0_dispatch_hooks

    ; --- Ask scheduler for next process ---
    call scheduler_pick_next        ; Returns PProcessContext in EAX (nil = idle)
    mov [current_process], eax

    test eax, eax
    jz .load_idle
    mov esp, [eax + SavedESP_offset]  ; Switch to next process's stack
    jmp .restore

.load_idle:
    mov esp, [idle_esp]             ; Switch to idle task stack

.restore:
    ; --- EOI ---
    mov al, $20
    out $20, al

    ; --- Restore new process's registers ---
    pop gs
    pop fs
    pop es
    pop ds
    popad
    iret                            ; Resume (potentially different) process
```

### Idle Task
The idle task is the original `kernel.yield()` HLT loop. Its ESP is captured once during init before any process is created. When the scheduler returns `nil` (no runnable process), the context switcher loads the idle ESP. The IRET jumps back into the HLT loop. The next IRQ0 will check again.

### Stack Frame Layout (per process)
When a new process is created, its stack is initialized with a fake interrupt frame so that the first context switch "returns" into it:

```
    StackBase + PROCESS_STACK_SIZE (high addresses)
    ┌───────────────────────────┐
    │  EFLAGS ($0202 = IF set)  │  ← IRET pops this
    │  CS     ($08)             │  ← IRET pops this
    │  EIP    (→ trampoline)    │  ← IRET pops this
    │  EAX    (0)               │  ← POPAD restores
    │  ECX    (0)               │
    │  EDX    (0)               │
    │  EBX    (0)               │
    │  ESP    (ignored by POPAD)│
    │  EBP    (0)               │
    │  ESI    (0)               │
    │  EDI    (0)               │
    │  DS     ($10)             │  ← POP DS restores
    │  ES     ($10)             │
    │  FS     ($10)             │
    │  GS     ($10)             │
    └───────────────────────────┘
    ← SavedESP points here
```

The trampoline is a small Pascal procedure:
```pascal
procedure process_trampoline;
{ This is the EIP that IRET jumps to on first schedule }
begin
    STI;  { Re-enable interrupts (IRET would have set IF from EFLAGS, but be safe) }
    CurrentProcess^.State := psRunning;
    CurrentProcess^.EntryPoint(CurrentProcess);  { Run the process }
    { If EntryPoint returns, process is done }
    CurrentProcess^.State := psFinished;
    { Yield to scheduler — we can't just return, we need to wait for next IRQ0 }
    while true do HLT;
end;
```

## Process Manager Unit (`processmanager.pas`)

### Interface
```pascal
unit processmanager;

interface

uses
    proctypes,
    stdio;

{ Core API }
function  create(name : pchar;
                 entry : TProcessEntryPoint;
                 localData : void;
                 priority : uint8) : PProcessContext;

function  findByID(pid : uint32) : PProcessContext;
function  findByName(name : pchar) : PProcessContext;
procedure sendMessage(pid : uint32; msg : TProcessSysMsg; data : void);
procedure terminate(pid : uint32);           { Sends smTerminate }
procedure kill(pid : uint32);                { Forces immediate destroy + reap }

{ Process self-management (called by the running process) }
procedure proc_yield;                        { Voluntarily release remaining quantum }
procedure proc_await;                        { Block until an event/message arrives }
procedure proc_suspend;                      { Pause self until explicit resume }
procedure proc_exit(exitCode : uint32);      { Terminate self }

{ Resource binding }
procedure bindResource(ctx : PProcessContext; kind : TResourceKind; handle : void; cleanup : pointer);
procedure unbindResource(ctx : PProcessContext; handle : void);
procedure unbindAllResources(ctx : PProcessContext);

{ Legacy command wrapper }
function  runCommand(method : TCommandMethod; params : PParamList;
                     stdin_buf, stdout_buf, stderr_buf : POutBuf) : PProcessContext;

{ Query }
function  processCount : uint32;
function  getProcessByIndex(idx : uint32) : PProcessContext;

{ Init (called from kernel.pas) }
procedure init;

{ Terminal commands: PS, KILL, TERMINATE }
```

### Internal Design

**Process Table:** `Processes : PDList` — stores `uint32` pointers to `TProcessContext` (same pattern as TCP connections DList).

**Scheduler (`scheduler_pick_next`):**
Called from the context switch ISR (in `contextswitcher.pas`) after all timer hooks have run.

```
function scheduler_pick_next : PProcessContext:
    { Reap dead processes first }
    Reap all psFinished/psError (unbind resources, kfree stack, kfree context, remove from table)

    { Increment TicksUsed on current process }
    if CurrentProcess <> nil and CurrentProcess^.State = psRunning then
        CurrentProcess^.TicksUsed += 1
        if CurrentProcess^.TicksUsed < CurrentProcess^.Quantum then
            return CurrentProcess  { Same process, still has quantum left }
        else
            CurrentProcess^.State := psReady
            CurrentProcess^.TicksUsed := 0

    { Round-robin through process table looking for psReady or psCreated }
    next := pick next psReady/psCreated process (round-robin from current index)
    if next <> nil then
        next^.State := psRunning  (or psCreated → first schedule via trampoline)
        return next
    else
        return nil  { No runnable process → idle }
```

**Priority:** `Quantum = Priority * BASE_QUANTUM`. Higher priority = more ticks before preemption. `BASE_QUANTUM = 8` (~8ms at 1024 Hz). A priority-1 process gets 8 ticks; priority-10 gets 80 ticks (~78ms).

**Reaping:** Dead processes are reaped at the **start** of the scheduling pass (inside the ISR, interrupts disabled). This is safe because no process code is running at that point.

## VTerminal Refactor — Multi-Instance Terminals

The vterminal is currently a singleton with ~12 global variables (scrollback buffer, input line, history, LVGL widget pointers, focus state). This prevents opening multiple terminals and tightly couples the UI to command execution.

### Goal
Refactor vterminal into a **multi-instance** design where each `launch` allocates its own `TVTermState` and each terminal instance runs commands as preemptive processes.

### TVTermState Record
All former globals move into a heap-allocated record:
```pascal
PVTermState = ^TVTermState;
TVTermState = record
    { LVGL widgets }
    win_id       : uint32;
    content      : Plv_obj;
    text_label   : Plv_obj;
    focused      : boolean;

    { Scrollback text buffer }
    text_buf     : array[0..MAX_TEXT-1] of char;
    text_len     : uint32;

    { Current input line }
    line_buf     : TCommandBuffer;
    line_len     : uint32;

    { Command history ring }
    hist         : array[0..HIST_SIZE-1] of TCommandBuffer;
    hist_count   : uint32;
    hist_head    : uint32;
    hist_pos     : sint32;
    saved_line   : TCommandBuffer;
    saved_len    : uint32;

    { Process integration }
    ForegroundPID : uint32;         { PID of the running command process, or 0 }
    fg_stdout     : POutBuf;        { Shared stdout buffer for the foreground process }
    fg_stderr     : POutBuf;        { Shared stderr buffer for the foreground process }
    last_drain    : uint32;         { stdout.len at last drain — for incremental rendering }
    last_drain_err: uint32;         { stderr.len at last drain }
    fg_params     : PParamList;     { Saved params pointer for cleanup after process finishes }
end;
```

### Instance Lifecycle
1. **`launch`** — `kalloc(SizeOf(TVTermState))`, initialise all fields, create LVGL window + widgets. Pass `state` as `user_data` to all LVGL event callbacks.
2. **Event callbacks** — retrieve state via `lv_event_get_user_data(e)`. No globals referenced.
3. **`onClose`** — if `ForegroundPID <> 0`, kill foreground process. Destroy LVGL widgets. `kfree(state)`.
4. **Desktop registers `launch`** once — each click creates a new independent terminal.

### Command Execution Flow (per-instance)
1. User types command, presses Enter.
2. `processCommand(state)` looks up the command via `stdio.findCommand`.
3. Creates per-process `POutBuf` buffers: `state^.fg_stdout := createOutBuf(1024)`, etc.
4. Calls `processmanager.runCommand(cmd^.method, params, stdin_buf, fg_stdout, fg_stderr)`.
5. Stores the returned `PProcessContext^.ProcessID` in `state^.ForegroundPID`.
6. Terminal enters **busy state** — keyboard input is buffered but Enter is ignored while a foreground process is active.

### Incremental Output Rendering
The graphics refresh tick (~120 FPS) already calls `desktop.update` → LVGL handler. We add a lightweight **drain check** in the vterminal's update path:

```pascal
procedure drainOutput(state : PVTermState);
var
    ctx : PProcessContext;
begin
    if state^.ForegroundPID = 0 then exit;
    ctx := processmanager.findByID(state^.ForegroundPID);

    { Drain any new stdout content since last check }
    if (state^.fg_stdout <> nil) and (state^.fg_stdout^.len > state^.last_drain) then begin
        appendTextRange(state, state^.fg_stdout^.buf, state^.last_drain, state^.fg_stdout^.len);
        state^.last_drain := state^.fg_stdout^.len;
    end;

    { Same for stderr }
    if (state^.fg_stderr <> nil) and (state^.fg_stderr^.len > state^.last_drain_err) then begin
        appendTextRange(state, state^.fg_stderr^.buf, state^.last_drain_err, state^.fg_stderr^.len);
        state^.last_drain_err := state^.fg_stderr^.len;
    end;

    { Check if process finished }
    if (ctx = nil) or (ctx^.State = psFinished) or (ctx^.State = psError) then begin
        { Final drain already done above }
        freeOutBuf(state^.fg_stdout);  state^.fg_stdout := nil;
        freeOutBuf(state^.fg_stderr);  state^.fg_stderr := nil;
        freeParams(state^.fg_params);  state^.fg_params := nil;
        state^.ForegroundPID := 0;
        state^.last_drain := 0;
        state^.last_drain_err := 0;
        showPrompt(state);
    end;

    refreshDisplay(state);
end;
```

This is called from a lightweight LVGL timer callback registered per-instance (e.g., every 100ms). No global hooks needed — each terminal polls its own foreground process.

### Foreground / Background
- Each terminal instance tracks its own `ForegroundPID`. Only that process's output is displayed in that terminal.
- Future: `&` suffix to run in background; `FG`/`BG`/`JOBS` commands (Phase 5).
- Multiple terminals can each have their own foreground process running simultaneously — true multitasking UI.

### Benefits
- **Multiple terminals** — each `launch` creates a fully independent instance.
- **No global state** — all callbacks use `user_data` to find their instance.
- **Per-terminal foreground process** — each terminal independently tracks and renders its command's output.
- **Clean teardown** — closing a terminal kills its foreground process and frees all per-instance memory.
- **Unchanged command procedures** — `TCommandMethod` callbacks write to `POutBuf` as before; they don't know (or care) which terminal instance owns them.

## Resource Binding System

Processes need access to shared resources (TCP sockets, VFS handles, etc.). When a process dies, its resources must be cleaned up.

### Binding Flow
```
1. Process creates a TCP socket:
      sock := tcp.connect(@ctx);
      processmanager.bindResource(myProcess, rkSocket, void(sock), @tcp.abort_connection);

2. Process runs normally, using sock.

3. On process destroy (normal or kill):
      processmanager.unbindAllResources(myProcess)
        → For each binding:
            if binding.Cleanup <> nil then
                TCleanupProc(binding.Cleanup)(binding.Handle)
            kfree(binding)
```

This ensures sockets are RST'd, files are closed, timers unhooked, etc. even on abnormal termination.

## Legacy Command Wrapper

To maintain backwards compatibility, existing `TCommandMethod` procedures are wrapped as true preemptive processes:

```pascal
procedure legacy_entry(ctx : PProcessContext);
var
    method : TCommandMethod;
    params : PParamList;
begin
    method := TCommandMethod(ctx^.EntryPoint); { Overloaded — see note }
    params := PParamList(ctx^.MsgData);
    method(params, ctx^.StdIn, ctx^.StdOut, ctx^.StdErr);
    { Procedure returns → trampoline sets psFinished }
end;
```

**How it works:** The legacy command procedure runs as real code on the process's own 8 KB stack. It calls `bufWriteStr`, `bufWriteInt`, etc. as normal. It may take microseconds (MEMINFO) or milliseconds (ARP table dump). Either way, when it returns, the process is done.

**For halt-based async commands** (PING, etc.): These currently set `stdio.Halted := true` and return immediately, with a timer hook doing work. Under the preemptive model, these can be refactored to loop inside the entry point:
```pascal
procedure ping_entry(ctx : PProcessContext);
begin
    while ctx^.PendingMsg <> smTerminate do begin
        icmp.send_echo(...);
        proc_await;  { Block until reply or timeout }
        { Display result }
    end;
end;
```
Until refactored, they continue to work via the legacy wrapper (the entry point returns immediately and the timer hook runs as before).

This means **zero changes** to existing command procedures. They just work.

## Terminal Commands

### `PS` — List Processes
```
PID         NAME                 STATE       PRI   EXIT
A3F21B00    dhclient             Running       5      -
0019CC42    ping 192.168.1.1     Awaiting     10      -
```

### `KILL <pid>` — Force-kill a Process
Calls `processmanager.kill(pid)`.

### `TERMINATE <pid>` — Graceful Shutdown
Calls `processmanager.terminate(pid)`.

## Re-entrancy & Shared State

Preemptive scheduling means a process can be interrupted **at any point** — including mid-`kalloc`, mid-DList-mutation, etc. Since all processes share the kernel address space, we need guards.

### Strategy: CLI/STI Critical Sections
```pascal
procedure enter_critical;  begin CLI; end;
procedure leave_critical;  begin STI; end;
```

These are placed around:
- `kalloc()` / `kfree()` — heap metadata must not be corrupted
- DList mutations (`DL_Add`, `DL_Delete`) on shared lists
- Any global variable write that another process or a timer hook might read

Timer hooks already run with interrupts disabled (TMR_0_ISR calls `CLI` first), so they are inherently safe.

**Cost:** ~2 instructions per critical section. At 1024 Hz interrupt rate, the window where we might preempt mid-critical-section is tiny. The guards just prevent the rare unlucky case.

### What Does NOT Need Guards
- Per-process `StdOut`/`StdErr` writes — only the owning process writes, terminal reads asynchronously (read-only is safe)
- Process-local data (`ctx^.Local`) — owned by one process
- `TProcessContext` fields modified only by the scheduler (which runs with interrupts disabled in the ISR)

## Memory Management Strategy
- `TProcessContext` allocated via `kalloc(SizeOf(TProcessContext))`, freed on reap.
- Per-process stack: `kalloc(PROCESS_STACK_SIZE)`, freed on reap. Stack grows downward from `StackBase + PROCESS_STACK_SIZE`.
- Per-process `StdIn`/`StdOut`/`StdErr` allocated via `stdio.createOutBuf()`, freed by the caller (vterminal or parent process).
- Resource bindings stored in a `PDList` per-process, each entry `kalloc`'d, freed on unbind.
- Process table is a single `PDList` storing `uint32` pointers to contexts.
- `Local` data is owned by the process — must be `kfree`'d before the entry point returns (or in a cleanup wrapper).

## Implementation Phases

### Phase 1: Core Infrastructure — Types & Process Manager
- [x] Create `src/include/proctypes.pas` with all type definitions (`TProcessState`, `TProcessSysMsg`, `TProcessEntryPoint`, `TProcessContext`, `TResourceBinding`, etc.)
- [x] Create `src/processmanager.pas` with: process table (DList), `create`, `findByID`, `findByName`, `sendMessage`, `terminate`, `kill`, `proc_yield`, `proc_await`, `proc_suspend`, `proc_exit`, `reap`
- [x] `PS` terminal command
- [x] `KILL` / `TERMINATE` commands
- [x] Register in `kernel.pas` init sequence (after stdio, before progmanager)
- [x] Compilation verification (no context switching yet — processes created but not run)

### Phase 2: Context Switcher & Preemption
- [x] Implement `contextswitcher.pas` with the assembly ISR stub
- [x] Capture idle ESP from `kernel.yield()` before entering the HLT loop
- [x] Replace ISR_32's IDT entry with the custom context switch stub
- [x] Implement `scheduler_pick_next` (round-robin with priority quantum)
- [x] Implement `process_trampoline` (entry/exit wrapper)
- [x] Fake interrupt frame construction in `processmanager.create`
- [x] PUSHF/CLI...POPF guards on `kalloc`/`kfree` in `lmemorymanager.pas`
- [x] Create two trivial test processes (print "Hello from program 1/2" once per second)
- [x] Boot-test: verify timer hooks (graphics, USB, BIOS tick) still fire
- [x] Boot-test: verify test processes run, interleave correctly, ~1 msg/sec each

### Phase 3: VTerminal Multi-Instance + Legacy Command Integration
- [x] `runCommand` wrapper for existing `TCommandMethod` commands (as `legacy_entry` process) — already implemented in `processmanager.pas`
- [x] Define `PVTermState`/`TVTermState` record containing all current vterminal globals
- [x] Refactor `launch` to `kalloc` a new `TVTermState` per invocation
- [x] Pass `state` as `user_data` to all LVGL event callbacks (`content_click_cb`, `content_key_cb`, `content_defocus_cb`)
- [x] Refactor all internal procedures (`appendText`, `refreshDisplay`, `showPrompt`, `processCommand`) to take `state : PVTermState` parameter
- [x] Refactor `onClose` to kill foreground process (if any) and `kfree(state)`
- [x] Modify `processCommand` to call `processmanager.runCommand` instead of calling `cmd^.method` directly
- [x] Implement `drainOutput(state)` — incremental stdout/stderr rendering via LVGL timer callback per-instance
- [x] Per-instance `ForegroundPID` tracking: block Enter while process is running, restore prompt on finish
- [x] Build + boot-test: zero panics, clean boot, test processes still interleaving at ~1 msg/sec
- [x] CTRL+C terminal interrupt — `LV_KEY_CTRLC` via keyboard hook, `killForeground` in vterminal
- [x] Per-terminal CWD and dir stack — CD/LS/PUSHD/POPD as vterminal builtins
- [ ] Verify all existing commands still work identically (MEMINFO, CPU, ARP, LS, etc.) — requires manual UI testing

### Phase 4: Resource Binding & Cleanup
- [x] `bindResource` / `unbindResource` / `unbindAllResources` — implemented in processmanager.pas (Phase 1)
- [x] `unbindResourceNoCleanup` — removes binding without invoking cleanup callback (prevents re-entrancy)
- [x] Re-entrancy safety — `unbindAllResources` detaches resource list before iterating
- [x] `OwnerPID` field on `TTCPSocket` — tracks owning process
- [x] `socket_cleanup` wrapper in tcp.pas — calls `abort_connection` to RST and destroy
- [x] TCP `connect` / `listen` auto-bind socket to `CurrentProcess`
- [x] TCP `DestroySocket` auto-unbinds from owning process (no cleanup, prevents infinite recursion)
- [x] Build + boot-test: clean boot, no crashes
- [ ] Integrate with VFS (file handles auto-bound) — N/A, VFS file operations are stubs
- [ ] Verify cleanup on kill (RST sockets, close files) — requires manual network testing

### Phase 5: Process-Aware Async Commands & Command Consolidation
- [x] Refactor PING to be a proper looping process — `src/prog/ping.pas`, heap-allocated state, 5s timeout
- [x] `proc_sleep_ms` universal sleep in processmanager.pas
- [x] Parent-child process relationship — `reapFinished` sends `smChildExited` to parent before reaping
- [x] Centralize all scattered `registerCommand` calls into `progmanager.pas` — 14 commands moved from 9 units (kernel, cpu, drivermanagement, processmanager, arp, ipv4, tcp, storagemanagement, usbcore)
- [x] Export command procedures in host unit interfaces — procedures remain with their data but registration is centralized
- [x] Add `&` background suffix support in vterminal — `TBackgroundJob` record, `bg_jobs` PDList per terminal
- [x] `JOBS` command — lists background jobs with status
- [x] `FG` command — brings first background job to foreground
- [ ] Refactor dhclient to be a background process (can already be launched with `&` suffix)

**Kept as-is (not moved):**
- E1000/MAC commands — conditionally registered in `load()` callback (hardware-dependent)
- TRACER command — circular dependency prevents export (stdio↔tracer)
- stdio builtins (VERSION, CLEAR, HELP, ECHO, TIME, REBOOT) — intrinsic shell commands

### Phase 6: WASM Integration (future)
- [ ] `PWASMContext` as `Local` data
- [ ] EntryPoint loads WASM module, enters execution loop
- [ ] Loop calls `wasm.vm.execute(N_INSTRUCTIONS)` per iteration, checks `PendingMsg`
- [ ] `smTerminate` breaks the loop → returns → psFinished
- [ ] Terminal command: `WASM <file.wasm>` → creates WASM process

## Files Modified/Created
| File | Changes |
|---|---|
| `src/include/proctypes.pas` | **New** — all process type definitions |
| `src/processmanager.pas` | **New** — core process management unit, scheduler, reaper, resource binding, `proc_sleep_ms` |
| `src/contextswitcher.pas` | **Rewritten** — custom ISR_32 assembly stub, idle ESP capture, trampoline |
| `src/kernel.pas` | Add `processmanager.init`, `contextswitcher.init`; modify `yield()` to capture idle ESP |
| `src/lmemorymanager.pas` | Add CLI/STI guards around `kalloc`/`kfree` |
| `src/prog/vterminal.pas` | **Major refactor** — multi-instance, CTRL+C (`killForeground`), per-terminal CWD/dir stack, FS builtins (CD/LS/PUSHD/POPD) |
| `src/prog/ping.pas` | **New** — standalone ICMP ping process with heap-allocated state, 5s timeout, concurrency-safe |
| `src/prog/testcmd.pas` | **New** — TEST command (5 lines with 1s delays via `proc_sleep_ms`) |
| `src/driver/video/lvgl.pas` | `LV_KEY_CTRLC` constant + Ctrl+C interception in keyboard hook |
| `src/driver/storage/vfs.pas` | Per-terminal VFS helpers (`makeAbsolutePathFrom`, `changeDirectoryFrom`, `GetDirectoryListingFrom`); removed FS command registrations |
| `src/driver/net/include/nettypes.pas` | `OwnerPID` field on `TTCPSocket` (Phase 4) |
| `src/driver/net/l4/tcp.pas` | Auto-bind sockets to calling process; `socket_cleanup` + `DestroySocket` unbind (Phase 4) |
| `src/driver/net/l4/icmp.pas` | `UserData` parameter on ICMP callbacks for ping concurrency |
| `src/progmanager.pas` | Central command registration + register testcmd, ping, and 14 commands from provider units |
| `src/stdio.pas` | Minor: expose halt state for legacy wrapper (Phase 3) |
| `src/isr/isrmanager.pas` | Minor: allow ISR_32 IDT gate to be overridden (Phase 2) |
| `src/vmemorymanager.pas` | Bugfix: `vtop` mask `$FFFFFF` → `$3FFFFF` (22-bit offset for 4MB pages) |

## Risk Considerations
| Risk | Mitigation |
|---|---|
| Triple-fault on bad ESP swap | Extensive serial logging in context switch; test with single trivial process first |
| Re-entrancy in `kalloc`/`kfree` | CLI/STI guards around all allocator calls |
| Timer hooks disrupted | Hooks dispatched **before** context switch — identical to today; test first |
| Process crash = kernel crash | Ring-0 limitation — processes share address space. Future: per-process fault handler |
| DList mutation during ISR reap | Reaping runs in ISR with interrupts disabled — no concurrent mutation possible |
| Memory leaks on process death | `unbindAllResources` + `kfree(stack)` + `kfree(ctx)` in reap |
| Legacy command compatibility | Legacy wrapper is a real process — runs the exact same code on its own stack |
| FPC runtime hidden globals | Avoid `Str()`, dynamic strings etc. in process code; use `bufWrite*` helpers |
| Stack overflow (8 KB limit) | Sufficient for typical commands; future: guard page at stack base (unmapped page → #PF → kill process) |
| WASM VM infinite loop | Preemption handles this naturally — VM process is preempted like any other |
| VTerminal multi-instance memory | Each instance is ~10 KB (4 KB scrollback + 1 KB input + 5 KB history). 10 terminals = ~100 KB — acceptable |
| LVGL user_data lifetime | State pointer must outlive the LVGL objects — guaranteed by `kfree` only in `onClose` after widget destruction |

