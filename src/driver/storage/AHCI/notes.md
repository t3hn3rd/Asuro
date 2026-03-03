# AHCI Driver Notes

## Pre-scheduling / Process Kill Hazards

### 1. Dangling DMA Buffer (critical)
When a process is killed, its `kalloc`'d buffers get freed. But the AHCI hardware
is still DMA'ing into that physical memory. The DMA write lands on whatever now
occupies that memory, silently corrupting the kernel heap or another process.

**Fix:** Before freeing a process's memory, either:
- Wait for all its pending AHCI slots to drain (`cmd_issue` bits clear), or
- Issue a port reset to abort in-flight commands, *then* free memory.

### 2. Dangling Completion Callback / Userdata Pointer (critical)
In `storage_read`/`storage_write`, the completion callback writes to `@done` —
a **stack-local variable**. If the scheduler preempts or kills the process while
it's in the `hlt` loop, that stack frame is gone. The ISR fires and writes to a
dangling stack address, corrupting whatever now uses that stack page.

**Fix:** The `done` flag and completion context must be heap-allocated (or in a
kernel-owned structure that outlives the process). A per-request struct like:
```pascal
type TPendingIO = record
    done     : uint32;
    ownerPID : uint32;  { skip delivery if process is dead }
end;
```

### 3. Command Slot Leak
If a process is killed with pending I/O, `pending[slot].inUse` stays `true`
forever. Eventually all 32 slots fill up and the device becomes unusable.

**Fix:** When killing a process, scan all AHCI devices for `pending[]` entries
belonging to that process, and either:
- Let the hardware finish but null out the completion callback (ISR just frees slot), or
- Abort the command (port reset) and clear the slot.

### 4. Interrupt-Disabled Preemption
The `asm sti` before the `hlt` loop is fine, but if the timer fires during setup
(between `readCallbackAsync(...)` and `asm sti`), the process could be switched
out with interrupts in an unexpected state. `hlt` is also not preemption-safe.

**Fix:** Move to a proper wait-queue/sleep mechanism instead of `hlt`.

## Recommended Path Forward
Implement a small **I/O request queue** owned by the kernel (not the process stack):
1. Allocate a request struct
2. Put it on a per-device queue
3. ISR completes it
4. Process kill walks the queue and cancels entries for that PID

## Other Bugs Fixed (2026-03-03)
- **vtop mask bug:** `$FFFFFF` (24-bit) → `$3FFFFF` (22-bit) for 4MB page offset
- **find_cmd_slot:** Now checks `pending[].inUse` in addition to `cmd_issue` bit
- **Missing lba5:** Both `send_read_dma_async` and `send_write_dma_async` now write all 48 LBA bits
- **IOAPIC routing:** PCI interrupts routed through IOAPIC so AHCI interrupts actually reach the CPU
- **LAPIC EOI:** `ISR_N` now sends LAPIC EOI for IOAPIC-delivered interrupts
- **PxIS pre-clear removed:** No longer blanket-clears port interrupt status before issuing commands (was eating other slots' completions)
