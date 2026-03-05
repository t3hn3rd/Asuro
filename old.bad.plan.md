# Asuro Development Plan

## Phase 0 — Cleanup
1. Strip all `[RFP]`, `[OF]`, `[RF]`, `[F32]` diagnostic prints from `vfs.pas` and `fat32.pas`
2. Investigate / fix the OS hang after idle time

---

## Phase 1 — IO Buffer Helpers
> Goal: prevent buffer overflows from ad-hoc allocations by providing correct-size helpers.

1. Create `iobuf` unit with:
   - `AllocSectorBuffer(vol) : puint32` — allocates one sector (vol^.sectorSize bytes), zeroed
   - `AllocClusterBuffer(vol) : puint32` — allocates one cluster (sectorSize × spc bytes), zeroed
   - `FreeSectorBuffer(buf)` / `FreeClusterBuffer(buf)`
2. Refactor `fat32.readFile` / `fat32.writeFile` to use these helpers instead of raw `kalloc`
3. Refactor `vfs.WriteFile` padding logic to use `AllocClusterBuffer`

---

## Phase 2 — File Handle Unit & Shared/Private Handle Model
> Goal: move file handle management out of VFS into its own unit with a proper sharing model.

### New unit: `filehandles`

#### Handle Types
| Mode | Behaviour |
|------|-----------|
| **Shared Read** | Multiple handles can coexist. Blocks private-read openers. |
| **Shared Write** | Multiple handles can coexist. Blocks private-write openers. |
| **Shared Read/Write** | Multiple handles can coexist. Blocks any private opener. |
| **Private Read** | Only one allowed. Closes all existing **shared read** handles on the same file. Blocks new shared-read and any private openers. |
| **Private Write** | Only one allowed. Closes all existing **shared write** handles on the same file. Blocks new shared-write and any private openers. |
| **Private Read/Write** | Only one allowed. Closes **all** existing shared handles on the same file. Blocks all new openers. |

#### Rules
- At most **one** private handle per file at any time.
- Opening a private handle forcibly closes conflicting shared handles.
- Shared handles do not block other shared handles (even different modes).
- Handle table stored in `filehandles` unit, not in VFS.

#### Interface sketch
```pascal
type
    THandleMode = (hmSharedRead, hmSharedWrite, hmSharedReadWrite,
                   hmPrivateRead, hmPrivateWrite, hmPrivateReadWrite);

function  AcquireHandle(filePath : pchar; mode : THandleMode) : TFileHandle;
function  ReleaseHandle(handle : TFileHandle) : boolean;
function  HandleRead(handle : TFileHandle; pos : uint32; buf : puint8; len : uint32) : uint32;
function  HandleWrite(handle : TFileHandle; pos : uint32; buf : puint8; len : uint32) : uint32;
function  HandleSeek(handle : TFileHandle; pos : uint32) : boolean;
function  HandleSize(handle : TFileHandle) : uint32;
```

#### Internal record
```pascal
TOpenHandle = record
    inUse      : boolean;
    filePath   : pchar;       { absolute path — used for conflict checking }
    mode       : THandleMode;
    volume     : PStorage_Volume;
    directory  : pchar;
    fileName   : pchar;
    extension  : pchar;
    dataBuffer : puint32;
    dataSize   : uint32;
    position   : uint32;      { current read/write cursor }
    loaded     : boolean;
end;
```

### Migration
- VFS `OpenFile` / `ReadFile` / `WriteFile` / `CloseFile` become thin wrappers around `filehandles`
- Old `TOpenMode` / `TWriteMode` map onto `THandleMode`
- Existing callers (inio, edit) updated to new API

---

## Phase 3 — Filesystem Manager Abstraction
> Goal: VFS should not know about FAT32-specific details (extension splitting, dir entry format).

