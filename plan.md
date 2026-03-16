# FAT32 Rewrite Plan

Implement this entire plan without stopping.

## Goal

Replace the current FAT32 runtime I/O architecture with a simpler, faster design where open-time metadata work builds a cached runtime view, and steady-state file reads and writes consume that cached view with direct storage I/O.

The rewrite should make the common path thin enough that contiguous, preopened reads are near raw block I/O performance, while preserving correctness for fragmented files, append/growth, and metadata updates.

## Immediate Direction

1. Rename the current FAT32 implementation file to `driver.storage.fs.fat32.old.pas`.
2. Create a new `driver.storage.fs.fat32.pas` as the public registration/entry unit.
3. Move the new implementation into a dedicated `fat32/` folder with multiple focused units instead of another monolithic source file.
4. Rebuild the internals from a simpler architecture instead of continuing to patch the old design.

The old file remains as a reference during migration and can be deleted after parity is reached.

## Core Problems To Fix

1. The current runtime path is overcomplicated.
2. Ordinary file I/O pays too much control-plane overhead.
3. Fragmented files are treated as a special slow path instead of a normal case.
4. The async API still hides synchronous behavior in some cases.
5. FAT and directory metadata work leaks into the steady-state transfer loop.
6. The current source layout is too large to maintain comfortably as one unit.

## Design Principles

1. Fragmentation is normal, not a special case.
2. File I/O should be run-map driven.
3. FAT is metadata, not the runtime transfer engine.
4. The common path must avoid `kalloc`/`kfree`.
5. Async APIs must actually be async.
6. The same architecture must handle 1 run or 100 runs.
7. Metadata work should be deferred or isolated from the hot path.
8. Ownership and lifetime rules must be explicit at the file, volume, and transfer levels.

## Architectural Layers

The new design should keep three layers separate so FAT policy does not leak back into the transfer engine.

### A. FAT Metadata Layer

Responsible for:

- boot record and FAT geometry interpretation
- FAT entry reads/writes
- FAT chain traversal
- directory entry lookup
- raw directory entry locator resolution
- directory entry update/commit
- cluster allocation/free
- run-map build/rebuild
- corruption detection and validation

### B. Open-File State Layer

Responsible for:

- pointer/reference to the mounted volume
- pointer/reference to shared immutable `TFATVolumeInfo`
- first cluster
- committed byte size
- allocated cluster count
- cached run map
- logical dirty state
- reusable scratch sector buffer
- sequential cursor hints
- cached raw directory entry location
- open-handle lifetime and teardown bookkeeping

### C. Transfer Layer

Responsible for:

- offset/length to run slicing
- direct storage I/O submission
- partial-sector read-modify-write handling
- async continuation/chaining
- completed-byte accounting
- EOF/capacity bounds enforcement

The transfer layer must not perform FAT scans, directory searches, or cluster allocation from IRQ/completion context.

## Runtime View: Runs, Not FAT Walks

Define the runtime view explicitly:

- run = contiguous range of file clusters on disk
- run map = ordered in-memory array of all file runs for one open handle

The run map is the authoritative transfer view for that handle. FAT is consulted only during open, growth, explicit rebuild/validation, or metadata commit.

Fragmentation only changes how many runs are walked. It must not select a different architecture.

## Volume Geometry And Shared State

Do not copy boot/FAT geometry into every file handle.

Use a shared per-volume immutable record such as `TFATVolumeInfo` containing:

- sector size
- sectors per cluster
- FAT start
- FAT size
- data start
- root cluster
- max cluster
- other immutable geometry/cache references needed for fast translation

Each open file should hold:

- `Volume`
- pointer/reference to `TFATVolumeInfo`

## Open File State

Each open file should own a compact cached state record such as `TFATOpenFile` containing:

- `Volume`
- `VolumeInfo`
- `FirstCluster`
- `ByteSize`
- `AllocClusters`
- run map
- sequential cursor hint
- reusable scratch sector buffer
- dirty allocation / dirty size / dirty dir-entry flags
- raw directory entry locator

This state replaces repeated rediscovery and repeated FAT walking during normal I/O.

### Raw Directory Entry Locator

Every open file must cache enough information to update the on-disk directory entry without rescanning the parent directory. The cached form should include either:

- parent directory first cluster plus raw entry location data

or a fully resolved raw location such as:

- raw directory entry cluster
- raw sector LBA
- entry index within sector

This is required to avoid regressions in first-cluster and size updates.

### File Size And Allocation State

The plan must keep these rules explicit:

- `ByteSize` = committed logical EOF
- `AllocClusters` = current allocated chain length
- allocated capacity = `AllocClusters * ClusterSize`
- writes may use existing allocated capacity without allocation growth
- `ByteSize` advances only from actual completed writes, never intended request length

This directly protects against partial-growth and short-write corruption.

### Empty File Creation Model

For a newly created empty file:

- `FirstCluster` may be `0`
- run map is initially empty
- `ByteSize = 0`
- `AllocClusters = 0`
- raw directory entry locator is known immediately
- first allocation happens only when a write requires storage

