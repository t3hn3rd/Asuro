# USB Implementation Plan

> Living document — tracks design decisions, architecture, progress, and open questions for Asuro's USB subsystem.

## Table of Contents
- [1. Overview](#1-overview)
- [2. Design Decisions](#2-design-decisions)
- [3. Architecture](#3-architecture)
- [4. File Layout](#4-file-layout)
- [5. Shared Types (`usbtypes.pas`)](#5-shared-types-usbtypespas)
- [6. USB Core (`usbcore.pas`)](#6-usb-core-usbcorepas)
- [7. Host Controller Drivers](#7-host-controller-drivers)
- [8. Hub Driver (`usbhub.pas`)](#8-hub-driver-usbhubpas)
- [9. USB Class Drivers](#9-usb-class-drivers)
- [10. Integration with drivermanagement](#10-integration-with-drivermanagement)
- [11. Memory & DMA Strategy](#11-memory--dma-strategy)
- [12. Transfer Scheduling](#12-transfer-scheduling)
- [13. Implementation Phases](#13-implementation-phases)
- [14. Progress Tracker](#14-progress-tracker)

---

## 1. Overview

Implement a full USB subsystem for Asuro, supporting all four host controller types (UHCI → OHCI → EHCI → xHCI), all four transfer types (Control, Interrupt, Bulk, Isochronous), full hub support, and a class-driver model integrated with `drivermanagement`. Initial class drivers: USB Keyboard and USB Mouse.

**Target environment:** VirtualBox (PIIX3 = UHCI, ICH9 = OHCI + EHCI, optional xHCI), bare-metal i386, ring 0, Standard Pascal (FPC cross-compiler), no runtime library.

---

## 2. Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| HC implementation order | UHCI → OHCI → EHCI → xHCI | UHCI first (VirtualBox PIIX3 default), then OHCI, then EHCI for USB 2.0, xHCI last |
| Transfer types | All four (Control, Interrupt, Bulk, Isochronous) | Full spec compliance over time |
| Hub support | Full from the start | Needed for real hardware; root hub + external hubs |
| USB device ↔ class driver matching | `drivermanagement` with `biUSB` bus type | Reuse existing driver lifecycle, no parallel systems |
| Completion model | Interrupt-driven (ISR on PCI IRQ, PollBusy guard) | Inline polling fallback in usb_control_msg; ISR fires completion hooks for HID drivers |
| DMA memory | Existing `pmemorymanager` / `vmemorymanager` (`force_alloc_block` / `map_page`) | Already proven in OHCI stub; identity-mapped pages for DMA |
| File layout | `src/driver/bus/usb/` subdirectory | Keep HC logic together; class drivers in `src/driver/hid/` and `src/driver/storage/` |
| Data structures | `lists.pas` linked lists + manual `kalloc`/`kfree` records | Avoid static arrays, use existing infrastructure; class drivers (keyboard, mouse, storage) all use dynamic lists for unlimited device tracking |

---

## 3. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      drivermanagement                            │
│  register_driver(biUSB, class/sub/proto) ←→ register_device()   │
├──────────────────────────────────────────────────────────────────┤
│                        USB Class Drivers                         │
│   ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│   │ USB Keyboard  │  │  USB Mouse   │  │  USB Mass Storage  │   │
│   │ (src/hid/)    │  │ (src/hid/)   │  │  (src/storage/)    │   │
│   └──────┬───────┘  └──────┬───────┘  └────────┬───────────┘   │
│          │                  │                    │                │
├──────────┴──────────────────┴────────────────────┴───────────────┤
│                         usbcore.pas                              │
│   Device enumeration, configuration, pipe management,            │
│   control transfers, descriptor parsing, address assignment      │
├──────────────────────────────────────────────────────────────────┤
│                         usbhub.pas                               │
│   Hub driver, port status/change, reset sequencing,              │
│   topology tracking, split transaction TT info                   │
├──────────────────────────────────────────────────────────────────┤
│              Host Controller Interface (HCI) Abstraction         │
│                        usbtypes.pas                              │
│   TUSBHCDriver record with function pointers:                    │
│     init, reset, start, stop, submit_transfer, poll              │
├─────────┬──────────┬──────────┬──────────┬───────────────────────┤
│  UHCI   │   OHCI   │   EHCI   │   xHCI   │  Host Controller     │
│  .pas   │   .pas   │   .pas   │   .pas   │  Drivers             │
├─────────┴──────────┴──────────┴──────────┴───────────────────────┤
│                           PCI Bus                                │
│                         (PCI.pas)                                 │
└──────────────────────────────────────────────────────────────────┘

* = future, not in initial implementation
```

---

## 4. File Layout

```
src/driver/bus/usb/
├── usbtypes.pas       # Shared types, constants, HC abstraction record
├── usbcore.pas        # Enumeration, configuration, control transfers, pipe API
├── usbhub.pas         # Hub driver (root + external)
├── UHCI.pas           # UHCI host controller driver (moved from bus/)
├── OHCI.pas           # OHCI host controller driver (moved from bus/)
├── EHCI.pas           # EHCI host controller driver (moved from bus/)
├── XHCI.pas           # xHCI host controller driver (moved from bus/)
└── USB.pas            # Init entry point, PCI registration (moved from bus/)

src/driver/hid/
├── usb_keyboard.pas   # USB HID keyboard class driver
└── usb_mouse.pas      # USB HID mouse class driver

src/driver/storage/
└── usb_storage.pas    # USB Mass Storage class driver (BOT + SCSI)
```

> **Migration:** Existing `UHCI.pas`, `OHCI.pas`, `EHCI.pas`, `XHCI.pas`, `USB.pas` move from `src/driver/bus/` into `src/driver/bus/usb/`. Build scripts will need path updates.

---

## 5. Shared Types (`usbtypes.pas`)

### 5.1 USB Descriptor Types

```pascal
{ Standard descriptor type constants }
const
    USB_DESC_DEVICE        = $01;
    USB_DESC_CONFIGURATION = $02;
    USB_DESC_STRING        = $03;
    USB_DESC_INTERFACE     = $04;
    USB_DESC_ENDPOINT      = $05;
    USB_DESC_HUB           = $29;

{ USB Request Types }
    USB_REQ_GET_STATUS     = $00;
    USB_REQ_CLEAR_FEATURE  = $01;
    USB_REQ_SET_FEATURE    = $03;
    USB_REQ_SET_ADDRESS    = $05;
    USB_REQ_GET_DESCRIPTOR = $06;
    USB_REQ_SET_CONFIG     = $09;

{ Endpoint direction }
    USB_DIR_OUT = $00;
    USB_DIR_IN  = $80;

{ Transfer types }
    USB_TRANSFER_CONTROL     = 0;
    USB_TRANSFER_ISOCHRONOUS = 1;
    USB_TRANSFER_BULK        = 2;
    USB_TRANSFER_INTERRUPT   = 3;

{ USB speeds }
    USB_SPEED_LOW   = 0;  { 1.5 Mbps  }
    USB_SPEED_FULL  = 1;  { 12 Mbps   }
    USB_SPEED_HIGH  = 2;  { 480 Mbps  }
    USB_SPEED_SUPER = 3;  { 5 Gbps    }

{ Max devices per controller }
    USB_MAX_DEVICES = 127;
    USB_MAX_ENDPOINTS = 32;
```

### 5.2 Standard Descriptors (packed records)

```pascal
type
    PUSBDeviceDescriptor = ^TUSBDeviceDescriptor;
    TUSBDeviceDescriptor = packed record
        bLength            : uint8;
        bDescriptorType    : uint8;
        bcdUSB             : uint16;
        bDeviceClass       : uint8;
        bDeviceSubClass    : uint8;
        bDeviceProtocol    : uint8;
        bMaxPacketSize0    : uint8;
        idVendor           : uint16;
        idProduct          : uint16;
        bcdDevice          : uint16;
        iManufacturer      : uint8;
        iProduct           : uint8;
        iSerialNumber      : uint8;
        bNumConfigurations : uint8;
    end;

    PUSBConfigDescriptor = ^TUSBConfigDescriptor;
    TUSBConfigDescriptor = packed record
        bLength             : uint8;
        bDescriptorType     : uint8;
        wTotalLength        : uint16;
        bNumInterfaces      : uint8;
        bConfigurationValue : uint8;
        iConfiguration      : uint8;
        bmAttributes        : uint8;
        bMaxPower           : uint8;
    end;

    PUSBInterfaceDescriptor = ^TUSBInterfaceDescriptor;
    TUSBInterfaceDescriptor = packed record
        bLength            : uint8;
        bDescriptorType    : uint8;
        bInterfaceNumber   : uint8;
        bAlternateSetting  : uint8;
        bNumEndpoints      : uint8;
        bInterfaceClass    : uint8;
        bInterfaceSubClass : uint8;
        bInterfaceProtocol : uint8;
        iInterface         : uint8;
    end;

    PUSBEndpointDescriptor = ^TUSBEndpointDescriptor;
    TUSBEndpointDescriptor = packed record
        bLength          : uint8;
        bDescriptorType  : uint8;
        bEndpointAddress : uint8;
        bmAttributes     : uint8;
        wMaxPacketSize   : uint16;
        bInterval        : uint8;
    end;

    PUSBHubDescriptor = ^TUSBHubDescriptor;
    TUSBHubDescriptor = packed record
        bDescLength         : uint8;
        bDescriptorType     : uint8;
        bNbrPorts           : uint8;
        wHubCharacteristics : uint16;
        bPwrOn2PwrGood      : uint8;
        bHubContrCurrent    : uint8;
        { Variable-length DeviceRemovable + PortPwrCtrlMask follow }
    end;
```

### 5.3 Setup Packet

```pascal
    PUSBSetupPacket = ^TUSBSetupPacket;
    TUSBSetupPacket = packed record
        bmRequestType : uint8;
        bRequest      : uint8;
        wValue        : uint16;
        wIndex        : uint16;
        wLength       : uint16;
    end;
```

### 5.4 USB Device / Endpoint / Pipe State

```pascal
    { Transfer completion status }
    TUSBTransferStatus = (
        tsSuccess,
        tsStall,
        tsNAK,
        tsBabble,
        tsDataBufferError,
        tsCRCError,
        tsBitStuffError,
        tsTimeout,
        tsNotStarted,
        tsInProgress
    );

    { Transfer direction }
    TUSBDirection = (dirOut, dirIn, dirSetup);

    { Pipe type matches transfer type }
    TUSBPipeType = (ptControl, ptIsochronous, ptBulk, ptInterrupt);

    PUSBEndpoint = ^TUSBEndpoint;
    TUSBEndpoint = record
        Address      : uint8;      { Endpoint number (0-15) }
        Direction    : TUSBDirection;
        PipeType     : TUSBPipeType;
        MaxPacket    : uint16;
        Interval     : uint8;      { Polling interval (interrupt/iso) }
        Toggle       : uint8;      { Data toggle state: 0 or 1 }
    end;

    PUSBDevice = ^TUSBDevice;

    { Forward declaration for HC driver }
    PUSBHCDriver = ^TUSBHCDriver;

    PUSBTransfer = ^TUSBTransfer;
    TUSBTransfer = record
        Device      : PUSBDevice;
        Endpoint    : PUSBEndpoint;
        Direction   : TUSBDirection;
        PipeType    : TUSBPipeType;
        Buffer      : Pointer;
        BufferLen   : uint32;
        ActualLen   : uint32;     { Bytes actually transferred }
        Status      : TUSBTransferStatus;
        Setup       : TUSBSetupPacket; { For control transfers }
        HCPriv      : Pointer;    { HC-specific data (TD chain, etc.) }
    end;

    TUSBDevice = record
        Address     : uint8;       { Assigned USB address (1-127) }
        Speed       : uint8;       { USB_SPEED_* }
        MaxPacket0  : uint8;       { EP0 max packet size }
        HC          : PUSBHCDriver;
        HCPort      : uint8;       { Root hub port or hub port }
        ParentHub   : PUSBDevice;  { nil for root-hub-attached devices }
        ParentPort  : uint8;       { Port on parent hub }
        DevDesc     : TUSBDeviceDescriptor;
        Endpoints   : array[0..USB_MAX_ENDPOINTS-1] of TUSBEndpoint;
        NumEndpoints: uint8;
        Configured  : boolean;
    end;
```

### 5.5 Host Controller Abstraction

```pascal
    { HC operations - each HC driver fills in these function pointers }
    TUSBHCInit     = function(dev : PPCI_Device) : boolean;
    TUSBHCReset    = function(hc : PUSBHCDriver) : boolean;
    TUSBHCStart    = function(hc : PUSBHCDriver) : boolean;
    TUSBHCStop     = procedure(hc : PUSBHCDriver);
    TUSBHCSubmit   = function(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
    TUSBHCPoll     = procedure(hc : PUSBHCDriver);
    TUSBHCPortReset = function(hc : PUSBHCDriver; port : uint8) : boolean;
    TUSBHCPortStatus = function(hc : PUSBHCDriver; port : uint8) : uint32;

    TUSBHCDriver = record
        Name         : PChar;
        HCType       : uint8;       { 0=UHCI, 1=OHCI, 2=EHCI, 3=xHCI }
        NumPorts     : uint8;
        PCIDev       : TPCI_Device; { Owning PCI device }
        BaseAddr     : uint32;      { I/O base (UHCI) or MMIO base (OHCI/EHCI/xHCI) }
        PrivData     : Pointer;     { HC-specific state (frame list, HCCA, etc.) }
        Devices      : PLinkedListBase; { List of TUSBDevice attached to this HC }
        NextAddress  : uint8;       { Next available USB address }
        { Operations }
        fnReset      : TUSBHCReset;
        fnStart      : TUSBHCStart;
        fnStop       : TUSBHCStop;
        fnSubmit     : TUSBHCSubmit;
        fnPoll       : TUSBHCPoll;
        fnPortReset  : TUSBHCPortReset;
        fnPortStatus : TUSBHCPortStatus;
    end;
```

---

## 6. USB Core (`usbcore.pas`)

The core module orchestrates enumeration and provides the public transfer API used by class drivers.

### 6.1 Responsibilities

1. **Maintain a global list of HC drivers** (`HCList : PLinkedListBase`)
2. **Register/unregister HC drivers** — called by each HC's `load` function
3. **Device enumeration sequence** (called when hub reports a new device):
   - Port reset (via HC abstraction)
   - Create `TUSBDevice` with address 0, EP0 at 8 bytes
   - GET_DESCRIPTOR(Device, 8 bytes) → read `bMaxPacketSize0`
   - SET_ADDRESS(N) → assign unique address
   - GET_DESCRIPTOR(Device, 18 bytes) → full device descriptor
   - GET_DESCRIPTOR(Configuration) → all configs, interfaces, endpoints
   - Parse interface descriptors → populate `Endpoints[]`
   - SET_CONFIGURATION(1)
   - Call `drivermanagement.register_device()` with `biUSB` bus identifier
4. **Control transfer helpers**:
   - `usb_control_msg(dev, requestType, request, value, index, buf, len) : TUSBTransferStatus`
   - `usb_get_descriptor(dev, descType, descIdx, buf, len) : TUSBTransferStatus`
   - `usb_set_address(dev, addr) : TUSBTransferStatus`
   - `usb_set_configuration(dev, config) : TUSBTransferStatus`
5. **Interrupt/Bulk transfer helpers**:
   - `usb_interrupt_transfer(dev, endpoint, buf, len) : TUSBTransferStatus`
   - `usb_bulk_transfer(dev, endpoint, buf, len) : TUSBTransferStatus`
6. **Polling loop** — called from timer/scheduler tick:
   - Iterate all HC drivers → call `fnPoll`
   - HC poll checks for completed transfers and port status changes
   - Port status changes trigger hub logic → enumeration

### 6.2 Device Identifier Encoding for drivermanagement

When a USB device is enumerated, we register it via:

```pascal
DevID.Bus := biUSB;
DevID.id0 := (idVendor SHL 16) OR idProduct;  { Vendor:Product }
DevID.id1 := bDeviceClass;
DevID.id2 := bInterfaceClass;      { From first/matching interface }
DevID.id3 := bInterfaceSubClass;
DevID.id4 := bInterfaceProtocol;
DevID.ex  := nil;  { Could chain additional interface descriptors }
```

Class drivers register with wildcards where appropriate:

```pascal
{ HID Keyboard driver registers: }
DevID.Bus := biUSB;
DevID.id0 := idANY;               { Any vendor/product }
DevID.id1 := idANY;               { Any device class }
DevID.id2 := $03;                  { HID class }
DevID.id3 := $01;                  { Boot interface subclass }
DevID.id4 := $01;                  { Keyboard protocol }
```

The `TDriverLoadCallback` receives a pointer to a `PUSBDevice`, giving the class driver full access to endpoints and the HC transfer API.

---

## 7. Host Controller Drivers

### 7.1 UHCI (Universal Host Controller Interface)

**Priority: First**  
**Spec:** Intel UHCI Design Guide, Rev 1.1  
**I/O model:** Port I/O (not MMIO)  
**PCI prog_if:** `$00`

#### Registers (I/O port offsets from BAR4)
| Offset | Name | Size | Description |
|--------|------|------|-------------|
| $00 | USBCMD | 16-bit | Command register |
| $02 | USBSTS | 16-bit | Status register |
| $04 | USBINTR | 16-bit | Interrupt enable |
| $06 | FRNUM | 16-bit | Frame number |
| $08 | FRBASEADD | 32-bit | Frame list base address |
| $0C | SOFMOD | 8-bit | Start of frame modify |
| $10 | PORTSC1 | 16-bit | Port 1 status/control |
| $12 | PORTSC2 | 16-bit | Port 2 status/control |

#### Key Data Structures (all physically contiguous, 16-byte aligned)
- **Frame List:** 1024 × 32-bit pointers (4KB page-aligned)
- **Queue Head (QH):** 8 bytes — `QH_Link_Pointer`, `QH_Element_Pointer`
- **Transfer Descriptor (TD):** 16 bytes — `TD_Link_Pointer`, `TD_Control_Status`, `TD_Token`, `TD_Buffer_Pointer`

#### Implementation Steps
1. Read BAR4 from PCI config → I/O base address
2. Stop controller (clear USBCMD.RS)
3. Global reset (USBCMD.GRESET), wait 10ms, clear
4. Allocate frame list (4KB, page-aligned, identity-mapped)
5. Initialize all 1024 frame list entries to terminate (T-bit set)
6. Write frame list physical address to FRBASEADD
7. Set FRNUM = 0
8. Create skeleton QH schedule:
   - Control QH → Bulk QH → Interrupt QHs (at frame list intervals)
9. Start controller (USBCMD.RS = 1)
10. For each port: check PORTSC, detect device, trigger enumeration
11. Poll: check USBSTS for completion, walk TD chains for completed transfers

#### UHCI Private Data
```pascal
PUHCIData = ^TUHCIData;
TUHCIData = record
    IOBase       : uint16;
    FrameList    : Pointer;    { 4KB-aligned physical address }
    ControlQH    : Pointer;    { Control transfer queue head }
    BulkQH       : Pointer;    { Bulk transfer queue head }
    IntQH        : array[0..7] of Pointer; { Interrupt QHs at different intervals }
end;
```

### 7.2 OHCI (Open Host Controller Interface)

**Priority: Second**  
**Spec:** OHCI Rev 1.0a  
**I/O model:** MMIO (BAR0)  
**PCI prog_if:** `$10`

#### Key Registers (already partially in existing `TOHCI_MMR`)
Already have the MMIO register record. Need to extend with:
- Operational registers (HcControl, HcCommandStatus, etc.)
- `HcHCCA` → points to 256-byte Host Controller Communications Area
- Port status registers (`HcRhPortStatus[1..N]`)

#### Key Data Structures
- **HCCA:** 256 bytes, 256-byte aligned — contains interrupt table (32 × ED pointers) and frame counter
- **Endpoint Descriptor (ED):** 16 bytes — links to TD list
- **Transfer Descriptor (TD):** 16 bytes (General) or 32 bytes (Isochronous)

#### Implementation Steps
1. Map BAR0 MMIO region (existing code does this)
2. Reset: write OHCI_RESET to HcCommandStatus, wait for completion
3. Allocate HCCA (256-byte aligned)
4. Set HcHCCA register
5. Build ED skeleton schedule (Control, Bulk, Interrupt, Isochronous lists)
6. Set HcControl to OPERATIONAL state
7. Enable relevant interrupts in HcIntEnable
8. Set HcPeriodicStart
9. Power on root hub ports via HcRhPortStatus
10. Detect devices, trigger enumeration
11. Poll: read HcDoneHead for completed TDs

### 7.3 EHCI (Enhanced Host Controller Interface)

**Priority: Third**  
**Spec:** EHCI Rev 1.0  
**I/O model:** MMIO (BAR0)  
**PCI prog_if:** `$20`

#### Key Concepts
- **Capability Registers** (read-only, offset 0): CAPLENGTH, HCSPARAMS, HCCPARAMS
- **Operational Registers** (offset CAPLENGTH): USBCMD, USBSTS, USBINTR, FRINDEX, etc.
- **Periodic Frame List:** 1024 × 32-bit frame list entries (4KB aligned)
- **Async Schedule:** Circular linked list of Queue Heads (QHs)
- **Queue Head (QH):** 48 bytes — contains overlay area for current TD
- **Queue Transfer Descriptor (qTD):** 32 bytes, 32-byte aligned

#### Companion Controller Handling
EHCI routes full/low-speed devices to companion controllers (UHCI/OHCI) via port routing logic. We must:
- Read HCSPARAMS for N_PORTS and N_CC (companion controllers)
- Handle port owner change (CONFIGFLAG, PORTSC[n].PortOwner)

#### Implementation Steps
1. Map BAR0, read capability registers
2. Stop controller (USBCMD.RS = 0), wait for halt
3. Reset (USBCMD.HCRESET), wait for clear
4. Allocate periodic frame list + async QH
5. Set PERIODICLISTBASE, ASYNCLISTADDR
6. Set CONFIGFLAG = 1 (claim all ports from companions)
7. Enable async + periodic schedules
8. Start controller
9. Port detection, reset (50ms PORTRESET), enumeration
10. Poll: check USBSTS for async/periodic completion

### 7.4 xHCI (eXtensible Host Controller Interface)

**Priority: Fourth (last)**  
**Spec:** xHCI Rev 1.2  
**I/O model:** MMIO (BAR0, 64-bit capable)  
**PCI prog_if:** `$30`

#### Key Concepts (significantly different from UHCI/OHCI/EHCI)
- **No frame list** — uses ring-based command/transfer/event model
- **Device Context:** per-device state maintained by hardware
- **Command Ring:** kernel submits commands (enable slot, address device, etc.)
- **Transfer Ring:** per-endpoint ring of TRBs (Transfer Request Blocks)
- **Event Ring:** hardware posts completions
- **Doorbell Registers:** notify controller of new TRBs
- **Scratchpad Buffers:** required by some controllers

#### Implementation Steps
1. Map BAR0 (may need 64-bit BAR handling)
2. Read capability registers (CAPLENGTH, HCSPARAMS1/2/3, HCCPARAMS1)
3. Stop controller, wait for halt
4. Reset (USBCMD.HCRST)
5. Program MaxSlots, MaxIntrs
6. Allocate DCBAA (Device Context Base Address Array)
7. Allocate Command Ring, Event Ring(s), Scratchpad
8. Set DCBAAP, CRCR registers
9. Define Interrupter 0 event ring
10. Start controller
11. For each port: check PORTSC, issue Port Reset, Enable Slot, Address Device
12. Poll: read Event Ring for completion TRBs, advance dequeue pointer

---

## 8. Hub Driver (`usbhub.pas`)

### 8.1 Hub Detection

Hubs are detected during enumeration when `bDeviceClass = $09` (Hub) or `bInterfaceClass = $09`. The hub driver is registered as a USB class driver via `drivermanagement`:

```pascal
DevID.Bus := biUSB;
DevID.id0 := idANY;
DevID.id1 := $09;      { Hub device class }
DevID.id2 := $09;      { Hub interface class }
DevID.id3 := idANY;    { Subclass }
DevID.id4 := idANY;    { Protocol }
```

### 8.2 Hub Responsibilities

1. **GET_HUB_DESCRIPTOR** → determine number of downstream ports
2. **SET_PORT_POWER** for each port (if not ganged-power)
3. **Poll hub status endpoint** (interrupt IN endpoint) for port status change bitmap
4. On port change:
   - **GET_PORT_STATUS** → check `PORT_CONNECTION`, `PORT_ENABLE`, `PORT_RESET`
   - If new device: **SET_PORT_FEATURE(PORT_RESET)**, wait, **CLEAR_PORT_FEATURE(C_PORT_RESET)**
   - Call `usbcore` enumeration for the new device (with `ParentHub` set)
   - If device removed: tear down device, notify class driver, free resources
5. **Topology tracking** — maintain parent/child relationships for split transactions (EHCI TT)

### 8.3 Root Hub Emulation

Each HC driver emulates root hub ports using its native port status registers. The HC abstraction (`fnPortReset`, `fnPortStatus`) provides this. `usbcore` treats root hub ports uniformly by calling these functions during initial scan.

---

## 9. USB Class Drivers

### 9.1 USB Keyboard (`usb_keyboard.pas`)

**USB HID Boot Protocol Keyboard**

- Registers with `drivermanagement` for `biUSB`, class=$03, subclass=$01, protocol=$01
- `load` callback receives `PUSBDevice`
- SET_PROTOCOL(0) → Boot protocol (simpler 8-byte reports)
- SET_IDLE(0) → Only report on change
- Find interrupt IN endpoint from device's endpoint list
- Poll endpoint periodically (using interrupt transfer API)
- Parse 8-byte boot report:
  - Byte 0: modifier keys (Ctrl, Shift, Alt, GUI)
  - Byte 1: reserved
  - Bytes 2-7: keycodes (up to 6 simultaneous)
- Translate keycodes to existing `TKeyInfo` format
- Feed into existing `keyboard.hook` mechanism

### 9.2 USB Mouse (`usb_mouse.pas`)

**USB HID Boot Protocol Mouse**

- Registers for `biUSB`, class=$03, subclass=$01, protocol=$02
- SET_PROTOCOL(0) → Boot protocol
- Find interrupt IN endpoint
- Poll for 3-byte (or 4-byte with scroll) boot reports:
  - Byte 0: buttons (bit0=left, bit1=right, bit2=middle)
  - Byte 1: X displacement (signed)
  - Byte 2: Y displacement (signed)
  - Byte 3: wheel (optional)
- Feed into existing `mousestate` / `mouse` driver system

---

## 10. Integration with drivermanagement

### 10.1 PCI → HC Driver Loading (existing pattern, refined)

The existing `USB.init` procedure already registers four PCI device identifiers with `drivermanagement`. When PCI scan finds a USB controller, `drivermanagement.register_device` triggers the matching HC driver's `load` callback. This stays the same.

### 10.2 HC Driver → USB Core

Each HC driver's `load` function:
1. Initializes hardware
2. Fills in a `TUSBHCDriver` record (kalloc'd)
3. Calls `usbcore.register_hc(@hcdriver)` to add to the global HC list
4. Calls `usbcore.scan_ports(@hcdriver)` to enumerate root hub ports

### 10.3 USB Core → Class Driver Loading

When `usbcore` completes device enumeration:
1. For each interface on the device, create a `TDeviceIdentifier` with `biUSB` and class/subclass/protocol
2. Call `drivermanagement.register_device('USB Device', @DevID, @usbdev)` 
3. `drivermanagement` matches against registered class drivers and calls their `load` callback
4. Class driver receives `PUSBDevice` via the `ptr` parameter, begins operation

### 10.4 Lifecycle Flow

```
Boot
  → kernel.init
    → drivermanagement.init
    → PCI.init  (registers PCI driver, force_load)
      → PCI.load  (scans all buses)
        → For each PCI device: drivermanagement.register_device(biPCI, ...)
          → Matches USB-UHCI/OHCI/EHCI/XHCI drivers registered by USB.init
            → UHCI.load / OHCI.load / EHCI.load / XHCI.load
              → HC hardware init
              → usbcore.register_hc(hc)
              → usbcore.scan_ports(hc)
                → For each port with a device:
                  → port reset
                  → enumeration (GET_DESCRIPTOR, SET_ADDRESS, SET_CONFIG)
                  → drivermanagement.register_device(biUSB, class/sub/proto, @usbdev)
                    → Matches usb_keyboard / usb_mouse / usbhub drivers
                      → Class driver load callback
                        → Begin polling / operation
```

---

## 11. Memory & DMA Strategy

### 11.1 Requirements

USB host controllers require physically-contiguous, properly-aligned memory that must be accessible by the hardware (DMA). In Asuro's identity-mapped kernel space, virtual = physical (for pages set up via `force_alloc_block` + `map_page`).

### 11.2 Allocation Patterns

| Structure | Size | Alignment | Allocator |
|---|---|---|---|
| UHCI Frame List | 4096 bytes | 4KB (page) | `force_alloc_block` + `map_page` (full page) |
| UHCI TD | 32 bytes | 16-byte | `kalloc(32)` — ensure returned address is 16-byte aligned (may need alignment wrapper) |
| UHCI QH | 16 bytes | 16-byte | `kalloc(16)` + alignment |
| OHCI HCCA | 256 bytes | 256-byte | Need aligned alloc helper |
| OHCI ED | 16 bytes | 16-byte | `kalloc(16)` + alignment |
| OHCI TD | 16 bytes | 16-byte | `kalloc(16)` + alignment |
| EHCI Periodic Frame List | 4096 bytes | 4KB | `force_alloc_block` + `map_page` |
| EHCI QH | 64 bytes | 32-byte | `kalloc(64)` + alignment |
| EHCI qTD | 32 bytes | 32-byte | `kalloc(32)` + alignment |
| xHCI rings | 4096+ bytes | 64-byte (TRBs are 16B) | Page allocation |
| xHCI DCBAA | N × 8 bytes | 64-byte | Page allocation |
| Transfer buffers | Variable | 4KB for bulk/iso | `kalloc` or page alloc |

### 11.3 Alignment Helper

```pascal
{ Allocate size bytes with specified alignment }
function kalloc_aligned(size : uint32; alignment : uint32) : Pointer;
var
    raw      : Pointer;
    aligned  : uint32;
    overhead : uint32;
begin
    overhead := alignment + sizeof(uint32);
    raw := Pointer(kalloc(size + overhead));
    aligned := (uint32(raw) + overhead + alignment - 1) AND (NOT (alignment - 1));
    { Store original pointer just before aligned address for kfree }
    PUint32(aligned - 4)^ := uint32(raw);
    kalloc_aligned := Pointer(aligned);
end;

procedure kfree_aligned(p : Pointer);
var
    raw : Pointer;
begin
    raw := Pointer(PUint32(uint32(p) - 4)^);
    kfree(void(raw));
end;
```

This utility should go in `usbtypes.pas` or a dedicated `usbmem.pas`.

---

## 12. Transfer Scheduling

### 12.1 Polled Model

All four HC types use a polled completion model initially:

1. A **timer callback** (registered with the existing timer/scheduler system) fires periodically
2. Calls `usbcore.poll_all()` which iterates all registered HCs and calls `hc^.fnPoll(hc)`
3. Each HC's poll function:
   - Checks hardware status register for completion events
   - Walks completed TD/TRB chains
   - Updates `TUSBTransfer.Status` and `TUSBTransfer.ActualLen`
   - Frees completed TDs/TRBs
   - For hub interrupt endpoints: checks for port status changes, triggers enumeration/removal

### 12.2 Transfer Submission Flow

```
Class Driver                    usbcore                     HC Driver
    │                              │                            │
    ├─ usb_interrupt_transfer() ──►│                            │
    │                              ├─ build TUSBTransfer ──────►│
    │                              │   hc^.fnSubmit(transfer)   │
    │                              │                            ├─ Build TD/QH/TRB chain
    │                              │                            ├─ Link into schedule
    │                              │                            ├─ Ring doorbell (xHCI)
    │                              │◄──────────── true ─────────┤
    │◄──── tsInProgress ───────────┤                            │
    │                              │                            │
    │    ... time passes ...       │                            │
    │                              │                            │
    │                              ├─ poll_all() ──────────────►│
    │                              │                            ├─ Check status register
    │                              │                            ├─ Walk done list
    │                              │                            ├─ Update transfer status
    │                              │◄──────────────────────────┤
    │                              │                            │
    │  (Class driver checks        │                            │
    │   transfer.Status on next    │                            │
    │   poll cycle)                │                            │
```

### 12.3 Interrupt Transfer Resubmission

HID devices need periodic interrupt transfers. After a successful completion, the class driver (or a helper in usbcore) automatically resubmits the interrupt transfer to maintain continuous polling. The poll interval is derived from `bInterval` in the endpoint descriptor.

---

## 13. Unit Testing Strategy

All phases must include unit tests where appropriate, following the pattern established in `strings.pas`:

- Each unit that has testable logic exposes a `procedure UnitTest;` in its interface
- The `UnitTest` procedure uses a local `Assert(condition, testName)` nested procedure
- Tests log via `syslog` with the unit name as tag
- A `PrintSummary` nested procedure reports passed/failed counts
- Tests are called from `kernel.pas` after init (alongside `strings.UnitTest`)
- Tests must properly `kfree` any allocated memory to avoid leaks
- Since this is bare-metal, tests run at boot — focus on logic that can be validated without hardware (descriptor parsing, data structure manipulation, encoding/decoding, identifier matching)

**What to test per phase:**
| Phase | Testable Items |
|-------|---------------|
| 0 (Foundation) | `usbtypes`: `kalloc_aligned`/`kfree_aligned`, setup packet building, descriptor size constants |
| 1 (Core) | `usbcore`: descriptor parsing, address assignment, identifier encoding, endpoint extraction |
| 2-3 (UHCI/OHCI) | TD/QH/ED construction helpers, frame list setup validation, register bitmask helpers |
| 4 (Hub) | Port status bitmap parsing, topology depth calculation |
| 5 (HID) | Boot report parsing (keyboard modifier decode, mouse delta extraction) |
| 6-7 (EHCI/xHCI) | QH/qTD/TRB construction, capability register parsing |

---

## 14. Implementation Phases

### Phase 0: Foundation (Prerequisites)
- [x] Create `src/driver/bus/usb/` directory structure
- [x] Move existing USB/UHCI/OHCI/EHCI/XHCI .pas files to new location
- [x] Update build scripts (`compile_sources.sh`) for new paths
- [x] Implement `usbtypes.pas` — all shared types, constants, HC abstraction record
- [x] Implement alignment helper (`kalloc_aligned` / `kfree_aligned`)
- [x] Implement `usbtypes.UnitTest` — test alignment helpers, setup packet building, constants
- [x] Create `usbcore.pas` skeleton — HC registration, device list, poll stubs
- [x] Verify build still succeeds with moved files

### Phase 1: USB Core Skeleton
- [x] Implement `usb_control_msg()` — builds setup packet, submits via HC abstraction
- [x] Implement descriptor parsing helpers (device, config, interface, endpoint)
- [x] Implement address assignment logic
- [x] Implement full enumeration sequence (reset → get desc → set addr → get full desc → set config → register device)
- [x] ~~Register a timer/scheduler callback for `poll_all()`~~ — **DEFERRED**: hooking `poll_all` into TMR_0_ISR caused severe UI lag (runs inside IRQ0 with interrupts disabled). Removed for now. `usb_control_msg` polls inline. A non-ISR polling approach (e.g. main loop or scheduler task) is needed later.
- [x] Implement `usbcore.UnitTest` — descriptor parsing, identifier encoding, endpoint extraction (47 tests)

### Phase 2: UHCI Host Controller
- [x] UHCI register definitions and private data structure
- [x] UHCI init: read BAR4, global reset, allocate frame list
- [x] UHCI skeleton schedule: create QH chain (control, bulk, interrupt)
- [x] UHCI start: write FRBASEADD, set RS bit
- [x] UHCI port detection: read PORTSC, detect connected devices
- [x] UHCI port reset sequence
- [x] UHCI submit_transfer: build TD chain, link to appropriate QH
- [x] UHCI poll: check USBSTS, walk TDs for completion, update transfer status
- [x] UHCI control transfer: implemented in `uhci_submit_control` (live test needs real UHCI hardware)
- [x] UHCI interrupt transfer: implemented via `uhci_submit_async` (live test needs real UHCI hardware)
- [x] UHCI bulk transfer: implemented via `uhci_submit_async` (live test needs real UHCI hardware)
- [ ] UHCI isochronous transfer support (low priority — no current use case)
- [x] UHCI unit tests: TD/QH construction helpers, bitmask encoding (47 tests)
- [ ] Test: enumerate a USB device on real UHCI hardware — VirtualBox never emulates UHCI (always uses OHCI for USB 1.1)

### Phase 3: OHCI Host Controller
- [x] Extend existing `TOHCI_MMR` with full register set
- [x] OHCI init: map MMIO, reset, allocate HCCA (256-byte aligned)
- [x] OHCI ED/TD management: create, link, free
- [x] OHCI skeleton schedule: control/bulk/interrupt/isochronous ED lists
- [x] OHCI start: set operational, enable port power
- [x] OHCI port detection and reset
- [x] OHCI submit_transfer: build TD chain, attach to ED, place in appropriate list
- [x] OHCI poll: read HcDoneHead, process completed TDs
- [x] OHCI control, interrupt, bulk, isochronous transfers
- [x] OHCI unit tests: ED/TD construction, register bitmask helpers (78/78 pass)
- [x] Test: enumerate device on VirtualBox (ICH9 chipset) — VID=80EE PID=0021, address 1
- [x] Fix: DMA virtual→physical address conversion via `vtop()` for all HC-visible pointers

### Phase 4: Hub Support
- [x] Implement `usbhub.pas` — hub class driver
- [x] Hub detection during enumeration (class $09) via drivermanagement (biUSB, id1=$09)
- [x] GET_HUB_DESCRIPTOR, port power on (SET_FEATURE PORT_POWER per port)
- [x] Hub interrupt IN endpoint polling (status change bitmap)
- [x] Port status change handling (connect, disconnect, reset, overcurrent, enable, suspend)
- [x] Recursive enumeration for devices behind hubs (depth-limited to 5)
- [x] Device removal / cleanup path — `usb_remove_device()` with `fnDisconnect` callback (implemented in Phase 8)
- [x] Topology tracking (parent hub, port, depth via TUSBDevice.ParentHub/ParentPort)
- [x] Root hub emulation consistency — enumerate_device skips HC port_reset when parentHub<>nil
- [x] Hub unit tests: port status bitmap parsing, speed detection, constants (44/44 pass)

### Phase 5: USB HID Class Drivers
- [x] `usb_keyboard.pas` — register with drivermanagement (biUSB, $03/$01/$01)
- [x] Keyboard: SET_PROTOCOL(boot), SET_IDLE(0)
- [x] Keyboard: find interrupt IN endpoint, begin polling
- [x] Keyboard: parse 8-byte boot report, translate to `TKeyInfo` via HID usage tables
- [x] Keyboard: integrate with existing keyboard hook system (`captin_hook`, modifier globals)
- [x] `usb_mouse.pas` — register with drivermanagement (biUSB, $03/$01/$02)
- [x] Mouse: SET_PROTOCOL(boot), find interrupt IN endpoint
- [x] Mouse: parse 3/4-byte boot report (buttons, X, Y, wheel) with signed delta extraction
- [x] Mouse: integrate with existing mousestate system (setMousePos, fireMouseEvent, addScroll)
- [x] HID unit tests: boot report parsing — keyboard 62 tests, mouse 33 tests (modifier keys, usage-to-ASCII, deltas, buttons, scroll)
- [x] Test: USB keyboard in VirtualBox (xHCI) — boot protocol keyboard on slot 1, EP1 interrupt transfers, input working

### Phase 6: EHCI Host Controller
- [x] EHCI capability + operational register mapping
- [x] EHCI init: reset, halt, allocate periodic frame list + async QH
- [x] EHCI QH/qTD management
- [x] EHCI async schedule (control + bulk)
- [x] EHCI periodic schedule (interrupt + isochronous)
- [x] EHCI port routing: CONFIGFLAG, companion controller handoff
- [x] EHCI split transactions for full/low-speed devices behind hubs (TT)
- [x] EHCI start, port detection, reset, enumeration
- [x] EHCI poll: USBSTS, async/periodic doorbell, qTD completion
- [x] EHCI unit tests: QH/qTD construction, capability parsing (90 tests pass)
- [x] Test: USB 2.0 device on VirtualBox (ICH9) — Intel 8086:265C detected, companion routing works

### Phase 7: xHCI Host Controller
- [x] xHCI capability register parsing (CAPLENGTH, HCSPARAMS1/2, HCCPARAMS1, DBOFF, RTSOFF)
- [x] xHCI init: reset, halt, MaxSlots, DCBAA, scratchpad buffers
- [x] xHCI Command Ring, Event Ring, Transfer Ring allocation (page-aligned, Link TRBs)
- [x] xHCI Interrupter 0 setup (ERST, ERDP, polling mode — no hardware interrupts)
- [x] xHCI start controller (RS, HSEE, no INTE)
- [x] xHCI BIOS/OS handoff (USBLEGSUP extended capability)
- [x] xHCI port detection: PORTSC scan, speed mapping
- [x] xHCI Enable Slot → Address Device commands (Input Context, Slot+EP0 contexts)
- [x] xHCI Configure Endpoint: lazy per-endpoint ring allocation + command for non-EP0 endpoints
- [x] xHCI transfer submission: control (Setup/Data/Status TRBs, SET_ADDRESS interception), bulk/interrupt (Normal TRBs)
- [x] xHCI poll: dequeue Event Ring, process Transfer Events + Command Completion + Port Status Change
- [x] xHCI unit tests: TRB construction, DCI calculation, speed mapping, EP type mapping (119 tests pass)
- [x] Test: USB device on VirtualBox (xHCI enabled) — Intel 8086:1E31 detected, keyboard enumerated + input working

### Phase 8: Hardening & Extras
- [x] Error recovery: stall handling (CLEAR_FEATURE ENDPOINT_HALT) — `usb_clear_halt()` in usbcore
- [x] Transfer timeouts — `usb_control_msg` uses `bios_data_area.Counters.c32` (1024 Hz) with 5-second real-time timeout instead of spin-loop
- [x] Device disconnect cleanup (free TDs, endpoints, device record) — `usb_remove_device()` in usbcore
- [x] `USB` terminal command for USB device information
- [x] Interrupt-driven completion (ISR registered for each HC on PCI interrupt line)
- [x] USB Mass Storage (Bulk-Only Transport) class driver — `usb_storage.pas` with CBW/CSW, SCSI (INQUIRY, TEST_UNIT_READY, READ_CAPACITY, READ_10, WRITE_10), storagemanagement integration
- [x] Hotplug: ISR-driven detection (OHCI RHSC, EHCI PCD, xHCI Port Status Change TRB) → deferred `usb_check_hotplug` in main loop; `HotplugArmed` guard prevents spurious boot-time events
- [x] Disconnect callbacks: `TUSBDisconnectCallback` on `TUSBDevice.fnDisconnect`, called by `usb_remove_device` before freeing — keyboard/mouse/storage drivers clean up transfers and deactivate
- [x] Dynamic device lists: keyboard, mouse, storage drivers use `lists.pas` linked lists (no static array limits); devices freely plug/unplug without slot exhaustion
- [x] HID fail-count guard: 3 consecutive transfer failures → self-deactivate (handles race between unplug and deferred hotplug processing)
- [x] `usb_bulk_transfer_wait` — blocking bulk helper with timer-based timeout, used by mass storage BOT
- [ ] Code audit: verify all kalloc/kfree pairs, no leaks

---

## 14. Progress Tracker

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 0: Foundation | **Complete** | Files moved to `src/driver/bus/usb/`, `usbtypes.pas` + `usbcore.pas` created, build scripts updated, 71 unit tests passing (51 usbtypes + 20 usbcore) |
| Phase 1: USB Core | **Complete** | Descriptor parsing helpers, control/bulk/interrupt transfer API, inline polling |
| Phase 2: UHCI | **Complete** | Full UHCI driver with QH/TD, registers, schedule, control+bulk+interrupt submit, poll — 47 unit tests pass. Live testing requires real UHCI hardware (VirtualBox always uses OHCI for USB 1.1, never UHCI). Isochronous not yet implemented (low priority). |
| Phase 3: OHCI | **Complete** | Full OHCI driver: HCCA+ED+TD, MMIO, reset/start/stop, control+async submit, poll with TD chain cleanup, vtop() DMA fix — 78 unit tests pass, VirtualBox ICH9 enumerates VID=80EE PID=0021 at address 1 |
| Phase 4: Hub Support | **Complete** | `usbhub.pas` hub class driver: hub descriptor, port power, port reset, status change polling, recursive enumeration, depth limit — 44 unit tests pass. Device removal via `usb_remove_device()` + `fnDisconnect` (Phase 8). |
| Phase 5: HID Drivers | **Complete** | `usb_keyboard.pas` (62 tests) + `usb_mouse.pas` (33 tests): HID boot protocol, usage-to-ASCII tables, signed delta extraction, mousestate/keyboard hook integration. VBox live test pending (no HID keyboard/mouse hardware attached). |
| Phase 6: EHCI | **Complete** | Full EHCI driver: capability/operational registers, QH+qTD 32-byte aligned, async+periodic schedule, BIOS legacy handoff (EECP), port reset with companion controller routing (low-speed/not-enabled → OHCI), control+bulk+interrupt submit, poll with qTD chain completion — 90 unit tests pass. VBox ICH9 live: Intel 8086:265C detected, CONFIGFLAG routes ports, full-speed devices correctly handed off to companion OHCI. |
| Phase 7: xHCI | **Complete** | Full xHCI driver: capability parsing, ring-based model (Cmd/Evt/Transfer rings), BIOS handoff, DCBAA, scratchpad, polling mode (no IRQ), Enable Slot + Address Device + Configure Endpoint, control+bulk+interrupt submit, event ring poll — 119 unit tests pass. VBox xHCI live: Intel 8086:1E31, keyboard on slot 1 with lazy EP configuration, input working. |
| Phase 8: Hardening | **Complete** | `usb_clear_halt()` stall recovery, `usb_remove_device()` with `fnDisconnect` callback, `USB` terminal command, interrupt-driven completion for all 4 HCs, completion hooks for HID drivers, polling removed from kernel main loop. Timer-based transfer timeouts (5s via `bios_data_area.Counters.c32`). USB Mass Storage BOT driver (`usb_storage.pas`) with SCSI over bulk endpoints + storagemanagement registration. Hotplug: ISR sets `PortChangePending` (guarded by `HotplugArmed`), deferred `usb_check_hotplug` in main loop. Disconnect callbacks clean up class driver state. Dynamic linked lists replace static arrays — unlimited plug/unplug cycles. HID fail-count self-deactivation (3 strikes). Remaining: kalloc/kfree audit. |

---

## Appendix A: USB Class Codes (Reference)

| Class | Description | Subclass examples |
|-------|-------------|-------------------|
| $00 | Use interface descriptors | — |
| $03 | HID | $01 Boot, Protocol: $01 Keyboard, $02 Mouse |
| $08 | Mass Storage | $06 SCSI, $50 Bulk-Only |
| $09 | Hub | $00 Full-speed, $01 Hi-speed single TT, $02 Hi-speed multi TT |

## Appendix B: VirtualBox USB Testing Notes

- **PIIX3 chipset** → emulates OHCI + EHCI (VirtualBox never emulates UHCI)
- **ICH9 chipset** → emulates OHCI + EHCI companion pair
- **xHCI** → optional, enable in VM settings (USB 3.0 controller)
- USB device passthrough or VirtualBox's emulated USB tablet/keyboard for testing
- Serial output via `Get-Content "C:\Temp\asuro.log"` for debug logging
- VirtualBox USB filters can attach host USB devices to the VM

## Appendix C: Known Issues & Future Work

- **UHCI live-hardware testing**: VirtualBox never emulates UHCI (always uses OHCI for USB 1.1 regardless of PIIX3/ICH9 chipset). UHCI driver code is complete with 47 unit tests but needs real Intel ICH southbridge hardware (Pentium 4 era) for end-to-end testing.