### New `filesystemmanager` interface
```pascal
type
    TFSReadFile    = function(vol: PStorage_Volume; relPath: pchar; buf: PPuint32; size: puint32): uint32;
    TFSWriteFile   = function(vol: PStorage_Volume; relPath: pchar; data: puint32; size: uint32): uint32;
    TFSDeleteFile  = function(vol: PStorage_Volume; relPath: pchar): uint32;
    TFSMkDir       = function(vol: PStorage_Volume; relPath: pchar): uint32;
    TFSRmDir       = function(vol: PStorage_Volume; relPath: pchar): uint32;
    TFSRename      = function(vol: PStorage_Volume; oldPath: pchar; newPath: pchar): uint32;
    TFSListDir     = function(vol: PStorage_Volume; relPath: pchar): PLinkedListBase;

    TFilesystem = record
        sName         : pchar;
        readFile      : TFSReadFile;
        writeFile     : TFSWriteFile;
        deleteFile    : TFSDeleteFile;
        makeDir       : TFSMkDir;
        removeDir     : TFSRmDir;
        rename        : TFSRename;
        listDir       : TFSListDir;
        { ... existing fields like readCallback kept temporarily for compat }
    end;
```

### Changes
1. Move filename/extension splitting from VFS `ResolveFilePath` **into** FAT32 (FAT32 receives `hello.txt` as a single relative path, splits internally)
2. Move `TDirectory_Entry` construction into FAT32
3. VFS resolves volume + relative path, calls `filesystemmanager.readFile(vol, relPath, ...)` etc.
4. FAT32 registers full interface at init time

---

## Phase 4 — File & Directory Operations
> Goal: complete CRUD for files and directories.

### FAT32 implementations
1. `fat32.deleteFile(vol, relPath)` — find dir entry, zero it out, free FAT chain clusters
2. `fat32.createDirectory(vol, relPath)` — allocate cluster, write `.` and `..` entries, add to parent
3. `fat32.deleteDirectory(vol, relPath)` — check empty, remove entry, free cluster
4. `fat32.renameEntry(vol, oldPath, newPath)` — update dir entry filename/extension in place

### Shell commands
| Command | Usage | Description |
|---------|-------|-------------|
| `mkdir` | `mkdir <path>` | Create directory |
| `rmdir` | `rmdir <path>` | Remove empty directory |
| `rm`    | `rm <path>` | Delete file |
| `mv`    | `mv <old> <new>` | Rename file or directory |

### Wire-up
- Each shell command goes through VFS → filesystemmanager → fat32
- Add units: `mkdircmd.pas`, or integrate into existing `volcmd.pas` / new `fscmd.pas`

---

## Phase 5 — File Index / Position Tracking
> Goal: proper sequential I/O with automatic position advancement.

1. Each `TOpenHandle` tracks a `position : uint32` cursor
2. `HandleRead` / `HandleWrite` advance position by bytes transferred
3. `HandleSeek(handle, pos)` sets absolute position
4. Add `SeekFile` to VFS public interface (wraps `HandleSeek`)
5. Support append mode: on open with write, seek to end
6. Update `edit.pas` and `inio.pas` to use sequential reads (no explicit position)

---

## Phase 6 — FPC 3.2.2 Upgrade
1. Merge / pull the `fpc3.2.2` branch
2. Update `Dockerfile` to install FPC 3.2.2
3. Fix compilation errors (stricter type checks, deprecated syntax, new reserved words)
4. Full boot + IO regression test
5. Verify no regressions

---

## Dependency Graph
```
Phase 0 (cleanup)
    │
    ├── Phase 1 (iobuf)
    │       │
    │       └── Phase 3 (FS manager abstraction)
    │               │
    │               ├── Phase 4 (file/dir CRUD + shell commands)
    │               │
    │               └── Phase 2 (file handles unit)
    │                       │
    │                       └── Phase 5 (file indexing / position)
    │
    ├── Phase 6 (FPC 3.2.2) — can run in parallel after Phase 0
    │
    └── Phase 7 (async I/O) — can start immediately; independent of Phases 1–6
            ├── 7.1 storagetypes — new async types
            ├── 7.2 storagemanager — async block I/O functions  (depends on 7.1)
            ├── 7.3 fat32 — multi-stage async callbacks          (depends on 7.2)
            ├── 7.4 vfs — async VFS API                         (depends on 7.3)
            └── 7.5 E1000 — async TX path                       (independent of 7.1–7.4)
```

