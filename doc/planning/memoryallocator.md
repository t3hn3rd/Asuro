# Memory Management Analysis

> Living document for the PMM / VMM / LMM refactor.
> Last updated: 2025-07-11 — All phases complete.

---

## Architecture Overview

Asuro's memory management is split into three cooperating units:

| Unit | File | Role |
|------|------|------|
| **PMM** | `src/pmemorymanager.pas` | Physical page allocator — bitmap tracks which 4 MB physical blocks are free/used |
| **VMM** | `src/vmemorymanager.pas` | Virtual memory mapper — manages x86 PSE 4 MB page directory entries |
| **LMM** | `src/lmemorymanager.pas` | Logical (heap) allocator — bitmap-based `kalloc`/`kfree` for kernel objects |

Call flow: `kalloc` → LMM bitmap scan → if no space, `new_heap_page` → VMM `new_page` → PMM `new_block`.

---

## 1  Physical Memory Manager (PMM)

### Current Design

- 1024-element static array (`Memory_Map: array[0..1023] of TMemoryBlock`), each entry covers a 4 MB block → **4 GB addressable**.
- `TMemoryBlock` stores `Address` (physical) and `Used` (boolean).
- `init()` walks the Multiboot memory map and marks blocks free/used.
- `alloc_block` / `free_block` linearly scan the array.

### Issues

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Important** | `alloc_block` scans linearly from index 0 every time — O(n) per allocation. Should maintain a hint/cursor or use a bitmap. |
| 2 | **Important** | `free_block` looks up by address using a linear scan — O(n). A direct index calculation (`addr SHR 22`) would be O(1). |
| 3 | **Important** | No OOM handling — `alloc_block` loops forever (`while true`) if all blocks are used. Should return a sentinel or nil. |
| 4 | Nice-to-have | Static array of 1024 × `TMemoryBlock` wastes space; a simple 1024-bit bitmap (128 bytes) would suffice. |
| 5 | Nice-to-have | The `Address` field stores `(i * $400000) SHL 10` during init — the extra `SHL 10` is suspicious and may cause mismatches with `free_block`'s comparison. Needs audit. |
| 6 | Nice-to-have | No support for >4 GB (PAE). Fine for now but worth noting. |

---

## 2  Virtual Memory Manager (VMM)

### Current Design

- x86 PSE (4 MB pages) — single-level page directory, no page tables.
- `alloc_page(vaddr)` asks PMM for a physical block, writes the PDE, and `invlpg`s.
- `free_page(vaddr)` clears the PDE and returns the physical block to PMM.
- `map_page(paddr, vaddr)` creates a fixed mapping without PMM involvement.
- Page directory is a 1024-entry array of `uint32` at a static address.

### Issues

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Critical** | `free_page` extracts the physical block number incorrectly. It reads `Address` from the PMM block (which was stored with `SHL 10` during PMM init), then applies `SHR 10` — this should be `SHR 22` to convert a physical address to a 4 MB block index. The current code frees the **wrong block**. |
| 2 | **Critical** | `invlpg` operand is wrong in `free_page` — it passes the page-directory *index* (`block`) instead of the virtual address. `invlpg` requires a virtual address. |
| 3 | **Critical** | Page directory may not be page-aligned. It's declared as a typed pointer (`PuInt32`) allocated via `alloc_page`, but PSE page directories **must** be 4 KB-aligned (they are, since `alloc_page` returns 4 MB-aligned blocks, but this is not enforced or documented). |
| 4 | **Important** | `alloc_page` does not check the PMM return value for failure — if PMM is exhausted (and we fix PMM to return a sentinel), VMM will write a garbage PDE. |
| 5 | **Important** | No TLB shootdown for multi-core. Single-core only for now, but worth noting. |
| 6 | **Important** | `map_page` doesn't check whether the PDE slot is already occupied — silently overwrites existing mappings. |
| 7 | Important | `alloc_page` sets PDE flags to `$83` (Present + R/W + PSE) for all pages. No distinction between kernel/user pages. |
| 8 | Nice-to-have | No guard pages, no unmapped gaps between allocations. |
| 9 | Nice-to-have | `free_page` doesn't zero the page contents before returning to PMM — potential info leak if pages are reused by different subsystems. |

