# boot.mgr

Boot initialization manager providing self-registering, dependency-ordered unit initialization with barrier-based phasing and glob pattern matching.

## Overview

`boot.mgr` replaces the hardcoded initialization sequence in `kmain` with a dynamic, dependency-driven boot process. Units register themselves during their Pascal `initialization` sections by calling `registerBoot()` with a name, init procedure, splash text, and an optional dependency. When `boot.mgr.run()` is called from `kmain`, it performs a topological sort of registrations and executes them in dependency order, respecting barrier boundaries.

Because registration happens before `kmain` (via `FPC_INITIALIZEUNITS`), and therefore before the heap exists, all storage uses static allocation. This is one of the justified cases for static arrays in the kernel.

## Dependencies

`boot.mgr`'s interface has no `uses` clause — it relies only on built-in types from the `system` unit to avoid circular dependencies. The implementation section uses `io.syslog` and `boot.splash` for progress output, and includes all silo units that must be compiled into the kernel.

## Constants

### MAX_BOOT_ENTRIES

`128` — Maximum number of boot entries that can be registered. Sized as an upper bound for the total number of kernel units. If exceeded during registration, the system halts immediately (fatal misconfiguration).

### Barrier Constants

Named barrier phases that define the boot ordering. Each barrier is registered via `registerBarrier` in the `initialization` section of `boot.mgr` itself, chained so they execute in the order listed:

| Constant | Value | Purpose |
|----------|-------|---------|
| `BOOT_MGR_BARRIER_IMMEDIATE` | `'immediate'` | First phase — no dependency (`nil`). |
| `BOOT_MGR_BARRIER_EARLY` | `'early'` | Depends on `immediate`. |
| `BOOT_MGR_BARRIER_MID` | `'middle'` | Depends on `early`. |
| `BOOT_MGR_BARRIER_STORAGE` | `'storage'` | Depends on `middle`. Storage subsystem init. |
| `BOOT_MGR_BARRIER_BUS` | `'bus'` | Depends on `storage`. Bus drivers (PCI, USB core). |
| `BOOT_MGR_BARRIER_DEVICE` | `'device'` | Depends on `bus`. Class/device drivers (HID, mass storage). |
| `BOOT_MGR_BARRIER_BUS_LATE` | `'bus.late'` | Depends on `device`. PCI scan and HC loading. |
| `BOOT_MGR_BARRIER_LATE` | `'late'` | Depends on `bus.late`. Late init (VFS mount, tests). |
| `BOOT_MGR_BARRIER_FINAL` | `'final'` | Depends on `late`. Final phase (WASM, desktop). |

**Execution order:** `immediate → early → middle → storage → bus → device → bus.late → late → final`.

Between each barrier, all non-barrier entries depending on the previous barrier run first. The topological sort's two-pass algorithm ensures this interleaving.

## Types

### TBootProc / PBootProc

```pascal
TBootProc = procedure;
```

Parameterless procedure pointer for boot init callbacks. Units with parameterized `init()` procedures should create a local wrapper that captures the needed arguments.

### TBootEntry / PBootEntry

```pascal
TBootEntry = record
    Name      : PChar;
    InitProc  : TBootProc;
    Status    : PChar;
    DependsOn : PChar;
    Barrier   : Boolean;
end;
```

| Field | Description |
|-------|-------------|
| Name | Unique identifier for this entry (e.g. `'arch.x86.gdt'`). Used for dependency lookups. |
| InitProc | Parameterless procedure to call during boot. |
| Status | Text displayed on the splash screen while this entry runs. |
| DependsOn | Name of another entry that must run before this one, a glob pattern, or `nil` for entries with no dependency (roots). |
| Barrier | If `true`, this entry is deferred until all non-barrier entries at the same dependency level have been emitted. Set by `registerBarrier`. |

## Variables

### Entries

```pascal
var Entries : array[0..MAX_BOOT_ENTRIES - 1] of TBootEntry;
```

Static registration table populated during `initialization` sections. BSS-zeroed at startup.

### EntryCount

```pascal
var EntryCount : uint32;
```

Number of entries currently registered.

### SortedOrder

```pascal
var SortedOrder : TOrderArray;
```

Module-level scratch array holding the resolved execution order (indices into `Entries[]`). Kept at module scope rather than on the stack because 512 bytes on the 16 KB kernel stack would leave too little headroom for deeply-nested driver init chains and their ISRs.

## Procedures

### registerBoot

```pascal
procedure registerBoot(Name: PChar; InitProc: TBootProc; Status: PChar; DependsOn: PChar);
```

Register a boot entry. Intended to be called from unit `initialization` sections, which run before `kmain` via `FPC_INITIALIZEUNITS`. Appends the entry to the static `Entries` array with `Barrier := false`. Halts the system if `MAX_BOOT_ENTRIES` is exceeded.

**Parameters:**

- `Name` — Unique string identifier (must be a string literal or constant).
- `InitProc` — Parameterless procedure to call.
- `Status` — Splash screen text shown while this entry executes.
- `DependsOn` — Name of the entry this depends on, a glob pattern (see below), or `nil` for no dependency.

**Example:**

```pascal
uses boot.mgr;

procedure boot_init;
begin
    { ... actual init work ... }
end;

initialization
    registerBoot('driver.io.serial', @boot_init, 'Initializing serial ports...', nil);
```

**Example with barrier dependency:**

```pascal
initialization
    registerBoot('io.syslog', @boot_init, 'Initializing syslog...', BOOT_MGR_BARRIER_EARLY);
```

### registerBarrier

```pascal
procedure registerBarrier(Name: PChar; InitProc: TBootProc; Status: PChar; DependsOn: PChar);
```

