# xHCI Implementation Plan

> Living document — tracks design decisions, architecture, progress, and open questions for the xHCI (USB 3.0) host controller driver.

---

## 0. Progress Tracker

| Stage | Status | Notes |
|-------|--------|-------|
| Stage 1: Constants & Types | **Done** | Register offsets, TRB types, packed records |
| Stage 2: MMIO & Allocation Helpers | **Done** | 32/64-bit MMIO, ring/context allocation |
| Stage 3: Ring Management | **Done** | Enqueue/dequeue, cycle bit, command ring |
| Stage 4: Init/Reset/Start/Stop | **Done** | BIOS handoff, DCBAA, scratchpad, event ring |
| Stage 5: Port Status & Reset | **Done** | PORTSC, Enable Slot, Address Device |
| Stage 6: Submit & Poll | **Done** | TRB submission, event ring processing |
| Stage 7: Load + UnitTests | **Done** | PCI scan, HC registration, unit tests |
| Stage 8: kernel.pas Integration | **Done** | uses clause, UnitTest call, build+test |

**Estimated total:** ~1800-2000 lines (EHCI was 1717 lines; xHCI is more complex but has less legacy baggage)

---

## 1. Architecture Overview

xHCI (eXtensible Host Controller Interface) is fundamentally different from UHCI/OHCI/EHCI.
Instead of frame lists, QHs, and TDs, xHCI uses a **ring-based** command/transfer/event model.

### Key Differences from EHCI
| Concept | EHCI | xHCI |
|---|---|---|
| I/O model | MMIO (BAR0 32-bit) | MMIO (BAR0, 64-bit capable) |
| PCI prog_if | `$20` | `$30` |
| Transfer descriptors | QH + qTD chains | TRB (Transfer Request Block) rings |
| Scheduling | Frame list + async list | Command Ring + per-EP Transfer Rings |
| Completions | Poll qTD ACTIVE bits | Event Ring with dequeue pointer |
| Device management | Software SET_ADDRESS | Controller manages slots (Enable Slot, Address Device commands) |
| Speed support | High-speed only (companions for LS/FS) | All speeds (LS/FS/HS/SS) natively |
| Notifications | Interrupts + polling | Doorbell Registers |

### Register Layout (MMIO)
```
BAR0 + 0x00      Capability Registers (read-only)
  CAPLENGTH (8-bit)   → offset to Operational regs
  HCIVERSION (16-bit) → spec version
  HCSPARAMS1 (32-bit) → MaxSlots, MaxIntrs, MaxPorts
  HCSPARAMS2 (32-bit) → scratchpad info
  HCSPARAMS3 (32-bit) → latency
  HCCPARAMS1 (32-bit) → addressing capability, XECP pointer
  DBOFF (32-bit)       → Doorbell Array offset from BAR0
  RTSOFF (32-bit)      → Runtime Register Space offset from BAR0

BAR0 + CAPLENGTH  Operational Registers
  USBCMD    ($00) → Run/Stop, HCRST, etc.
  USBSTS    ($04) → HCHalted, HSE, EINT, PCD
  DNCTRL    ($14) → Device Notification Control
  CRCR      ($18) → Command Ring Control (64-bit)
  DCBAAP    ($30) → Device Context Base Address Array Pointer (64-bit)
  CONFIG    ($38) → Max Device Slots Enabled

  PORTSC[n] ($400 + 16*n) → Port Status & Control

BAR0 + RTSOFF     Runtime Registers
  Interrupter[n]:
    IMAN   ($20 + 32*n + $00) → Interrupt Management
    IMOD   ($20 + 32*n + $04) → Interrupt Moderation
    ERSTSZ ($20 + 32*n + $08) → Event Ring Segment Table Size
    ERSTBA ($20 + 32*n + $10) → Event Ring Segment Table Base Address (64-bit)
    ERDP   ($20 + 32*n + $18) → Event Ring Dequeue Pointer (64-bit)

BAR0 + DBOFF      Doorbell Registers
  DB[0]     → Host Controller (Command Ring)
  DB[n]     → Device Slot n (Transfer Ring for target endpoint)
```

### Data Structures (Hardware)

**TRB (Transfer Request Block)** — 16 bytes, 16-byte aligned
```
Offset  Size  Field
$00     8     Parameter (address or immediate data)
$04     4     Status (transfer length, completion code, etc.)
$08     4     Control (TRB Type, Cycle bit, flags)
```