---

## 3  Logical Memory Manager (LMM)

### Current Design

- Each "heap page" is a 4 MB region obtained from VMM (`klalloc`).
- Within each page, an `Entries` array (`MAX_ENTRIES = $60000` = 393,216 entries) tracks allocation status.
- Each entry corresponds to an 8-byte "allocation unit" (`ALLOC_SPACE = 8`).
- `kalloc(size)` scans entries for a contiguous run of `Free = true` entries, marks them `Used`, returns `base + index * 8 + DATA_OFFSET`.
- `kfree(ptr)` finds the matching range and marks entries free again.
- `DATA_OFFSET = $100000` — first 1 MB of each 4 MB page is reserved for the entry metadata.

### Issues

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Critical** | `klalloc` uses **decimal** `4000000` instead of **hex** `$400000` for the page size. `4000000` decimal = `$3D0900` ≈ 3.8 MB, which is **not** a 4 MB-aligned allocation and will cause the VMM mapping to be misaligned. Should be `$400000`. |
| 2 | **Critical** | `klfree` is unimplemented (body is empty) — any `klalloc`'d page is leaked forever. The heap can only grow, never shrink. |
| 3 | **Critical** | No allocation type tag — `kfree` cannot distinguish between small allocations (served by `kalloc` from the entry array) and large allocations (served by `klalloc` directly). Calling `kfree` on a `klalloc`'d pointer will corrupt the entry array. |
| 4 | **Important** | `kalloc` linear scan is O(n) over `MAX_ENTRIES` (393K entries) per allocation — extremely slow for a hot path. Should use a bitmap or free-list. |
| 5 | **Important** | `kalloc` zeroes returned memory with a byte-by-byte loop. Should use `FillDWord` / `rep stosd` for 4× throughput. |
| 6 | **Important** | No mutex/lock — concurrent `kalloc`/`kfree` from interrupts or (future) threads will corrupt the entry array. |
| 7 | **Important** | `MAX_ENTRIES × sizeof(THeapEntry)` metadata overhead: each `THeapEntry` is ~6 bytes × 393K = ~2.3 MB of the 4 MB page used for bookkeeping — only ~1.7 MB usable per page (43% efficiency). |
| 8 | **Important** | Magic number validation in `kfree` (`if Entries^[idx].Magic <> $600D` → "Bad KFree") halts the kernel via `psod`. No graceful recovery. |
| 9 | Important | Fragmentation: after many alloc/free cycles, the linear scan will skip over many small free gaps, causing both slowdown and wasted space. No compaction or coalescing strategy. |
| 10 | Nice-to-have | `DATA_OFFSET = $100000` (1 MB) is hardcoded but the actual metadata size depends on `MAX_ENTRIES × sizeof(THeapEntry)`. If the record size changes, the offset may overlap with data or waste space. |
| 11 | Nice-to-have | The linked list of heap pages (`THeapPage`) is traversed linearly to find which page owns a pointer during `kfree` — O(pages) per free. |
| 12 | Nice-to-have | `kalloc` always starts scanning from entry 0 — a roving pointer (next-fit) would reduce average scan time. |
| 13 | Nice-to-have | No statistics tracking (total allocated, peak usage, fragmentation metrics). |

---

## 4  Cross-Unit Issues

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Critical** | PMM `Address` field stores `(i * $400000) SHL 10` — this value does not match the raw physical address. VMM and LMM both assume they're getting a real physical address from PMM. If the stored value is actually `phys SHL 10`, every consumer is mapping the wrong physical memory. Needs immediate audit. |
| 2 | **Important** | No unified OOM path — PMM infinite-loops, VMM doesn't check, LMM doesn't check. A single allocation failure cascades into a hang. Should propagate `nil` up the chain. |
| 3 | **Important** | Memory is never returned to the system — `klfree` is a no-op, so VMM pages are never freed, so PMM blocks are never freed. The system can only allocate, never deallocate at the page level. |
| 4 | Nice-to-have | No memory map dump / debug command to inspect PMM/VMM/LMM state at runtime. |

---