Register a barrier entry. Identical to `registerBoot` except the entry's `Barrier` field is set to `true`, which causes the topological sort to defer it until all non-barrier entries at the same dependency level have been emitted.

Barriers define ordering phases — e.g. the `bus` barrier ensures all entries depending on `storage` have completed before any `bus`-dependent entries begin. The built-in barriers are registered by `boot.mgr` itself during its `initialization` section.

### run

```pascal
procedure run;
```

Execute all registered boot entries in dependency order. Called once from `kmain`.

1. **Topological sort** — `topoSort` resolves the dependency graph into a flat execution order using a two-pass algorithm (see below).
2. **Tree print** — Logs the resolved boot tree to syslog for diagnostics.
3. **Execute** — Walks the sorted order and calls each entry's `InitProc`, updating the splash screen.

If a dependency cycle or missing dependency is detected, the affected entries are skipped (they will not execute) and a warning is logged.

## Internal Functions

### pcharEqual

```pascal
function pcharEqual(a, b: PChar): Boolean;
```

Null-safe PChar equality comparison. Does not allocate memory. Used by the dependency resolver to match entry names.

### pcharLen

```pascal
function pcharLen(s: PChar): uint32;
```

Returns the length of a null-terminated PChar string.

### isGlob

```pascal
function isGlob(pattern: PChar): Boolean;
```

Returns `true` if the given pattern contains any `*` character.

### globMatches

```pascal
function globMatches(name, pattern: PChar): Boolean;
```

Matches a name against a glob pattern. `*` matches zero or more of any character and may appear multiple times (e.g. `'arch.*.memory.*'`). Uses a greedy two-cursor algorithm with backtracking. No heap allocation.

### allGlobEmitted

```pascal
function allGlobEmitted(pattern: PChar; var Emitted: array of Boolean): Boolean;
```

Returns `true` when every entry whose name matches the glob pattern has been emitted. Returns `true` vacuously if no entries match (nothing to wait for).

### isEligible

```pascal
function isEligible(i: uint32; var Emitted: array of Boolean): Boolean;
```

Checks whether entry `i` can be emitted: it must not already be emitted, and its dependency must be satisfied — either `nil` (no dependency), all glob matches emitted, or the exact named dependency emitted.

### findEntry

```pascal
function findEntry(Name: PChar): uint32;
```

Looks up a boot entry index by name. Returns the index, or `$FFFFFFFF` if not found.

### topoSort

```pascal
function topoSort(var Order: TOrderArray): uint32;
```

Performs topological sort of `Entries[]` into the output `Order[]` array. Uses a repeated-scan approach (O(n²), no heap required) with a **two-pass barrier algorithm**:

1. **Sub-pass 1 (non-barriers):** Repeatedly scans all entries and emits every eligible non-barrier entry until no more progress is made.
2. **Sub-pass 2 (one barrier):** Emits exactly one eligible barrier entry, then returns to sub-pass 1 so that non-barrier entries unlocked by this barrier run before the next barrier fires.

This interleaving prevents barriers from cascading (e.g. `immediate → early → middle → late` all in one shot) and ensures non-barrier entries are always scheduled between barrier phases.

Returns the number of entries placed into `Order[]`.

### entryDepth

```pascal
function entryDepth(idx: uint32): uint32;
```

Returns the dependency chain depth of an entry by following its `DependsOn` links iteratively. Glob dependencies count as depth 1. Capped at 16 to guard against cycles. Used by the tree printer for indentation.

### printBootEntriesTree

Logs the resolved boot order as an indented tree to syslog, showing the execution sequence and dependency structure.

## Dependency Model

The dependency model is a single-parent tree with optional glob matching:

- Each entry has at most one dependency (`DependsOn`).
- `DependsOn` can be an exact entry name, a glob pattern containing `*`, or `nil` (root).
- Transitive ordering is resolved naturally — if A depends on B, and B depends on C, then C runs first, then B, then A.
- **Glob dependencies** (e.g. `DependsOn = 'arch.*'`) wait for **all** matching entries to complete before becoming eligible. This is useful for barrier-like grouping.
- **Barrier entries** are deferred until all non-barrier entries at the same level have run. This creates clean phase boundaries.
- Entries with `DependsOn = nil` are roots and can execute in any order relative to each other.

**Barrier chain:**

```
nil ← immediate ← early ← middle ← storage ← bus ← device ← bus.late ← late ← final
```

**Example dependency tree:**

```
nil ← driver.io.serial ← io.syslog ← arch.x86.gdt ← arch.x86.idt
nil ← driver.video ← driver.video.lvgl ← boot.splash
immediate ←(barrier)← early ←(barrier)← middle ← [entries at MID phase]
```

## Usage Pattern

1. Each unit adds `uses boot.mgr` and an `initialization` section that calls `registerBoot()` with one of the `BOOT_MGR_BARRIER_*` constants as the dependency.
2. `kmain` calls `boot.mgr.run()` to execute all registered entries.
3. The barrier chain guarantees phase ordering: storage controllers init before bus drivers, bus drivers before device/class drivers, etc.

## Notes

- Registration order does not matter — the topological sort resolves execution order from dependency declarations.
- All string parameters (`Name`, `Status`, `DependsOn`) must point to string literals or constants, as no copying is performed. This is safe because Pascal string literals live in the `.rodata` section.
- The `MAX_BOOT_ENTRIES` limit of 128 is generous for the current kernel. If the kernel grows beyond this, the constant can be increased.
- The `SortedOrder` array is kept at module scope to avoid consuming kernel stack space during `run()`.