**Device Context** — 32 or 64 bytes per slot/endpoint context entry
- Slot Context: route string, speed, hub info, etc.
- Endpoint Context[0..30]: EP type, max packet, TR dequeue pointer, etc.

**Input Context** — Same layout, used to program device/endpoint changes

**DCBAA** — Device Context Base Address Array: array of 64-bit pointers, one per slot + slot 0 (scratchpad)

**Event Ring Segment Table Entry** — 16 bytes
```
Offset  Size  Field
$00     8     Ring Segment Base Address
$08     4     Ring Segment Size (number of TRBs)
$0C     4     Reserved
```

### Ring Model
- **Command Ring**: Kernel enqueues command TRBs, rings doorbell 0. Controller processes and posts Command Completion Event on Event Ring.
- **Transfer Ring**: Per-endpoint. Kernel enqueues transfer TRBs, rings the device's doorbell. Controller processes and posts Transfer Event on Event Ring.
- **Event Ring**: Controller writes completion TRBs. Software reads and advances dequeue pointer.
- **Cycle Bit**: Producer toggles cycle bit at wrap; consumer checks it to detect new entries without needing a separate write pointer.

### Integration with usbcore Abstraction

The existing `TUSBHCDriver` function pointers map to xHCI as follows:

| Callback | xHCI Implementation |
|---|---|
| `fnReset` | Halt + HCRST, wait, allocate DCBAA/rings/scratchpad |
| `fnStart` | Set MaxSlots, DCBAAP, CRCR, Interrupter 0, set RS=1 |
| `fnStop` | Clear RS, wait for HCHalted |
| `fnPortStatus` | Read PORTSC[port], return bit 0 = CCS |
| `fnPortReset` | Set PORTSC.PR, wait for PRC, Enable Slot + Address Device |
| `fnSubmit` | Build TRBs on transfer ring, ring doorbell |
| `fnPoll` | Read Event Ring, process completions, advance ERDP |

### SET_ADDRESS Interception (Critical)

xHCI manages USB addresses internally via the **Address Device** command (issued during `fnPortReset`). The usbcore `enumerate_device` flow calls `usb_set_address()` which submits a SET_ADDRESS control transfer. Our `fnSubmit` **must intercept** `SET_ADDRESS` requests:

1. Detect: `transfer^.PipeType = ptControl` AND `transfer^.Setup.bRequest = USB_REQ_SET_ADDRESS`
2. Action: Set `transfer^.Status := tsSuccess`, return `true` — do NOT send to hardware
3. Reason: xHCI already assigned the address during Enable Slot / Address Device in `fnPortReset`

The usbcore then sets `dev^.Address := addr` and increments `hc^.NextAddress`. For xHCI, the actual USB address is managed by the controller (stored in the Device Context), and the address used by software is the **Slot ID** (1-based). We set `dev^.Address` to the slot ID during `fnPortReset` so subsequent transfers target the correct slot.

**Approach:** In `xhci_port_reset`, after Address Device succeeds, store the slot ID in a slot→port mapping table in `TXHCI_PrivData`, and set the device's address in the HC's `NextAddress`. When usbcore calls `usb_set_address(dev, addr)`, our submit intercepts it and returns success. The device's `Address` field effectively becomes the slot ID.

### Slot ↔ Port Mapping

xHCI uses slot IDs (1–MaxSlots) to identify devices. We need a mapping:

```
TXHCI_PrivData:
    SlotPort   : array[1..256] of uint8   { slot → root port number }
    SlotSpeed  : array[1..256] of uint8   { slot → USB_SPEED_* }
    SlotRing   : array[1..256] of Pointer { slot → EP0 Transfer Ring }
    SlotCtx    : array[1..256] of Pointer { slot → Output Device Context }
```

These arrays are dynamically allocated (MaxSlots * element_size) to avoid kernel bloat. MaxSlots is capped at 256 (xHCI spec max) but typically 32–64 in practice.

---

## 2. Implementation Stages