## 5  Public Interface Contracts (preserved)

All callers outside the three memory units use these entry points. The refactor
preserved identical names & signatures so no consumer code needed to change.

### PMM — `pmemorymanager`
```pascal
procedure init;
function  alloc_block(block : uint16; caller : uint32) : boolean;
procedure force_alloc_block(block : uint16; caller : uint32);
function  new_block(caller : uint32) : uint16;        { returns 0 on OOM }
procedure free_block(block : uint16; caller : uint32);
function  pmm_free_blocks : uint32;                    { popcount of free bits }
function  pmm_total_blocks : uint32;                   { popcount of PhysPresent }
```

### VMM — `vmemorymanager`
```pascal
procedure init;
function  new_page(page_number : uint16) : boolean;
function  page_mappable(page_number : uint16) : boolean;
function  map_page(page_number : uint16; block : uint16) : boolean;
function  map_page_ex(page_number : uint16; block : uint16; PD : PPageDirectory) : boolean;
function  new_page_at_address(address : uint32) : boolean;
procedure free_page(page_number : uint16);
procedure free_page_at_address(address : uint32);
function  new_page_directory : uint32;
function  new_kernel_mapped_page_directory : uint32;
function  vtop(address : uint32) : uint32;
```

### LMM — `lmemorymanager`
```pascal
procedure init;
function  kalloc(size : uint32) : void;   { alias 'kernel_kalloc' }
function  klalloc(size : uint32) : void;
procedure klfree(address : uint32);
function  kpalloc(address : uint32) : void;
procedure kfree(area : void);             { alias 'kernel_kfree' }
function  lmm_total_free : uint32;        { sum of FreeUnits×8 across pages }
function  lmm_page_count : uint32;        { number of heap pages }
```

---

## 6  Refactor Completion Summary

### Phase 1 — PMM Rewrite ✅

Replaced ~8 KB record array with compact bitmaps (384 bytes total):

| Structure | Size | Purpose |
|-----------|------|---------|
| `PhysPresent[0..31]` | 128 B | Which blocks exist (from multiboot) |
| `PhysAlloc[0..31]` | 128 B | Which blocks are allocated |
| `PhysScanned[0..31]` | 128 B | Walk-once optimisation |
| `PhysOwner[0..1023]` | 4 KB | Per-block owner tracking |

- `new_block`: O(1) amortised via `NextFreeHint` + dword-level BSF scan. Returns 0 as OOM sentinel.
- `free_block`: O(1) direct bit clear with double-free detection.
- `alloc_block`: Validates `PhysPresent` and `PhysAlloc` bits before allocation.
- Stats: `pmm_free_blocks` (popcount), `pmm_total_blocks`.
- First 4 blocks (0–3, 16 MB) reserved for kernel/BIOS.

### Phase 2 — VMM Correctness Fixes ✅

Five bugs fixed:

1. **`free_page` block extraction** — Was using raw Address field; fixed to `Address SHR 10`.
2. **`invlpg` operand** — Was passing PDE index; fixed to `page_number SHL 22` (virtual address).
3. **PDE clear** — Now zeroes the PDE entry before returning block to PMM.
4. **`map_page` double-write** — Removed redundant direct PDE writes; delegates to `map_page_ex`.
5. **OOM propagation** — `new_page` returns false if PMM returns 0; missing `pop_trace` added.

Critical discovery: `free_page` was **always broken** before our fix — virtual pages could never
be freed, making `try_release_page` in the LMM a no-op.

### Phase 3 — LMM Rewrite ✅

Complete rewrite with bitmap allocator. Per-page layout:

```
[0x000000..0x000017]  THeapPageHeader   (24 bytes)
[0x000018..0x00FC17]  Bitmap            (64512 bytes = 516096 bits)
[0x00FC18..0x00FFFF]  Padding           (1000 bytes)
[0x010000..0x3FFFFF]  Data area         (4128768 bytes = 516096 × 8)
```

~93% page efficiency (up from ~43%).