## Run-Map Lifetime Rules

This needs to be defined up front:

1. Each open file owns its own run map.
2. The run map is built once at open and then trusted for that handle unless the same handle grows or explicitly rebuilds it.
3. Writes through that handle update that handle's run map incrementally in memory.
4. Other open handles are not kept coherent in the first rewrite. Their run maps and sizes are treated as open-time snapshots until reopen.
5. Concurrent write opens for the same file should be disallowed for the first rewrite, or explicitly treated as unsupported/undefined. Prefer rejecting the second writable open.
6. Flush/close commits directory entry and FAT changes from the handle's current state; optional full rebuild-and-validate before commit is a later hardening step, not part of the hot path.

## Unified Transfer Engine

Implement one transfer engine for both reads and writes.

It should:

- accept open-file state, buffer, offset, length, mode, callback
- translate byte ranges into run slices
- issue direct storage I/O chunk by chunk
- handle completion by advancing precomputed transfer state
- use scratch-sector read-modify-write only for unaligned edges
- complete without separate aligned/fragmented architectures

The old special-case direct path should become the normal path.

## Async Execution Model

For the first rewrite, define one concrete model:

- open/build-run-map may remain synchronous
- read/write entrypoints submit async storage I/O and return immediately
- transfer progression uses a small pooled `TFATTransferCtx`
- IRQ/completion callbacks only advance precomputed transfer state and schedule the next I/O or final completion
- IRQ/completion callbacks must not call helpers that can perform blocking FAT or directory I/O
- close/flush may remain synchronous initially if that keeps the contract honest and simple

This keeps async behavior explicit and avoids hidden blocking inside async hooks.

## Rare Heavy Work Only

Only these operations should do heavier FAT or metadata work:

- opening a file
- building or rebuilding a run map
- allocating/extending clusters
- updating directory entries
- flushing FAT or metadata
- partial-sector read-modify-write preparation
- corruption validation/failure handling

These must not dominate steady-state transfer throughput.

## Corruption And Validation Rules

When FAT traversal or run-map build finds:

- out-of-range cluster
- cycle
- bad-cluster marker
- premature EOC relative to stored size

the first rewrite should fail the open or mark the file invalid for transfer. It should not attempt automatic repair.

All corruption-handling loops must be bounded by hard limits derived from FAT size / max cluster count.

## Required Runtime Invariants

Invariant 1

For any open file:

`sum(run.length_clusters) = AllocClusters`

Invariant 2

Committed logical size must satisfy:

`ByteSize <= AllocClusters * ClusterSize`

Invariant 3

On successful flush/close:

- directory entry first cluster matches open state
- directory entry size matches committed bytes
- FAT chain matches the run map if dirty allocation occurred

Invariant 4

No async transfer may outlive:

- file handle
- volume object
- transfer context backing storage

Invariant 5

The run map is the authoritative transfer view for the handle; FAT is not re-walked in the steady-state transfer path.

## What To Remove From The New Design

The new implementation should avoid carrying forward these ideas:

- worker-centric per-chunk file transfer orchestration
- separate fast path and general path for aligned vs fragmented I/O
- synchronous fallbacks hidden inside async hooks
- repeated FAT-chain walking during ordinary sequential transfer
- hot-path temporary allocations
- parent-directory rescans just to commit file size or first cluster

## Planned Source Layout

The rewrite should move FAT32 internals into a dedicated folder so the code remains readable and reviewable.

Planned shape:

- `src/driver/storage/fs/driver.storage.fs.fat32.pas` for public registration and top-level hook wiring
- `src/driver/storage/fs/driver.storage.fs.fat32.old.pas` for the temporary legacy reference
- `src/driver/storage/fs/fat32/` for focused internal units

Likely internal unit split:

- volume / geometry
- FAT metadata helpers
- directory lookup and raw entry location
- open-file state and handle lifetime
- run-map construction
- transfer engine
- allocation/growth
- flush/sync

Exact file names can be finalized during Phase 0, but the rewrite should not collapse back into one large source file.

## Migration Plan

### Phase 0: File Split And Scaffolding

1. Rename existing FAT32 unit source to `driver.storage.fs.fat32.old.pas`.
2. Create a new `driver.storage.fs.fat32.pas` that preserves the public filesystem registration contract.
3. Create the `src/driver/storage/fs/fat32/` folder and split new internals into focused units from the start.

### Phase 1A: Volume Geometry And FAT Primitives

Build and validate:

- `TFATVolumeInfo`
- shared geometry decode
- FAT entry read helper
- bounded FAT chain traversal helper
- run-map builder
- raw directory entry locator helper

At the end of this phase, the core metadata primitives are usable without the old runtime architecture.

### Phase 1B: Minimal Read-Only Mount/Open

Build the new unit with only:

- type definitions needed by the filesystem manager
- boot record and directory entry structures
- volume identify/detect hooks
- basic open/close hooks
- read-only run-map construction