## Status
| Phase | Status |
|-------|--------|
| 0 — Cleanup | Not started |
| 1 — IO Buffer Helpers | Not started |
| 2 — File Handle Unit | Not started |
| 3 — FS Manager Abstraction | Not started |
| 4 — File & Directory Ops | Not started |
| 5 — File Index / Position | Not started |
| 6 — FPC 3.2.2 Upgrade | Not started |
| 7 — Async I/O | Not started |

---

## Phase 7 — Async I/O (VFS → Disk → Ethernet)

> Goal: make the **entire** I/O stack async-first. Every layer — VFS, filesystem driver,
> storage manager, E1000 TX — becomes natively asynchronous using completion callbacks.
> The old synchronous `OpenFile`/`ReadFile`/`WriteFile`, `storage_read`/`storage_write`,
> and `sendPacket` are rewritten as thin sync wrappers that spin-wait on the async path.
> No caller sees a new API unless it opts into async; but internally, every I/O operation
> flows through the async path.

### Background: current call graph

```
vfs.OpenFile                                          ← blocks caller
  └─ vol.filesystem.readCallback(vol, dir, fname)     ← FS driver, sync
       └─ storagemanager.storage_read(device, …)      ← sync bridge, spin-waits
            └─ device.readCallbackAsync(…)            ← AHCI DMA, non-blocking
                  ← bridge spins: while done=0 do pollCallback()
            ← AHCI ISR → pending[slot].completion → done:=1 → bridge exits
```

### Target call graph (async-first)

```
vfs.OpenFile                                          ← async internally
  └─ vol.filesystem.readCallback(vol, dir, fname, completion, userdata)
       └─ storagemanager.storage_read(device, …, completion, userdata)
            └─ device.readCallbackAsync(…)            ← AHCI DMA, non-blocking
            ← returns immediately
       ← returns immediately
  ← returns immediately
  …
  ← AHCI ISR fires → storagemanager completion → FS completion → VFS completion → caller notified
```

---

### 7.1 Types — `storagetypes.pas`

#### Replace sync FS callback types with async equivalents

The old sync types (`PPReadHook`, `PPWriteHook`, `PPReadOffsetHook`) are **removed**.
Every filesystem callback now carries a completion + userdata pair:

```pascal
{ Completion fired when a VFS-level I/O operation finishes }
TVFSCompletion = procedure(error      : TError;
                            buffer     : puint32;
                            byteCount  : uint32;
                            userdata   : puint32);

{ FS read callback — replaces PPReadHook }
PPReadHook = procedure(volume     : PStorage_Volume;
                        directory  : pchar;
                        fileName   : pchar;
                        buffer     : puint32;
                        bytecount  : puint32;
                        completion : TVFSCompletion;
                        userdata   : puint32);

{ FS write callback — replaces PPWriteHook }
PPWriteHook = procedure(volume     : PStorage_Volume;
                          directory  : pchar;
                          entry      : PDirectory_Entry;
                          byteCount  : uint32;
                          buffer     : puint32;
                          statusOut  : puint32;
                          completion : TVFSCompletion;
                          userdata   : puint32);

{ FS read-at-offset callback — replaces PPReadOffsetHook }
PPReadOffsetHook = procedure(volume     : PStorage_Volume;
                               directory  : pchar;
                               fileName   : pchar;
                               offset     : uint32;
                               buffer     : puint32;
                               byteCount  : uint32;
                               completion : TVFSCompletion;
                               userdata   : puint32);
```

`TFilesystem` stays structurally the same (same field names), but each callback now has the async signature:

```pascal
TFilesystem = record
    sName              : pchar;
    system_id          : uint8;
    writeCallback      : PPWriteHook;        { now async }
    readCallback       : PPReadHook;         { now async }
    createCallback     : PPCreateHook;       { unchanged — one-shot, sync is fine }
    detectCallback     : PPDetectHook;       { unchanged }
    createDirCallback  : PPCreateDirHook;    { unchanged }
    readDirCallback    : PPReadDirHook;      { unchanged }
    deleteFileCallback : PPDeleteFileHook;   { unchanged }
    deleteDirCallback  : PPDeleteDirHook;    { unchanged }
    identifyCallback   : PPIdentifyHook;     { unchanged }
    readOffsetCallback : PPReadOffsetHook;   { now async }
end;
```

#### Network send completion (for step 7.5)

Add to `nettypes.pas`:

