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

## 10. Never Call Synchronous Disk I/O From an LVGL Timer or Event Callback
LVGL timer callbacks (`lv_timer_create`) and event callbacks run synchronously inside the LVGL render loop. Calling any function that parks the current process waiting for disk I/O (e.g. `vfs.FileSize`, `vfs.OpenFile`, `vfs.ReadFile`) from inside a timer or event callback will hang the entire UI — the process blocks mid-callback and the LVGL loop never resumes. All disk I/O that must occur in a UI context must either: (a) use the async VFS API (`OpenFileAsync`, `WriteFileAsync`) with a completion callback that triggers a deferred LVGL update, or (b) be deferred to a dedicated worker process that signals back via a flag the UI can poll. `GetDirectoryListingFrom` is the one bulk exception — it was already present in the original picker and works because it loads into a snapshot synchronously as a single operation; per-file calls like `FileSize` in a loop are the problem.

## 11. Never Allocate Large Arrays as Local Variables in Deep Kernel Call Chains
Local variables are stack-allocated in Pascal. Kernel processes have a fixed, limited stack (≈8 KB). In deep LVGL callback chains (kernel → LVGL render loop → timer callback → app code), there may only be a few KB of usable stack remaining by the time app code executes. Declaring local arrays larger than ~200–400 bytes (e.g. `array[0..255] of pchar` = 1024 bytes) inside any procedure that runs in this context will silently overflow the stack, corruptung adjacent memory and causing a page fault with a garbled call trace. **Rule**: any local variable array larger than ~128 bytes in a UI callback or procedure called from one must be moved to the heap with `kalloc`/`kfree`. The corruption pattern is a page fault with a call stack full of completely unrelated function names.

## 12. Pascal Silently Ignores Everything After `end.` — Dead Code Masquerades as Live Code
FPC compiles everything up to and including the first `end.` and silently discards the rest of the file. If a file is partially rewritten by prepending a new implementation but the old implementation is not deleted, the old code survives after `end.`. Forward declarations resolve to the **last** implementation before `end.` — so if the new code was added before the old `end.` but the old procedures were in the "dead" zone they have no effect. However the reverse is dangerous: if the old `end.` was replaced/removed and the new code placed before it, the old procedures in the dead zone still compile to nothing but pollute the source. **Rule**: after any large-scale replacement of a Pascal unit, explicitly check where `end.` falls with a text search and PowerShell-truncate the file at the first `end.`. Never assume a multi-step replacement tool correctly removed all old code — always verify with `Select-String -Pattern "^end\.$"`.

## 13. `for i := 0 to uint32_count - 1` Wraps to 4 Billion When Count is Zero
In Free Pascal, `uint32` arithmetic wraps: if `dir_count` is `uint32` and equals `0`, then `dir_count - 1 = 0xFFFFFFFF`. A `for i := 0 to dir_count - 1 do` loop with zero count does NOT skip — it runs 4 billion iterations, immediately accessing invalid memory and page faulting. FPC does not emit a warning for this. **Rule**: always guard `uint32`-bounded for loops: `if count > 0 then for i := 0 to count - 1 do`. Alternatively, use `sint32` for loop counters that might legitimately be zero.

## 14. FAT32 Deleted Entries ($E5) Must Be Filtered in getDirEntries
When a FAT32 directory entry is deleted, `fileName[0]` is overwritten with `$E5` but the rest of the entry (including the cluster pointer) remains intact on disk. `getDirEntries` must explicitly skip entries where `fileName[0] = char($E5)` — stopping only at `char(0)` (end-of-directory) is not enough. If `$E5` entries are returned to callers, they appear in directory listings with a garbage first character, and navigating into them follows a stale/freed cluster chain, which causes reads into arbitrary memory or FAT data, leading to a triple fault. Fix location: the `while i < maxEntries` loop in `fat32.getDirEntries`.