At the end of this phase, the new unit should compile, mount a FAT32 volume, open files, and build read-only run maps.

### Phase 2: Read Path First

Implement a unified run-driven read engine:

- build run map at open
- read from runs directly
- support multi-run files without architectural fallback
- use a pooled transfer context
- use a reusable scratch sector buffer only for unaligned reads

Acceptance target:

- aligned sequential reads on contiguous preopened files should be near raw `STORBENCH` read speed
- fragmented reads should scale mainly with run count, not collapse architecturally

### Phase 3: Writes Within Existing Allocation

Implement overwrite and in-capacity write support on the same transfer model:

- direct writes over existing runs
- partial-sector handling through reusable scratch buffer
- metadata dirtied in memory, not rewritten every chunk
- logical EOF advanced only from actual completed bytes

Acceptance target:

- aligned writes over preallocated files use the same thin transfer engine as reads
- no per-chunk metadata rewrite

### Phase 4: Allocation And Growth

Implement append and extension logic:

- allocate clusters when writes exceed current capacity
- extend the open-file run map incrementally
- prefer contiguous growth when possible
- keep allocation outside the steady-state transfer loop
- handle first-cluster update for empty files

Acceptance target:

- append-heavy writes remain much closer to preallocated write performance than today
- fragmented growth still remains run-driven

### Phase 5: Metadata Commit Rules

Implement clean flush/close behavior:

- FAT dirty tracking
- directory entry update on close or explicit sync
- first-cluster update for newly created files
- byte-size commit from actual completed bytes only
- handle/volume teardown rules for in-flight transfers

Acceptance target:

- no regression in crash-safety compared with current design assumptions
- no hot-path metadata thrash

### Phase 6: Async Contract Cleanup

Make the async API honest and documented:

- async hooks always return immediately
- no synchronous disk I/O hidden inside async entrypoints
- callback context is consistent and documented
- FD lifetime and teardown rules are enforced
- close/unmount/process-exit races are explicitly handled

Acceptance target:

- `ReadFileAsync` and `WriteFileAsync` are genuinely async for all supported cases
- no blocking FAT work is re-entered from IRQ/completion context

## Required Supporting Structures

The new implementation should include:

- `TFATVolumeInfo` for shared immutable geometry
- `TFATOpenFile` with run map, logical state, raw directory entry locator, and reusable scratch buffer
- pooled `TFATTransferCtx`
- compact run representation
- read/write helpers that work from run maps, not repeated FAT scans
- explicit flush/sync helpers

It should not require a per-volume worker just to progress ordinary file transfers.

## Compatibility Requirements

The new implementation should preserve compatibility with:

- `driver.storage.fs.mgr`
- `driver.storage.vfs`
- current filesystem hook signatures in `driver.storage.types`
- current FAT32 on-disk format

The rewrite should change the internal architecture, not the external filesystem contract, unless a later cleanup intentionally revises that contract.

## Performance Targets

Track both open/close cost and steady-state transfer throughput.

Initial realistic targets:

- reads on contiguous preopened files should be near raw block I/O throughput
- writes on preallocated files should be much closer to raw than today
- append/growth will remain measurably slower due to FAT and directory updates
- the remaining gap to raw should be mostly metadata/allocation cost, not control-plane overhead

Longer-term target:

- once FAT32 overhead is reduced, remaining limits should mainly be in storage/AHCI

## Correctness Requirements

Must explicitly preserve:

- correct handling of fragmented files
- correct file size updates
- correct first-cluster updates
- correct directory entry location handling
- no shared DMA-buffer hazards
- no blocking FAT work from IRQ callbacks
- no use-after-free during close/unmount/process teardown
- bounded handling of bad or cyclic FAT chains
- correct behavior for empty files with `FirstCluster = 0`

## Validation Plan

1. Compile after each phase.
2. Smoke-test mount/open/read on a known FAT32 volume.
3. Measure open/close cost separately from transfer throughput.
4. Run `IOTEST` on a fresh 4 KB cluster FAT32 volume.
5. Run `STORBENCH` on the same disk and compare.
6. Test fragmented-file read/write behavior.
7. Test create, append, close, reopen, and verify.
8. Test writable-open rejection or unsupported-path behavior for concurrent writers.
9. Test close-during-async and volume invalidation edge cases.
10. Test corruption detection on invalid or cyclic cluster chains.

## Non-Goals For The First Rewrite

These are explicitly not required for the first clean rewrite:

- perfect crash-consistency semantics
- journaled metadata behavior
- aggressive readahead/writeback cache
- cross-handle cache coherency for concurrent file writers
- automatic FAT repair

Those can come after the architecture is clean.

## Definition Of Success

The rewrite is successful when:

1. FAT32 ordinary file I/O is run-driven by default.
2. The old direct path no longer exists as a separate idea because it became the main path.
3. Async hooks are genuinely async.
4. Hot-path allocator churn is removed.
5. Directory entry updates no longer require parent-directory rescans during ordinary file writes.
6. FAT32 throughput is no longer dominated by internal orchestration overhead.