```pascal
TNetSendCompletion = procedure(success : boolean; userdata : puint32);
```

---

### 7.2 Block I/O — `storagemanager.pas`

`storage_read` and `storage_write` become **async-native**. The old sync signatures become wrappers.

#### New primary functions (async)

```pascal
procedure storage_read(device     : PStorage_Device;
                        addr       : uint32;
                        sectors    : uint32;
                        buffer     : puint32;
                        completion : TStorageCompletion;
                        userdata   : puint32);
```

Logic:
- `device^.readCallbackAsync ≠ nil` → call it, pass `completion`/`userdata` through, **return immediately**.
- `device^.readCallback ≠ nil` → call old sync hook, then `completion(true, userdata)` inline.
- Otherwise → `completion(false, userdata)`.

```pascal
procedure storage_write(device     : PStorage_Device;
                          addr       : uint32;
                          sectors    : uint32;
                          buffer     : puint32;
                          completion : TStorageCompletion;
                          userdata   : puint32);
```

Same pattern with `writeCallbackAsync` / `writeCallback`.

#### Sync wrappers (for callers that still block)

```pascal
{ Spins until completion fires — same as old storage_read behaviour }
procedure storage_read_sync(device  : PStorage_Device;
                              addr    : uint32;
                              sectors : uint32;
                              buffer  : puint32);

procedure storage_write_sync(device  : PStorage_Device;
                               addr    : uint32;
                               sectors : uint32;
                               buffer  : puint32);
```

Implementation: allocate a local `done : uint32 := 0`, call `storage_read(…, @sync_done, @done)`, spin `while done = 0`. Identical to the current `storage_read` body — the spin just moves into the wrapper.

---

### 7.3 Filesystem drivers — `fat32.pas` / `flatfs.pas`

All three data-path callbacks (`readCallback`, `writeCallback`, `readOffsetCallback`) are rewritten to the async signature. They call `storage_read` / `storage_write` (which are now async) and chain continuations.

#### `TFat32AsyncCtx` — multi-stage continuation state

```pascal
MAX_FAT32_CLUSTERS = 4096;

TFat32AsyncCtx = record
    { caller inputs }
    volume       : PStorage_Volume;
    directory    : pchar;
    fileName     : pchar;
    destBuffer   : puint32;
    bytecountOut : puint32;
    completion   : TVFSCompletion;
    userdata     : puint32;
    { internal walk state }
    clusterList  : array[0..MAX_FAT32_CLUSTERS-1] of uint32;
    clusterCount : uint32;
    clusterIndex : uint32;   { cluster currently being read }
    sectorIndex  : uint32;   { sector within current cluster }
    byteOffset   : uint32;   { bytes written into destBuffer so far }
    totalBytes   : uint32;
    stageBuf     : puint32;  { one-sector DMA staging buffer }
end;
PFat32AsyncCtx = ^TFat32AsyncCtx;
```

Heap-allocated at entry, freed when the final `completion` fires.

#### Stage flow for `readFile` (now async)

| Stage | Triggered by | Action |
|-------|-------------|--------|
| 1 | VFS caller | `storage_read(…, @stage2_cb, ctx)` for BPB sector |
| 2 | BPB DMA done | Parse BPB; `storage_read(…, @stage3_cb, ctx)` for first FAT sector |
| 3 | FAT sector done | Walk FAT chain; append cluster to `clusterList`; loop Stage 3 until end-of-chain |
| 4 | Chain complete | Per cluster: `storage_read(…, @stage4_cb, ctx)`; copy into `destBuffer`; advance `byteOffset`; fire `completion` after last cluster; free ctx |

```pascal
{ Replaces old sync readFile — same field name in TFilesystem }
procedure readFile(volume     : PStorage_Volume;
                    directory  : pchar;
                    fileName   : pchar;
                    buffer     : puint32;
                    bytecount  : puint32;
                    completion : TVFSCompletion;
                    userdata   : puint32);

{ Replaces old sync writeFile }
procedure writeFile(volume     : PStorage_Volume;
                      directory  : pchar;
                      entry      : PDirectory_Entry;
                      byteCount  : uint32;
                      buffer     : puint32;
                      statusOut  : puint32;
                      completion : TVFSCompletion;
                      userdata   : puint32);

{ Replaces old sync readFileAtOffset }
procedure readFileAtOffset(volume     : PStorage_Volume;
                             directory  : pchar;
                             fileName   : pchar;
                             offset     : uint32;
                             buffer     : puint32;
                             byteCount  : uint32;
                             completion : TVFSCompletion;
                             userdata   : puint32);
```