Key constants:
- `ALLOC_UNIT = 8` — bytes per allocation unit
- `SIZE_PREFIX = 16` — 4B size + 12B padding for 16-byte alignment (SSE MOVAPS requirement)
- `DATA_OFFSET = $10000` — data area starts at 64 KB into each page
- `LARGE_ALLOC_MAGIC = $FFFFFFFE` — sentinel for klalloc'd multi-page allocations

Interrupt safety: `pushfd; cli; pop saved_flags` (stack-balanced) + `restore_if(saved_flags)`
inline procedure that only restores IF via `sti`, avoiding dangerous EFLAGS restoration
(IOPL, NT, VM, AC bits that caused Bad-TSS on IRET).

`try_release_page`: Returns completely-free heap pages to VMM/PMM (unlinks from doubly-linked
list, fixes Search_Page, calls `free_page_at_address`). Skips Root_Page.

### Phase 4 — Integration & Hardening ✅

#### 4a. OOM path — BSOD
- `kalloc` now calls `BSOD('OOM', ...)` instead of returning nil on OOM.
- 65 of 72 callers (90%) don't check nil — a nil return would cascade into
  undefined behaviour. Kernel panic is the correct response.
- Large allocation path (`klalloc` returns nil) also triggers BSOD from kalloc.

#### 4b. Double-free detection ✅
- `kfree` verifies bitmap bits are set before clearing (`bitmap_all_set`).
- If already clear → syslog error + GPF.

#### 4c. Guard bytes (`{$IFDEF DEBUG_LMM}`) ✅
- Compile with `-dDEBUG_LMM` to enable.
- `kalloc` allocates one extra ALLOC_UNIT and writes `$DEADBEEF` at the end.
- `kfree` verifies the guard sentinel; corrupted guard → syslog error + GPF.
- Detects buffer overrun corruption.

#### 4d. `kpalloc` validation ✅
- Bounds check: block index must be < 1024 (GPF otherwise).
- Logs identity-map operations via syslog for MMIO auditing.
- `alloc_block` in PMM already validates `PhysPresent` bit.

### Phase 5 — Observability ✅

#### 5a. PMM stats ✅
- `pmm_free_blocks`: popcount of free bits across `PhysPresent AND NOT PhysAlloc`.
- `pmm_total_blocks`: popcount of `PhysPresent`.

#### 5b. LMM stats ✅
- `lmm_total_free`: sum of `FreeUnits × ALLOC_UNIT` across all heap pages.
- `lmm_page_count`: count of heap pages in the linked list.

#### 5c. MEMINFO command ✅
- Moved from inline `kernel.pas` to `src/prog/meminfo.pas` (following prog pattern).
- Registered via `progmanager.pas` → `meminfo.init()`.
- Displays: Multiboot memory, PMM block stats, LMM heap stats (pages, size, free).

---

## 7  Bugs Fixed During Refactor

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| Bad TSS exception during network processing | `pushfd`/`popfd` across separate asm blocks: FPC doesn't track ESP changes in asm, causing EFLAGS corruption (NT=1, IOPL wrong) → Bad TSS on IRET | Stack-balanced `pushfd; cli; pop local_var` + `restore_if()` that only does `sti` if IF was set |
| GPF from SSE MOVAPS in doublebuffer flush | `SIZE_PREFIX=4`→8 gave 8-byte alignment; `MOVAPS` needs 16-byte. `klalloc` returned `page+8` (not 16-aligned) | `SIZE_PREFIX=16` (4B size + 12B pad), klalloc header expanded to 16 bytes |
| Pages never freed (historic) | `free_page` extracted wrong block index from PDE Address field | Fixed extraction to `Address SHR 10` — page freeing works for the first time |

---

## 8  Risk Assessment (Post-Refactor)

| Area | Status | Notes |
|------|--------|-------|
| PMM bitmap | ✅ Validated | Full boot, 664 unit tests pass |
| VMM page free | ✅ Validated | `try_release_page` exercises free path |
| LMM bitmap allocator | ✅ Validated | All kernel subsystems functional |
| Large allocations (klalloc) | ✅ Validated | E1000, USB, LVGL all use large allocs |
| Interrupt safety | ✅ Validated | Network IRQs during allocation work correctly |
| SSE alignment | ✅ Validated | Doublebuffer flush (MOVAPS) works |