### Stage 1: Constants & Types (~200 lines)
- All register offsets (capability, operational, runtime, doorbell)
- Bit definitions for USBCMD, USBSTS, PORTSC, HCSPARAMS1/2/3, HCCPARAMS1
- PORTSC speed bits (Port Speed field bits 13:10)
- TRB type codes: Normal ($01), Setup Stage ($02), Data Stage ($03), Status Stage ($04), Link ($06), Enable Slot ($09), Disable Slot ($0A), Address Device ($0B), Configure Endpoint ($0C), Evaluate Context ($0D), Reset Endpoint ($0E), No Op Command ($17), Transfer Event ($20), Command Completion Event ($21), Port Status Change Event ($22)
- TRB flag bits: Cycle ($01), ENT ($02), ISP ($04), NS ($08), CH ($10), IOC ($20), IDT ($40)
- TRB completion codes: Success ($01), Data Buffer Error ($02), Babble ($03), USB Transaction Error ($04), TRB Error ($05), Stall ($06), Short Packet ($0D), etc.
- Packed records:
  - `TXHCI_TRB` — 16 bytes (Param: uint32[2], Status: uint32, Control: uint32)
  - `TXHCI_SlotCtx` — 32 bytes (route, speed, hub info, port, max exit latency, etc.)
  - `TXHCI_EPCtx` — 32 bytes (EP type, max packet, interval, TR dequeue ptr, avg TRB len, etc.)
  - `TXHCI_InputCtrlCtx` — 32 bytes (Drop/Add context flags)
  - `TXHCI_ERSTE` — 16 bytes (Ring Segment Base Address, Ring Segment Size, Reserved)
- Private data record: `TXHCI_PrivData` (see below)
- Ring descriptor: `TXHCI_Ring` (Base pointer, Size, Enqueue index, Cycle bit)

### Stage 2: MMIO & Allocation Helpers (~100 lines)
- `xhci_readl(base, reg)` / `xhci_writel(base, reg, val)` — 32-bit MMIO (same pattern as EHCI)
- `xhci_readq(base, reg)` / `xhci_writeq(base, reg, val)` — 64-bit MMIO (two 32-bit reads/writes, low then high, for i386)
- `xhci_alloc_ring(size)` — allocate a TRB ring (page-aligned, zeroed), place Link TRB at last entry pointing back to start
- `xhci_free_ring(ring)` — free ring via `kfree_aligned`
- `xhci_alloc_ctx(ctxSize)` — allocate device/input context (64-byte aligned, zeroed)
- `xhci_free_ctx(ctx)` — free context via `kfree_aligned`
- `xhci_context_size(hcc)` — returns 32 or 64 based on HCCPARAMS1.AC64 bit

### Stage 3: Ring Management (~150 lines)
- `xhci_ring_enqueue(ring, trb)` — copy TRB to ring at enqueue index, set cycle bit, advance enqueue. If next slot is Link TRB, toggle cycle and wrap to index 0.
- `xhci_ring_doorbell(priv, slotID, target)` — write to doorbell register: `DB[slotID] = target`
- `xhci_event_pending(priv)` — check if Event Ring has a pending event (cycle bit matches software CCS)
- `xhci_event_dequeue(priv, trb)` — read next event TRB into `trb`, advance dequeue, handle segment wrap
- `xhci_event_advance_erdp(priv)` — write current dequeue pointer to ERDP register
- `xhci_send_command(priv, trb)` — enqueue command TRB, ring doorbell 0
- `xhci_wait_command(priv, completionTrb, timeout)` — spin-poll Event Ring for Command Completion Event, return completion code
- `xhci_make_trb(param0, param1, status, control)` — helper to build a TRB from components

### Stage 4: Init/Reset/Start/Stop (~250 lines)
- `xhci_bios_handoff(priv, pciDev)` — Walk XECP chain (HCCPARAMS1 bits 31:16) to find USBLEGSUP capability (ID=1). Set OS Owned Semaphore (bit 24), wait for BIOS Owned (bit 16) to clear. Same pattern as EHCI but via XECP pointer, not EECP.
- `xhci_reset(hc)`:
  1. Clear USBCMD.RS, wait for USBSTS.HCH=1
  2. Set USBCMD.HCRST, wait for self-clear AND USBSTS.CNR=0 (Controller Not Ready)
  3. Allocate DCBAA: `(MaxSlots + 1) * 8` bytes, 64-byte aligned
  4. Allocate Command Ring: 256 TRBs (4KB page), Link TRB at entry 255
  5. Allocate Event Ring: 256 TRBs (4KB page)
  6. Allocate Event Ring Segment Table: 1 entry (16 bytes), 64-byte aligned
  7. Allocate scratchpad buffers if HCSPARAMS2 indicates any needed
  8. Allocate slot arrays (SlotPort, SlotSpeed, SlotRing, SlotCtx) sized to MaxSlots