Wired in `fat32.init` to the same `TFilesystem` field names as today (`readCallback`, `writeCallback`, `readOffsetCallback`).

**flatfs**: same async signature. If flatfs has no real async I/O need, its callbacks can call `storage_read` and the completion will fire inline (via the sync fallback in `storage_read`). No special handling required.

---

### 7.4 VFS — `vfs.pas`

The VFS layer becomes async-first. The public functions take completions.

#### Completion types

```pascal
TVFSOpenCompletion = procedure(handle   : TFileHandle;
                                 error    : TError;
                                 userdata : puint32);
```

#### `OpenFile` (async-native)

```pascal
procedure OpenFile(filename   : pchar;
                    mode       : TOpenMode;
                    writeMode  : TWriteMode;
                    lock       : boolean;
                    completion : TVFSOpenCompletion;
                    userdata   : puint32);
```

- Finds a free slot in the 16-entry `OpenFiles` table; marks it `inUse := true` immediately (reserves the slot).
- Calls `ResolveFilePath` → `vol`, `dir`, `fname`.
- Calls `vol^.filesystem^.readCallback(vol, dir, fname, buf, size, @open_done, ctx)`.
- `open_done` stores buffer/size into the `TOpenFileEntry`, sets `loaded := true`, fires `TVFSOpenCompletion(handle, eNone, userdata)`.

#### `ReadFile` (async-native)

```pascal
procedure ReadFile(handle     : TFileHandle;
                    position   : uint32;
                    buffer     : puint8;
                    length     : uint32;
                    completion : TVFSCompletion;
                    userdata   : puint32);
```

- `omStream` mode: calls `vol^.filesystem^.readOffsetCallback(…, completion, userdata)`.
- Pre-loaded modes (`omReadOnly`, `omReadWrite`): copies from `entry^.dataBuffer`, fires `completion(eNone, …)` immediately (no disk I/O).

#### `WriteFile` (async-native)

```pascal
procedure WriteFile(handle     : TFileHandle;
                      position   : uint32;
                      buffer     : puint8;
                      length     : uint32;
                      completion : TVFSCompletion;
                      userdata   : puint32);
```

- Calls `vol^.filesystem^.writeCallback(…, completion, userdata)`.

#### Sync wrappers (backward compat for existing callers)

```pascal
{ Blocking open — spins until async OpenFile completes }
function  OpenFileSync(filename : pchar; mode : TOpenMode;
                         writeMode : TWriteMode; lock : boolean;
                         error : PError) : TFileHandle;

{ Blocking read }
function  ReadFileSync(handle : TFileHandle; position : uint32;
                         buffer : puint8; length : uint32) : uint32;

{ Blocking write }
function  WriteFileSync(handle : TFileHandle; position : uint32;
                          buffer : puint8; length : uint32) : uint32;
```

Each wrapper: allocates a local `done : uint32 := 0`, calls the async function with a completion that sets `done := 1`, spins `while done = 0 do begin asm sti end; if pollCallback <> nil then pollCallback() end`. Identical to the current `storagemanager` sync bridge pattern.

#### Migration of existing callers

All current callers of `OpenFile` / `ReadFile` / `WriteFile` (`inio.pas`, `edit.pas`, `OOBE.pas`, `desktop.pas`, shell commands, etc.) are changed to call `OpenFileSync` / `ReadFileSync` / `WriteFileSync`. This is a **rename-only** change at each call site — no logic changes.

---

### 7.5 Async TX — `E1000.pas` / `net.pas` / `eth2.pas`

The network send path becomes async-first, same pattern as disk.

#### Per-slot pending table in `E1000.pas`

```pascal
TE1000TxPending = record
    inUse      : boolean;
    completion : TNetSendCompletion;
    userdata   : puint32;
end;

var txPending : array[0..E1000_NUM_TX_DESC-1] of TE1000TxPending;
```

#### `sendPacket` (async-native)

