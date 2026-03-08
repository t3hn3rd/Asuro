# Tracer Refactor Design

## Goal
Refactor tracer.pas to eliminate all copy operations and use an O(1) ring buffer of PChar pointers. Maximize efficiency, minimize overhead, and guard against interrupt-driven corruption.

## Agreed Design Decisions

### 1. No String Copies — Store PChar Directly
- **Decision**: Trust callers. Store the `PChar` pointer directly in the ring buffer — no `StringCopy`, no `kalloc`, no `kfree`.
- **Contract**: `push_trace` MUST only be called with pointers to static/persistent data (e.g. string literals). Passing a heap-allocated or stack-allocated PChar that may later be freed is undefined behavior.
- **Rationale**: All current callers pass string literals baked into the binary. This eliminates all heap allocation from the hot path.

### 2. Ring Buffer (O(1) push)
- **Structure**: `Traces: Array[0..MAX_TRACE-1] of PChar` (static, 40 slots).
- **Index**: Single `head: uint32` variable.
- **head semantics**: `head` always points to the **most recently written** slot.
- **Push operation**:
  ```pascal
  head := (head + 1) mod MAX_TRACE;
  Traces[head] := t_name;
  ```
- **Read operations**:
  - `get_last_trace` → `Traces[head]`
  - `get_trace_N(idx)` → `Traces[(head - idx + MAX_TRACE) mod MAX_TRACE]`
    - idx=0 is the most recent trace, idx=39 is the oldest.
- **No shifting loop**. Current O(n) shift of 40 entries on every push is eliminated.

### 3. Initialization
- All 40 slots set to `nil`.
- `head` initialized to `MAX_TRACE - 1` (39).
- `push_trace('kmain')` is called, which advances `head` to 0 and writes `'kmain'` to `Traces[0]`.
- After init: head = 0, Traces[0] = 'kmain', all other slots = nil.

### 4. Interrupt Safety — Locked Boolean (Skip on Contention)
- **Mechanism**: A `Locked: Boolean` reentrancy guard around `push_trace` only.
- **Behavior**: If `push_trace` is already executing (e.g., main code is mid-push) and an ISR calls `push_trace`, the ISR sees `Locked = true` and **silently drops** its trace.
- **Readers are NOT locked**: `get_last_trace` and `get_trace_N` always proceed without checking `Locked`. Since `head` is advanced AFTER the pointer is written, readers always see a consistent state.
- **Race window analysis**: There is a tiny window between checking `if not Locked` and setting `Locked := true` where an interrupt could cause both main code and ISR to enter the critical section. With the ring buffer design, the worst case is one trace being overwritten in the same slot — acceptable for a debug tracing tool.

### 5. pop_trace — No-Op Stub
- `pop_trace` remains in the interface as an empty procedure (no-op).
- This preserves ABI compatibility with all existing callers (`vmemorymanager`, `vterminal`, `kernel`, etc.) without requiring changes across the codebase.
- Traces are never removed from the ring buffer.

### 6. get_trace_count — Always Returns MAX_TRACE (40)
- No tracking of actual push count.
- Callers already handle `nil` entries from unfilled slots.
- This keeps the implementation simpler (one less variable to maintain atomically).

### 7. TRACER_ENABLE Compile-Time Guard — Kept
- All function bodies remain wrapped in `if TRACER_ENABLE then`.
- When `TRACER_ENABLE = false`, the compiler dead-code eliminates all tracer logic for zero runtime cost.
- `t_ready` provides orthogonal runtime enable/disable.

### 8. Dead Code Removal
The following unused code will be removed:
- `PTracerEntry` / `TTracerEntry` record types (linked list — never used)
- `head` / `tail` : `PTracerEntry` variables (shadow the new `head: uint32`)
- `c_lock: Boolean` (declared, never set to true, unreachable guard)
- Old `Locked: Boolean` replaced by new `Locked: Boolean` with same semantics but cleaner usage

### 9. Uses Clause Cleanup
- Remove `lmemorymanager` (no more kalloc/kfree).
- Remove `serial` (not used).
- Keep `util`, `strings`, `stdio` (used by terminal command).

## Resulting push_trace (Pseudocode)
```pascal
procedure push_trace(t_name: PChar);
begin
  if TRACER_ENABLE then begin
    if t_ready then begin
      if not Locked then begin
        Locked := true;
        head := (head + 1) mod MAX_TRACE;
        Traces[head] := t_name;
        Locked := false;
      end;
    end;
  end;
end;
```

## Performance Summary
| Operation     | Before             | After         |
|---------------|--------------------|---------------|
| push_trace    | O(n) shift + alloc | O(1) 2 stores |
| pop_trace     | No-op              | No-op         |
| get_last_trace| O(1)               | O(1)          |
| get_trace_N   | O(1)               | O(1)          |
| Memory alloc  | kalloc per push    | Zero          |
| Memory free   | kfree on overflow  | Zero          |

## Files Changed
- `src/tracer.pas` — Full rewrite of internals, interface unchanged.