- `xhci_start(hc)`:
  1. Write CONFIG register: MaxSlots Enabled = MaxSlots
  2. Write DCBAAP (64-bit) = physical address of DCBAA
  3. Write CRCR (64-bit) = physical address of Command Ring | initial cycle bit
  4. Program Interrupter 0: ERSTSZ=1, ERSTBA=physical ERST, ERDP=physical Event Ring base
  5. Set USBCMD.RS=1, USBCMD.INTE=1, USBCMD.HSEE=1
  6. Wait for USBSTS.HCH=0
- `xhci_stop(hc)`:
  1. Clear USBCMD.RS
  2. Wait for USBSTS.HCH=1
- `xhci_alloc_scratchpad(priv)`:
  1. Read Max Scratchpad Bufs from HCSPARAMS2 (bits 25:21 high, bits 4:0 from HCSPARAMS2 high word)
  2. If > 0: allocate scratchpad buffer array (N * 8 bytes, 64-byte aligned), allocate N pages, fill array with physical addresses, store array pointer at DCBAA[0]

### Stage 5: Port Status & Reset (~200 lines)
- `xhci_port_status(hc, port)`:
  - Read PORTSC[port] at OpBase + $400 + (port * $10)
  - Return raw PORTSC value (bit 0 = CCS for usbcore compatibility)
- `xhci_port_speed(portsc)`:
  - Extract Port Speed field (bits 13:10)
  - Map: 1=Full, 2=Low, 3=High, 4=Super → USB_SPEED_*
- `xhci_port_reset(hc, port)`:
  1. Read PORTSC, check CCS (Current Connect Status)
  2. Determine if USB2 or USB3 port (xHCI assigns port numbers: USB2 ports first, then USB3)
  3. For USB2: set PORTSC.PR (Port Reset, bit 4), wait for PRC (bit 21)
  4. For USB3: set PORTSC.WPR (Warm Port Reset, bit 31) if needed, wait for PRC
  5. Clear change bits (CSC, PRC, etc.) by writing 1s
  6. Read speed from PORTSC
  7. **Enable Slot:** Send Enable Slot command TRB, wait for completion → get Slot ID
  8. **Build Input Context:** Allocate Input Context, set Input Control Context (Add flags for Slot + EP0), fill Slot Context (speed, route, root hub port, context entries=1), fill EP0 Context (EP type=Control Bidirectional, MaxPacketSize based on speed, TR Dequeue Pointer = EP0 ring, CErr=3, avg TRB length=8)
  9. **Address Device:** Send Address Device command TRB (Input Context pointer, Slot ID), wait for completion
  10. Store slot→port mapping, store EP0 ring pointer, store output device context pointer (from DCBAA[SlotID])
  11. Set `hc^.NextAddress` to slot ID so usbcore assigns this as the device address
  12. Return true on success

### Stage 6: Submit & Poll (~250 lines)
- `xhci_find_slot(priv, devAddr)` — look up slot ID from device address (for xHCI, dev address IS the slot ID)
- `xhci_submit_control(hc, transfer)`:
  1. **Intercept SET_ADDRESS:** If `transfer^.Setup.bRequest = USB_REQ_SET_ADDRESS`, set `transfer^.Status := tsSuccess`, return true
  2. Find slot ID from `transfer^.Device^.Address`
  3. Get EP0 Transfer Ring for this slot
  4. Build **Setup Stage TRB**: IDT=1 (Immediate Data), TRT (Transfer Type) based on direction, 8 bytes of setup data in Parameter fields
  5. Build **Data Stage TRB(s)** if BufferLen > 0: physical buffer address, transfer length, direction bit, chain if multiple
  6. Build **Status Stage TRB**: direction opposite to data (or IN if no data), IOC=1
  7. Ring doorbell for slot (DB[SlotID], target = 1 for EP0)
  8. Store transfer reference for poll completion
- `xhci_submit_bulk_intr(hc, transfer)`:
  1. Find slot ID
  2. Determine EP ring from endpoint address → DCI (Device Context Index = epNum * 2 + direction)
  3. Build **Normal TRB(s)**: buffer physical address, transfer length, IOC on last TRB
  4. Ring doorbell (DB[SlotID], target = DCI)
