# Lessons Learnt

## 1. File Pickers Must Be Proper Reusable OS Components
Inline pickers hacked into app code are broken and not reusable. Build file pickers as a standalone unit (`filepicker.pas`) that any program can call via a callback.

## 2. All Errors Need Visible In-App Feedback
Never use `syslog.logln` as the only error output. Always show the user a dialog, msgbox, or status bar message. Syslog is supplemental only.

## 4. Shell Command Output Goes to stdout_buf, Not syslog
Use `stdio.bufWriteStr(stdout_buf, ...)` for all shell command output. `syslog` is for kernel diagnostics only.

## 5. Unit Test Convention
New subsystem units get a `procedure UnitTest` (called at boot from kernel.pas) and a `procedure init` that registers a CLI command so tests can be re-run at runtime. Tests use a nested `Assert(condition, name)` that increments `passed`/`failed` and logs failures via `syslog.logln`. At-boot tests must not do disk I/O — only test in-memory/virtual structures.

## 6. ISR-Visible Spin-Wait Flags Must Use Pointer Dereferencing
FPC has no `volatile` keyword. Any `while flag = 0 do asm hlt end` loop where `flag` is set by an ISR will hang forever because FPC hoists the load into a register before the loop and never re-reads memory. Always access the flag through a pointer: `while puint32(@flag)^ = 0 do proc_yield()`. This applies everywhere in the kernel that spins waiting for ISR-written state (e.g. `submit_io_wait`, `proc_await`-style loops, DMA done flags).

## 7. Never Spawn a Process Per I/O Operation
Spawning a new kernel process for each FAT32 read/write/dir operation is pure overhead: process creation (kalloc 8 KB stack, fake IRET frame, DList insertion), an extra context switch, and a double-wait (VFS spins on the worker, worker spins on AHCI). Instead, submit the I/O directly and park the calling process via `psAwaiting` until the AHCI ISR fires the completion callback — zero extra processes, zero wasted scheduler ticks.

## 8. Use psAwaiting to Park a Process Pending Async I/O (not proc_yield spin)
The correct way to block a process on an async I/O result is: (1) set up a completion callback that sets `State := psReady` then `Done := 1`, (2) atomically check if the operation is already done (under CLI) and set `CurrentProcess^.State := psAwaiting` if not, (3) spin on `Done` via `puint32(@wait.Done)^` per Lesson #6 with `asm hlt end` inside the loop. The process is removed from the runnable set while hardware works. **Do NOT call `proc_await` from `submit_io_wait`** — `proc_await` spins on `CurrentProcess^.State = psAwaiting` without pointer indirection and FPC caches the value in a register, causing it to return immediately before the I/O completes. The calling code then reads garbage from the DMA buffer, causing invalid pointer dereferences and page faults.

## 9. VFS GetDirectoryListing Must Return a Snapshot, Not a Live Tree Reference
`GetDirectoryListing` for `otVDIRECTORY` nodes previously returned `PHashMap(Obj^.Reference)` — a direct pointer into the live VFS tree. When callers called `FreeDirectoryListing` on the returned map, it freed the live VFSObjects and their name strings, destroying the VFS tree. Any subsequent `GetObjectFromPath` call would then dereference the trashed memory and page fault. **Fix**: always return a heap-allocated snapshot copy of the directory (new `PHashMap`, new `PVFSObject` entries with `stringCopy`'d keys). `FreeDirectoryListing` can then safely own and free the snapshot without touching the live tree. The rule: any function that returns a `PHashMap` to a caller who will call `FreeDirectoryListing` must allocate a fresh map — never return a raw interior pointer to a live data structure.

