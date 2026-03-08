{
    Driver->Bus->driver.bus.usb->driver.bus.usb.uhci - Universal Host Controller Interface Driver.

    Implements the driver.bus.usb.uhci (driver.bus.usb 1.x) host controller for I/O-port-based controllers.
    driver.bus.usb.uhci uses a 1024-entry frame list, Queue Heads (QH) and Transfer Descriptors (TD).

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.bus.usb.uhci;

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

{ ========================= driver.bus.usb.uhci Register Offsets (from I/O Base) ========================= }

const
    UHCI_REG_USBCMD     = $00;  { driver.bus.usb Command (16-bit) }
    UHCI_REG_USBSTS     = $02;  { driver.bus.usb Status (16-bit) }
    UHCI_REG_USBINTR    = $04;  { driver.bus.usb Interrupt Enable (16-bit) }
    UHCI_REG_FRNUM      = $06;  { Frame Number (16-bit) }
    UHCI_REG_FRBASEADD  = $08;  { Frame List Base Address (32-bit, 4K aligned) }
    UHCI_REG_SOFMOD     = $0C;  { Start of Frame Modify (8-bit) }
    UHCI_REG_PORTSC1    = $10;  { Port 1 Status/Control (16-bit) }
    UHCI_REG_PORTSC2    = $12;  { Port 2 Status/Control (16-bit) }

    { USBCMD bits }
    UHCI_CMD_RS          = $0001; { Run/Stop }
    UHCI_CMD_HCRESET     = $0002; { Host Controller Reset }
    UHCI_CMD_GRESET      = $0004; { Global Reset }
    UHCI_CMD_EGSM        = $0008; { Enter Global Suspend Mode }
    UHCI_CMD_FGR         = $0010; { Force Global Resume }
    UHCI_CMD_SWDBG       = $0020; { SW Debug mode }
    UHCI_CMD_CF          = $0040; { Configure Flag }
    UHCI_CMD_MAXP        = $0080; { Max Packet (1=64 bytes, 0=32 bytes) }

    { USBSTS bits }
    UHCI_STS_USBINT      = $0001; { driver.bus.usb Interrupt }
    UHCI_STS_ERROR        = $0002; { driver.bus.usb Error Interrupt }
    UHCI_STS_RD           = $0004; { Resume Detect }
    UHCI_STS_HSE          = $0008; { Host System Error }
    UHCI_STS_HCPE         = $0010; { Host Controller Process Error }
    UHCI_STS_HCH          = $0020; { HC Halted }

    { USBINTR bits }
    UHCI_INTR_TIMEOUT     = $0001; { Timeout/CRC interrupt enable }
    UHCI_INTR_RESUME      = $0002; { Resume interrupt enable }
    UHCI_INTR_IOC         = $0004; { Interrupt on Complete enable }
    UHCI_INTR_SP          = $0008; { Short Packet interrupt enable }

    { PORTSC bits }
    UHCI_PORT_CCS         = $0001; { Current Connect Status }
    UHCI_PORT_CSC         = $0002; { Connect Status Change }
    UHCI_PORT_PE          = $0004; { Port Enabled }
    UHCI_PORT_PEC         = $0008; { Port Enable Change }
    UHCI_PORT_LS          = $0030; { Line Status (bits 5:4) }
    UHCI_PORT_LS_SHIFT    = 4;
    UHCI_PORT_RD          = $0040; { Resume Detect }
    UHCI_PORT_LSDA        = $0100; { Low Speed Device Attached }
    UHCI_PORT_PR          = $0200; { Port Reset }
    UHCI_PORT_SUSP        = $1000; { Suspend }

    { TD Control/Status bits }
    UHCI_TD_ACTIVE        = $00800000; { Active - HC should process }
    UHCI_TD_STALLED       = $00400000; { Stalled }
    UHCI_TD_DBUF_ERR      = $00200000; { Data Buffer Error }
    UHCI_TD_BABBLE        = $00100000; { Babble Detected }
    UHCI_TD_NAK           = $00080000; { NAK Received }
    UHCI_TD_CRC_TIMEOUT   = $00040000; { CRC/Timeout Error }
    UHCI_TD_BITSTUFF      = $00020000; { Bitstuff Error }
    UHCI_TD_IOC           = $01000000; { Interrupt on Complete }
    UHCI_TD_IOS           = $02000000; { Isochronous Select }
    UHCI_TD_LS            = $04000000; { Low Speed Device }
    UHCI_TD_SPD           = $20000000; { Short Packet Detect }
    UHCI_TD_CERR_SHIFT    = 27;        { Error counter shift (bits 28:27) }
    UHCI_TD_ACTLEN_MASK   = $000007FF; { Actual Length mask (bits 10:0) }

    { TD Token bits }
    UHCI_TD_PID_SETUP     = $2D;
    UHCI_TD_PID_IN        = $69;
    UHCI_TD_PID_OUT       = $E1;
    UHCI_TD_TOKEN_D_SHIFT = 19;  { Data Toggle bit in token }
    UHCI_TD_TOKEN_MAXLEN_SHIFT = 21; { MaxLen field shift }
    UHCI_TD_TOKEN_EP_SHIFT = 15; { Endpoint field shift }
    UHCI_TD_TOKEN_ADDR_SHIFT = 8; { Device address shift }

    { Frame list }
    UHCI_FRAME_LIST_SIZE  = 1024;
    UHCI_FL_PTR_TERMINATE = $0001; { T bit: Terminate }
    UHCI_FL_PTR_QH        = $0002; { Q bit: points to QH (vs TD) }

    { QH/TD link pointer bits }
    UHCI_LP_TERMINATE     = $0001;
    UHCI_LP_QH            = $0002;
    UHCI_LP_DEPTH         = $0004; { Depth-first select (TD only) }

    { Max number of TDs we'll allocate per transfer }
    UHCI_MAX_TDS_PER_TRANSFER = 128;

    { Number of root hub ports }
    UHCI_NUM_PORTS        = 2;

{ ========================= driver.bus.usb.uhci Data Structures ========================= }

type
    { Transfer Descriptor - must be 16-byte aligned }
    PUHCI_TD = ^TUHCI_TD;
    TUHCI_TD = packed record
        LinkPointer   : uint32; { Next TD/QH pointer (or Terminate) }
        ControlStatus : uint32; { Control and status }
        Token         : uint32; { PID, device addr, endpoint, data toggle, max length }
        BufferPointer : uint32; { Physical address of data buffer }
        { Software fields (not read by HC, but we store them here for convenience) }
        { These extend the TD beyond 16 bytes but that's fine since we allocate 32-byte aligned blocks }
        SWNext        : PUHCI_TD;  { Software linked list next pointer }
        SWTransfer    : Pointer;   { Back-pointer to the owning TUSBTransfer }
        SWPad1        : uint32;
        SWPad2        : uint32;
    end;

    { Queue Head - must be 16-byte aligned }
    PUHCI_QH = ^TUHCI_QH;
    TUHCI_QH = packed record
        HeadLink    : uint32; { Horizontal link to next QH (or Terminate) }
        ElementLink : uint32; { Vertical link to first TD (or Terminate) }
        { Software fields }
        SWNext      : PUHCI_QH; { Software pointer to next QH in our chain }
        SWPad       : uint32;
    end;

    { Private data for a driver.bus.usb.uhci host controller instance }
    PUHCI_PrivData = ^TUHCI_PrivData;
    TUHCI_PrivData = record
        IOBase      : uint16;   { I/O port base address }
        FrameList   : Pointer;  { 4K-aligned frame list (1024 uint32 entries) }
        QHControl   : PUHCI_QH; { Queue Head for control transfers }
        QHBulk      : PUHCI_QH; { Queue Head for bulk transfers }
        QHInterrupt : PUHCI_QH; { Queue Head for interrupt transfers }
        PollBusy    : boolean;  { Re-entrancy guard for poll }
        PCIBus      : uint8;    { driver.bus.pci bus/slot/func for bus mastering }
        PCISlot     : uint8;
        PCIFunc     : uint8;
    end;

{ ========================= I/O Helpers ========================= }

procedure uhci_write16(iobase : uint16; reg : uint16; val : uint16);
begin
    outw(iobase + reg, val);
end;

function uhci_read16(iobase : uint16; reg : uint16) : uint16;
begin
    uhci_read16 := inw(iobase + reg);
end;

procedure uhci_write32(iobase : uint16; reg : uint16; val : uint32);
begin
    outl(iobase + reg, val);
end;

function uhci_read32(iobase : uint16; reg : uint16) : uint32;
begin
    uhci_read32 := inl(iobase + reg);
end;

procedure uhci_write8(iobase : uint16; reg : uint16; val : uint8);
begin
    outb(iobase + reg, val);
end;

{ ========================= TD/QH Construction Helpers ========================= }

{ Allocate a TD (16-byte aligned) }
function uhci_alloc_td : PUHCI_TD;
begin
    uhci_alloc_td := PUHCI_TD(kalloc_aligned(sizeof(TUHCI_TD), 16));
    if uhci_alloc_td <> nil then
        memset(uint32(uhci_alloc_td), 0, sizeof(TUHCI_TD));
end;

{ Free a TD }
procedure uhci_free_td(td : PUHCI_TD);
begin
    if td <> nil then
        kfree_aligned(td);
end;

{ Allocate a QH (16-byte aligned) }
function uhci_alloc_qh : PUHCI_QH;
begin
    uhci_alloc_qh := PUHCI_QH(kalloc_aligned(sizeof(TUHCI_QH), 16));
    if uhci_alloc_qh <> nil then
        memset(uint32(uhci_alloc_qh), 0, sizeof(TUHCI_QH));
end;

{ Free a QH }
procedure uhci_free_qh(qh : PUHCI_QH);
begin
    if qh <> nil then
        kfree_aligned(qh);
end;

{ Build a TD token dword.
  pid:     UHCI_TD_PID_SETUP / _IN / _OUT
  devAddr: driver.bus.usb device address (0-127)
  ep:      endpoint number (0-15)
  toggle:  data toggle (0 or 1)
  maxLen:  max bytes for this TD (0 means zero-length data encoded as $7FF; 
           otherwise encoded as maxLen-1) }
function uhci_make_token(pid : uint8; devAddr : uint8; ep : uint8; toggle : uint8; maxLen : uint16) : uint32;
var
    ml : uint32;
begin
    if maxLen = 0 then
        ml := $7FF  { Special encoding: zero-length data }
    else
        ml := uint32(maxLen - 1);
    uhci_make_token := uint32(pid)
        OR (uint32(devAddr) SHL UHCI_TD_TOKEN_ADDR_SHIFT)
        OR (uint32(ep) SHL UHCI_TD_TOKEN_EP_SHIFT)
        OR (uint32(toggle) SHL UHCI_TD_TOKEN_D_SHIFT)
        OR (ml SHL UHCI_TD_TOKEN_MAXLEN_SHIFT);
end;

{ Build TD control/status dword.
  isLowSpeed: true for low-speed devices
  ioc:        interrupt on complete
  errCount:   error retry count (typically 3) }
function uhci_make_control(isLowSpeed : boolean; ioc : boolean; errCount : uint8) : uint32;
begin
    uhci_make_control := UHCI_TD_ACTIVE
        OR (uint32(errCount AND $03) SHL UHCI_TD_CERR_SHIFT);
    if isLowSpeed then
        uhci_make_control := uhci_make_control OR UHCI_TD_LS;
    if ioc then
        uhci_make_control := uhci_make_control OR UHCI_TD_IOC;
end;

{ ========================= HC Callback Implementations ========================= }

{ Forward declarations }
function uhci_reset(hc : PUSBHCDriver) : boolean; forward;
function uhci_start(hc : PUSBHCDriver) : boolean; forward;
procedure uhci_stop(hc : PUSBHCDriver); forward;
function uhci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean; forward;
procedure uhci_poll(hc : PUSBHCDriver); forward;
function uhci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean; forward;
function uhci_port_status(hc : PUSBHCDriver; port : uint8) : uint32; forward;

{ ========================= Reset ========================= }

function uhci_reset(hc : PUSBHCDriver) : boolean;
var
    priv  : PUHCI_PrivData;
    loops : uint32;
begin
    push_trace('UHCI.uhci_reset');
    uhci_reset := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PUHCI_PrivData(hc^.PrivData);

    { Stop the controller first }
    uhci_write16(priv^.IOBase, UHCI_REG_USBCMD, 0);

    { Global reset }
    uhci_write16(priv^.IOBase, UHCI_REG_USBCMD, UHCI_CMD_GRESET);
    { Wait approx 50ms - busy wait }
    loops := 0;
    while loops < 50000 do inc(loops);
    uhci_write16(priv^.IOBase, UHCI_REG_USBCMD, 0);

    { Host controller reset }
    uhci_write16(priv^.IOBase, UHCI_REG_USBCMD, UHCI_CMD_HCRESET);
    loops := 0;
    while (loops < 100000) and ((uhci_read16(priv^.IOBase, UHCI_REG_USBCMD) AND UHCI_CMD_HCRESET) <> 0) do
        inc(loops);

    if (uhci_read16(priv^.IOBase, UHCI_REG_USBCMD) AND UHCI_CMD_HCRESET) <> 0 then begin
        io.syslog.logln('driver.bus.usb.uhci', 'HC reset timeout!');
        pop_trace;
        exit;
    end;

    { Clear status }
    uhci_write16(priv^.IOBase, UHCI_REG_USBSTS, $FFFF);

    { Disable all interrupts (we are polling) }
    uhci_write16(priv^.IOBase, UHCI_REG_USBINTR, 0);

    uhci_reset := true;
    pop_trace;
end;

{ ========================= Schedule Setup ========================= }

procedure uhci_setup_schedule(hc : PUSBHCDriver);
var
    priv  : PUHCI_PrivData;
    fl    : Pointer;
    i     : uint32;
begin
    push_trace('UHCI.uhci_setup_schedule');
    priv := PUHCI_PrivData(hc^.PrivData);

    { Allocate the frame list (4096 bytes, 4096-byte aligned) }
    priv^.FrameList := kalloc_aligned(UHCI_FRAME_LIST_SIZE * 4, 4096);
    if priv^.FrameList = nil then begin
        io.syslog.logln('driver.bus.usb.uhci', 'Failed to allocate frame list!');
        pop_trace;
        exit;
    end;

    { Allocate Queue Heads }
    priv^.QHInterrupt := uhci_alloc_qh;
    priv^.QHControl   := uhci_alloc_qh;
    priv^.QHBulk      := uhci_alloc_qh;

    if (priv^.QHInterrupt = nil) or (priv^.QHControl = nil) or (priv^.QHBulk = nil) then begin
        io.syslog.logln('driver.bus.usb.uhci', 'Failed to allocate QHs!');
        pop_trace;
        exit;
    end;

    { Chain: Interrupt QH -> Control QH -> Bulk QH -> Terminate
      Each QH HeadLink points to the next QH in the horizontal chain.
      ElementLink starts as Terminate (no TDs yet). }

    { Interrupt QH -> Control QH }
    priv^.QHInterrupt^.HeadLink    := uint32(priv^.QHControl) OR UHCI_LP_QH;
    priv^.QHInterrupt^.ElementLink := UHCI_LP_TERMINATE;
    priv^.QHInterrupt^.SWNext     := priv^.QHControl;

    { Control QH -> Bulk QH }
    priv^.QHControl^.HeadLink    := uint32(priv^.QHBulk) OR UHCI_LP_QH;
    priv^.QHControl^.ElementLink := UHCI_LP_TERMINATE;
    priv^.QHControl^.SWNext     := priv^.QHBulk;

    { Bulk QH -> Terminate }
    priv^.QHBulk^.HeadLink    := UHCI_LP_TERMINATE;
    priv^.QHBulk^.ElementLink := UHCI_LP_TERMINATE;
    priv^.QHBulk^.SWNext     := nil;

    { Fill frame list: every entry points to the Interrupt QH }
    fl := priv^.FrameList;
    for i := 0 to UHCI_FRAME_LIST_SIZE - 1 do begin
        PUint32(uint32(fl) + (i * 4))^ := uint32(priv^.QHInterrupt) OR UHCI_FL_PTR_QH;
    end;

    pop_trace;
end;

{ ========================= Start ========================= }

function uhci_start(hc : PUSBHCDriver) : boolean;
var
    priv : PUHCI_PrivData;
begin
    push_trace('UHCI.uhci_start');
    uhci_start := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PUHCI_PrivData(hc^.PrivData);

    { Set frame list base address }
    uhci_write32(priv^.IOBase, UHCI_REG_FRBASEADD, uint32(priv^.FrameList));

    { Start at frame 0 }
    uhci_write16(priv^.IOBase, UHCI_REG_FRNUM, 0);

    { Set SOF timing to default }
    uhci_write8(priv^.IOBase, UHCI_REG_SOFMOD, $40);

    { Start the controller: Run + Configure Flag + Max Packet (64 bytes) }
    uhci_write16(priv^.IOBase, UHCI_REG_USBCMD, UHCI_CMD_RS OR UHCI_CMD_CF OR UHCI_CMD_MAXP);

    { Verify it's running }
    if (uhci_read16(priv^.IOBase, UHCI_REG_USBSTS) AND UHCI_STS_HCH) <> 0 then begin
        io.syslog.logln('driver.bus.usb.uhci', 'Controller failed to start (HCH still set).');
        pop_trace;
        exit;
    end;

    io.syslog.logln('driver.bus.usb.uhci', 'Controller started.');
    uhci_start := true;
    pop_trace;
end;

{ ========================= Stop ========================= }

procedure uhci_stop(hc : PUSBHCDriver);
var
    priv : PUHCI_PrivData;
begin
    push_trace('UHCI.uhci_stop');
    if (hc <> nil) and (hc^.PrivData <> nil) then begin
        priv := PUHCI_PrivData(hc^.PrivData);
        uhci_write16(priv^.IOBase, UHCI_REG_USBCMD, 0);
        io.syslog.logln('driver.bus.usb.uhci', 'Controller stopped.');
    end;
    pop_trace;
end;

{ ========================= Port Status ========================= }

function uhci_port_status(hc : PUSBHCDriver; port : uint8) : uint32;
var
    priv : PUHCI_PrivData;
    reg  : uint16;
begin
    push_trace('UHCI.uhci_port_status');
    uhci_port_status := 0;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PUHCI_PrivData(hc^.PrivData);
    if port = 0 then
        reg := UHCI_REG_PORTSC1
    else if port = 1 then
        reg := UHCI_REG_PORTSC2
    else begin
        pop_trace;
        exit;
    end;
    uhci_port_status := uhci_read16(priv^.IOBase, reg);
    pop_trace;
end;

{ ========================= Port Reset ========================= }

function uhci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean;
var
    priv   : PUHCI_PrivData;
    reg    : uint16;
    status : uint16;
    loops  : uint32;
begin
    push_trace('UHCI.uhci_port_reset');
    uhci_port_reset := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PUHCI_PrivData(hc^.PrivData);
    if port = 0 then
        reg := UHCI_REG_PORTSC1
    else if port = 1 then
        reg := UHCI_REG_PORTSC2
    else begin
        pop_trace;
        exit;
    end;

    { Assert port reset }
    status := uhci_read16(priv^.IOBase, reg);
    uhci_write16(priv^.IOBase, reg, status OR UHCI_PORT_PR);

    { Hold reset for ~50ms (busy wait) }
    loops := 0;
    while loops < 50000 do inc(loops);

    { Clear reset bit }
    status := uhci_read16(priv^.IOBase, reg);
    uhci_write16(priv^.IOBase, reg, status AND (NOT UHCI_PORT_PR));

    { Wait for port to stabilize }
    loops := 0;
    while loops < 10000 do inc(loops);

    { Enable port and clear status change bits }
    status := uhci_read16(priv^.IOBase, reg);
    uhci_write16(priv^.IOBase, reg, status OR UHCI_PORT_PE OR UHCI_PORT_CSC OR UHCI_PORT_PEC);

    { Small delay }
    loops := 0;
    while loops < 10000 do inc(loops);

    { Check if port is enabled }
    status := uhci_read16(priv^.IOBase, reg);
    if (status AND UHCI_PORT_PE) <> 0 then begin
        io.syslog.log('driver.bus.usb.uhci', 'Port ');
        io.syslog.writeint(port);
        io.syslog.writestringln(' reset and enabled.');
        uhci_port_reset := true;
    end else begin
        io.syslog.log('driver.bus.usb.uhci', 'Port ');
        io.syslog.writeint(port);
        io.syslog.writestringln(' reset failed (not enabled).');
    end;
    pop_trace;
end;

{ ========================= Submit Transfer ========================= }

{ Build a chain of TDs for a control transfer and link to the control QH }
function uhci_submit_control(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var
    priv     : PUHCI_PrivData;
    dev      : PUSBDevice;
    td       : PUHCI_TD;
    firstTD  : PUHCI_TD;
    prevTD   : PUHCI_TD;
    devAddr  : uint8;
    ep       : uint8;
    maxPkt   : uint16;
    isLS     : boolean;
    remaining : uint32;
    offset   : uint32;
    pktLen   : uint16;
    toggle   : uint8;
    pid      : uint8;
    setupBuf : Pointer;
begin
    push_trace('UHCI.uhci_submit_control');
    uhci_submit_control := false;
    priv := PUHCI_PrivData(hc^.PrivData);
    dev := transfer^.Device;
    devAddr := dev^.Address;
    ep := 0; { Control transfers always use EP0 }
    maxPkt := dev^.MaxPacket0;
    if maxPkt = 0 then maxPkt := 8;
    isLS := (dev^.Speed = USB_SPEED_LOW);

    firstTD := nil;
    prevTD := nil;

    { === SETUP TD === }
    td := uhci_alloc_td;
    if td = nil then begin pop_trace; exit; end;
    firstTD := td;

    { Allocate 8 bytes for setup packet and copy }
    setupBuf := Pointer(kalloc(8));
    memcpy(uint32(@transfer^.Setup), uint32(setupBuf), 8);

    td^.Token         := uhci_make_token(UHCI_TD_PID_SETUP, devAddr, ep, 0, 8);
    td^.ControlStatus := uhci_make_control(isLS, false, 3);
    td^.BufferPointer := uint32(setupBuf);
    td^.SWTransfer    := Pointer(transfer);
    td^.SWNext        := nil;
    prevTD := td;

    { === DATA TDs === }
    toggle := 1; { First data packet after SETUP uses DATA1 }
    remaining := transfer^.BufferLen;
    offset := 0;

    while remaining > 0 do begin
        td := uhci_alloc_td;
        if td = nil then begin pop_trace; exit; end;

        if remaining > maxPkt then
            pktLen := maxPkt
        else
            pktLen := remaining;

        { Direction: if bmRequestType bit 7 is set, data stage is IN, else OUT }
        if (transfer^.Setup.bmRequestType AND $80) <> 0 then
            pid := UHCI_TD_PID_IN
        else
            pid := UHCI_TD_PID_OUT;

        td^.Token         := uhci_make_token(pid, devAddr, ep, toggle, pktLen);
        td^.ControlStatus := uhci_make_control(isLS, false, 3);
        td^.BufferPointer := uint32(transfer^.Buffer) + offset;
        td^.SWTransfer    := Pointer(transfer);
        td^.SWNext        := nil;

        { Link previous TD to this one }
        prevTD^.LinkPointer := uint32(td) OR UHCI_LP_DEPTH;
        prevTD^.SWNext      := td;
        prevTD := td;

        toggle := toggle XOR 1;
        offset := offset + pktLen;
        remaining := remaining - pktLen;
    end;

    { === STATUS TD === }
    td := uhci_alloc_td;
    if td = nil then begin pop_trace; exit; end;

    { Status stage direction is opposite of data stage }
    if (transfer^.Setup.bmRequestType AND $80) <> 0 then
        pid := UHCI_TD_PID_OUT
    else
        pid := UHCI_TD_PID_IN;

    td^.Token         := uhci_make_token(pid, devAddr, ep, 1, 0); { DATA1, zero length }
    td^.ControlStatus := uhci_make_control(isLS, true, 3); { IOC on status TD }
    td^.BufferPointer := 0;
    td^.SWTransfer    := Pointer(transfer);
    td^.SWNext        := nil;
    td^.LinkPointer   := UHCI_LP_TERMINATE;

    prevTD^.LinkPointer := uint32(td) OR UHCI_LP_DEPTH;
    prevTD^.SWNext      := td;

    { Store first TD in transfer HCPriv for later cleanup }
    transfer^.HCPriv := Pointer(firstTD);
    transfer^.Status := tsInProgress;

    { Link TD chain into Control QH }
    priv^.QHControl^.ElementLink := uint32(firstTD);

    uhci_submit_control := true;
    pop_trace;
end;

{ Build TDs for an interrupt or bulk transfer }
function uhci_submit_async(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var
    priv     : PUHCI_PrivData;
    dev      : PUSBDevice;
    td       : PUHCI_TD;
    firstTD  : PUHCI_TD;
    prevTD   : PUHCI_TD;
    devAddr  : uint8;
    epNum    : uint8;
    maxPkt   : uint16;
    isLS     : boolean;
    remaining : uint32;
    offset   : uint32;
    pktLen   : uint16;
    toggle   : uint8;
    pid      : uint8;
    qh       : PUHCI_QH;
begin
    push_trace('UHCI.uhci_submit_async');
    uhci_submit_async := false;
    priv := PUHCI_PrivData(hc^.PrivData);
    dev := transfer^.Device;
    devAddr := dev^.Address;
    epNum := transfer^.Endpoint^.Address;
    maxPkt := transfer^.Endpoint^.MaxPacket;
    if maxPkt = 0 then maxPkt := 8;
    isLS := (dev^.Speed = USB_SPEED_LOW);
    toggle := transfer^.Endpoint^.Toggle;

    if transfer^.Direction = dirIn then
        pid := UHCI_TD_PID_IN
    else
        pid := UHCI_TD_PID_OUT;

    firstTD := nil;
    prevTD := nil;
    remaining := transfer^.BufferLen;
    offset := 0;

    { Build TD chain }
    repeat
        td := uhci_alloc_td;
        if td = nil then begin pop_trace; exit; end;

        if firstTD = nil then firstTD := td;

        if remaining > maxPkt then
            pktLen := maxPkt
        else if remaining > 0 then
            pktLen := remaining
        else
            pktLen := 0;

        td^.Token         := uhci_make_token(pid, devAddr, epNum, toggle, pktLen);
        td^.ControlStatus := uhci_make_control(isLS, false, 3);
        td^.BufferPointer := uint32(transfer^.Buffer) + offset;
        td^.SWTransfer    := Pointer(transfer);
        td^.SWNext        := nil;
        td^.LinkPointer   := UHCI_LP_TERMINATE;

        if prevTD <> nil then begin
            prevTD^.LinkPointer := uint32(td) OR UHCI_LP_DEPTH;
            prevTD^.SWNext      := td;
        end;
        prevTD := td;

        toggle := toggle XOR 1;
        if remaining > maxPkt then begin
            offset := offset + maxPkt;
            remaining := remaining - maxPkt;
        end else begin
            offset := offset + remaining;
            remaining := 0;
        end;
    until remaining = 0;

    { Mark last TD with IOC }
    if prevTD <> nil then
        prevTD^.ControlStatus := prevTD^.ControlStatus OR UHCI_TD_IOC;

    { Update endpoint toggle }
    transfer^.Endpoint^.Toggle := toggle;

    { Store first TD for cleanup }
    transfer^.HCPriv := Pointer(firstTD);
    transfer^.Status := tsInProgress;

    { Link to appropriate QH }
    if transfer^.PipeType = ptInterrupt then
        qh := priv^.QHInterrupt
    else
        qh := priv^.QHBulk;

    qh^.ElementLink := uint32(firstTD);

    uhci_submit_async := true;
    pop_trace;
end;

function uhci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
begin
    push_trace('UHCI.uhci_submit');
    uhci_submit := false;
    if (hc = nil) or (transfer = nil) or (transfer^.Device = nil) then begin
        pop_trace;
        exit;
    end;

    case transfer^.PipeType of
        ptControl:
            uhci_submit := uhci_submit_control(hc, transfer);
        ptInterrupt, ptBulk:
            uhci_submit := uhci_submit_async(hc, transfer);
    else
        io.syslog.logln('driver.bus.usb.uhci', 'Unsupported pipe type for submit.');
    end;
    pop_trace;
end;

{ ========================= Interrupt-Driven Completion ========================= }

const
    UHCI_MAX_INSTANCES = 4;

var
    UHCIInstances     : array[0..UHCI_MAX_INSTANCES-1] of PUSBHCDriver;
    UHCIInstanceCount : uint32;

{ ISR handler — registered on the driver.bus.pci interrupt line. }
procedure uhci_isr;
var
    i      : uint32;
    hc     : PUSBHCDriver;
    priv   : PUHCI_PrivData;
    status : uint16;
begin
    for i := 0 to UHCIInstanceCount - 1 do begin
        hc := UHCIInstances[i];
        if hc = nil then continue;
        priv := PUHCI_PrivData(hc^.PrivData);
        if priv = nil then continue;

        { Check if this controller has pending interrupt status }
        status := uhci_read16(priv^.IOBase, UHCI_REG_USBSTS);
        if (status AND (UHCI_STS_USBINT OR UHCI_STS_ERROR)) = 0 then continue;

        { Acknowledge interrupt status NOW to de-assert level-triggered driver.bus.pci line.
          Must happen before uhci_poll, because PollBusy guard may skip the
          acknowledge inside poll — leaving the line asserted = interrupt storm. }
        uhci_write16(priv^.IOBase, UHCI_REG_USBSTS, status AND (UHCI_STS_USBINT OR UHCI_STS_ERROR));

        { Process completions (walks QH/TD chains) }
        uhci_poll(hc);
    end;
    driver.bus.usb.core.fire_completion_hooks;
end;

{ Enable hardware interrupts: Interrupt-on-Complete, Short Packet, Timeout/CRC. }
procedure uhci_enable_interrupts(hc : PUSBHCDriver);
var
    priv : PUHCI_PrivData;
begin
    if (hc = nil) or (hc^.PrivData = nil) then exit;
    priv := PUHCI_PrivData(hc^.PrivData);
    uhci_write16(priv^.IOBase, UHCI_REG_USBINTR,
        UHCI_INTR_IOC OR UHCI_INTR_SP OR UHCI_INTR_TIMEOUT);
    io.syslog.logln('driver.bus.usb.uhci', 'Hardware interrupts enabled.');
end;

{ ========================= Poll / Completion ========================= }

procedure uhci_poll(hc : PUSBHCDriver);
var
    priv   : PUHCI_PrivData;
    status : uint16;
    qh     : PUHCI_QH;
    td     : PUHCI_TD;
    cs     : uint32;
    actualLen : uint32;
    totalLen  : uint32;
    transfer  : PUSBTransfer;
    allDone   : boolean;
    hasError  : boolean;
begin
    if (hc = nil) or (hc^.PrivData = nil) then exit;
    priv := PUHCI_PrivData(hc^.PrivData);

    { Re-entrancy guard }
    if priv^.PollBusy then exit;
    priv^.PollBusy := true;

    { Read and clear status register }
    status := uhci_read16(priv^.IOBase, UHCI_REG_USBSTS);
    if (status AND (UHCI_STS_USBINT OR UHCI_STS_ERROR)) <> 0 then
        uhci_write16(priv^.IOBase, UHCI_REG_USBSTS, status AND (UHCI_STS_USBINT OR UHCI_STS_ERROR));

    { Check if controller had a fatal error }
    if (status AND UHCI_STS_HSE) <> 0 then begin
        io.syslog.logln('driver.bus.usb.uhci', 'Host System Error detected!');
        uhci_write16(priv^.IOBase, UHCI_REG_USBSTS, UHCI_STS_HSE);
    end;

    { Walk each QH and check its TD chain for completion }
    qh := priv^.QHInterrupt;
    while qh <> nil do begin
        { Check if QH has active TDs }
        if (qh^.ElementLink AND UHCI_LP_TERMINATE) = 0 then begin
            td := PUHCI_TD(qh^.ElementLink AND $FFFFFFF0);
            if (td <> nil) and (td^.SWTransfer <> nil) then begin
                transfer := PUSBTransfer(td^.SWTransfer);
                if transfer^.Status = tsInProgress then begin
                    { Walk the TD chain from the head stored in HCPriv }
                    td := PUHCI_TD(transfer^.HCPriv);
                    totalLen := 0;
                    allDone := true;
                    hasError := false;
                    while td <> nil do begin
                        cs := td^.ControlStatus;
                        if (cs AND UHCI_TD_ACTIVE) <> 0 then begin
                            allDone := false;
                            break;
                        end;
                        if (cs AND UHCI_TD_STALLED) <> 0 then begin
                            hasError := true;
                            transfer^.Status := tsStall;
                            break;
                        end;
                        if (cs AND UHCI_TD_BABBLE) <> 0 then begin
                            hasError := true;
                            transfer^.Status := tsBabble;
                            break;
                        end;
                        if (cs AND UHCI_TD_DBUF_ERR) <> 0 then begin
                            hasError := true;
                            transfer^.Status := tsDataBufferError;
                            break;
                        end;
                        if (cs AND UHCI_TD_CRC_TIMEOUT) <> 0 then begin
                            hasError := true;
                            transfer^.Status := tsCRCError;
                            break;
                        end;
                        if (cs AND UHCI_TD_BITSTUFF) <> 0 then begin
                            hasError := true;
                            transfer^.Status := tsBitStuffError;
                            break;
                        end;
                        actualLen := cs AND UHCI_TD_ACTLEN_MASK;
                        if actualLen <> $7FF then
                            totalLen := totalLen + actualLen + 1;
                        td := td^.SWNext;
                    end;
                    if allDone and (not hasError) then begin
                        transfer^.ActualLen := totalLen;
                        transfer^.Status := tsSuccess;
                    end;
                    { If transfer is done (success or error), clear the QH element link }
                    if transfer^.Status <> tsInProgress then
                        qh^.ElementLink := UHCI_LP_TERMINATE;
                end;
            end;
        end;
        qh := qh^.SWNext;
    end;
    priv^.PollBusy := false;
end;

{ ========================= Load / Init ========================= }

function load : boolean;
var
    devices : TDeviceArray;
    count   : uint32;
    i       : uint32;
    priv    : PUHCI_PrivData;
    hc      : TUSBHCDriver;
    hcEntry : PUSBHCDriver;
    iobase  : uint32;
begin
    push_trace('UHCI.load');
    load := false;
    UHCIInstanceCount := 0;

    devices := driver.bus.pci.getDeviceInfo($0C, $03, $00, count);
    io.syslog.log('driver.bus.usb.uhci', 'Found ');
    io.syslog.writeint(count);
    io.syslog.writestringln(' driver.bus.usb.uhci controller(s).');

    if count = 0 then begin
        load := true;
        pop_trace;
        exit;
    end;

    for i := 0 to count - 1 do begin
        io.syslog.log('driver.bus.usb.uhci', 'Controller[');
        io.syslog.writeint(i);
        io.syslog.writestring(']: VID=');
        io.syslog.writehex(devices[i].vendor_id);
        io.syslog.writestring(' DID=');
        io.syslog.writehex(devices[i].device_id);
        io.syslog.writestring(' BAR4=');
        io.syslog.writehexln(devices[i].address4);

        { BAR4 is the I/O base for UHCI. Bit 0 = 1 means I/O space. }
        iobase := devices[i].address4 AND $FFFFFFFC; { Mask off type bits }
        if iobase = 0 then begin
            io.syslog.logln('driver.bus.usb.uhci', 'Invalid I/O base (BAR4=0), skipping.');
            continue;
        end;

        { Enable driver.bus.pci bus mastering }
        driver.bus.pci.setBusMaster(devices[i].bus, devices[i].slot, devices[i].func, true);

        { Allocate private data }
        priv := PUHCI_PrivData(kalloc(sizeof(TUHCI_PrivData)));
        if priv = nil then begin
            io.syslog.logln('driver.bus.usb.uhci', 'Failed to allocate private data!');
            continue;
        end;
        memset(uint32(priv), 0, sizeof(TUHCI_PrivData));
        priv^.IOBase  := uint16(iobase);
        priv^.PCIBus  := devices[i].bus;
        priv^.PCISlot := devices[i].slot;
        priv^.PCIFunc := devices[i].func;

        { Initialize HC driver record }
        usb_hc_init_record(@hc);
        hc.Name         := 'driver.bus.usb.uhci';
        hc.HCType       := USB_HC_UHCI;
        hc.NumPorts     := UHCI_NUM_PORTS;
        hc.PCIDev       := devices[i];
        hc.BaseAddr     := iobase;
        hc.PrivData     := Pointer(priv);
        hc.Devices      := LL_New(sizeof(TUSBDevice));
        hc.NextAddress  := 1;
        hc.fnReset      := TUSBHCReset(@uhci_reset);
        hc.fnStart      := TUSBHCStart(@uhci_start);
        hc.fnStop       := TUSBHCStop(@uhci_stop);
        hc.fnSubmit     := TUSBHCSubmit(@uhci_submit);
        hc.fnPoll       := TUSBHCPoll(@uhci_poll);
        hc.fnPortReset  := TUSBHCPortReset(@uhci_port_reset);
        hc.fnPortStatus := TUSBHCPortStatus(@uhci_port_status);

        { Reset the controller }
        if not uhci_reset(@hc) then begin
            io.syslog.logln('driver.bus.usb.uhci', 'Reset failed, skipping controller.');
            kfree(void(priv));
            continue;
        end;

        { Setup the schedule (frame list + QH chain) }
        uhci_setup_schedule(@hc);

        { Start the controller }
        if not uhci_start(@hc) then begin
            io.syslog.logln('driver.bus.usb.uhci', 'Start failed, skipping controller.');
            if priv^.FrameList <> nil then kfree_aligned(priv^.FrameList);
            if priv^.QHInterrupt <> nil then uhci_free_qh(priv^.QHInterrupt);
            if priv^.QHControl <> nil then uhci_free_qh(priv^.QHControl);
            if priv^.QHBulk <> nil then uhci_free_qh(priv^.QHBulk);
            kfree(void(priv));
            continue;
        end;

        { Register with driver.bus.usb core }
        { Register with driver.bus.usb core — get back the stable heap pointer }
        hcEntry := driver.bus.usb.core.register_hc(@hc);

        { Scan ports for connected devices (use the stable pointer, not stack-local @hc) }
        if hcEntry <> nil then begin
            { Track instance for ISR dispatch }
            if UHCIInstanceCount < UHCI_MAX_INSTANCES then begin
                UHCIInstances[UHCIInstanceCount] := hcEntry;
                inc(UHCIInstanceCount);
            end;

            { Register ISR on driver.bus.pci interrupt line }
            io.syslog.log('driver.bus.usb.uhci', 'Registering ISR on IRQ ');
            io.syslog.writeintln(devices[i].interrupt_line);
            arch.x86.isr.mgr.registerISR(32 + devices[i].interrupt_line, @uhci_isr);

            { Enable hardware interrupts }
            uhci_enable_interrupts(hcEntry);

            { Scan for connected devices }
            driver.bus.usb.core.scan_ports(hcEntry);
        end else
            io.syslog.logln('driver.bus.usb.uhci', 'Failed to register HC with driver.bus.usb core.');

        io.syslog.logln('driver.bus.usb.uhci', 'Controller initialized and registered.');
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
            io.syslog.logln('driver.bus.usb.uhci', msg);
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
        io.syslog.logln('driver.bus.usb.uhci', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

var
    token  : uint32;
    ctrl   : uint32;
    td     : PUHCI_TD;
    qh     : PUHCI_QH;
begin
    passed := 0;
    failed := 0;
    io.syslog.logln('driver.bus.usb.uhci', 'Unit tests starting...');

    { === TD/QH Size and Alignment === }
    Assert(sizeof(TUHCI_TD) = 32, 'sizeof TD=32');
    Assert(sizeof(TUHCI_QH) = 16, 'sizeof QH=16');

    { === Token Building === }
    { SETUP to addr 0, EP0, toggle 0, 8 bytes }
    token := uhci_make_token(UHCI_TD_PID_SETUP, 0, 0, 0, 8);
    Assert((token AND $FF) = UHCI_TD_PID_SETUP, 'token PID=SETUP');
    Assert(((token SHR UHCI_TD_TOKEN_ADDR_SHIFT) AND $7F) = 0, 'token addr=0');
    Assert(((token SHR UHCI_TD_TOKEN_EP_SHIFT) AND $0F) = 0, 'token ep=0');
    Assert(((token SHR UHCI_TD_TOKEN_D_SHIFT) AND $01) = 0, 'token toggle=0');
    Assert(((token SHR UHCI_TD_TOKEN_MAXLEN_SHIFT) AND $7FF) = 7, 'token maxlen=7 (8 bytes)');

    { IN to addr 5, EP1, toggle 1, 64 bytes }
    token := uhci_make_token(UHCI_TD_PID_IN, 5, 1, 1, 64);
    Assert((token AND $FF) = UHCI_TD_PID_IN, 'token PID=IN');
    Assert(((token SHR UHCI_TD_TOKEN_ADDR_SHIFT) AND $7F) = 5, 'token addr=5');
    Assert(((token SHR UHCI_TD_TOKEN_EP_SHIFT) AND $0F) = 1, 'token ep=1');
    Assert(((token SHR UHCI_TD_TOKEN_D_SHIFT) AND $01) = 1, 'token toggle=1');
    Assert(((token SHR UHCI_TD_TOKEN_MAXLEN_SHIFT) AND $7FF) = 63, 'token maxlen=63 (64 bytes)');

    { OUT to addr 127, EP15, toggle 0, 0 bytes (status stage) }
    token := uhci_make_token(UHCI_TD_PID_OUT, 127, 15, 0, 0);
    Assert((token AND $FF) = UHCI_TD_PID_OUT, 'token PID=OUT');
    Assert(((token SHR UHCI_TD_TOKEN_ADDR_SHIFT) AND $7F) = 127, 'token addr=127');
    Assert(((token SHR UHCI_TD_TOKEN_EP_SHIFT) AND $0F) = 15, 'token ep=15');
    Assert(((token SHR UHCI_TD_TOKEN_MAXLEN_SHIFT) AND $7FF) = $7FF, 'token maxlen=$7FF (0 bytes)');

    { === Control/Status Building === }
    { Full speed, no IOC, 3 retries }
    ctrl := uhci_make_control(false, false, 3);
    Assert((ctrl AND UHCI_TD_ACTIVE) <> 0, 'ctrl active set');
    Assert((ctrl AND UHCI_TD_LS) = 0, 'ctrl not low-speed');
    Assert((ctrl AND UHCI_TD_IOC) = 0, 'ctrl no IOC');
    Assert(((ctrl SHR UHCI_TD_CERR_SHIFT) AND $03) = 3, 'ctrl cerr=3');

    { Low speed, with IOC, 1 retry }
    ctrl := uhci_make_control(true, true, 1);
    Assert((ctrl AND UHCI_TD_ACTIVE) <> 0, 'ctrl_ls active set');
    Assert((ctrl AND UHCI_TD_LS) <> 0, 'ctrl_ls low-speed set');
    Assert((ctrl AND UHCI_TD_IOC) <> 0, 'ctrl_ls IOC set');
    Assert(((ctrl SHR UHCI_TD_CERR_SHIFT) AND $03) = 1, 'ctrl_ls cerr=1');

    { === TD Allocation & Alignment === }
    td := uhci_alloc_td;
    Assert(td <> nil, 'alloc_td not nil');
    Assert((uint32(td) AND $0F) = 0, 'alloc_td 16-byte aligned');
    Assert(td^.LinkPointer = 0, 'alloc_td zeroed link');
    Assert(td^.ControlStatus = 0, 'alloc_td zeroed ctrl');
    Assert(td^.Token = 0, 'alloc_td zeroed token');
    Assert(td^.BufferPointer = 0, 'alloc_td zeroed buffer');
    uhci_free_td(td);

    { === QH Allocation & Alignment === }
    qh := uhci_alloc_qh;
    Assert(qh <> nil, 'alloc_qh not nil');
    Assert((uint32(qh) AND $0F) = 0, 'alloc_qh 16-byte aligned');
    Assert(qh^.HeadLink = 0, 'alloc_qh zeroed head');
    Assert(qh^.ElementLink = 0, 'alloc_qh zeroed elem');
    uhci_free_qh(qh);

    { === Link Pointer Constants === }
    Assert(UHCI_LP_TERMINATE = $01, 'LP_TERMINATE=$01');
    Assert(UHCI_LP_QH = $02, 'LP_QH=$02');
    Assert(UHCI_FL_PTR_TERMINATE = $01, 'FL_PTR_TERMINATE=$01');
    Assert(UHCI_FL_PTR_QH = $02, 'FL_PTR_QH=$02');

    { === Register offset sanity === }
    Assert(UHCI_REG_USBCMD = $00, 'REG_USBCMD=$00');
    Assert(UHCI_REG_USBSTS = $02, 'REG_USBSTS=$02');
    Assert(UHCI_REG_FRBASEADD = $08, 'REG_FRBASEADD=$08');
    Assert(UHCI_REG_PORTSC1 = $10, 'REG_PORTSC1=$10');
    Assert(UHCI_REG_PORTSC2 = $12, 'REG_PORTSC2=$12');

    { === Port status bit constants === }
    Assert(UHCI_PORT_CCS = $0001, 'PORT_CCS=$0001');
    Assert(UHCI_PORT_PE = $0004, 'PORT_PE=$0004');
    Assert(UHCI_PORT_PR = $0200, 'PORT_PR=$0200');
    Assert(UHCI_PORT_LSDA = $0100, 'PORT_LSDA=$0100');

    PrintSummary;
end;

end.