- `xhci_submit(hc, transfer)` — dispatch: control → `xhci_submit_control`, bulk/interrupt → `xhci_submit_bulk_intr`
- `xhci_poll(hc)`:
  1. While event pending on Event Ring:
     a. Read event TRB
     b. Check TRB type:
        - **Transfer Event ($20):** Extract Slot ID, Endpoint ID, completion code, transfer length. Find matching pending transfer. Update `transfer^.Status` and `transfer^.ActualLen`. Free EP ring resources if needed.
        - **Command Completion Event ($21):** Handled by `xhci_wait_command` (set a flag/store result in priv data for the blocking waiter)
        - **Port Status Change Event ($22):** Log the event, could trigger hot-plug enumeration (future)
     c. Advance dequeue pointer
  2. Write ERDP to acknowledge processed events

### Stage 7: Load + UnitTests (~250 lines)
- `load`:
  1. `PCI.getDeviceInfo($0C, $03, $30, count)` — find xHCI controllers
  2. For each controller:
     a. Read BAR0 (handle 64-bit BAR: BAR0 low + BAR1 high, mask low 4 bits; for i386 we only use the low 32 bits)
     b. Map MMIO: `block := mmioBase SHR 22; force_alloc_block(block, 0); map_page(block, block)`
     c. Enable PCI bus mastering: `PCI.setBusMaster(bus, slot, func, true)`
     d. Read capability registers: CAPLENGTH, HCIVERSION, HCSPARAMS1/2/3, HCCPARAMS1, DBOFF, RTSOFF
     e. Compute OpBase = mmioBase + CAPLENGTH, RTBase = mmioBase + RTSOFF, DBBase = mmioBase + DBOFF
     f. Allocate `TXHCI_PrivData`, populate fields
     g. BIOS handoff
     h. Build `TUSBHCDriver` record (same pattern as EHCI.load)
     i. Reset → Start → `usbcore.register_hc` → `usbcore.scan_ports`
- `UnitTest`:
  - Structure size checks: `TXHCI_TRB=16`, `TXHCI_SlotCtx=32`, `TXHCI_EPCtx=32`, `TXHCI_InputCtrlCtx=32`, `TXHCI_ERSTE=16`
  - TRB construction helpers: verify type encoding, cycle bit, parameter placement
  - Ring allocation: verify page alignment, Link TRB at end
  - Ring enqueue/dequeue: verify cycle bit toggling on wrap
  - Context size helper: AC64=0 → 32, AC64=1 → 64
  - Port speed mapping: PORTSC speed field → USB_SPEED_*
  - Constant sanity checks (register offsets, TRB types, bit masks)
  - DCI calculation: epNum, direction → DCI
  - Estimated: ~80-100 assertions

### Stage 8: kernel.pas Integration + Build
- kernel.pas already has `XHCI` in the uses chain via `USB.pas` → `XHCI` (USB.pas imports XHCI)
- But kernel.pas does NOT currently import XHCI directly or call `XHCI.UnitTest`
- Changes needed:
  1. Add `XHCI` to kernel.pas uses clause (after EHCI)
  2. Add `XHCI.UnitTest;` call after `EHCI.UnitTest;`
  3. Build: `docker-compose run builder | Tee-Object -FilePath .\build.log`
  4. Check: `Select-String -Path .\build.log -Pattern "Error|Fatal|Success|No errors|Failed" -CaseSensitive`
  5. Test: Enable USB 3.0 (xHCI) controller in VirtualBox VM settings, boot, check serial log

---

## 3. Concrete Record Definitions

### TXHCI_TRB (16 bytes, 16-byte aligned)
```pascal
PXHCI_TRB = ^TXHCI_TRB;
TXHCI_TRB = packed record
    Param0  : uint32;  { Parameter low dword (address low or immediate data) }
    Param1  : uint32;  { Parameter high dword (address high or immediate data) }
    Status  : uint32;  { Status / Transfer Length / Completion Code }
    Control : uint32;  { Cycle bit, TRB Type (bits 15:10), flags }
end;
```

### TXHCI_Ring (software descriptor for a TRB ring)
```pascal
PXHCI_Ring = ^TXHCI_Ring;
TXHCI_Ring = record
    Base      : PXHCI_TRB;  { Virtual base address of ring buffer }
    Size      : uint32;      { Number of TRB entries (including Link TRB) }
    Enqueue   : uint32;      { Current enqueue index }
    Dequeue   : uint32;      { Current dequeue index (Event Ring only) }
    CycleBit  : uint8;       { Current producer cycle state (0 or 1) }
end;
```

