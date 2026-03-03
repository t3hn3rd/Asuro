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
    └── Phase 6 (FPC 3.2.2) — can run in parallel after Phase 0
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