```pascal
function sendPacket(p_data     : void;
                      p_len      : uint16;
                      completion : TNetSendCompletion;
                      userdata   : puint32) : boolean;
```

1. Write descriptor + `REG_TXDESCTAIL` — **do not spin**.
2. Store `{completion, userdata}` in `txPending[old_cur]`.
3. Return `true` immediately.

#### TX-complete ISR (in `fire()`)

When `Status AND $04 > 0` (TX queue empty):
```pascal
for i := 0 to E1000_NUM_TX_DESC-1 do
    if txPending[i].inUse then
        if (tx_descs[i]^.status AND TSTA_DD) > 0 then begin
            txPending[i].inUse := false;
            txPending[i].completion(true, txPending[i].userdata);
        end;
```

#### Sync wrapper

```pascal
function sendPacketSync(p_data : void; p_len : uint16) : sint32;
```

Spin-waits on a local `done` flag, same pattern.

#### Plumbing through `net.pas` / `eth2.pas`

| Layer | Async (primary) | Sync wrapper |
|-------|-----------------|--------------|
| `net.pas` | `send(p_data, p_len, completion, userdata)` | `sendSync(p_data, p_len)` |
| `eth2.pas` | `send(p_data, p_len, eth_type, ctx, completion, userdata)` | `sendSync(p_data, p_len, eth_type, ctx)` |
| `E1000.pas` | `sendPacket(p_data, p_len, completion, userdata)` | `sendPacketSync(p_data, p_len)` |

All current callers (`arp.pas`, `ipv4.pas`, `udp.pas`, `icmp.pas`, `dhcp.pas`) are changed to call the sync wrappers initially, then migrated to async as needed.

---

### 7.6 Caller migration plan

Since the whole stack changes signatures, callers must be updated. The migration is mechanical:

| Caller | Current call | After Phase 7 |
|--------|-------------|----------------|
| `inio.pas` | `vfs.OpenFile(…)` | `vfs.OpenFileSync(…)` |
| `edit.pas` | `vfs.OpenFile(…)` / `ReadFile` / `WriteFile` | `OpenFileSync` / `ReadFileSync` / `WriteFileSync` |
| `OOBE.pas` | `vfs.OpenFile(…)` | `vfs.OpenFileSync(…)` |
| `desktop.pas` | `vfs.OpenFile(…)` | `vfs.OpenFileSync(…)` |
| `base64_prog.pas` | `vfs.OpenFile(…)` / `ReadFile` | `OpenFileSync` / `ReadFileSync` |
| `md5sum.pas` | `vfs.OpenFile(…)` / `ReadFile` | `OpenFileSync` / `ReadFileSync` |
| `volcmd.pas` / `partcmd.pas` | `storagemanager.storage_read/write` | `storage_read_sync` / `storage_write_sync` |
| `MBR.pas` | `storagemanager.storage_read/write` | `storage_read_sync` / `storage_write_sync` |
| `volumemanager.pas` | `storagemanager.storage_read/write` | `storage_read_sync` / `storage_write_sync` |
| `arp.pas` / `ipv4.pas` / `udp.pas` / `icmp.pas` / `dhcp.pas` | `net.send` / `eth2.send` | `net.sendSync` / `eth2.sendSync` |

This is a **rename-only** change at each call site. No logic changes. After this, callers can be incrementally migrated to pass their own completions for true end-to-end async.

---

### Constraints and notes

- Steps 7.1 → 7.2 → 7.3 → 7.4 must be implemented in order (each depends on the previous types/signatures).
- Step 7.5 (network TX) is independent of 7.1–7.4 and can proceed in parallel.
- Step 7.6 (caller migration) is done alongside each step — e.g. when 7.2 changes `storage_read`, all `storage_read` call sites move to `storage_read_sync` in the same commit.
- Once Phase 3 (FS Manager Abstraction) lands, the async `TFilesystem` callback signatures must be carried forward.
- The 16-slot `OpenFiles` table is not enlarged; a slot is reserved (`inUse := true`) immediately on `OpenFile` entry to prevent double-allocation during async operations.
- Interrupts must be enabled (`asm sti end`) before entering any sync-wrapper spin loop; `pollCallback` must be called inside the loop for devices that need inline polling.