### TXHCI_SlotCtx (32 bytes)
```pascal
PXHCI_SlotCtx = ^TXHCI_SlotCtx;
TXHCI_SlotCtx = packed record
    RouteAndSpeed : uint32;  { Route String (19:0), Speed (23:20), MTT (25), Hub (26), Context Entries (31:27) }
    LatencyAndPort : uint32; { Max Exit Latency (15:0), Root Hub Port Number (23:16), Num Ports (31:24) }
    ParentInfo    : uint32;  { Parent Hub Slot ID (7:0), Parent Port (15:8), TTT (17:16), Interrupter Target (31:22) }
    DevStateAddr  : uint32;  { Device Address (7:0), Slot State (31:27) }
    Reserved      : array[0..3] of uint32; { Pad to 32 bytes }
end;
```

### TXHCI_EPCtx (32 bytes)
```pascal
PXHCI_EPCtx = ^TXHCI_EPCtx;
TXHCI_EPCtx = packed record
    EPInfo1     : uint32;  { Interval (23:16), LSA (15), MaxPStreams (14:10), Mult (9:8), EP State (2:0) }
    EPInfo2     : uint32;  { Max Packet Size (31:16), Max Burst Size (15:8), HID (7), EP Type (5:3), CErr (2:1) }
    TRDeqLo     : uint32;  { TR Dequeue Pointer Low (physical) | DCS (bit 0) }
    TRDeqHi     : uint32;  { TR Dequeue Pointer High }
    EPInfo3     : uint32;  { Average TRB Length (15:0), Max ESIT Payload (31:16) }
    Reserved    : array[0..2] of uint32; { Pad to 32 bytes }
end;
```

### TXHCI_InputCtrlCtx (32 bytes)
```pascal
PXHCI_InputCtrlCtx = ^TXHCI_InputCtrlCtx;
TXHCI_InputCtrlCtx = packed record
    DropFlags  : uint32;  { Drop Context flags (bits 31:2, bit 1=slot context) }
    AddFlags   : uint32;  { Add Context flags (bit 0=slot, bit 1=EP0, etc.) }
    Reserved   : array[0..5] of uint32; { Pad to 32 bytes }
end;
```

### TXHCI_ERSTE (16 bytes, 64-byte aligned)
```pascal
PXHCI_ERSTE = ^TXHCI_ERSTE;
TXHCI_ERSTE = packed record
    BaseAddrLo : uint32;  { Ring Segment Base Address Low (physical) }
    BaseAddrHi : uint32;  { Ring Segment Base Address High }
    SegSize    : uint32;  { Ring Segment Size (number of TRBs) }
    Reserved   : uint32;
end;
```

### TXHCI_PrivData
```pascal
PXHCI_PrivData = ^TXHCI_PrivData;
TXHCI_PrivData = record
    MMIOBase    : uint32;      { BAR0 MMIO base (virtual = physical) }
    OpBase      : uint32;      { Operational registers = MMIOBase + CAPLENGTH }
    RTBase      : uint32;      { Runtime registers = MMIOBase + RTSOFF }
    DBBase      : uint32;      { Doorbell array = MMIOBase + DBOFF }

    MaxSlots    : uint8;       { From HCSPARAMS1 bits 7:0 }
    MaxIntrs    : uint16;      { From HCSPARAMS1 bits 18:8 }
    MaxPorts    : uint8;       { From HCSPARAMS1 bits 31:24 }
    CtxSize     : uint8;       { 32 or 64 bytes per context entry }

    HCSPARAMS1  : uint32;      { Cached }
    HCSPARAMS2  : uint32;      { Cached }
    HCCPARAMS1  : uint32;      { Cached }

    DCBAA       : Pointer;     { Device Context Base Address Array (physical-accessible) }

    CmdRing     : TXHCI_Ring;  { Command Ring descriptor }
    EvtRing     : TXHCI_Ring;  { Event Ring descriptor (Interrupter 0) }
    ERST        : PXHCI_ERSTE; { Event Ring Segment Table }

    ScratchBufs : Pointer;     { Scratchpad buffer array (or nil) }
    NumScratch  : uint16;      { Number of scratchpad buffers }

    { Per-slot data (dynamically allocated arrays, indexed 1..MaxSlots) }
    SlotPort    : Pointer;     { ^array of uint8: slot → root port }
    SlotSpeed   : Pointer;     { ^array of uint8: slot → USB_SPEED_* }
    SlotRings   : Pointer;     { ^array of PXHCI_Ring: slot → EP0 Transfer Ring }
    SlotOutCtx  : Pointer;     { ^array of Pointer: slot → Output Device Context }

    { Pending command completion (for blocking xhci_wait_command) }
    CmdComplete   : boolean;
    CmdResult     : uint32;    { Completion TRB for last command }
    CmdResultCode : uint8;     { Completion code }

    PCIBus      : uint8;
    PCISlot     : uint8;
    PCIFunc     : uint8;
end;
```

