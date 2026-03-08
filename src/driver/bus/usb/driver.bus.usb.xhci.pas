{
    Driver->Bus->driver.bus.usb->driver.bus.usb.xhci - eXtensible Host Controller Interface Driver.

    Implements the driver.bus.usb.xhci (driver.bus.usb 3.0) host controller using ring-based
    command/transfer/event model with TRBs (Transfer Request Blocks).

    driver.bus.usb.xhci manages device addresses internally via Enable Slot / Address Device
    commands. This driver intercepts SET_ADDRESS from driver.bus.usb.core and uses
    slot IDs as device addresses.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.bus.usb.xhci;

interface

uses
    debug.tracer,
    io.syslog,
    driver.bus.pci,
    driver.types,
    arch.x86.memory.physical,
    arch.x86.memory.virtual,
    memory.heap,
    core.util, arch.x86.util,
    driver.mgr,
    driver.bus.usb.types,
    driver.bus.usb.core,
    arch.x86.isr.mgr,
    core.ds.lists,
    core.strings;

function load : boolean;
procedure UnitTest;

implementation

{ ========================= Stage 1: Constants & Types ========================= }

{ ---- Capability Register Offsets (from BAR0) ---- }
const
    XHCI_CAP_CAPLENGTH    = $00;  { 1 byte: offset to operational registers }
    XHCI_CAP_HCIVERSION   = $02;  { 2 bytes: BCD interface version }
    XHCI_CAP_HCSPARAMS1   = $04;  { 4 bytes: structural parameters 1 }
    XHCI_CAP_HCSPARAMS2   = $08;  { 4 bytes: structural parameters 2 }
    XHCI_CAP_HCSPARAMS3   = $0C;  { 4 bytes: structural parameters 3 }
    XHCI_CAP_HCCPARAMS1   = $10;  { 4 bytes: capability parameters 1 }
    XHCI_CAP_DBOFF        = $14;  { 4 bytes: doorbell offset }
    XHCI_CAP_RTSOFF       = $18;  { 4 bytes: runtime register space offset }
    XHCI_CAP_HCCPARAMS2   = $1C;  { 4 bytes: capability parameters 2 }

{ ---- Operational Register Offsets (from OpBase = BAR0 + CAPLENGTH) ---- }

    XHCI_OP_USBCMD        = $00;  { driver.bus.usb Command }
    XHCI_OP_USBSTS        = $04;  { driver.bus.usb Status }
    XHCI_OP_PAGESIZE      = $08;  { Page Size }
    XHCI_OP_DNCTRL        = $14;  { Device Notification Control }
    XHCI_OP_CRCR_LO       = $18;  { Command Ring Control - low 32 bits }
    XHCI_OP_CRCR_HI       = $1C;  { Command Ring Control - high 32 bits }
    XHCI_OP_DCBAAP_LO     = $30;  { Device Context Base Address Array Pointer - low }
    XHCI_OP_DCBAAP_HI     = $34;  { Device Context Base Address Array Pointer - high }
    XHCI_OP_CONFIG        = $38;  { Configure }
    XHCI_OP_PORTSC_BASE   = $400; { Port Status and Control base (+ $10 * port) }

{ ---- USBCMD Bits ---- }

    XHCI_CMD_RS            = $00000001; { Run/Stop }
    XHCI_CMD_HCRST         = $00000002; { Host Controller Reset }
    XHCI_CMD_INTE          = $00000004; { Interrupter Enable }
    XHCI_CMD_HSEE          = $00000008; { Host System Error Enable }
    XHCI_CMD_LHCRST        = $00000080; { Light Host Controller Reset }
    XHCI_CMD_CSS           = $00000100; { Controller Save State }
    XHCI_CMD_CRS           = $00000200; { Controller Restore State }
    XHCI_CMD_EWE           = $00000400; { Enable Wrap Event }
    XHCI_CMD_EU3S          = $00000800; { Enable U3 MFINDEX Stop }

{ ---- USBSTS Bits ---- }

    XHCI_STS_HCH           = $00000001; { HC Halted }
    XHCI_STS_HSE           = $00000004; { Host System Error }
    XHCI_STS_EINT          = $00000008; { Event Interrupt }
    XHCI_STS_PCD           = $00000010; { Port Change Detect }
    XHCI_STS_SSS           = $00000100; { Save State Status }
    XHCI_STS_RSS           = $00000200; { Restore State Status }
    XHCI_STS_SRE           = $00000400; { Save/Restore Error }
    XHCI_STS_CNR           = $00000800; { Controller Not Ready }
    XHCI_STS_HCE           = $00001000; { Host Controller Error }

{ ---- PORTSC Bits ---- }

    XHCI_PORTSC_CCS        = $00000001; { Current Connect Status }
    XHCI_PORTSC_PED        = $00000002; { Port Enabled/Disabled }
    XHCI_PORTSC_OCA        = $00000008; { Over-current Active }
    XHCI_PORTSC_PR         = $00000010; { Port Reset }
    XHCI_PORTSC_PLS_MASK   = $000001E0; { Port Link State (bits 8:5) }
    XHCI_PORTSC_PLS_SHIFT  = 5;
    XHCI_PORTSC_PP         = $00000200; { Port Power }
    XHCI_PORTSC_SPEED_MASK = $00003C00; { Port Speed (bits 13:10) }
    XHCI_PORTSC_SPEED_SHIFT = 10;
    XHCI_PORTSC_PIC_MASK   = $0000C000; { Port Indicator Control (bits 15:14) }
    XHCI_PORTSC_LWS        = $00010000; { Port Link State Write Strobe }
    XHCI_PORTSC_CSC        = $00020000; { Connect Status Change }
    XHCI_PORTSC_PEC        = $00040000; { Port Enabled/Disabled Change }
    XHCI_PORTSC_WRC        = $00080000; { Warm Port Reset Change }
    XHCI_PORTSC_OCC        = $00100000; { Over-current Change }
    XHCI_PORTSC_PRC        = $00200000; { Port Reset Change }
    XHCI_PORTSC_PLC        = $00400000; { Port Link State Change }
    XHCI_PORTSC_CEC        = $00800000; { Port Config Error Change }
    XHCI_PORTSC_CAS        = $01000000; { Cold Attach Status }
    XHCI_PORTSC_WCE        = $02000000; { Wake on Connect Enable }
    XHCI_PORTSC_WDE        = $04000000; { Wake on Disconnect Enable }
    XHCI_PORTSC_WOE        = $08000000; { Wake on Over-current Enable }
    XHCI_PORTSC_DR         = $40000000; { Device Removable }
    XHCI_PORTSC_WPR        = $80000000; { Warm Port Reset }

    { Write-clear change bits in PORTSC }
    XHCI_PORTSC_CHANGE_BITS = XHCI_PORTSC_CSC OR XHCI_PORTSC_PEC OR
                               XHCI_PORTSC_WRC OR XHCI_PORTSC_OCC OR
                               XHCI_PORTSC_PRC OR XHCI_PORTSC_PLC OR
                               XHCI_PORTSC_CEC;

    { Bits to preserve when writing PORTSC (mask out change bits and read-only) }
    XHCI_PORTSC_PRESERVE   = XHCI_PORTSC_PP OR XHCI_PORTSC_PIC_MASK;

{ ---- PORTSC Speed Values (bits 13:10) ---- }

    XHCI_SPEED_FULL        = 1;
    XHCI_SPEED_LOW         = 2;
    XHCI_SPEED_HIGH        = 3;
    XHCI_SPEED_SUPER       = 4;

{ ---- HCSPARAMS1 Fields ---- }

    XHCI_HCS1_MAXSLOTS_MASK  = $000000FF; { bits 7:0 }
    XHCI_HCS1_MAXINTRS_MASK  = $0007FF00; { bits 18:8 }
    XHCI_HCS1_MAXINTRS_SHIFT = 8;
    XHCI_HCS1_MAXPORTS_MASK  = $FF000000; { bits 31:24 }
    XHCI_HCS1_MAXPORTS_SHIFT = 24;

{ ---- HCSPARAMS2 Fields ---- }

    XHCI_HCS2_IST_MASK          = $0000000F; { bits 3:0 }
    XHCI_HCS2_ERST_MAX_MASK     = $000000F0; { bits 7:4 }
    XHCI_HCS2_ERST_MAX_SHIFT    = 4;
    XHCI_HCS2_SCRATCH_HI_MASK   = $03E00000; { bits 25:21 }
    XHCI_HCS2_SCRATCH_HI_SHIFT  = 21;
    XHCI_HCS2_SPR               = $04000000; { Scratchpad Restore }
    XHCI_HCS2_SCRATCH_LO_MASK   = $F8000000; { bits 31:27 }
    XHCI_HCS2_SCRATCH_LO_SHIFT  = 27;

{ ---- HCCPARAMS1 Fields ---- }

    XHCI_HCC1_AC64          = $00000001; { 64-bit Addressing Capability }
    XHCI_HCC1_BNC           = $00000002; { BW Negotiation Capability }
    XHCI_HCC1_CSZ           = $00000004; { Context Size (1=64 byte, 0=32 byte) }
    XHCI_HCC1_PPC           = $00000008; { Port Power Control }
    XHCI_HCC1_PIND          = $00000010; { Port Indicators }
    XHCI_HCC1_LHRC          = $00000020; { Light HC Reset Capability }
    XHCI_HCC1_LTC           = $00000040; { Latency Tolerance Messaging }
    XHCI_HCC1_NSS           = $00000080; { No Secondary SID Support }
    XHCI_HCC1_PAE           = $00000100; { Parse All Event Data }
    XHCI_HCC1_XECP_MASK     = $FFFF0000; { driver.bus.usb.xhci Extended Capabilities Pointer (bits 31:16) }
    XHCI_HCC1_XECP_SHIFT    = 16;

{ ---- Runtime Register Offsets (from RTBase) ---- }

    XHCI_RT_MFINDEX          = $00;     { Microframe Index }
    XHCI_RT_IR0_BASE         = $20;     { Interrupter 0 base }
    { Per-Interrupter offsets (from IR base) }
    XHCI_IR_IMAN             = $00;     { Interrupter Management }
    XHCI_IR_IMOD             = $04;     { Interrupter Moderation }
    XHCI_IR_ERSTSZ           = $08;     { Event Ring Segment Table Size }
    XHCI_IR_ERSTBA_LO        = $10;     { Event Ring Segment Table Base Address Low }
    XHCI_IR_ERSTBA_HI        = $14;     { Event Ring Segment Table Base Address High }
    XHCI_IR_ERDP_LO          = $18;     { Event Ring Dequeue Pointer Low }
    XHCI_IR_ERDP_HI          = $1C;     { Event Ring Dequeue Pointer High }

{ ---- IMAN Bits ---- }

    XHCI_IMAN_IP             = $00000001; { Interrupt Pending }
    XHCI_IMAN_IE             = $00000002; { Interrupt Enable }

{ ---- TRB Type Codes (bits 15:10 of Control dword) ---- }

    { Transfer TRB Types }
    XHCI_TRB_NORMAL          = 1;
    XHCI_TRB_SETUP_STAGE     = 2;
    XHCI_TRB_DATA_STAGE      = 3;
    XHCI_TRB_STATUS_STAGE    = 4;
    XHCI_TRB_ISOCH           = 5;
    XHCI_TRB_LINK            = 6;
    XHCI_TRB_EVENT_DATA      = 7;
    XHCI_TRB_NOOP_TRANSFER   = 8;

    { Command TRB Types }
    XHCI_TRB_ENABLE_SLOT     = 9;
    XHCI_TRB_DISABLE_SLOT    = 10;
    XHCI_TRB_ADDRESS_DEVICE  = 11;
    XHCI_TRB_CONFIG_EP       = 12;
    XHCI_TRB_EVALUATE_CTX    = 13;
    XHCI_TRB_RESET_EP        = 14;
    XHCI_TRB_STOP_EP         = 15;
    XHCI_TRB_SET_TR_DEQUEUE  = 16;
    XHCI_TRB_RESET_DEVICE    = 17;
    XHCI_TRB_NOOP_CMD        = 23;

    { Event TRB Types }
    XHCI_TRB_TRANSFER_EVENT  = 32;
    XHCI_TRB_CMD_COMPLETION  = 33;
    XHCI_TRB_PORT_STATUS_CHG = 34;
    XHCI_TRB_BW_REQUEST      = 35;
    XHCI_TRB_DOORBELL_EVENT  = 36;
    XHCI_TRB_HOST_CTRL_EVENT = 37;
    XHCI_TRB_DEV_NOTIFY      = 38;
    XHCI_TRB_MFINDEX_WRAP    = 39;

    XHCI_TRB_TYPE_SHIFT      = 10;
    XHCI_TRB_TYPE_MASK       = $FC00;    { bits 15:10 }

{ ---- TRB Flag Bits (Control dword) ---- }

    XHCI_TRB_CYCLE           = $00000001; { Cycle bit }
    XHCI_TRB_ENT             = $00000002; { Evaluate Next TRB }
    XHCI_TRB_ISP             = $00000004; { Interrupt on Short Packet }
    XHCI_TRB_NS              = $00000008; { No Snoop }
    XHCI_TRB_CH              = $00000010; { Chain bit }
    XHCI_TRB_IOC             = $00000020; { Interrupt On Completion }
    XHCI_TRB_IDT             = $00000040; { Immediate Data }
    XHCI_TRB_BSR             = $00000200; { Block Set Address Request (Address Device) }
    XHCI_TRB_TC              = $00000002; { Toggle Cycle (Link TRB) }

    { Setup Stage TRB: Transfer Type (bits 17:16) }
    XHCI_TRB_TRT_NONE        = $00000000; { No Data Stage }
    XHCI_TRB_TRT_OUT         = $00020000; { OUT Data Stage }
    XHCI_TRB_TRT_IN          = $00030000; { IN Data Stage }

    { Data Stage / Status Stage: Direction (bit 16) }
    XHCI_TRB_DIR_OUT         = $00000000;
    XHCI_TRB_DIR_IN          = $00010000;

{ ---- TRB Completion Codes (Status dword bits 31:24) ---- }

    XHCI_CC_INVALID           = 0;
    XHCI_CC_SUCCESS           = 1;
    XHCI_CC_DATA_BUFFER_ERROR = 2;
    XHCI_CC_BABBLE            = 3;
    XHCI_CC_USB_TRANSACTION   = 4;
    XHCI_CC_TRB_ERROR         = 5;
    XHCI_CC_STALL             = 6;
    XHCI_CC_RESOURCE_ERROR    = 7;
    XHCI_CC_BANDWIDTH_ERROR   = 8;
    XHCI_CC_NO_SLOTS          = 9;
    XHCI_CC_INVALID_STREAM    = 10;
    XHCI_CC_SLOT_NOT_ENABLED  = 11;
    XHCI_CC_EP_NOT_ENABLED    = 12;
    XHCI_CC_SHORT_PACKET      = 13;
    XHCI_CC_RING_UNDERRUN     = 14;
    XHCI_CC_RING_OVERRUN      = 15;
    XHCI_CC_VF_EVENT_RING_FULL = 16;
    XHCI_CC_PARAMETER_ERROR   = 17;
    XHCI_CC_CONTEXT_STATE_ERROR = 19;
    XHCI_CC_CMD_RING_STOPPED  = 24;
    XHCI_CC_CMD_ABORTED       = 25;
    XHCI_CC_STOPPED           = 26;
    XHCI_CC_STOPPED_LENGTH    = 27;

    XHCI_CC_SHIFT             = 24;
    XHCI_CC_MASK              = $FF000000;

{ ---- Slot Context Field Helpers ---- }

    XHCI_SLOT_ROUTE_MASK       = $000FFFFF; { bits 19:0 }
    XHCI_SLOT_SPEED_SHIFT      = 20;
    XHCI_SLOT_SPEED_MASK       = $00F00000; { bits 23:20 }
    XHCI_SLOT_MTT              = $02000000; { bit 25 }
    XHCI_SLOT_HUB              = $04000000; { bit 26 }
    XHCI_SLOT_CTX_ENTRIES_SHIFT = 27;
    XHCI_SLOT_CTX_ENTRIES_MASK = $F8000000; { bits 31:27 }

    XHCI_SLOT_RHP_SHIFT        = 16;       { Root Hub Port Number shift (dword 1) }
    XHCI_SLOT_RHP_MASK         = $00FF0000;

{ ---- Endpoint Context Field Helpers ---- }

    XHCI_EP_STATE_MASK         = $00000007; { bits 2:0 }
    XHCI_EP_MULT_SHIFT         = 8;
    XHCI_EP_INTERVAL_SHIFT     = 16;

    XHCI_EP_CERR_SHIFT         = 1;
    XHCI_EP_CERR_MASK          = $00000006; { bits 2:1 of EPInfo2 }
    XHCI_EP_TYPE_SHIFT         = 3;
    XHCI_EP_TYPE_MASK          = $00000038; { bits 5:3 of EPInfo2 }
    XHCI_EP_MAXBURST_SHIFT     = 8;
    XHCI_EP_MAXPACKET_SHIFT    = 16;
    XHCI_EP_MAXPACKET_MASK     = $FFFF0000;

    { Endpoint Types }
    XHCI_EP_TYPE_NOT_VALID     = 0;
    XHCI_EP_TYPE_ISOCH_OUT     = 1;
    XHCI_EP_TYPE_BULK_OUT      = 2;
    XHCI_EP_TYPE_INTR_OUT      = 3;
    XHCI_EP_TYPE_CONTROL       = 4;
    XHCI_EP_TYPE_ISOCH_IN      = 5;
    XHCI_EP_TYPE_BULK_IN       = 6;
    XHCI_EP_TYPE_INTR_IN       = 7;

{ ---- Ring / Queue Sizes ---- }

    XHCI_CMD_RING_SIZE         = 256;  { Number of TRBs in command ring }
    XHCI_EVT_RING_SIZE         = 256;  { Number of TRBs in event ring }
    XHCI_TRANSFER_RING_SIZE    = 256;  { Number of TRBs per EP transfer ring }
    XHCI_MAX_SLOTS             = 256;  { driver.bus.usb.xhci spec max }

{ ---- USBLEGSUP (Extended Capability for BIOS handoff) ---- }

    XHCI_LEGSUP_CAP_ID        = $01;
    XHCI_LEGSUP_BIOS_OWNED    = $00010000; { bit 16 }
    XHCI_LEGSUP_OS_OWNED      = $01000000; { bit 24 }

{ ========================= Packed Record Types ========================= }

type
    { TRB — 16 bytes, universal transfer/command/event block }
    PXHCI_TRB = ^TXHCI_TRB;
    TXHCI_TRB = packed record
        Param0  : uint32;  { Parameter low dword }
        Param1  : uint32;  { Parameter high dword }
        Status  : uint32;  { Status / Transfer Length / Completion Code }
        Control : uint32;  { Cycle bit, TRB Type (bits 15:10), flags }
    end;

    { Ring descriptor (software-only, not hardware-visible) }
    PXHCI_Ring = ^TXHCI_Ring;
    TXHCI_Ring = record
        Base      : PXHCI_TRB;  { Virtual base address of TRB array }
        Size      : uint32;      { Total entries (including Link TRB for cmd/xfer rings) }
        Enqueue   : uint32;      { Current enqueue index }
        Dequeue   : uint32;      { Current dequeue index (Event Ring primarily) }
        CycleBit  : uint8;       { Current producer/consumer cycle state }
    end;

    { Slot Context — 32 bytes }
    PXHCI_SlotCtx = ^TXHCI_SlotCtx;
    TXHCI_SlotCtx = packed record
        Field0    : uint32;  { Route String, Speed, MTT, Hub, Context Entries }
        Field1    : uint32;  { Max Exit Latency, Root Hub Port, Num Ports }
        Field2    : uint32;  { Parent Hub Slot ID, Parent Port, TTT, Intr Target }
        Field3    : uint32;  { Device Address, Slot State }
        Rsvd      : array[0..3] of uint32;
    end;

    { Endpoint Context — 32 bytes }
    PXHCI_EPCtx = ^TXHCI_EPCtx;
    TXHCI_EPCtx = packed record
        Field0    : uint32;  { EP State, Mult, MaxPStreams, LSA, Interval }
        Field1    : uint32;  { CErr, EP Type, HID, Max Burst Size, Max Packet Size }
        TRDeqLo   : uint32;  { TR Dequeue Pointer Low | DCS (bit 0) }
        TRDeqHi   : uint32;  { TR Dequeue Pointer High }
        Field4    : uint32;  { Average TRB Length, Max ESIT Payload }
        Rsvd      : array[0..2] of uint32;
    end;

    { Input Control Context — 32 bytes }
    PXHCI_InputCtrlCtx = ^TXHCI_InputCtrlCtx;
    TXHCI_InputCtrlCtx = packed record
        DropFlags : uint32;
        AddFlags  : uint32;
        Rsvd      : array[0..5] of uint32;
    end;

    { Event Ring Segment Table Entry — 16 bytes }
    PXHCI_ERSTE = ^TXHCI_ERSTE;
    TXHCI_ERSTE = packed record
        BaseAddrLo : uint32;
        BaseAddrHi : uint32;
        SegSize    : uint32;
        Rsvd       : uint32;
    end;

    { Pending transfer tracking entry }
    PXHCI_PendingTransfer = ^TXHCI_PendingTransfer;
    TXHCI_PendingTransfer = record
        Transfer : PUSBTransfer;
        SlotID   : uint8;
        EPID     : uint8;
    end;

    { Private data for an driver.bus.usb.xhci host controller instance }
    PXHCI_PrivData = ^TXHCI_PrivData;
    TXHCI_PrivData = record
        MMIOBase    : uint32;
        OpBase      : uint32;
        RTBase      : uint32;
        DBBase      : uint32;

        MaxSlots    : uint8;
        MaxIntrs    : uint16;
        MaxPorts    : uint8;
        CtxSize     : uint8;       { 32 or 64 }

        HCSPARAMS1  : uint32;
        HCSPARAMS2  : uint32;
        HCCPARAMS1  : uint32;

        DCBAA       : Pointer;

        CmdRing     : TXHCI_Ring;
        EvtRing     : TXHCI_Ring;
        ERST        : PXHCI_ERSTE;

        ScratchBufs : Pointer;
        NumScratch  : uint16;

        { Per-slot dynamic arrays (kalloc'd, 1-indexed via offset) }
        SlotPort    : Pointer;     { ^uint8 array [0..MaxSlots-1] }
        SlotSpeed   : Pointer;     { ^uint8 array }
        SlotOutCtx  : Pointer;     { ^Pointer array (output device contexts) }

        { Per-slot per-DCI transfer ring pointers.
          Flat array: index = (slotID-1)*32 + dci.
          Each entry is a PXHCI_Ring (or nil if not configured). }
        SlotEPRings   : Pointer;   { ^PXHCI_Ring flat array [MaxSlots * 32] }

        { Pending transfers list }
        PendingList : PLinkedListBase;

        { Blocking command completion state }
        CmdComplete   : boolean;
        CmdResultCode : uint8;
        CmdSlotID     : uint8;

        { Re-entrancy guard: prevents ISR from calling poll while
          inline code is already inside poll. }
        PollBusy    : boolean;

        PCIBus      : uint8;
        PCISlot     : uint8;
        PCIFunc     : uint8;
    end;

{ ========================= Stage 2: MMIO Helpers ========================= }

function xhci_readl(base : uint32; reg : uint32) : uint32;
begin
    xhci_readl := PUint32(base + reg)^;
end;

procedure xhci_writel(base : uint32; reg : uint32; val : uint32);
begin
    PUint32(base + reg)^ := val;
end;

function xhci_readb(base : uint32; reg : uint32) : uint8;
begin
    xhci_readb := PUint8(base + reg)^;
end;

function xhci_readw(base : uint32; reg : uint32) : uint16;
begin
    xhci_readw := PUint16(base + reg)^;
end;

{ 64-bit read: low then high (i386) }
procedure xhci_readq(base : uint32; reg : uint32; var rlo, rhi : uint32);
begin
    rlo := PUint32(base + reg)^;
    rhi := PUint32(base + reg + 4)^;
end;

{ 64-bit write: low then high (i386, high = 0 for 32-bit system) }
procedure xhci_writeq(base : uint32; reg : uint32; lo : uint32; hi : uint32);
begin
    PUint32(base + reg)^ := lo;
    PUint32(base + reg + 4)^ := hi;
end;

{ ========================= Allocation Helpers ========================= }

{ Allocate a TRB ring with Link TRB at the last entry.
  Returns a TXHCI_Ring descriptor. Ring is page-aligned. }
function xhci_alloc_ring(numTRBs : uint32) : TXHCI_Ring;
var
    ring    : TXHCI_Ring;
    linkTRB : PXHCI_TRB;
    phys    : uint32;
begin
    ring.Size := numTRBs;
    ring.Enqueue := 0;
    ring.Dequeue := 0;
    ring.CycleBit := 1;
    ring.Base := PXHCI_TRB(kalloc_aligned(numTRBs * sizeof(TXHCI_TRB), 4096));
    if ring.Base <> nil then begin
        memset(uint32(ring.Base), 0, numTRBs * sizeof(TXHCI_TRB));
        { Set up Link TRB at the last entry pointing back to start }
        linkTRB := PXHCI_TRB(uint32(ring.Base) + ((numTRBs - 1) * sizeof(TXHCI_TRB)));
        phys := vtop(uint32(ring.Base));
        linkTRB^.Param0 := phys;
        linkTRB^.Param1 := 0;
        linkTRB^.Status := 0;
        linkTRB^.Control := (XHCI_TRB_LINK SHL XHCI_TRB_TYPE_SHIFT) OR XHCI_TRB_TC;
        { Note: Cycle bit on Link TRB will be set by enqueue logic }
    end;
    xhci_alloc_ring := ring;
end;

{ Allocate an event ring (no Link TRB, controller wraps based on segment size) }
function xhci_alloc_event_ring(numTRBs : uint32) : TXHCI_Ring;
var
    ring : TXHCI_Ring;
begin
    ring.Size := numTRBs;
    ring.Enqueue := 0;
    ring.Dequeue := 0;
    ring.CycleBit := 1;
    ring.Base := PXHCI_TRB(kalloc_aligned(numTRBs * sizeof(TXHCI_TRB), 4096));
    if ring.Base <> nil then
        memset(uint32(ring.Base), 0, numTRBs * sizeof(TXHCI_TRB));
    xhci_alloc_event_ring := ring;
end;

procedure xhci_free_ring(var ring : TXHCI_Ring);
begin
    if ring.Base <> nil then begin
        kfree_aligned(ring.Base);
        ring.Base := nil;
    end;
end;

function xhci_alloc_ctx(ctxSize : uint32) : Pointer;
begin
    xhci_alloc_ctx := kalloc_aligned(ctxSize, 64);
    if xhci_alloc_ctx <> nil then
        memset(uint32(xhci_alloc_ctx), 0, ctxSize);
end;

procedure xhci_free_ctx(ctx : Pointer);
begin
    if ctx <> nil then
        kfree_aligned(ctx);
end;

{ Return context entry size: 32 (standard) or 64 (if CSZ bit set) }
function xhci_context_entry_size(hccparams1 : uint32) : uint8;
begin
    if (hccparams1 AND XHCI_HCC1_CSZ) <> 0 then
        xhci_context_entry_size := 64
    else
        xhci_context_entry_size := 32;
end;

{ Build a TRB from components }
function xhci_make_trb(p0, p1, status, control : uint32) : TXHCI_TRB;
begin
    xhci_make_trb.Param0  := p0;
    xhci_make_trb.Param1  := p1;
    xhci_make_trb.Status  := status;
    xhci_make_trb.Control := control;
end;

{ Map driver.bus.usb.xhci PORTSC speed field to USB_SPEED_* }
function xhci_map_speed(portscSpeed : uint32) : uint8;
begin
    case portscSpeed of
        XHCI_SPEED_FULL:  xhci_map_speed := USB_SPEED_FULL;
        XHCI_SPEED_LOW:   xhci_map_speed := USB_SPEED_LOW;
        XHCI_SPEED_HIGH:  xhci_map_speed := USB_SPEED_HIGH;
        XHCI_SPEED_SUPER: xhci_map_speed := USB_SPEED_SUPER;
    else
        xhci_map_speed := USB_SPEED_FULL;
    end;
end;

{ Map USB_SPEED_* to driver.bus.usb.xhci slot context speed value }
function xhci_slot_speed(usbSpeed : uint8) : uint32;
begin
    case usbSpeed of
        USB_SPEED_FULL:  xhci_slot_speed := XHCI_SPEED_FULL;
        USB_SPEED_LOW:   xhci_slot_speed := XHCI_SPEED_LOW;
        USB_SPEED_HIGH:  xhci_slot_speed := XHCI_SPEED_HIGH;
        USB_SPEED_SUPER: xhci_slot_speed := XHCI_SPEED_SUPER;
    else
        xhci_slot_speed := XHCI_SPEED_FULL;
    end;
end;

{ Calculate Device Context Index from endpoint number and direction.
  DCI = (epNum * 2) + direction(0=OUT,1=IN). EP0 is always DCI=1. }
function xhci_ep_to_dci(epNum : uint8; isIn : boolean) : uint8;
begin
    if epNum = 0 then
        xhci_ep_to_dci := 1
    else begin
        xhci_ep_to_dci := epNum * 2;
        if isIn then
            xhci_ep_to_dci := xhci_ep_to_dci + 1;
    end;
end;

{ Get default max packet size for EP0 based on speed }
function xhci_default_max_packet(speed : uint8) : uint16;
begin
    case speed of
        USB_SPEED_LOW:   xhci_default_max_packet := 8;
        USB_SPEED_FULL:  xhci_default_max_packet := 8;
        USB_SPEED_HIGH:  xhci_default_max_packet := 64;
        USB_SPEED_SUPER: xhci_default_max_packet := 512;
    else
        xhci_default_max_packet := 8;
    end;
end;

{ ========================= Stage 3: Ring Management ========================= }

{ Enqueue a TRB onto a command or transfer ring.
  Sets the cycle bit according to the ring's current cycle state. }
procedure xhci_ring_enqueue(ring : PXHCI_Ring; trb : PXHCI_TRB);
var
    dest    : PXHCI_TRB;
    linkTRB : PXHCI_TRB;
begin
    if (ring = nil) or (ring^.Base = nil) or (trb = nil) then exit;

    dest := PXHCI_TRB(uint32(ring^.Base) + (ring^.Enqueue * sizeof(TXHCI_TRB)));

    { Copy TRB data }
    dest^.Param0  := trb^.Param0;
    dest^.Param1  := trb^.Param1;
    dest^.Status  := trb^.Status;

    { Set cycle bit: clear it first, then OR in the current cycle }
    dest^.Control := (trb^.Control AND (NOT uint32(XHCI_TRB_CYCLE))) OR uint32(ring^.CycleBit);

    { Advance enqueue pointer }
    ring^.Enqueue := ring^.Enqueue + 1;

    { Check if we've reached the Link TRB (last entry in command/transfer rings) }
    if ring^.Enqueue >= (ring^.Size - 1) then begin
        { Set cycle bit on the Link TRB }
        linkTRB := PXHCI_TRB(uint32(ring^.Base) + ((ring^.Size - 1) * sizeof(TXHCI_TRB)));
        linkTRB^.Control := (linkTRB^.Control AND (NOT uint32(XHCI_TRB_CYCLE))) OR uint32(ring^.CycleBit);
        { Toggle cycle bit and wrap to beginning }
        if ring^.CycleBit = 1 then
            ring^.CycleBit := 0
        else
            ring^.CycleBit := 1;
        ring^.Enqueue := 0;
    end;
end;

{ Ring a doorbell register. slotID=0 for command ring. }
procedure xhci_ring_doorbell(priv : PXHCI_PrivData; slotID : uint32; target : uint32);
begin
    if priv <> nil then
        xhci_writel(priv^.DBBase, slotID * 4, target);
end;

{ Check if there's a pending event on the Event Ring (cycle bit matches) }
function xhci_event_pending(priv : PXHCI_PrivData) : boolean;
var
    evt : PXHCI_TRB;
    cyc : uint32;
begin
    xhci_event_pending := false;
    if (priv = nil) or (priv^.EvtRing.Base = nil) then exit;

    evt := PXHCI_TRB(uint32(priv^.EvtRing.Base) + (priv^.EvtRing.Dequeue * sizeof(TXHCI_TRB)));
    cyc := evt^.Control AND XHCI_TRB_CYCLE;

    if cyc = uint32(priv^.EvtRing.CycleBit) then
        xhci_event_pending := true;
end;

{ Dequeue the next event TRB. Returns true if an event was available. }
function xhci_event_dequeue(priv : PXHCI_PrivData; var trb : TXHCI_TRB) : boolean;
var
    evt : PXHCI_TRB;
begin
    xhci_event_dequeue := false;
    if not xhci_event_pending(priv) then exit;

    evt := PXHCI_TRB(uint32(priv^.EvtRing.Base) + (priv^.EvtRing.Dequeue * sizeof(TXHCI_TRB)));
    trb := evt^;

    { Advance dequeue pointer }
    priv^.EvtRing.Dequeue := priv^.EvtRing.Dequeue + 1;
    if priv^.EvtRing.Dequeue >= priv^.EvtRing.Size then begin
        priv^.EvtRing.Dequeue := 0;
        { Toggle consumer cycle bit on wrap }
        if priv^.EvtRing.CycleBit = 1 then
            priv^.EvtRing.CycleBit := 0
        else
            priv^.EvtRing.CycleBit := 1;
    end;

    xhci_event_dequeue := true;
end;

{ Write the Event Ring Dequeue Pointer to acknowledge processed events }
procedure xhci_advance_erdp(priv : PXHCI_PrivData);
var
    erdp   : uint32;
    irBase : uint32;
begin
    if priv = nil then exit;
    irBase := priv^.RTBase + XHCI_RT_IR0_BASE;

    { ERDP = physical address of current dequeue position }
    erdp := vtop(uint32(priv^.EvtRing.Base) + (priv^.EvtRing.Dequeue * sizeof(TXHCI_TRB)));

    { Set EHB (Event Handler Busy) bit 3 to clear it }
    xhci_writeq(irBase, XHCI_IR_ERDP_LO, erdp OR $08, 0);
end;

{ Send a command TRB on the Command Ring and ring doorbell 0 }
procedure xhci_send_command(priv : PXHCI_PrivData; trb : PXHCI_TRB);
begin
    if priv = nil then exit;
    priv^.CmdComplete := false;
    priv^.CmdResultCode := 0;
    priv^.CmdSlotID := 0;
    xhci_ring_enqueue(@priv^.CmdRing, trb);
    xhci_ring_doorbell(priv, 0, 0);
end;

{ Wait for a command completion event. Polls the Event Ring with timeout.
  Returns the completion code. }
function xhci_wait_command(priv : PXHCI_PrivData; timeout : uint32) : uint8;
var
    loops : uint32;
begin
    xhci_wait_command := XHCI_CC_TRB_ERROR;
    if priv = nil then exit;

    { With interrupt-driven completion, the ISR calls xhci_poll which
      sets CmdComplete/CmdResultCode/CmdSlotID on Command Completion
      events. We just spin here waiting for the ISR to do its work. }
    loops := 0;
    while loops < timeout do begin
        if priv^.CmdComplete then begin
            xhci_wait_command := priv^.CmdResultCode;
            exit;
        end;
        inc(loops);
    end;

    io.syslog.logln('driver.bus.usb.xhci', 'Command timeout!');
end;

{ ========================= HC Callback Forward Declarations ========================= }

function xhci_reset(hc : PUSBHCDriver) : boolean; forward;
function xhci_start(hc : PUSBHCDriver) : boolean; forward;
procedure xhci_stop(hc : PUSBHCDriver); forward;
function xhci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean; forward;
procedure xhci_poll(hc : PUSBHCDriver); forward;
function xhci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean; forward;
function xhci_port_status(hc : PUSBHCDriver; port : uint8) : uint32; forward;

{ ========================= Stage 4: BIOS Handoff ========================= }

procedure xhci_bios_handoff(priv : PXHCI_PrivData; pciDev : TPCI_Device);
var
    xecp    : uint32;
    capAddr : uint32;
    capVal  : uint32;
    loops   : uint32;
begin
    push_trace('driver.bus.usb.xhci.xhci_bios_handoff');

    { XECP = HCCPARAMS1 bits 31:16 (dword offset from BAR0) }
    xecp := (priv^.HCCPARAMS1 AND XHCI_HCC1_XECP_MASK) SHR XHCI_HCC1_XECP_SHIFT;
    if xecp = 0 then begin
        pop_trace;
        exit;
    end;

    { XECP is in dwords, convert to byte offset from BAR0 }
    capAddr := priv^.MMIOBase + (xecp SHL 2);

    { Walk the extended capability list }
    loops := 0;
    while loops < 100 do begin
        capVal := xhci_readl(capAddr, 0);

        { Check capability ID (bits 7:0) }
        if (capVal AND $FF) = XHCI_LEGSUP_CAP_ID then begin
            { Found driver.bus.usb Legacy Support }
            if (capVal AND XHCI_LEGSUP_BIOS_OWNED) = 0 then begin
                io.syslog.logln('driver.bus.usb.xhci', 'BIOS does not own controller.');
                pop_trace;
                exit;
            end;

            { Request ownership: set OS Owned (bit 24) }
            xhci_writel(capAddr, 0, capVal OR XHCI_LEGSUP_OS_OWNED);

            { Wait for BIOS to release (bit 16 clears) }
            loops := 0;
            while loops < 200000 do begin
                capVal := xhci_readl(capAddr, 0);
                if (capVal AND XHCI_LEGSUP_BIOS_OWNED) = 0 then begin
                    io.syslog.logln('driver.bus.usb.xhci', 'BIOS handoff complete.');
                    { Disable SMIs via legacy control/status (offset +4) }
                    xhci_writel(capAddr, 4, 0);
                    pop_trace;
                    exit;
                end;
                inc(loops);
            end;

            { Force ownership }
            io.syslog.logln('driver.bus.usb.xhci', 'BIOS handoff timeout, forcing.');
            capVal := xhci_readl(capAddr, 0);
            xhci_writel(capAddr, 0, (capVal AND (NOT XHCI_LEGSUP_BIOS_OWNED)) OR XHCI_LEGSUP_OS_OWNED);
            xhci_writel(capAddr, 4, 0);
            pop_trace;
            exit;
        end;

        { Next capability: bits 15:8 = next pointer (dword offset) }
        xecp := (capVal SHR 8) AND $FF;
        if xecp = 0 then break;
        capAddr := capAddr + (xecp SHL 2);
        inc(loops);
    end;

    io.syslog.logln('driver.bus.usb.xhci', 'No USBLEGSUP capability found.');
    pop_trace;
end;

{ ========================= Scratchpad Allocation ========================= }

procedure xhci_alloc_scratchpad(priv : PXHCI_PrivData);
var
    hi, lo   : uint32;
    nScratch : uint32;
    bufArray : Pointer;
    bufArrayPhys : uint32;
    i : uint32;
    page : Pointer;
    pagePhys : uint32;
begin
    push_trace('driver.bus.usb.xhci.xhci_alloc_scratchpad');

    { Extract scratchpad count from HCSPARAMS2 }
    hi := (priv^.HCSPARAMS2 AND XHCI_HCS2_SCRATCH_HI_MASK) SHR XHCI_HCS2_SCRATCH_HI_SHIFT;
    lo := (priv^.HCSPARAMS2 AND XHCI_HCS2_SCRATCH_LO_MASK) SHR XHCI_HCS2_SCRATCH_LO_SHIFT;
    nScratch := (hi SHL 5) OR lo;

    priv^.NumScratch := uint16(nScratch);
    priv^.ScratchBufs := nil;

    if nScratch = 0 then begin
        io.syslog.logln('driver.bus.usb.xhci', 'No scratchpad buffers needed.');
        pop_trace;
        exit;
    end;

    io.syslog.log('driver.bus.usb.xhci', 'Allocating ');
    io.syslog.writeint(nScratch);
    io.syslog.writestringln(' scratchpad buffers.');

    { Allocate the scratchpad buffer array (array of 64-bit physical addresses) }
    bufArray := kalloc_aligned(nScratch * 8, 64);
    if bufArray = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate scratchpad array!');
        pop_trace;
        exit;
    end;
    memset(uint32(bufArray), 0, nScratch * 8);
    priv^.ScratchBufs := bufArray;

    { Allocate individual scratchpad pages and fill the array }
    for i := 0 to nScratch - 1 do begin
        page := kalloc_aligned(4096, 4096);
        if page = nil then begin
            io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate scratchpad page!');
            pop_trace;
            exit;
        end;
        memset(uint32(page), 0, 4096);
        pagePhys := vtop(uint32(page));
        { Write 64-bit physical address to array entry }
        PUint32(uint32(bufArray) + (i * 8))^ := pagePhys;
        PUint32(uint32(bufArray) + (i * 8) + 4)^ := 0;
    end;

    { Store the scratchpad array physical address in DCBAA[0] }
    bufArrayPhys := vtop(uint32(bufArray));
    PUint32(uint32(priv^.DCBAA))^ := bufArrayPhys;
    PUint32(uint32(priv^.DCBAA) + 4)^ := 0;

    io.syslog.logln('driver.bus.usb.xhci', 'Scratchpad buffers allocated.');
    pop_trace;
end;

{ ========================= Reset ========================= }

function xhci_reset(hc : PUSBHCDriver) : boolean;
var
    priv      : PXHCI_PrivData;
    opbase    : uint32;
    loops     : uint32;
    cmd       : uint32;
    dcbaaSize : uint32;
begin
    push_trace('driver.bus.usb.xhci.xhci_reset');
    xhci_reset := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PXHCI_PrivData(hc^.PrivData);
    opbase := priv^.OpBase;

    { Step 1: Halt the controller (clear RS) }
    cmd := xhci_readl(opbase, XHCI_OP_USBCMD);
    cmd := cmd AND (NOT XHCI_CMD_RS);
    xhci_writel(opbase, XHCI_OP_USBCMD, cmd);

    { Wait for HCHalted }
    loops := 0;
    while loops < 100000 do begin
        if (xhci_readl(opbase, XHCI_OP_USBSTS) AND XHCI_STS_HCH) <> 0 then
            break;
        inc(loops);
    end;

    if (xhci_readl(opbase, XHCI_OP_USBSTS) AND XHCI_STS_HCH) = 0 then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Controller did not halt!');
        pop_trace;
        exit;
    end;

    { Step 2: Issue host controller reset }
    xhci_writel(opbase, XHCI_OP_USBCMD, XHCI_CMD_HCRST);

    { Wait for HCRST to self-clear AND CNR to become 0 }
    loops := 0;
    while loops < 200000 do begin
        cmd := xhci_readl(opbase, XHCI_OP_USBCMD);
        if (cmd AND XHCI_CMD_HCRST) = 0 then begin
            if (xhci_readl(opbase, XHCI_OP_USBSTS) AND XHCI_STS_CNR) = 0 then
                break;
        end;
        inc(loops);
    end;

    if ((xhci_readl(opbase, XHCI_OP_USBCMD) AND XHCI_CMD_HCRST) <> 0) or
       ((xhci_readl(opbase, XHCI_OP_USBSTS) AND XHCI_STS_CNR) <> 0) then begin
        io.syslog.logln('driver.bus.usb.xhci', 'HC reset timeout!');
        pop_trace;
        exit;
    end;

    { Step 3: Allocate DCBAA }
    dcbaaSize := (uint32(priv^.MaxSlots) + 1) * 8;
    priv^.DCBAA := kalloc_aligned(dcbaaSize, 64);
    if priv^.DCBAA = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate DCBAA!');
        pop_trace;
        exit;
    end;
    memset(uint32(priv^.DCBAA), 0, dcbaaSize);

    { Step 4: Allocate Command Ring }
    priv^.CmdRing := xhci_alloc_ring(XHCI_CMD_RING_SIZE);
    if priv^.CmdRing.Base = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate Command Ring!');
        pop_trace;
        exit;
    end;

    { Step 5: Allocate Event Ring }
    priv^.EvtRing := xhci_alloc_event_ring(XHCI_EVT_RING_SIZE);
    if priv^.EvtRing.Base = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate Event Ring!');
        pop_trace;
        exit;
    end;

    { Step 6: Allocate Event Ring Segment Table (1 segment) }
    priv^.ERST := PXHCI_ERSTE(kalloc_aligned(sizeof(TXHCI_ERSTE), 64));
    if priv^.ERST = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate ERST!');
        pop_trace;
        exit;
    end;
    memset(uint32(priv^.ERST), 0, sizeof(TXHCI_ERSTE));
    priv^.ERST^.BaseAddrLo := vtop(uint32(priv^.EvtRing.Base));
    priv^.ERST^.BaseAddrHi := 0;
    priv^.ERST^.SegSize := XHCI_EVT_RING_SIZE;

    { Step 7: Allocate scratchpad buffers }
    xhci_alloc_scratchpad(priv);

    { Step 8: Allocate per-slot arrays }
    priv^.SlotPort := Pointer(kalloc(uint32(priv^.MaxSlots)));
    priv^.SlotSpeed := Pointer(kalloc(uint32(priv^.MaxSlots)));
    priv^.SlotOutCtx := Pointer(kalloc(uint32(priv^.MaxSlots) * sizeof(Pointer)));
    priv^.SlotEPRings := Pointer(kalloc(uint32(priv^.MaxSlots) * 32 * sizeof(Pointer)));
    if (priv^.SlotPort <> nil) then
        memset(uint32(priv^.SlotPort), 0, uint32(priv^.MaxSlots));
    if (priv^.SlotSpeed <> nil) then
        memset(uint32(priv^.SlotSpeed), 0, uint32(priv^.MaxSlots));
    if (priv^.SlotOutCtx <> nil) then
        memset(uint32(priv^.SlotOutCtx), 0, uint32(priv^.MaxSlots) * sizeof(Pointer));
    if (priv^.SlotEPRings <> nil) then
        memset(uint32(priv^.SlotEPRings), 0, uint32(priv^.MaxSlots) * 32 * sizeof(Pointer));

    { Allocate pending transfer list }
    priv^.PendingList := LL_New(sizeof(TXHCI_PendingTransfer));

    { Clear all pending status bits (write-1-to-clear) }
    xhci_writel(opbase, XHCI_OP_USBSTS, $3F);

    io.syslog.logln('driver.bus.usb.xhci', 'HC reset complete.');
    xhci_reset := true;
    pop_trace;
end;

{ ========================= Start ========================= }

function xhci_start(hc : PUSBHCDriver) : boolean;
var
    priv     : PXHCI_PrivData;
    opbase   : uint32;
    irBase   : uint32;
    loops    : uint32;
    cmd      : uint32;
    crcrPhys : uint32;
    erstPhys : uint32;
    erdpPhys : uint32;
begin
    push_trace('driver.bus.usb.xhci.xhci_start');
    xhci_start := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PXHCI_PrivData(hc^.PrivData);
    opbase := priv^.OpBase;
    irBase := priv^.RTBase + XHCI_RT_IR0_BASE;

    io.syslog.logln('driver.bus.usb.xhci', 'Starting controller...');

    { Step 1: Set Max Device Slots Enabled }
    xhci_writel(opbase, XHCI_OP_CONFIG, uint32(priv^.MaxSlots));
    io.syslog.logln('driver.bus.usb.xhci', '  CONFIG set.');

    { Step 2: Program DCBAAP }
    xhci_writeq(opbase, XHCI_OP_DCBAAP_LO, vtop(uint32(priv^.DCBAA)), 0);
    io.syslog.logln('driver.bus.usb.xhci', '  DCBAAP set.');

    { Step 3: Program Command Ring Control Register (CRCR)
      Low 6 bits: RCS (Ring Cycle State) = 1, CS/CA/CRR = 0
      Physical address of ring base in bits 63:6 }
    crcrPhys := vtop(uint32(priv^.CmdRing.Base));
    xhci_writeq(opbase, XHCI_OP_CRCR_LO, crcrPhys OR uint32(priv^.CmdRing.CycleBit), 0);
    io.syslog.logln('driver.bus.usb.xhci', '  CRCR set.');

    { Step 4: Program Interrupter 0 }
    { ERSTSZ = 1 (one segment) }
    xhci_writel(irBase, XHCI_IR_ERSTSZ, 1);

    { ERDP = physical address of event ring start }
    erdpPhys := vtop(uint32(priv^.EvtRing.Base));
    xhci_writeq(irBase, XHCI_IR_ERDP_LO, erdpPhys, 0);

    { ERSTBA = physical address of ERST (writing this enables the event ring) }
    erstPhys := vtop(uint32(priv^.ERST));
    xhci_writeq(irBase, XHCI_IR_ERSTBA_LO, erstPhys, 0);

    { Polling mode — do NOT enable hardware interrupts (no ISR registered).
      Clear IMAN IP if set, leave IE disabled. }
    xhci_writel(irBase, XHCI_IR_IMAN, 0);
    xhci_writel(irBase, XHCI_IR_IMOD, 0);
    io.syslog.logln('driver.bus.usb.xhci', '  Interrupter 0 programmed (polling).');

    { Step 5: Start controller (RS only — no INTE since we poll) }
    cmd := XHCI_CMD_RS OR XHCI_CMD_HSEE;
    xhci_writel(opbase, XHCI_OP_USBCMD, cmd);
    io.syslog.logln('driver.bus.usb.xhci', '  USBCMD written, waiting for HCH clear...');

    { Wait for controller to be running (HCH clears) }
    loops := 0;
    while loops < 100000 do begin
        if (xhci_readl(opbase, XHCI_OP_USBSTS) AND XHCI_STS_HCH) = 0 then
            break;
        inc(loops);
    end;

    if (xhci_readl(opbase, XHCI_OP_USBSTS) AND XHCI_STS_HCH) <> 0 then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Controller failed to start!');
        pop_trace;
        exit;
    end;

    io.syslog.logln('driver.bus.usb.xhci', 'Controller started (operational).');
    xhci_start := true;
    pop_trace;
end;

{ ========================= Stop ========================= }

procedure xhci_stop(hc : PUSBHCDriver);
var
    priv   : PXHCI_PrivData;
    opbase : uint32;
    cmd    : uint32;
begin
    push_trace('driver.bus.usb.xhci.xhci_stop');
    if (hc <> nil) and (hc^.PrivData <> nil) then begin
        priv := PXHCI_PrivData(hc^.PrivData);
        opbase := priv^.OpBase;
        cmd := xhci_readl(opbase, XHCI_OP_USBCMD);
        cmd := cmd AND (NOT XHCI_CMD_RS);
        xhci_writel(opbase, XHCI_OP_USBCMD, cmd);
        io.syslog.logln('driver.bus.usb.xhci', 'Controller stopped.');
    end;
    pop_trace;
end;

{ ========================= Stage 5: Port Status & Reset ========================= }

function xhci_port_status(hc : PUSBHCDriver; port : uint8) : uint32;
var
    priv : PXHCI_PrivData;
begin
    push_trace('driver.bus.usb.xhci.xhci_port_status');
    xhci_port_status := 0;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PXHCI_PrivData(hc^.PrivData);
    if port >= priv^.MaxPorts then begin
        pop_trace;
        exit;
    end;
    xhci_port_status := xhci_readl(priv^.OpBase, XHCI_OP_PORTSC_BASE + (uint32(port) * $10));
    pop_trace;
end;

function xhci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean;
var
    priv     : PXHCI_PrivData;
    opbase   : uint32;
    regOfs   : uint32;
    portsc   : uint32;
    loops    : uint32;
    speed    : uint8;
    speedVal : uint32;
    slotID   : uint8;
    cmdTRB   : TXHCI_TRB;
    inputCtx : Pointer;
    icc      : PXHCI_InputCtrlCtx;
    slotCtx  : PXHCI_SlotCtx;
    ep0Ctx   : PXHCI_EPCtx;
    ep0Ring  : PXHCI_Ring;
    ep0RingPhys : uint32;
    outCtx   : Pointer;
    maxPkt   : uint16;
    cc       : uint8;
begin
    push_trace('driver.bus.usb.xhci.xhci_port_reset');
    xhci_port_reset := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PXHCI_PrivData(hc^.PrivData);
    opbase := priv^.OpBase;
    if port >= priv^.MaxPorts then begin
        pop_trace;
        exit;
    end;
    regOfs := XHCI_OP_PORTSC_BASE + (uint32(port) * $10);

    { Read PORTSC }
    portsc := xhci_readl(opbase, regOfs);

    { Check if device is connected }
    if (portsc AND XHCI_PORTSC_CCS) = 0 then begin
        pop_trace;
        exit;
    end;

    { Issue port reset: set PR bit, preserve PP, clear change bits }
    portsc := (portsc AND XHCI_PORTSC_PRESERVE) OR XHCI_PORTSC_PR;
    xhci_writel(opbase, regOfs, portsc);

    { Wait for Port Reset Change (PRC) }
    loops := 0;
    while loops < 500000 do begin
        portsc := xhci_readl(opbase, regOfs);
        if (portsc AND XHCI_PORTSC_PRC) <> 0 then
            break;
        inc(loops);
    end;

    if (portsc AND XHCI_PORTSC_PRC) = 0 then begin
        io.syslog.log('driver.bus.usb.xhci', 'Port ');
        io.syslog.writeint(port);
        io.syslog.writestringln(' reset timeout.');
        pop_trace;
        exit;
    end;

    { Clear change bits }
    xhci_writel(opbase, regOfs, (portsc AND XHCI_PORTSC_PRESERVE) OR XHCI_PORTSC_CHANGE_BITS);

    { Re-read PORTSC to get final state }
    portsc := xhci_readl(opbase, regOfs);

    { Check port is enabled }
    if (portsc AND XHCI_PORTSC_PED) = 0 then begin
        io.syslog.log('driver.bus.usb.xhci', 'Port ');
        io.syslog.writeint(port);
        io.syslog.writestringln(' not enabled after reset.');
        pop_trace;
        exit;
    end;

    { Determine speed }
    speedVal := (portsc AND XHCI_PORTSC_SPEED_MASK) SHR XHCI_PORTSC_SPEED_SHIFT;
    speed := xhci_map_speed(speedVal);
    maxPkt := xhci_default_max_packet(speed);

    io.syslog.log('driver.bus.usb.xhci', 'Port ');
    io.syslog.writeint(port);
    io.syslog.writestring(' reset OK, speed=');
    io.syslog.writeintln(speed);

    { ---- Enable Slot ---- }
    cmdTRB := xhci_make_trb(0, 0, 0, (XHCI_TRB_ENABLE_SLOT SHL XHCI_TRB_TYPE_SHIFT));
    xhci_send_command(priv, @cmdTRB);
    cc := xhci_wait_command(priv, 500000);
    if cc <> XHCI_CC_SUCCESS then begin
        io.syslog.log('driver.bus.usb.xhci', 'Enable Slot failed, cc=');
        io.syslog.writeintln(cc);
        pop_trace;
        exit;
    end;
    slotID := priv^.CmdSlotID;

    if (slotID = 0) or (slotID > priv^.MaxSlots) then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Invalid slot ID from Enable Slot.');
        pop_trace;
        exit;
    end;

    io.syslog.log('driver.bus.usb.xhci', 'Slot ');
    io.syslog.writeint(slotID);
    io.syslog.writestringln(' enabled.');

    { ---- Allocate EP0 Transfer Ring ---- }
    ep0Ring := PXHCI_Ring(kalloc(sizeof(TXHCI_Ring)));
    if ep0Ring = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate EP0 ring descriptor!');
        pop_trace;
        exit;
    end;
    ep0Ring^ := xhci_alloc_ring(XHCI_TRANSFER_RING_SIZE);
    if ep0Ring^.Base = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate EP0 ring buffer!');
        kfree(void(ep0Ring));
        pop_trace;
        exit;
    end;
    ep0RingPhys := vtop(uint32(ep0Ring^.Base));

    { ---- Allocate Output Device Context ---- }
    outCtx := xhci_alloc_ctx(uint32(priv^.CtxSize) * 32);
    if outCtx = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate output device context!');
        xhci_free_ring(ep0Ring^);
        kfree(void(ep0Ring));
        pop_trace;
        exit;
    end;

    { Store output context pointer in DCBAA[slotID] }
    PUint32(uint32(priv^.DCBAA) + (uint32(slotID) * 8))^ := vtop(uint32(outCtx));
    PUint32(uint32(priv^.DCBAA) + (uint32(slotID) * 8) + 4)^ := 0;

    { ---- Build Input Context for Address Device ---- }
    { Input Context = Input Control Ctx + Slot Ctx + EP0 Ctx (+ more EPs) }
    inputCtx := xhci_alloc_ctx(uint32(priv^.CtxSize) * 33);
    if inputCtx = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate input context!');
        xhci_free_ring(ep0Ring^);
        kfree(void(ep0Ring));
        xhci_free_ctx(outCtx);
        pop_trace;
        exit;
    end;

    { Input Control Context: Add Slot (bit 0) and EP0 (bit 1) }
    icc := PXHCI_InputCtrlCtx(inputCtx);
    icc^.DropFlags := 0;
    icc^.AddFlags := $03;  { A0=Slot, A1=EP0 }

    { Slot Context (at offset CtxSize from start of Input Context) }
    slotCtx := PXHCI_SlotCtx(uint32(inputCtx) + uint32(priv^.CtxSize));
    slotCtx^.Field0 :=
        (xhci_slot_speed(speed) SHL XHCI_SLOT_SPEED_SHIFT) OR
        (uint32(1) SHL XHCI_SLOT_CTX_ENTRIES_SHIFT);  { Context Entries = 1 (Slot + EP0) }
    slotCtx^.Field1 :=
        (uint32(port + 1) SHL XHCI_SLOT_RHP_SHIFT);  { Root Hub Port Number (1-based) }

    { EP0 Context (at offset CtxSize*2 from start of Input Context) }
    ep0Ctx := PXHCI_EPCtx(uint32(inputCtx) + uint32(priv^.CtxSize) * 2);
    ep0Ctx^.Field1 :=
        (uint32(3) SHL XHCI_EP_CERR_SHIFT) OR            { CErr = 3 }
        (uint32(XHCI_EP_TYPE_CONTROL) SHL XHCI_EP_TYPE_SHIFT) OR  { EP Type = Control Bidirectional }
        (uint32(maxPkt) SHL XHCI_EP_MAXPACKET_SHIFT);     { Max Packet Size }
    ep0Ctx^.TRDeqLo := ep0RingPhys OR 1;  { DCS = 1 (initial cycle state) }
    ep0Ctx^.TRDeqHi := 0;
    ep0Ctx^.Field4 := 8;  { Average TRB Length = 8 (for control) }

    { ---- Address Device Command ---- }
    cmdTRB := xhci_make_trb(
        vtop(uint32(inputCtx)),  { Input Context pointer (physical) }
        0,
        0,
        (XHCI_TRB_ADDRESS_DEVICE SHL XHCI_TRB_TYPE_SHIFT) OR
        (uint32(slotID) SHL 24)  { Slot ID in bits 31:24 }
    );
    xhci_send_command(priv, @cmdTRB);
    cc := xhci_wait_command(priv, 500000);

    { Free input context (no longer needed after command completes) }
    xhci_free_ctx(inputCtx);

    if cc <> XHCI_CC_SUCCESS then begin
        io.syslog.log('driver.bus.usb.xhci', 'Address Device failed, cc=');
        io.syslog.writeintln(cc);
        { Clean up }
        PUint32(uint32(priv^.DCBAA) + (uint32(slotID) * 8))^ := 0;
        xhci_free_ring(ep0Ring^);
        kfree(void(ep0Ring));
        xhci_free_ctx(outCtx);
        pop_trace;
        exit;
    end;

    io.syslog.log('driver.bus.usb.xhci', 'Device addressed at slot ');
    io.syslog.writeintln(slotID);

    { ---- Store slot data ---- }
    { Arrays are 0-indexed, slot IDs are 1-based, so index = slotID - 1 }
    PUint8(uint32(priv^.SlotPort) + uint32(slotID - 1))^ := port;
    PUint8(uint32(priv^.SlotSpeed) + uint32(slotID - 1))^ := speed;
    PUint32(uint32(priv^.SlotEPRings) + (uint32(slotID - 1) * 32 + 1) * 4)^ := uint32(ep0Ring);
    PUint32(uint32(priv^.SlotOutCtx) + (uint32(slotID - 1) * 4))^ := uint32(outCtx);

    { Set NextAddress so driver.bus.usb.core assigns slotID as the device "address" }
    hc^.NextAddress := slotID;

    xhci_port_reset := true;
    pop_trace;
end;

{ ========================= Stage 6: Submit & Poll ========================= }

{ Get the transfer ring for a given slot and DCI }
function xhci_get_ep_ring(priv : PXHCI_PrivData; slotID : uint8; dci : uint8) : PXHCI_Ring;
begin
    xhci_get_ep_ring := nil;
    if (priv = nil) or (slotID = 0) or (slotID > priv^.MaxSlots) then exit;
    if (dci = 0) or (dci > 31) then exit;
    xhci_get_ep_ring := PXHCI_Ring(
        PUint32(uint32(priv^.SlotEPRings) + (uint32(slotID - 1) * 32 + uint32(dci)) * 4)^
    );
end;

{ Get EP0 transfer ring (convenience wrapper, DCI=1) }
function xhci_get_ep0_ring(priv : PXHCI_PrivData; slotID : uint8) : PXHCI_Ring;
begin
    xhci_get_ep0_ring := xhci_get_ep_ring(priv, slotID, 1);
end;

{ Store a transfer ring pointer for a given slot and DCI }
procedure xhci_set_ep_ring(priv : PXHCI_PrivData; slotID : uint8; dci : uint8; ring : PXHCI_Ring);
begin
    if (priv = nil) or (slotID = 0) or (slotID > priv^.MaxSlots) then exit;
    if (dci = 0) or (dci > 31) then exit;
    PUint32(uint32(priv^.SlotEPRings) + (uint32(slotID - 1) * 32 + uint32(dci)) * 4)^ := uint32(ring);
end;

{ Map endpoint pipe type + direction to driver.bus.usb.xhci Endpoint Context Type value }
function xhci_ep_ctx_type(pipeType : TUSBPipeType; isIn : boolean) : uint8;
begin
    case pipeType of
        ptControl:     xhci_ep_ctx_type := XHCI_EP_TYPE_CONTROL;
        ptIsochronous: begin
            if isIn then xhci_ep_ctx_type := XHCI_EP_TYPE_ISOCH_IN
            else         xhci_ep_ctx_type := XHCI_EP_TYPE_ISOCH_OUT;
        end;
        ptBulk: begin
            if isIn then xhci_ep_ctx_type := XHCI_EP_TYPE_BULK_IN
            else         xhci_ep_ctx_type := XHCI_EP_TYPE_BULK_OUT;
        end;
        ptInterrupt: begin
            if isIn then xhci_ep_ctx_type := XHCI_EP_TYPE_INTR_IN
            else         xhci_ep_ctx_type := XHCI_EP_TYPE_INTR_OUT;
        end;
    else
        xhci_ep_ctx_type := XHCI_EP_TYPE_NOT_VALID;
    end;
end;

{ Configure an endpoint on a slot. Allocates a transfer ring, builds an
  Input Context with the endpoint context, issues Configure Endpoint command.
  Returns the PXHCI_Ring on success, nil on failure. }
function xhci_configure_endpoint(hc : PUSBHCDriver;
                                 slotID : uint8;
                                 ep : PUSBEndpoint) : PXHCI_Ring;
var
    priv       : PXHCI_PrivData;
    dci        : uint8;
    epIsIn     : boolean;
    ring       : PXHCI_Ring;
    ringPhys   : uint32;
    inputCtx   : Pointer;
    icc        : PXHCI_InputCtrlCtx;
    slotCtx    : PXHCI_SlotCtx;
    epCtx      : PXHCI_EPCtx;
    cmdTRB     : TXHCI_TRB;
    cc         : uint8;
    epType     : uint8;
    maxCtxEntries : uint32;
    interval   : uint32;
    speed      : uint8;
begin
    push_trace('driver.bus.usb.xhci.xhci_configure_endpoint');
    xhci_configure_endpoint := nil;
    if (hc = nil) or (hc^.PrivData = nil) or (ep = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PXHCI_PrivData(hc^.PrivData);

    epIsIn := (ep^.Direction = driver.bus.usb.types.dirIn);
    dci := xhci_ep_to_dci(ep^.Address, epIsIn);

    { Allocate transfer ring }
    ring := PXHCI_Ring(kalloc(sizeof(TXHCI_Ring)));
    if ring = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to alloc EP ring descriptor!');
        pop_trace;
        exit;
    end;
    ring^ := xhci_alloc_ring(XHCI_TRANSFER_RING_SIZE);
    if ring^.Base = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to alloc EP ring buffer!');
        kfree(void(ring));
        pop_trace;
        exit;
    end;
    ringPhys := vtop(uint32(ring^.Base));

    { Build Input Context: ICC + Slot Ctx + EP Ctx }
    inputCtx := xhci_alloc_ctx(uint32(priv^.CtxSize) * 33);
    if inputCtx = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'Failed to alloc input ctx for Configure EP!');
        xhci_free_ring(ring^);
        kfree(void(ring));
        pop_trace;
        exit;
    end;

    { Input Control Context: Add Slot (A0) and this EP (Adci) }
    icc := PXHCI_InputCtrlCtx(inputCtx);
    icc^.DropFlags := 0;
    icc^.AddFlags := (uint32(1) SHL 0) OR (uint32(1) SHL dci);  { A0 + Adci }

    { Slot Context: must update Context Entries to cover this DCI }
    slotCtx := PXHCI_SlotCtx(uint32(inputCtx) + uint32(priv^.CtxSize));
    { Read existing slot context from output context to get speed/port }
    speed := PUint8(uint32(priv^.SlotSpeed) + uint32(slotID - 1))^;
    maxCtxEntries := uint32(dci);  { Context Entries = highest DCI }
    slotCtx^.Field0 :=
        (xhci_slot_speed(speed) SHL XHCI_SLOT_SPEED_SHIFT) OR
        (maxCtxEntries SHL XHCI_SLOT_CTX_ENTRIES_SHIFT);
    slotCtx^.Field1 :=
        (uint32(PUint8(uint32(priv^.SlotPort) + uint32(slotID - 1))^ + 1) SHL XHCI_SLOT_RHP_SHIFT);

    { Endpoint Context at offset CtxSize * (dci + 1) — ICC is ctx 0, slot is ctx 1,
      EP contexts start at ctx 2 (DCI 1). Offset = CtxSize * (1 + dci). }
    epCtx := PXHCI_EPCtx(uint32(inputCtx) + uint32(priv^.CtxSize) * uint32(1 + dci));

    epType := xhci_ep_ctx_type(ep^.PipeType, epIsIn);

    { Compute interval: for interrupt endpoints, driver.bus.usb.xhci uses 2^(interval-1) * 125us frames.
      driver.bus.usb boot driver.hid.keyboard typically has bInterval=10 (ms). For HS, interval field = bInterval.
      For LS/FS interrupt, convert ms to 125us frames: interval = bInterval * 8,
      then express as log2. We'll use a simple mapping. }
    if (ep^.PipeType = ptInterrupt) then begin
        if (speed = USB_SPEED_HIGH) or (speed = USB_SPEED_SUPER) then begin
            { HS/SS: interval = bInterval (already log2-based) }
            interval := uint32(ep^.Interval);
            if interval > 15 then interval := 15;
        end else begin
            { LS/FS: bInterval is in ms. Convert: 2^(interval-1) = bInterval * 8 frames.
              Approximate: interval ~= ceil(log2(bInterval * 8)) + 1, but for simplicity
              use a fixed value of 6 (= 32 frames = 4ms) which works for most HID devices. }
            if ep^.Interval <= 1 then
                interval := 3  { 1ms }
            else if ep^.Interval <= 4 then
                interval := 5  { ~4ms }
            else if ep^.Interval <= 8 then
                interval := 6  { ~8ms }
            else
                interval := 7; { ~16ms }
        end;
    end else
        interval := 0;

    epCtx^.Field0 := (interval SHL XHCI_EP_INTERVAL_SHIFT);
    epCtx^.Field1 :=
        (uint32(3) SHL XHCI_EP_CERR_SHIFT) OR
        (uint32(epType) SHL XHCI_EP_TYPE_SHIFT) OR
        (uint32(ep^.MaxPacket) SHL XHCI_EP_MAXPACKET_SHIFT);
    epCtx^.TRDeqLo := ringPhys OR 1;  { DCS = 1 }
    epCtx^.TRDeqHi := 0;
    { Average TRB Length: for interrupt, use MaxPacket; for bulk, use 3KB }
    if ep^.PipeType = ptInterrupt then
        epCtx^.Field4 := ep^.MaxPacket
    else
        epCtx^.Field4 := 3072;

    { Issue Configure Endpoint command }
    cmdTRB := xhci_make_trb(
        vtop(uint32(inputCtx)),
        0,
        0,
        (XHCI_TRB_CONFIG_EP SHL XHCI_TRB_TYPE_SHIFT) OR
        (uint32(slotID) SHL 24)
    );
    xhci_send_command(priv, @cmdTRB);
    cc := xhci_wait_command(priv, 500000);

    xhci_free_ctx(inputCtx);

    if cc <> XHCI_CC_SUCCESS then begin
        io.syslog.log('driver.bus.usb.xhci', 'Configure Endpoint failed, cc=');
        io.syslog.writeintln(cc);
        xhci_free_ring(ring^);
        kfree(void(ring));
        pop_trace;
        exit;
    end;

    { Store the ring }
    xhci_set_ep_ring(priv, slotID, dci, ring);

    io.syslog.log('driver.bus.usb.xhci', 'Configured EP DCI=');
    io.syslog.writeint(dci);
    io.syslog.writestring(' slot=');
    io.syslog.writeintln(slotID);

    xhci_configure_endpoint := ring;
    pop_trace;
end;

{ Add a pending transfer to track for completion }
procedure xhci_add_pending(priv : PXHCI_PrivData; transfer : PUSBTransfer; slotID, epID : uint8);
var
    pend : PXHCI_PendingTransfer;
begin
    if (priv = nil) or (priv^.PendingList = nil) then exit;
    pend := PXHCI_PendingTransfer(LL_Add(priv^.PendingList));
    if pend <> nil then begin
        pend^.Transfer := transfer;
        pend^.SlotID := slotID;
        pend^.EPID := epID;
    end;
end;

{ Map driver.bus.usb.xhci completion code to driver.bus.usb transfer status }
function xhci_cc_to_status(cc : uint8) : TUSBTransferStatus;
begin
    case cc of
        XHCI_CC_SUCCESS:           xhci_cc_to_status := tsSuccess;
        XHCI_CC_SHORT_PACKET:      xhci_cc_to_status := tsSuccess; { Short packet is OK for IN }
        XHCI_CC_STALL:             xhci_cc_to_status := tsStall;
        XHCI_CC_BABBLE:            xhci_cc_to_status := tsBabble;
        XHCI_CC_DATA_BUFFER_ERROR: xhci_cc_to_status := tsDataBufferError;
        XHCI_CC_USB_TRANSACTION:   xhci_cc_to_status := tsCRCError;
        XHCI_CC_TRB_ERROR:         xhci_cc_to_status := tsDataBufferError;
    else
        xhci_cc_to_status := tsTimeout;
    end;
end;

{ Submit a control transfer }
function xhci_submit_control(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var
    priv     : PXHCI_PrivData;
    slotID   : uint8;
    ring     : PXHCI_Ring;
    trb      : TXHCI_TRB;
    setupLo  : uint32;
    setupHi  : uint32;
    trt      : uint32;
    dir      : uint32;
    bufPhys  : uint32;
begin
    push_trace('driver.bus.usb.xhci.xhci_submit_control');
    xhci_submit_control := false;
    priv := PXHCI_PrivData(hc^.PrivData);

    { ---- Intercept SET_ADDRESS ---- }
    if transfer^.Setup.bRequest = USB_REQ_SET_ADDRESS then begin
        transfer^.Status := tsSuccess;
        transfer^.ActualLen := 0;
        xhci_submit_control := true;
        pop_trace;
        exit;
    end;

    { Look up slot ID from device address }
    slotID := transfer^.Device^.Address;
    if slotID = 0 then begin
        { Device at address 0 — this is the initial 8-byte GET_DESCRIPTOR before SET_ADDRESS.
          For driver.bus.usb.xhci, the device was already addressed in port_reset. The driver.bus.usb.core calls
          with address 0 first, but we already set NextAddress = slotID, so after
          the first GET_DESCRIPTOR, driver.bus.usb.core sets the address = slotID via SET_ADDRESS.
          We need to use the slot ID that was just assigned. Find it from NextAddress. }
        slotID := hc^.NextAddress;
        if slotID = 0 then begin
            io.syslog.logln('driver.bus.usb.xhci', 'No slot for address-0 device!');
            pop_trace;
            exit;
        end;
    end;

    ring := xhci_get_ep0_ring(priv, slotID);
    if ring = nil then begin
        io.syslog.logln('driver.bus.usb.xhci', 'No EP0 ring for slot!');
        pop_trace;
        exit;
    end;

    { ---- Setup Stage TRB ---- }
    { Pack 8-byte setup packet into Param0 and Param1 }
    setupLo := uint32(transfer^.Setup.bmRequestType) OR
               (uint32(transfer^.Setup.bRequest) SHL 8) OR
               (uint32(transfer^.Setup.wValue) SHL 16);
    setupHi := uint32(transfer^.Setup.wIndex) OR
               (uint32(transfer^.Setup.wLength) SHL 16);

    { Determine Transfer Type for Setup Stage }
    if transfer^.BufferLen = 0 then
        trt := XHCI_TRB_TRT_NONE
    else if (transfer^.Setup.bmRequestType AND $80) <> 0 then
        trt := XHCI_TRB_TRT_IN
    else
        trt := XHCI_TRB_TRT_OUT;

    trb := xhci_make_trb(
        setupLo, setupHi,
        8,  { TRB Transfer Length = 8 (setup packet) }
        (XHCI_TRB_SETUP_STAGE SHL XHCI_TRB_TYPE_SHIFT) OR XHCI_TRB_IDT OR trt
    );
    xhci_ring_enqueue(ring, @trb);

    { ---- Data Stage TRB (if there's data) ---- }
    if transfer^.BufferLen > 0 then begin
        bufPhys := vtop(uint32(transfer^.Buffer));
        if (transfer^.Setup.bmRequestType AND $80) <> 0 then
            dir := XHCI_TRB_DIR_IN
        else
            dir := XHCI_TRB_DIR_OUT;

        trb := xhci_make_trb(
            bufPhys, 0,
            transfer^.BufferLen,
            (XHCI_TRB_DATA_STAGE SHL XHCI_TRB_TYPE_SHIFT) OR dir
        );
        xhci_ring_enqueue(ring, @trb);
    end;

    { ---- Status Stage TRB ---- }
    { Direction is opposite to data stage, or IN if no data }
    if transfer^.BufferLen = 0 then
        dir := XHCI_TRB_DIR_IN
    else if (transfer^.Setup.bmRequestType AND $80) <> 0 then
        dir := XHCI_TRB_DIR_OUT
    else
        dir := XHCI_TRB_DIR_IN;

    trb := xhci_make_trb(
        0, 0, 0,
        (XHCI_TRB_STATUS_STAGE SHL XHCI_TRB_TYPE_SHIFT) OR XHCI_TRB_IOC OR dir
    );
    xhci_ring_enqueue(ring, @trb);

    { Set status and track pending BEFORE ringing doorbell to avoid ISR race }
    transfer^.Status := tsInProgress;
    transfer^.HCPriv := Pointer(uint32(slotID));
    xhci_add_pending(priv, transfer, slotID, 1);

    { Ring the doorbell: slot=slotID, target=1 (EP 0 = DCI 1) }
    xhci_ring_doorbell(priv, uint32(slotID), 1);

    xhci_submit_control := true;
    pop_trace;
end;

{ Submit a bulk or interrupt transfer }
function xhci_submit_bulk_intr(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var
    priv    : PXHCI_PrivData;
    slotID  : uint8;
    epNum   : uint8;
    epIsIn  : boolean;
    dci     : uint8;
    ring    : PXHCI_Ring;
    trb     : TXHCI_TRB;
    bufPhys : uint32;
begin
    push_trace('driver.bus.usb.xhci.xhci_submit_bulk_intr');
    xhci_submit_bulk_intr := false;
    priv := PXHCI_PrivData(hc^.PrivData);

    slotID := transfer^.Device^.Address;
    if (slotID = 0) or (slotID > priv^.MaxSlots) then begin
        pop_trace;
        exit;
    end;

    epNum := transfer^.Endpoint^.Address;
    epIsIn := (transfer^.Direction = driver.bus.usb.types.dirIn);
    dci := xhci_ep_to_dci(epNum, epIsIn);

    { Look up per-endpoint transfer ring; configure endpoint lazily if needed }
    ring := xhci_get_ep_ring(priv, slotID, dci);
    if ring = nil then begin
        ring := xhci_configure_endpoint(hc, slotID, transfer^.Endpoint);
        if ring = nil then begin
            io.syslog.logln('driver.bus.usb.xhci', 'Failed to configure EP for bulk/intr!');
            pop_trace;
            exit;
        end;
    end;

    bufPhys := vtop(uint32(transfer^.Buffer));

    { Normal TRB }
    trb := xhci_make_trb(
        bufPhys, 0,
        transfer^.BufferLen,
        (XHCI_TRB_NORMAL SHL XHCI_TRB_TYPE_SHIFT) OR XHCI_TRB_IOC
    );
    xhci_ring_enqueue(ring, @trb);

    { Set status and track pending BEFORE ringing doorbell to avoid ISR race }
    transfer^.Status := tsInProgress;
    transfer^.HCPriv := Pointer(uint32(slotID));
    xhci_add_pending(priv, transfer, slotID, dci);

    { Ring doorbell: target = DCI }
    xhci_ring_doorbell(priv, uint32(slotID), uint32(dci));

    xhci_submit_bulk_intr := true;
    pop_trace;
end;

function xhci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
begin
    push_trace('driver.bus.usb.xhci.xhci_submit');
    xhci_submit := false;
    if (hc = nil) or (transfer = nil) or (transfer^.Device = nil) then begin
        pop_trace;
        exit;
    end;

    case transfer^.PipeType of
        ptControl:
            xhci_submit := xhci_submit_control(hc, transfer);
        ptBulk, ptInterrupt:
            xhci_submit := xhci_submit_bulk_intr(hc, transfer);
    else
        io.syslog.logln('driver.bus.usb.xhci', 'Unsupported pipe type for submit.');
    end;
    pop_trace;
end;

{ ========================= Interrupt-Driven Completion ========================= }

const
    XHCI_MAX_INSTANCES = 4;

var
    XHCIInstances     : array[0..XHCI_MAX_INSTANCES-1] of PUSBHCDriver;
    XHCIInstanceCount : uint32;

{ ISR handler — registered on the driver.bus.pci interrupt line.
  Checks each driver.bus.usb.xhci instance for pending events, processes completions,
  then fires driver.bus.usb completion hooks (driver.hid.keyboard, driver.hid.mouse, etc.). }
procedure xhci_isr;
var
    i      : uint32;
    hc     : PUSBHCDriver;
    priv   : PXHCI_PrivData;
    usbsts : uint32;
    irBase : uint32;
begin
    for i := 0 to XHCIInstanceCount - 1 do begin
        hc := XHCIInstances[i];
        if hc = nil then continue;
        priv := PXHCI_PrivData(hc^.PrivData);
        if priv = nil then continue;

        { Check if this controller raised the interrupt }
        usbsts := xhci_readl(priv^.OpBase, XHCI_OP_USBSTS);
        if (usbsts AND XHCI_STS_EINT) = 0 then continue;

        { Acknowledge: clear EINT in USBSTS (write-1-to-clear) }
        xhci_writel(priv^.OpBase, XHCI_OP_USBSTS, XHCI_STS_EINT);

        { Process events (dequeues from event ring, advances ERDP) }
        xhci_poll(hc);

        { Clear IMAN IP to re-arm interrupter (write-1-to-clear IP, preserve IE) }
        irBase := priv^.RTBase + XHCI_RT_IR0_BASE;
        xhci_writel(irBase, XHCI_IR_IMAN, XHCI_IMAN_IP OR XHCI_IMAN_IE);
    end;
    driver.bus.usb.core.fire_completion_hooks;
end;

{ Enable hardware interrupts on the controller: set IMAN IE + INTE.
  Must be called AFTER the ISR is registered with isrmanager. }
procedure xhci_enable_interrupts(hc : PUSBHCDriver);
var
    priv   : PXHCI_PrivData;
    irBase : uint32;
    cmd    : uint32;
begin
    if (hc = nil) or (hc^.PrivData = nil) then exit;
    priv := PXHCI_PrivData(hc^.PrivData);
    irBase := priv^.RTBase + XHCI_RT_IR0_BASE;

    { Enable Interrupter 0: set IE in IMAN }
    xhci_writel(irBase, XHCI_IR_IMAN, XHCI_IMAN_IE);

    { Enable INTE in USBCMD (global interrupt enable) }
    cmd := xhci_readl(priv^.OpBase, XHCI_OP_USBCMD);
    cmd := cmd OR XHCI_CMD_INTE;
    xhci_writel(priv^.OpBase, XHCI_OP_USBCMD, cmd);

    io.syslog.logln('driver.bus.usb.xhci', 'Hardware interrupts enabled.');
end;

{ ========================= Poll ========================= }

procedure xhci_poll(hc : PUSBHCDriver);
var
    priv      : PXHCI_PrivData;
    evt       : TXHCI_TRB;
    trbType   : uint32;
    cc        : uint8;
    slotID    : uint8;
    epID      : uint8;
    xferLen   : uint32;
    i         : uint32;
    pend      : PXHCI_PendingTransfer;
    transfer  : PUSBTransfer;
    processed : boolean;
    hpPortId  : uint8;
    hpPortSC  : uint32;
begin
    if (hc = nil) or (hc^.PrivData = nil) then exit;
    priv := PXHCI_PrivData(hc^.PrivData);

    { Re-entrancy guard: if inline code is already inside poll,
      the ISR must not re-enter. The inline poll will process events. }
    if priv^.PollBusy then exit;
    priv^.PollBusy := true;

    processed := false;

    while xhci_event_dequeue(priv, evt) do begin
        processed := true;
        trbType := (evt.Control AND XHCI_TRB_TYPE_MASK) SHR XHCI_TRB_TYPE_SHIFT;
        cc := uint8((evt.Status AND XHCI_CC_MASK) SHR XHCI_CC_SHIFT);

        case trbType of
            XHCI_TRB_TRANSFER_EVENT: begin
                { Extract slot ID (bits 31:24 of Control) and endpoint ID (bits 20:16) }
                slotID := uint8((evt.Control SHR 24) AND $FF);
                epID := uint8((evt.Control SHR 16) AND $1F);
                xferLen := evt.Status AND $00FFFFFF;

                { Find matching pending transfer }
                if priv^.PendingList <> nil then begin
                    for i := 0 to LL_Size(priv^.PendingList) - 1 do begin
                        pend := PXHCI_PendingTransfer(LL_Get(priv^.PendingList, i));
                        if (pend <> nil) and (pend^.Transfer <> nil) and
                           (pend^.SlotID = slotID) and (pend^.EPID = epID) then begin
                            transfer := pend^.Transfer;
                            transfer^.Status := xhci_cc_to_status(cc);
                            if (cc = XHCI_CC_SUCCESS) or (cc = XHCI_CC_SHORT_PACKET) then begin
                                { xferLen in Transfer Event is residual (remaining bytes) }
                                if xferLen <= transfer^.BufferLen then
                                    transfer^.ActualLen := transfer^.BufferLen - xferLen
                                else
                                    transfer^.ActualLen := transfer^.BufferLen;
                            end else
                                transfer^.ActualLen := 0;
                            LL_Delete(priv^.PendingList, i);
                            break;
                        end;
                    end;
                end;
            end;

            XHCI_TRB_CMD_COMPLETION: begin
                { Update blocking command waiter state }
                priv^.CmdComplete := true;
                priv^.CmdResultCode := cc;
                priv^.CmdSlotID := uint8((evt.Control SHR 24) AND $FF);
            end;

            XHCI_TRB_PORT_STATUS_CHG: begin
                { Port ID in bits 31:24 of Param0 (1-based) }
                hpPortId := uint8((evt.Param0 SHR 24) AND $FF);
                io.syslog.log('driver.bus.usb.xhci', 'Port Status Change: port ');
                io.syslog.writeintln(hpPortId);
                if hpPortId > 0 then begin
                    { Acknowledge port status change by writing W1C bits }
                    hpPortSC := xhci_readl(priv^.OpBase, XHCI_OP_PORTSC_BASE + ((hpPortId - 1) * $10));
                    xhci_writel(priv^.OpBase, XHCI_OP_PORTSC_BASE + ((hpPortId - 1) * $10),
                        (hpPortSC AND $0E00C3E0) OR $00FE0000);
                    { Flag for deferred hotplug processing }
                    if hc^.HotplugArmed then
                        hc^.PortChangePending := true;
                end;
            end;
        end;
    end;

    if processed then
        xhci_advance_erdp(priv);

    priv^.PollBusy := false;
end;

{ ========================= Stage 7: Load ========================= }

function load : boolean;
var
    devices  : TDeviceArray;
    count    : uint32;
    i        : uint32;
    priv     : PXHCI_PrivData;
    hc       : TUSBHCDriver;
    hcEntry  : PUSBHCDriver;
    mmioBase : uint32;
    block    : uint32;
    capLen   : uint8;
    hciver   : uint16;
    hcsparams1 : uint32;
    hcsparams2 : uint32;
    hccparams1 : uint32;
    dboff    : uint32;
    rtsoff   : uint32;
begin
    push_trace('driver.bus.usb.xhci.load');
    load := false;
    XHCIInstanceCount := 0;

    devices := driver.bus.pci.getDeviceInfo($0C, $03, $30, count);
    io.syslog.log('driver.bus.usb.xhci', 'Found ');
    io.syslog.writeint(count);
    io.syslog.writestringln(' driver.bus.usb.xhci controller(s).');

    if count = 0 then begin
        load := true;
        pop_trace;
        exit;
    end;

    for i := 0 to count - 1 do begin
        io.syslog.log('driver.bus.usb.xhci', 'Controller[');
        io.syslog.writeint(i);
        io.syslog.writestring(']: VID=');
        io.syslog.writehex(devices[i].vendor_id);
        io.syslog.writestring(' DID=');
        io.syslog.writehex(devices[i].device_id);
        io.syslog.writestring(' BAR0=');
        io.syslog.writehexln(devices[i].address0);

        { Read BAR0 — mask lower 4 bits (memory-mapped indicator/type bits) }
        mmioBase := devices[i].address0 AND $FFFFFFF0;
        if mmioBase = 0 then begin
            io.syslog.logln('driver.bus.usb.xhci', 'Invalid MMIO base (BAR0=0), skipping.');
            continue;
        end;

        { Map the MMIO region into identity-mapped address space }
        block := mmioBase SHR 22;
        force_alloc_block(block, 0);
        map_page(block, block);

        { Also map the next 4MB block in case registers span the boundary }
        force_alloc_block(block + 1, 0);
        map_page(block + 1, block + 1);

        { Enable bus mastering for DMA }
        driver.bus.pci.setBusMaster(devices[i].bus, devices[i].slot, devices[i].func, true);

        { Read capability registers }
        capLen := xhci_readb(mmioBase, XHCI_CAP_CAPLENGTH);
        hciver := xhci_readw(mmioBase, XHCI_CAP_HCIVERSION);
        hcsparams1 := xhci_readl(mmioBase, XHCI_CAP_HCSPARAMS1);
        hcsparams2 := xhci_readl(mmioBase, XHCI_CAP_HCSPARAMS2);
        hccparams1 := xhci_readl(mmioBase, XHCI_CAP_HCCPARAMS1);
        dboff := xhci_readl(mmioBase, XHCI_CAP_DBOFF) AND $FFFFFFFC;
        rtsoff := xhci_readl(mmioBase, XHCI_CAP_RTSOFF) AND $FFFFFFE0;

        io.syslog.log('driver.bus.usb.xhci', 'HCI Version: ');
        io.syslog.writehexln(hciver);
        io.syslog.log('driver.bus.usb.xhci', 'CAPLENGTH=');
        io.syslog.writehex(capLen);
        io.syslog.writestring(' HCSPARAMS1=');
        io.syslog.writehex(hcsparams1);
        io.syslog.writestring(' HCSPARAMS2=');
        io.syslog.writehex(hcsparams2);
        io.syslog.writestring(' HCCPARAMS1=');
        io.syslog.writehexln(hccparams1);
        io.syslog.log('driver.bus.usb.xhci', 'DBOFF=');
        io.syslog.writehex(dboff);
        io.syslog.writestring(' RTSOFF=');
        io.syslog.writehexln(rtsoff);

        { Allocate private data }
        priv := PXHCI_PrivData(kalloc(sizeof(TXHCI_PrivData)));
        if priv = nil then begin
            io.syslog.logln('driver.bus.usb.xhci', 'Failed to allocate private data!');
            continue;
        end;
        memset(uint32(priv), 0, sizeof(TXHCI_PrivData));

        priv^.MMIOBase   := mmioBase;
        priv^.OpBase     := mmioBase + capLen;
        priv^.RTBase     := mmioBase + rtsoff;
        priv^.DBBase     := mmioBase + dboff;
        priv^.HCSPARAMS1 := hcsparams1;
        priv^.HCSPARAMS2 := hcsparams2;
        priv^.HCCPARAMS1 := hccparams1;
        priv^.MaxSlots   := uint8(hcsparams1 AND XHCI_HCS1_MAXSLOTS_MASK);
        priv^.MaxIntrs   := uint16((hcsparams1 AND XHCI_HCS1_MAXINTRS_MASK) SHR XHCI_HCS1_MAXINTRS_SHIFT);
        priv^.MaxPorts   := uint8((hcsparams1 AND XHCI_HCS1_MAXPORTS_MASK) SHR XHCI_HCS1_MAXPORTS_SHIFT);
        priv^.CtxSize    := xhci_context_entry_size(hccparams1);
        priv^.PCIBus     := devices[i].bus;
        priv^.PCISlot    := devices[i].slot;
        priv^.PCIFunc    := devices[i].func;

        { Cap MaxSlots to our limit }
        if priv^.MaxSlots > XHCI_MAX_SLOTS then
            priv^.MaxSlots := XHCI_MAX_SLOTS;

        io.syslog.log('driver.bus.usb.xhci', 'MaxSlots=');
        io.syslog.writeint(priv^.MaxSlots);
        io.syslog.writestring(' MaxPorts=');
        io.syslog.writeint(priv^.MaxPorts);
        io.syslog.writestring(' CtxSize=');
        io.syslog.writeintln(priv^.CtxSize);

        { BIOS handoff }
        xhci_bios_handoff(priv, devices[i]);

        { Set up HC driver record }
        usb_hc_init_record(@hc);
        hc.Name         := 'driver.bus.usb.xhci';
        hc.HCType       := USB_HC_XHCI;
        hc.NumPorts     := priv^.MaxPorts;
        hc.PCIDev       := devices[i];
        hc.BaseAddr     := mmioBase;
        hc.PrivData     := Pointer(priv);
        hc.Devices      := LL_New(sizeof(TUSBDevice));
        hc.NextAddress  := 1;
        hc.fnReset      := TUSBHCReset(@xhci_reset);
        hc.fnStart      := TUSBHCStart(@xhci_start);
        hc.fnStop       := TUSBHCStop(@xhci_stop);
        hc.fnSubmit     := TUSBHCSubmit(@xhci_submit);
        hc.fnPoll       := TUSBHCPoll(@xhci_poll);
        hc.fnPortReset  := TUSBHCPortReset(@xhci_port_reset);
        hc.fnPortStatus := TUSBHCPortStatus(@xhci_port_status);

        { Reset the controller }
        if not xhci_reset(@hc) then begin
            io.syslog.logln('driver.bus.usb.xhci', 'Reset failed, skipping controller.');
            kfree(void(priv));
            continue;
        end;

        { Start the controller }
        if not xhci_start(@hc) then begin
            io.syslog.logln('driver.bus.usb.xhci', 'Start failed, skipping controller.');
            kfree(void(priv));
            continue;
        end;

        { Register with driver.bus.usb core and scan ports }
        hcEntry := driver.bus.usb.core.register_hc(@hc);

        if hcEntry <> nil then begin
            { Track instance for ISR dispatch }
            if XHCIInstanceCount < XHCI_MAX_INSTANCES then begin
                XHCIInstances[XHCIInstanceCount] := hcEntry;
                inc(XHCIInstanceCount);
            end;

            { Register ISR on driver.bus.pci interrupt line (must happen BEFORE enabling HW interrupts) }
            io.syslog.log('driver.bus.usb.xhci', 'Registering ISR on IRQ ');
            io.syslog.writeintln(devices[i].interrupt_line);
            arch.x86.isr.mgr.registerISR(32 + devices[i].interrupt_line, @xhci_isr);

            { Now safe to enable hardware interrupts }
            xhci_enable_interrupts(hcEntry);

            { Scan for connected devices }
            driver.bus.usb.core.scan_ports(hcEntry);
        end else
            io.syslog.logln('driver.bus.usb.xhci', 'Failed to register HC with driver.bus.usb core.');

        io.syslog.logln('driver.bus.usb.xhci', 'Controller initialized and registered.');
    end;

    load := true;
    pop_trace;
end;

{ ========================= Unit Tests ========================= }

procedure UnitTest;
var
    passed, failed : uint32;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            io.syslog.logln('driver.bus.usb.xhci', msg);
            kfree(void(msg));
        end;
    end;

    procedure PrintSummary;
    var
        pStr, fStr, msg, tmp : pchar;
    begin
        pStr := intToString(passed);
        fStr := intToString(failed);
        msg := stringConcat(pStr, ' passed, ');
        tmp := stringConcat(msg, fStr);
        kfree(void(msg));
        msg := stringConcat(tmp, ' failed.');
        kfree(void(tmp));
        io.syslog.logln('driver.bus.usb.xhci', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

var
    trb  : TXHCI_TRB;
    ring : TXHCI_Ring;
    dest : PXHCI_TRB;
begin
    passed := 0;
    failed := 0;
    io.syslog.logln('driver.bus.usb.xhci', 'Unit tests starting...');

    { === Structure Size Tests === }
    Assert(sizeof(TXHCI_TRB) = 16, 'sizeof TRB=16');
    Assert(sizeof(TXHCI_SlotCtx) = 32, 'sizeof SlotCtx=32');
    Assert(sizeof(TXHCI_EPCtx) = 32, 'sizeof EPCtx=32');
    Assert(sizeof(TXHCI_InputCtrlCtx) = 32, 'sizeof InputCtrlCtx=32');
    Assert(sizeof(TXHCI_ERSTE) = 16, 'sizeof ERSTE=16');

    { === TRB Construction === }
    trb := xhci_make_trb($12345678, $9ABCDEF0, $AABB0000, $CC00DD00);
    Assert(trb.Param0 = $12345678, 'trb Param0');
    Assert(trb.Param1 = $9ABCDEF0, 'trb Param1');
    Assert(trb.Status = $AABB0000, 'trb Status');
    Assert(trb.Control = $CC00DD00, 'trb Control');

    { TRB type encoding }
    trb := xhci_make_trb(0, 0, 0, XHCI_TRB_ENABLE_SLOT SHL XHCI_TRB_TYPE_SHIFT);
    Assert((trb.Control AND XHCI_TRB_TYPE_MASK) SHR XHCI_TRB_TYPE_SHIFT = XHCI_TRB_ENABLE_SLOT,
           'TRB type ENABLE_SLOT');

    trb := xhci_make_trb(0, 0, 0, XHCI_TRB_ADDRESS_DEVICE SHL XHCI_TRB_TYPE_SHIFT);
    Assert((trb.Control AND XHCI_TRB_TYPE_MASK) SHR XHCI_TRB_TYPE_SHIFT = XHCI_TRB_ADDRESS_DEVICE,
           'TRB type ADDRESS_DEVICE');

    trb := xhci_make_trb(0, 0, 0, XHCI_TRB_SETUP_STAGE SHL XHCI_TRB_TYPE_SHIFT);
    Assert((trb.Control AND XHCI_TRB_TYPE_MASK) SHR XHCI_TRB_TYPE_SHIFT = XHCI_TRB_SETUP_STAGE,
           'TRB type SETUP_STAGE');

    trb := xhci_make_trb(0, 0, 0, XHCI_TRB_LINK SHL XHCI_TRB_TYPE_SHIFT);
    Assert((trb.Control AND XHCI_TRB_TYPE_MASK) SHR XHCI_TRB_TYPE_SHIFT = XHCI_TRB_LINK,
           'TRB type LINK');

    { === TRB Flag Tests === }
    Assert(XHCI_TRB_CYCLE = $01, 'TRB_CYCLE=$01');
    Assert(XHCI_TRB_IOC = $20, 'TRB_IOC=$20');
    Assert(XHCI_TRB_IDT = $40, 'TRB_IDT=$40');
    Assert(XHCI_TRB_CH = $10, 'TRB_CH=$10');

    { === Completion Code Tests === }
    Assert(xhci_cc_to_status(XHCI_CC_SUCCESS) = tsSuccess, 'cc SUCCESS->tsSuccess');
    Assert(xhci_cc_to_status(XHCI_CC_SHORT_PACKET) = tsSuccess, 'cc SHORT_PACKET->tsSuccess');
    Assert(xhci_cc_to_status(XHCI_CC_STALL) = tsStall, 'cc STALL->tsStall');
    Assert(xhci_cc_to_status(XHCI_CC_BABBLE) = tsBabble, 'cc BABBLE->tsBabble');
    Assert(xhci_cc_to_status(XHCI_CC_DATA_BUFFER_ERROR) = tsDataBufferError, 'cc DATA_BUF');
    Assert(xhci_cc_to_status(XHCI_CC_USB_TRANSACTION) = tsCRCError, 'cc USB_TRANSACTION');
    Assert(xhci_cc_to_status(XHCI_CC_TRB_ERROR) = tsDataBufferError, 'cc TRB_ERROR');
    Assert(xhci_cc_to_status(0) = tsTimeout, 'cc 0->tsTimeout');

    { === Speed Mapping Tests === }
    Assert(xhci_map_speed(XHCI_SPEED_FULL) = USB_SPEED_FULL, 'speed FULL');
    Assert(xhci_map_speed(XHCI_SPEED_LOW) = USB_SPEED_LOW, 'speed LOW');
    Assert(xhci_map_speed(XHCI_SPEED_HIGH) = USB_SPEED_HIGH, 'speed HIGH');
    Assert(xhci_map_speed(XHCI_SPEED_SUPER) = USB_SPEED_SUPER, 'speed SUPER');
    Assert(xhci_map_speed(0) = USB_SPEED_FULL, 'speed 0->FULL');

    Assert(xhci_slot_speed(USB_SPEED_FULL) = XHCI_SPEED_FULL, 'slot_speed FULL');
    Assert(xhci_slot_speed(USB_SPEED_LOW) = XHCI_SPEED_LOW, 'slot_speed LOW');
    Assert(xhci_slot_speed(USB_SPEED_HIGH) = XHCI_SPEED_HIGH, 'slot_speed HIGH');
    Assert(xhci_slot_speed(USB_SPEED_SUPER) = XHCI_SPEED_SUPER, 'slot_speed SUPER');

    { === DCI Calculation Tests === }
    Assert(xhci_ep_to_dci(0, false) = 1, 'DCI EP0=1');
    Assert(xhci_ep_to_dci(0, true) = 1, 'DCI EP0 IN=1');
    Assert(xhci_ep_to_dci(1, false) = 2, 'DCI EP1 OUT=2');
    Assert(xhci_ep_to_dci(1, true) = 3, 'DCI EP1 IN=3');
    Assert(xhci_ep_to_dci(2, false) = 4, 'DCI EP2 OUT=4');
    Assert(xhci_ep_to_dci(2, true) = 5, 'DCI EP2 IN=5');
    Assert(xhci_ep_to_dci(15, true) = 31, 'DCI EP15 IN=31');

    { === Default Max Packet Tests === }
    Assert(xhci_default_max_packet(USB_SPEED_LOW) = 8, 'maxpkt LOW=8');
    Assert(xhci_default_max_packet(USB_SPEED_FULL) = 8, 'maxpkt FULL=8');
    Assert(xhci_default_max_packet(USB_SPEED_HIGH) = 64, 'maxpkt HIGH=64');
    Assert(xhci_default_max_packet(USB_SPEED_SUPER) = 512, 'maxpkt SUPER=512');

    { === Context Size Tests === }
    Assert(xhci_context_entry_size(0) = 32, 'ctxsize no CSZ=32');
    Assert(xhci_context_entry_size(XHCI_HCC1_CSZ) = 64, 'ctxsize CSZ=64');
    Assert(xhci_context_entry_size($FFFFFFFF) = 64, 'ctxsize all bits=64');

    { === Ring Allocation Tests === }
    ring := xhci_alloc_ring(16);
    Assert(ring.Base <> nil, 'alloc_ring not nil');
    Assert((uint32(ring.Base) AND $FFF) = 0, 'alloc_ring page aligned');
    Assert(ring.Size = 16, 'alloc_ring size=16');
    Assert(ring.Enqueue = 0, 'alloc_ring enqueue=0');
    Assert(ring.CycleBit = 1, 'alloc_ring cycle=1');
    { Check Link TRB at last entry }
    dest := PXHCI_TRB(uint32(ring.Base) + (15 * sizeof(TXHCI_TRB)));
    Assert((dest^.Control AND XHCI_TRB_TYPE_MASK) SHR XHCI_TRB_TYPE_SHIFT = XHCI_TRB_LINK,
           'alloc_ring link TRB at end');
    Assert((dest^.Control AND XHCI_TRB_TC) <> 0, 'alloc_ring link TC bit');
    Assert(dest^.Param0 = vtop(uint32(ring.Base)), 'alloc_ring link->start');
    xhci_free_ring(ring);

    { === Ring Enqueue Tests === }
    ring := xhci_alloc_ring(4); { 3 usable + 1 Link }
    Assert(ring.Enqueue = 0, 'enq initial=0');
    Assert(ring.CycleBit = 1, 'enq initial cycle=1');

    { Enqueue first TRB }
    trb := xhci_make_trb($AA, $BB, $CC, XHCI_TRB_NORMAL SHL XHCI_TRB_TYPE_SHIFT);
    xhci_ring_enqueue(@ring, @trb);
    Assert(ring.Enqueue = 1, 'enq after 1st=1');
    dest := PXHCI_TRB(uint32(ring.Base));
    Assert(dest^.Param0 = $AA, 'enq 1st Param0');
    Assert((dest^.Control AND XHCI_TRB_CYCLE) = 1, 'enq 1st cycle=1');

    { Enqueue second TRB }
    trb := xhci_make_trb($DD, $EE, $FF, XHCI_TRB_NORMAL SHL XHCI_TRB_TYPE_SHIFT);
    xhci_ring_enqueue(@ring, @trb);
    Assert(ring.Enqueue = 2, 'enq after 2nd=2');

    { Enqueue third TRB => hits Link TRB, wraps to 0, toggles cycle }
    trb := xhci_make_trb($11, $22, $33, XHCI_TRB_NORMAL SHL XHCI_TRB_TYPE_SHIFT);
    xhci_ring_enqueue(@ring, @trb);
    Assert(ring.Enqueue = 0, 'enq wrapped to 0');
    Assert(ring.CycleBit = 0, 'enq cycle toggled to 0');

    { Enqueue one more after wrap }
    trb := xhci_make_trb($44, $55, $66, XHCI_TRB_NORMAL SHL XHCI_TRB_TYPE_SHIFT);
    xhci_ring_enqueue(@ring, @trb);
    Assert(ring.Enqueue = 1, 'enq after wrap=1');
    dest := PXHCI_TRB(uint32(ring.Base));
    Assert((dest^.Control AND XHCI_TRB_CYCLE) = 0, 'enq wrap cycle=0');

    xhci_free_ring(ring);

    { === Event Ring Allocation Tests === }
    ring := xhci_alloc_event_ring(32);
    Assert(ring.Base <> nil, 'evt_ring not nil');
    Assert((uint32(ring.Base) AND $FFF) = 0, 'evt_ring page aligned');
    Assert(ring.Size = 32, 'evt_ring size=32');
    Assert(ring.CycleBit = 1, 'evt_ring cycle=1');
    xhci_free_ring(ring);

    { === Register Offset Constant Tests === }
    Assert(XHCI_CAP_CAPLENGTH = $00, 'CAPLENGTH=$00');
    Assert(XHCI_CAP_HCSPARAMS1 = $04, 'HCSPARAMS1=$04');
    Assert(XHCI_CAP_HCSPARAMS2 = $08, 'HCSPARAMS2=$08');
    Assert(XHCI_CAP_HCCPARAMS1 = $10, 'HCCPARAMS1=$10');
    Assert(XHCI_CAP_DBOFF = $14, 'DBOFF=$14');
    Assert(XHCI_CAP_RTSOFF = $18, 'RTSOFF=$18');

    Assert(XHCI_OP_USBCMD = $00, 'OP_USBCMD=$00');
    Assert(XHCI_OP_USBSTS = $04, 'OP_USBSTS=$04');
    Assert(XHCI_OP_CRCR_LO = $18, 'OP_CRCR=$18');
    Assert(XHCI_OP_DCBAAP_LO = $30, 'OP_DCBAAP=$30');
    Assert(XHCI_OP_CONFIG = $38, 'OP_CONFIG=$38');
    Assert(XHCI_OP_PORTSC_BASE = $400, 'PORTSC=$400');

    { === Bit Tests === }
    Assert(XHCI_CMD_RS = $01, 'CMD_RS=$01');
    Assert(XHCI_CMD_HCRST = $02, 'CMD_HCRST=$02');
    Assert(XHCI_CMD_INTE = $04, 'CMD_INTE=$04');
    Assert(XHCI_STS_HCH = $01, 'STS_HCH=$01');
    Assert(XHCI_STS_CNR = $800, 'STS_CNR=$800');
    Assert(XHCI_STS_HSE = $04, 'STS_HSE=$04');

    Assert(XHCI_PORTSC_CCS = $01, 'PORTSC_CCS=$01');
    Assert(XHCI_PORTSC_PED = $02, 'PORTSC_PED=$02');
    Assert(XHCI_PORTSC_PR = $10, 'PORTSC_PR=$10');
    Assert(XHCI_PORTSC_PP = $200, 'PORTSC_PP=$200');
    Assert(XHCI_PORTSC_CSC = $20000, 'PORTSC_CSC');
    Assert(XHCI_PORTSC_PRC = $200000, 'PORTSC_PRC');

    { === TRB Type Constants === }
    Assert(XHCI_TRB_NORMAL = 1, 'TRB_NORMAL=1');
    Assert(XHCI_TRB_SETUP_STAGE = 2, 'TRB_SETUP=2');
    Assert(XHCI_TRB_DATA_STAGE = 3, 'TRB_DATA=3');
    Assert(XHCI_TRB_STATUS_STAGE = 4, 'TRB_STATUS=4');
    Assert(XHCI_TRB_LINK = 6, 'TRB_LINK=6');
    Assert(XHCI_TRB_ENABLE_SLOT = 9, 'ENABLE_SLOT=9');
    Assert(XHCI_TRB_ADDRESS_DEVICE = 11, 'ADDRESS_DEV=11');
    Assert(XHCI_TRB_TRANSFER_EVENT = 32, 'XFER_EVENT=32');
    Assert(XHCI_TRB_CMD_COMPLETION = 33, 'CMD_COMPL=33');
    Assert(XHCI_TRB_PORT_STATUS_CHG = 34, 'PORT_CHG=34');

    { === Completion Code Constants === }
    Assert(XHCI_CC_SUCCESS = 1, 'CC_SUCCESS=1');
    Assert(XHCI_CC_STALL = 6, 'CC_STALL=6');
    Assert(XHCI_CC_SHORT_PACKET = 13, 'CC_SHORT=13');
    Assert(XHCI_CC_NO_SLOTS = 9, 'CC_NO_SLOTS=9');

    { === HCSPARAMS/HCCPARAMS field masks === }
    Assert(XHCI_HCS1_MAXSLOTS_MASK = $FF, 'MAXSLOTS=$FF');
    Assert(XHCI_HCS1_MAXPORTS_SHIFT = 24, 'MAXPORTS_SH=24');
    Assert(XHCI_HCC1_XECP_SHIFT = 16, 'XECP_SH=16');
    Assert(XHCI_HCC1_CSZ = $04, 'CSZ=$04');

    { === EP Type Constants === }
    Assert(XHCI_EP_TYPE_CONTROL = 4, 'EP_CTRL=4');
    Assert(XHCI_EP_TYPE_BULK_IN = 6, 'EP_BULK_IN=6');
    Assert(XHCI_EP_TYPE_BULK_OUT = 2, 'EP_BULK_OUT=2');
    Assert(XHCI_EP_TYPE_INTR_IN = 7, 'EP_INTR_IN=7');
    Assert(XHCI_EP_TYPE_INTR_OUT = 3, 'EP_INTR_OUT=3');

    { === IMAN Tests === }
    Assert(XHCI_IMAN_IP = $01, 'IMAN_IP=$01');
    Assert(XHCI_IMAN_IE = $02, 'IMAN_IE=$02');

    PrintSummary;
end;

end.