---

## 4. Size Constraints

All hardware structures must be packed records with exact sizes:
- TRB: 16 bytes, 16-byte aligned
- Slot/Endpoint Context: 32 bytes each (standard, 64 bytes if AC64=1 in HCCPARAMS1)
- Input Control Context: 32 bytes (or 64 if AC64=1)
- Device Context: Slot + 31 EP Contexts = 32 * 32 = 1024 bytes (or 2048 with 64-byte contexts)
- Input Context: Input Control + Slot + 31 EP = 33 * 32 = 1056 bytes (or 33 * 64 = 2112)
- DCBAA: (MaxSlots + 1) * 8 bytes, 64-byte aligned
- Event Ring Segment Table: 16 bytes per entry, 64-byte aligned
- TRB Ring: N * 16 bytes (+ Link TRB), page aligned preferred
- Scratchpad Buffer Array: MaxScratchpad * 8 bytes, 64-byte aligned

---

## 5. Known Constraints (Asuro-specific)

- `mod` operator is broken on bare-metal i386 (promotes to int64). Use branch arithmetic instead.
- PCI config access: `PCI.requestConfig(bus, slot, func, row)` + `inl($CFC)` for reads; `PCI.writeConfig(bus, slot, func, row, val)` for writes.
- DMA addresses: use `vtop()` from `vmemorymanager` to convert virtual→physical.
- MMIO mapping: `block := mmioBase SHR 22; force_alloc_block(block, 0); map_page(block, block)`. May need multiple blocks if registers span a 4MB boundary.
- No classes, no runtime library. Standard Pascal only.
- Use `kalloc()`/`kfree()` for dynamic allocation. `kalloc_aligned()` for aligned allocations.
- Large static arrays cause kernel bloat — prefer dynamic allocation.
- Ring 0 execution — an exception = system hang. Defensive programming required.
- 64-bit register access on i386: xHCI has many 64-bit registers (CRCR, DCBAAP, ERSTBA, ERDP). Must write as two 32-bit writes (low dword first, then high dword = 0 since we're 32-bit).

---

## 6. Lessons Learned from EHCI Implementation

These patterns from the EHCI driver (1717 lines) carry directly into xHCI:

1. **BIOS handoff** — essential for VirtualBox; without it, BIOS may still own the controller
2. **MMIO block mapping** — use `force_alloc_block` / `map_page` with `mmioBase SHR 22`
3. **PCI bus mastering** — must call `PCI.setBusMaster(bus, slot, func, true)` for DMA
4. **vtop() for all hardware-visible pointers** — every pointer written to HW registers or data structures must be physical
5. **HC driver record on stack, copied via register_hc** — `usbcore.register_hc` copies the record into the LL; the returned `hcEntry` pointer is what gets passed to `scan_ports`
6. **Forward declarations** for HC callbacks before implementation
7. **kalloc_aligned + memset(0)** for all hardware structures
8. **Unit test pattern** — local Assert/PrintSummary procedures, test helpers and constants without touching hardware
9. **Speed detection during port reset** — determine speed from port status register, needed for device context setup

---

## 7. VirtualBox Testing Notes

- Enable USB 3.0 (xHCI) controller in VM settings → Settings → USB → USB 3.0
- VirtualBox emulates Intel 7 Series/C210 Series xHCI (VID=8086, DID=1E31) or similar
- xHCI controller appears at PCI class $0C, subclass $03, prog_if $30
- VirtualBox does NOT automatically attach USB devices — must add USB filters or manually attach
- VBox emulated USB tablet (default pointing device) goes through OHCI/EHCI, not xHCI
- For testing: attach a USB device via VBox USB filter, or use the built-in emulated devices
- Serial log: `Get-Content "C:\Temp\asuro.log"` — filter for `XHCI` tag
