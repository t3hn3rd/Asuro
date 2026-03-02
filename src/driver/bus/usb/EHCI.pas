{
    Driver->Bus->USB->EHCI - Enhanced Host Controller Interface Driver.

    Implements the EHCI (USB 2.0) host controller for MMIO-based controllers.
    EHCI uses Queue Heads (QH), queue Transfer Descriptors (qTD), and a
    Periodic Frame List for scheduling high-speed transfers.

    EHCI also handles companion controller (UHCI/OHCI) routing for
    full/low-speed devices via the CONFIGFLAG and PORTSC port-owner bits.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit ehci;

interface

uses
    tracer,
    syslog,
    PCI,
    drivertypes,
    pmemorymanager,
    vmemorymanager,
    lmemorymanager,
    util,
    drivermanagement,
    usbtypes,
    usbcore,
    isrmanager,
    lists,
    strings;

function load : boolean;
procedure UnitTest;

implementation

{ ========================= EHCI Capability Register Offsets ========================= }

const
    { Capability Registers (read-only, at MMIO Base) }
    EHCI_CAP_CAPLENGTH         = $00;  { 1 byte: offset to operational registers }
    EHCI_CAP_HCIVERSION        = $02;  { 2 bytes: BCD interface version }
    EHCI_CAP_HCSPARAMS         = $04;  { 4 bytes: structural parameters }
    EHCI_CAP_HCCPARAMS         = $08;  { 4 bytes: capability parameters }
    EHCI_CAP_HCSP_PORTROUTE    = $0C;  { 8 bytes: companion port route (optional) }

{ ========================= EHCI Operational Register Offsets ========================= }

    { Operational Registers (at MMIO Base + CAPLENGTH) }
    EHCI_OP_USBCMD             = $00;  { USB Command }
    EHCI_OP_USBSTS             = $04;  { USB Status }
    EHCI_OP_USBINTR            = $08;  { USB Interrupt Enable }
    EHCI_OP_FRINDEX            = $0C;  { Frame Index }
    EHCI_OP_CTRLDSSEGMENT      = $10;  { 4G Segment Selector (64-bit, we use 0) }
    EHCI_OP_PERIODICLISTBASE   = $14;  { Periodic Frame List Base Address }
    EHCI_OP_ASYNCLISTADDR      = $18;  { Current Asynchronous List Address }
    EHCI_OP_CONFIGFLAG         = $40;  { Configure Flag }
    EHCI_OP_PORTSC             = $44;  { Port Status/Control (port 0); each port +4 }

{ ========================= USBCMD Bits ========================= }

    EHCI_CMD_RS                = $00000001; { Run/Stop: 1=run, 0=stop }
    EHCI_CMD_HCRESET           = $00000002; { Host Controller Reset }
    EHCI_CMD_FLS_MASK          = $0000000C; { Frame List Size (bits 3:2) }
    EHCI_CMD_FLS_1024          = $00000000; { 1024 elements }
    EHCI_CMD_FLS_512           = $00000004; { 512 elements }
    EHCI_CMD_FLS_256           = $00000008; { 256 elements }
    EHCI_CMD_PSE               = $00000010; { Periodic Schedule Enable }
    EHCI_CMD_ASE               = $00000020; { Asynchronous Schedule Enable }
    EHCI_CMD_IAAD              = $00000040; { Interrupt on Async Advance Doorbell }
    EHCI_CMD_LHCR              = $00000080; { Light Host Controller Reset }
    EHCI_CMD_ASPMC_MASK        = $00000300; { Async Schedule Park Mode Count }
    EHCI_CMD_ASPME             = $00000800; { Async Schedule Park Mode Enable }
    EHCI_CMD_ITC_MASK          = $00FF0000; { Interrupt Threshold Control }
    EHCI_CMD_ITC_1             = $00010000; { 1 micro-frame }
    EHCI_CMD_ITC_8             = $00080000; { 8 micro-frames (default, 1ms) }

{ ========================= USBSTS Bits ========================= }

    EHCI_STS_USBINT            = $00000001; { USB Interrupt (transfer complete) }
    EHCI_STS_USBERRINT         = $00000002; { USB Error Interrupt }
    EHCI_STS_PCD               = $00000004; { Port Change Detect }
    EHCI_STS_FLR               = $00000008; { Frame List Rollover }
    EHCI_STS_HSE               = $00000010; { Host System Error }
    EHCI_STS_IAA               = $00000020; { Interrupt on Async Advance }
    EHCI_STS_HCHALTED          = $00001000; { HCHalted }
    EHCI_STS_RECLAMATION       = $00002000; { Reclamation }
    EHCI_STS_PSS               = $00004000; { Periodic Schedule Status }
    EHCI_STS_ASS               = $00008000; { Async Schedule Status }

{ ========================= PORTSC Bits ========================= }

    EHCI_PORTSC_CCS            = $00000001; { Current Connect Status }
    EHCI_PORTSC_CSC            = $00000002; { Connect Status Change }
    EHCI_PORTSC_PE             = $00000004; { Port Enabled }
    EHCI_PORTSC_PEC            = $00000008; { Port Enable Change }
    EHCI_PORTSC_OCA            = $00000010; { Over-current Active }
    EHCI_PORTSC_OCC            = $00000020; { Over-current Change }
    EHCI_PORTSC_FPR            = $00000040; { Force Port Resume }
    EHCI_PORTSC_SUSPEND        = $00000080; { Suspend }
    EHCI_PORTSC_PRST           = $00000100; { Port Reset }
    EHCI_PORTSC_LS_MASK        = $00000C00; { Line Status (bits 11:10) }
    EHCI_PORTSC_LS_SE0         = $00000000; { SE0 }
    EHCI_PORTSC_LS_JSTATE      = $00000400; { J-state (low-speed) }
    EHCI_PORTSC_LS_KSTATE      = $00000800; { K-state (low-speed) }
    EHCI_PORTSC_PP             = $00001000; { Port Power }
    EHCI_PORTSC_PO             = $00002000; { Port Owner (1=companion HC) }
    EHCI_PORTSC_PIC_MASK       = $0000C000; { Port Indicator Control }
    EHCI_PORTSC_PTC_MASK       = $000F0000; { Port Test Control }
    EHCI_PORTSC_WKOC_E         = $00400000; { Wake on Over-current Enable }
    EHCI_PORTSC_WKDSCNNT_E    = $00200000; { Wake on Disconnect Enable }
    EHCI_PORTSC_WKCNNT_E      = $00100000; { Wake on Connect Enable }

    { Write-clear bits in PORTSC (must preserve when writing other bits) }
    EHCI_PORTSC_WC_BITS        = EHCI_PORTSC_CSC OR EHCI_PORTSC_PEC
                                  OR EHCI_PORTSC_OCC;

{ ========================= HCSPARAMS Bits ========================= }

    EHCI_HCS_N_PORTS_MASK      = $0000000F; { Number of Ports (bits 3:0) }
    EHCI_HCS_PPC               = $00000010; { Port Power Control }
    EHCI_HCS_PRR               = $00000080; { Port Routing Rules }
    EHCI_HCS_N_PCC_MASK        = $00000F00; { Ports per Companion Controller (bits 11:8) }
    EHCI_HCS_N_PCC_SHIFT       = 8;
    EHCI_HCS_N_CC_MASK         = $0000F000; { Number of Companion Controllers (bits 15:12) }
    EHCI_HCS_N_CC_SHIFT        = 12;
    EHCI_HCS_P_INDICATOR       = $00010000; { Port Indicators }
    EHCI_HCS_DPN_MASK          = $00F00000; { Debug Port Number (bits 23:20) }
    EHCI_HCS_DPN_SHIFT         = 20;

{ ========================= HCCPARAMS Bits ========================= }

    EHCI_HCC_64BIT             = $00000001; { 64-bit Addressing Capability }
    EHCI_HCC_PFLF              = $00000002; { Programmable Frame List Flag }
    EHCI_HCC_ASPC              = $00000004; { Async Schedule Park Capability }
    EHCI_HCC_IST_MASK          = $000000F0; { Isochronous Scheduling Threshold }
    EHCI_HCC_EECP_MASK         = $0000FF00; { EHCI Extended Capabilities Pointer }
    EHCI_HCC_EECP_SHIFT        = 8;

{ ========================= CONFIGFLAG ========================= }

    EHCI_CF_FLAG               = $00000001; { Configure Flag: 1=route all ports to EHCI }

{ ========================= Frame List ========================= }

    EHCI_FL_SIZE               = 1024;     { Number of frame list entries }
    EHCI_FL_BYTES              = 4096;     { 1024 x 4 bytes = 4KB }
    EHCI_FL_ALIGN              = 4096;     { 4KB alignment }

    { Frame List Entry bits }
    EHCI_FL_T                  = $00000001; { Terminate bit }
    EHCI_FL_TYPE_MASK          = $00000006; { Type (bits 2:1) }
    EHCI_FL_TYPE_ITD           = $00000000; { Isochronous Transfer Descriptor }
    EHCI_FL_TYPE_QH            = $00000002; { Queue Head }
    EHCI_FL_TYPE_SITD          = $00000004; { Split Transaction Isochronous TD }
    EHCI_FL_TYPE_FSTN          = $00000006; { Frame Span Traversal Node }

{ ========================= Queue Head (QH) ========================= }

    EHCI_QH_ALIGN              = 32;       { 32-byte alignment }

    { QH Endpoint Characteristics (DWord 1) }
    EHCI_QH_DEVADDR_MASK       = $0000007F; { Device Address (bits 6:0) }
    EHCI_QH_I                  = $00000080; { Inactivate on Next Transaction }
    EHCI_QH_ENDPT_MASK         = $00000F00; { Endpoint Number (bits 11:8) }
    EHCI_QH_ENDPT_SHIFT        = 8;
    EHCI_QH_EPS_MASK           = $00003000; { Endpoint Speed (bits 13:12) }
    EHCI_QH_EPS_FULL           = $00000000; { Full Speed }
    EHCI_QH_EPS_LOW            = $00001000; { Low Speed }
    EHCI_QH_EPS_HIGH           = $00002000; { High Speed }
    EHCI_QH_DTC                = $00004000; { Data Toggle Control }
    EHCI_QH_H                  = $00008000; { Head of Reclamation List Flag }
    EHCI_QH_MPL_MASK           = $07FF0000; { Maximum Packet Length (bits 26:16) }
    EHCI_QH_MPL_SHIFT          = 16;
    EHCI_QH_C                  = $08000000; { Control Endpoint Flag }
    EHCI_QH_RL_MASK            = $F0000000; { NAK Count Reload (bits 31:28) }
    EHCI_QH_RL_SHIFT           = 28;

    { QH Endpoint Capabilities (DWord 2) }
    EHCI_QH_SMASK_MASK         = $000000FF; { Interrupt Schedule Mask (bits 7:0) }
    EHCI_QH_CMASK_MASK         = $0000FF00; { Split Completion Mask (bits 15:8) }
    EHCI_QH_CMASK_SHIFT        = 8;
    EHCI_QH_HUBADDR_MASK       = $007F0000; { Hub Address (bits 22:16) }
    EHCI_QH_HUBADDR_SHIFT      = 16;
    EHCI_QH_HUBPORT_MASK       = $3F800000; { Hub Port (bits 29:23) }
    EHCI_QH_HUBPORT_SHIFT      = 23;
    EHCI_QH_MULT_MASK          = $C0000000; { High-Bandwidth Pipe Multiplier (bits 31:30) }
    EHCI_QH_MULT_SHIFT         = 30;

{ ========================= Queue Transfer Descriptor (qTD) ========================= }

    EHCI_QTD_ALIGN             = 32;       { 32-byte alignment }

    { qTD Token (DWord 2) }
    EHCI_QTD_STATUS_MASK       = $000000FF; { Status (bits 7:0) }
    EHCI_QTD_STS_ACTIVE        = $00000080; { Active }
    EHCI_QTD_STS_HALTED        = $00000040; { Halted }
    EHCI_QTD_STS_BUFERR        = $00000020; { Data Buffer Error }
    EHCI_QTD_STS_BABBLE        = $00000010; { Babble Detected }
    EHCI_QTD_STS_XACTERR       = $00000008; { Transaction Error }
    EHCI_QTD_STS_MISSED_UF     = $00000004; { Missed Micro-Frame }
    EHCI_QTD_STS_SPLITXSTATE   = $00000002; { Split Transaction State }
    EHCI_QTD_STS_PING          = $00000001; { Ping State / ERR }
    EHCI_QTD_PID_MASK          = $00000300; { PID Code (bits 9:8) }
    EHCI_QTD_PID_OUT           = $00000000; { OUT token }
    EHCI_QTD_PID_IN            = $00000100; { IN token }
    EHCI_QTD_PID_SETUP         = $00000200; { SETUP token }
    EHCI_QTD_CERR_MASK         = $00000C00; { Error Counter (bits 11:10) }
    EHCI_QTD_CERR_SHIFT        = 10;
    EHCI_QTD_CPAGE_MASK        = $00007000; { Current Page (bits 14:12) }
    EHCI_QTD_CPAGE_SHIFT       = 12;
    EHCI_QTD_IOC               = $00008000; { Interrupt On Complete }
    EHCI_QTD_TOTALBYTES_MASK   = $7FFF0000; { Total Bytes to Transfer (bits 30:16) }
    EHCI_QTD_TOTALBYTES_SHIFT  = 16;
    EHCI_QTD_DT                = $80000000; { Data Toggle (bit 31) }

    { qTD Next/AltNext pointer }
    EHCI_QTD_T                 = $00000001; { Terminate bit }

    { Max transfer size per qTD (5 pages x 4KB, minus page offset of first) }
    EHCI_QTD_MAX_TRANSFER      = 20480;    { 5 x 4096 }

    { Max qTDs per transfer }
    EHCI_MAX_QTDS_PER_TRANSFER = 128;

{ ========================= EHCI Data Structures ========================= }

type
    { Queue Transfer Descriptor (qTD) - 32 bytes HC-visible, 32-byte aligned }
    PEHCI_qTD = ^TEHCI_qTD;
    TEHCI_qTD = packed record
        NextqTD    : uint32; { Next qTD pointer (physical | T-bit) }
        AltNextqTD : uint32; { Alternate next qTD pointer }
        Token      : uint32; { Status, PID, error counter, bytes, toggle, IOC }
        Buffer     : array[0..4] of uint32; { Buffer page pointers (physical) }
        { -- Software fields (beyond the 32 bytes the HC reads) -- }
        SWNext     : PEHCI_qTD;  { Software linked list }
        SWTransfer : Pointer;    { Back-pointer to owning TUSBTransfer }
        SWPad0     : uint32;
        SWPad1     : uint32;
    end;

    { Queue Head (QH) - 48 bytes HC-visible, 32-byte aligned, padded to 64 }
    PEHCI_QH = ^TEHCI_QH;
    TEHCI_QH = packed record
        HorizLink   : uint32; { Horizontal link pointer (physical | type | T) }
        EPChars     : uint32; { Endpoint characteristics }
        EPCaps      : uint32; { Endpoint capabilities }
        CurqTD      : uint32; { Current qTD pointer }
        { Overlay area (transfer state, 32 bytes) }
        OvlNextqTD  : uint32;
        OvlAltNext  : uint32;
        OvlToken    : uint32;
        OvlBuffer   : array[0..4] of uint32;
        { -- Software fields -- }
        SWNext      : PEHCI_QH;   { Software linked list of QHs }
        SWTransfer  : Pointer;    { Back-pointer to owning TUSBTransfer }
        SWFirstqTD  : PEHCI_qTD; { First qTD in chain (for cleanup) }
        SWPad       : uint32;
    end;

    { Private data for an EHCI host controller instance }
    PEHCI_PrivData = ^TEHCI_PrivData;
    TEHCI_PrivData = record
        MMIOBase     : uint32;     { BAR0 MMIO base (virtual = physical) }
        OpBase       : uint32;     { Operational registers base (MMIOBase + CAPLENGTH) }
        FrameList    : Pointer;    { 4KB-aligned periodic frame list }
        AsyncQH      : PEHCI_QH;  { Async schedule head (reclamation head) }
        IntrQH       : PEHCI_QH;  { Interrupt schedule sentinel QH }
        NumPorts     : uint8;      { Number of downstream ports }
        NumCC        : uint8;      { Number of companion controllers }
        PortsPerCC   : uint8;      { Ports per companion controller }
        Has64Bit     : boolean;    { 64-bit addressing capable }
        HCSPARAMS    : uint32;     { Cached structural parameters }
        HCCPARAMS    : uint32;     { Cached capability parameters }
        PollBusy     : boolean;    { Re-entrancy guard for poll }
        PCIBus       : uint8;
        PCISlot      : uint8;
        PCIFunc      : uint8;
    end;

{ ========================= MMIO Helpers ========================= }

function ehci_readl(base : uint32; reg : uint32) : uint32;
begin
    ehci_readl := PUint32(base + reg)^;
end;

procedure ehci_writel(base : uint32; reg : uint32; val : uint32);
begin
    PUint32(base + reg)^ := val;
end;

function ehci_readb(base : uint32; reg : uint32) : uint8;
begin
    ehci_readb := PUint8(base + reg)^;
end;

function ehci_readw(base : uint32; reg : uint32) : uint16;
begin
    ehci_readw := PUint16(base + reg)^;
end;

{ ========================= qTD/QH Allocation ========================= }

function ehci_alloc_qtd : PEHCI_qTD;
begin
    ehci_alloc_qtd := PEHCI_qTD(kalloc_aligned(sizeof(TEHCI_qTD), EHCI_QTD_ALIGN));
    if ehci_alloc_qtd <> nil then
        memset(uint32(ehci_alloc_qtd), 0, sizeof(TEHCI_qTD));
end;

procedure ehci_free_qtd(qtd : PEHCI_qTD);
begin
    if qtd <> nil then
        kfree_aligned(qtd);
end;

function ehci_alloc_qh : PEHCI_QH;
begin
    ehci_alloc_qh := PEHCI_QH(kalloc_aligned(sizeof(TEHCI_QH), EHCI_QH_ALIGN));
    if ehci_alloc_qh <> nil then
        memset(uint32(ehci_alloc_qh), 0, sizeof(TEHCI_QH));
end;

procedure ehci_free_qh(qh : PEHCI_QH);
begin
    if qh <> nil then
        kfree_aligned(qh);
end;

{ ========================= qTD/QH Construction Helpers ========================= }

{ Build QH endpoint characteristics dword }
function ehci_make_qh_epchars(devAddr : uint8; ep : uint8; speed : uint32;
                               maxPkt : uint16; dtc : boolean;
                               isHead : boolean; ctrlEP : boolean;
                               nakRL : uint8) : uint32;
begin
    ehci_make_qh_epchars :=
        (uint32(devAddr) AND $7F)
        OR ((uint32(ep) AND $0F) SHL EHCI_QH_ENDPT_SHIFT)
        OR (speed AND EHCI_QH_EPS_MASK)
        OR ((uint32(maxPkt) AND $7FF) SHL EHCI_QH_MPL_SHIFT)
        OR ((uint32(nakRL) AND $0F) SHL EHCI_QH_RL_SHIFT);
    if dtc then
        ehci_make_qh_epchars := ehci_make_qh_epchars OR EHCI_QH_DTC;
    if isHead then
        ehci_make_qh_epchars := ehci_make_qh_epchars OR EHCI_QH_H;
    if ctrlEP then
        ehci_make_qh_epchars := ehci_make_qh_epchars OR EHCI_QH_C;
end;

{ Build QH endpoint capabilities dword }
function ehci_make_qh_epcaps(sMask : uint8; cMask : uint8;
                              hubAddr : uint8; hubPort : uint8;
                              mult : uint8) : uint32;
begin
    ehci_make_qh_epcaps :=
        (uint32(sMask) AND $FF)
        OR ((uint32(cMask) AND $FF) SHL EHCI_QH_CMASK_SHIFT)
        OR ((uint32(hubAddr) AND $7F) SHL EHCI_QH_HUBADDR_SHIFT)
        OR ((uint32(hubPort) AND $3F) SHL EHCI_QH_HUBPORT_SHIFT)
        OR ((uint32(mult) AND $03) SHL EHCI_QH_MULT_SHIFT);
end;

{ Build a qTD token dword }
function ehci_make_qtd_token(pid : uint32; toggle : boolean;
                              totalBytes : uint16; ioc : boolean;
                              cerr : uint8) : uint32;
begin
    ehci_make_qtd_token :=
        EHCI_QTD_STS_ACTIVE
        OR (pid AND EHCI_QTD_PID_MASK)
        OR ((uint32(cerr) AND $03) SHL EHCI_QTD_CERR_SHIFT)
        OR ((uint32(totalBytes) AND $7FFF) SHL EHCI_QTD_TOTALBYTES_SHIFT);
    if toggle then
        ehci_make_qtd_token := ehci_make_qtd_token OR EHCI_QTD_DT;
    if ioc then
        ehci_make_qtd_token := ehci_make_qtd_token OR EHCI_QTD_IOC;
end;

{ Extract status byte from qTD token }
function ehci_qtd_status(qtd : PEHCI_qTD) : uint8;
begin
    ehci_qtd_status := uint8(qtd^.Token AND EHCI_QTD_STATUS_MASK);
end;

{ Extract total bytes remaining from qTD token }
function ehci_qtd_bytes_remaining(qtd : PEHCI_qTD) : uint16;
begin
    ehci_qtd_bytes_remaining := uint16((qtd^.Token AND EHCI_QTD_TOTALBYTES_MASK) SHR EHCI_QTD_TOTALBYTES_SHIFT);
end;

{ Map qTD status bits to USB transfer status }
function ehci_status_to_usb(status : uint8) : TUSBTransferStatus;
begin
    if (status AND EHCI_QTD_STS_ACTIVE) <> 0 then
        ehci_status_to_usb := tsInProgress
    else if (status AND EHCI_QTD_STS_HALTED) <> 0 then begin
        if (status AND EHCI_QTD_STS_BABBLE) <> 0 then
            ehci_status_to_usb := tsBabble
        else if (status AND EHCI_QTD_STS_BUFERR) <> 0 then
            ehci_status_to_usb := tsDataBufferError
        else if (status AND EHCI_QTD_STS_XACTERR) <> 0 then
            ehci_status_to_usb := tsCRCError
        else
            ehci_status_to_usb := tsStall;
    end else
        ehci_status_to_usb := tsSuccess;
end;

{ Fill qTD buffer pointers for a given virtual buffer.
  EHCI qTDs use up to 5 page pointers (each 4KB-aligned) plus
  the offset in the first page. }
procedure ehci_fill_qtd_buffers(qtd : PEHCI_qTD; buf : Pointer; len : uint32);
var
    phys    : uint32;
    pg      : uint32;
    remain  : uint32;
begin
    if (buf = nil) or (len = 0) then exit;
    phys := vtop(uint32(buf));
    qtd^.Buffer[0] := phys;
    { Remaining pages }
    remain := len;
    { Bytes left on first page }
    pg := 4096 - (phys AND $FFF);
    if pg >= remain then exit;
    remain := remain - pg;
    phys := (phys AND $FFFFF000) + 4096;
    if remain > 0 then begin
        qtd^.Buffer[1] := phys;
        if remain > 4096 then begin
            phys := phys + 4096;
            remain := remain - 4096;
            qtd^.Buffer[2] := phys;
            if remain > 4096 then begin
                phys := phys + 4096;
                remain := remain - 4096;
                qtd^.Buffer[3] := phys;
                if remain > 4096 then begin
                    phys := phys + 4096;
                    qtd^.Buffer[4] := phys;
                end;
            end;
        end;
    end;
end;

{ ========================= HC Callback Forward Declarations ========================= }

function ehci_reset(hc : PUSBHCDriver) : boolean; forward;
function ehci_start(hc : PUSBHCDriver) : boolean; forward;
procedure ehci_stop(hc : PUSBHCDriver); forward;
function ehci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean; forward;
procedure ehci_poll(hc : PUSBHCDriver); forward;
function ehci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean; forward;
function ehci_port_status(hc : PUSBHCDriver; port : uint8) : uint32; forward;

{ ========================= BIOS Handoff (Legacy Support) ========================= }

procedure ehci_bios_handoff(priv : PEHCI_PrivData; pciDev : TPCI_Device);
var
    eecp   : uint32;
    row    : uint8;
    cap    : uint32;
    legsup : uint32;
    loops  : uint32;
begin
    push_trace('EHCI.ehci_bios_handoff');
    eecp := (priv^.HCCPARAMS AND EHCI_HCC_EECP_MASK) SHR EHCI_HCC_EECP_SHIFT;
    if eecp < $40 then begin
        pop_trace;
        exit; { No extended capabilities or invalid }
    end;

    row := uint8(eecp SHR 2);

    { Read capability ID at EECP offset in PCI config }
    PCI.requestConfig(pciDev.bus, pciDev.slot, pciDev.func, row);
    cap := inl($CFC);
    if (cap AND $FF) <> 1 then begin
        { Not a USB Legacy Support capability }
        pop_trace;
        exit;
    end;

    { Check BIOS ownership (bit 16 of the legacy support register) }
    legsup := cap;
    if (legsup AND $00010000) = 0 then begin
        syslog.logln('EHCI', 'BIOS does not own controller.');
        pop_trace;
        exit;
    end;

    { Request ownership: set OS Owned Semaphore (bit 24) }
    PCI.writeConfig(pciDev.bus, pciDev.slot, pciDev.func, row,
                     legsup OR $01000000);

    { Wait for BIOS to release (bit 16 clears) }
    loops := 0;
    while loops < 200000 do begin
        PCI.requestConfig(pciDev.bus, pciDev.slot, pciDev.func, row);
        legsup := inl($CFC);
        if (legsup AND $00010000) = 0 then begin
            syslog.logln('EHCI', 'BIOS handoff complete.');
            pop_trace;
            exit;
        end;
        inc(loops);
    end;

    { Force ownership if BIOS did not release }
    syslog.logln('EHCI', 'BIOS handoff timeout, forcing ownership.');
    PCI.writeConfig(pciDev.bus, pciDev.slot, pciDev.func, row,
                     (legsup AND (NOT uint32($00010000))) OR $01000000);

    { Clear legacy support control/status }
    if (eecp + 4) < 256 then
        PCI.writeConfig(pciDev.bus, pciDev.slot, pciDev.func, row + 1, 0);

    pop_trace;
end;

{ ========================= Reset ========================= }

function ehci_reset(hc : PUSBHCDriver) : boolean;
var
    priv   : PEHCI_PrivData;
    opbase : uint32;
    loops  : uint32;
    cmd    : uint32;
begin
    push_trace('EHCI.ehci_reset');
    ehci_reset := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PEHCI_PrivData(hc^.PrivData);
    opbase := priv^.OpBase;

    { Stop the controller first }
    cmd := ehci_readl(opbase, EHCI_OP_USBCMD);
    cmd := cmd AND (NOT EHCI_CMD_RS);
    cmd := cmd AND (NOT EHCI_CMD_ASE);
    cmd := cmd AND (NOT EHCI_CMD_PSE);
    ehci_writel(opbase, EHCI_OP_USBCMD, cmd);

    { Wait for halted }
    loops := 0;
    while loops < 100000 do begin
        if (ehci_readl(opbase, EHCI_OP_USBSTS) AND EHCI_STS_HCHALTED) <> 0 then
            break;
        inc(loops);
    end;

    if (ehci_readl(opbase, EHCI_OP_USBSTS) AND EHCI_STS_HCHALTED) = 0 then begin
        syslog.logln('EHCI', 'Controller did not halt!');
        pop_trace;
        exit;
    end;

    { Issue reset }
    ehci_writel(opbase, EHCI_OP_USBCMD, EHCI_CMD_HCRESET);

    { Wait for reset to complete (HCRESET bit self-clears) }
    loops := 0;
    while loops < 100000 do begin
        if (ehci_readl(opbase, EHCI_OP_USBCMD) AND EHCI_CMD_HCRESET) = 0 then
            break;
        inc(loops);
    end;

    if (ehci_readl(opbase, EHCI_OP_USBCMD) AND EHCI_CMD_HCRESET) <> 0 then begin
        syslog.logln('EHCI', 'HC reset timeout!');
        pop_trace;
        exit;
    end;

    { Disable all interrupts }
    ehci_writel(opbase, EHCI_OP_USBINTR, 0);

    { Clear all pending status }
    ehci_writel(opbase, EHCI_OP_USBSTS, $3F);

    { Set 4G segment to 0 (we are 32-bit) }
    ehci_writel(opbase, EHCI_OP_CTRLDSSEGMENT, 0);

    syslog.logln('EHCI', 'HC reset complete.');
    ehci_reset := true;
    pop_trace;
end;

{ ========================= Schedule Setup ========================= }

procedure ehci_setup_schedule(hc : PUSBHCDriver);
var
    priv     : PEHCI_PrivData;
    framePtr : PUint32;
    i        : uint32;
    asyncQH  : PEHCI_QH;
    intrQH   : PEHCI_QH;
begin
    push_trace('EHCI.ehci_setup_schedule');
    priv := PEHCI_PrivData(hc^.PrivData);

    { Allocate periodic frame list (4KB, page-aligned) }
    priv^.FrameList := kalloc_aligned(EHCI_FL_BYTES, EHCI_FL_ALIGN);
    if priv^.FrameList = nil then begin
        syslog.logln('EHCI', 'Failed to allocate frame list!');
        pop_trace;
        exit;
    end;

    { Create interrupt sentinel QH (linked into periodic schedule) }
    intrQH := ehci_alloc_qh;
    if intrQH = nil then begin
        syslog.logln('EHCI', 'Failed to allocate interrupt QH!');
        pop_trace;
        exit;
    end;
    priv^.IntrQH := intrQH;

    { Configure interrupt QH as a dummy/sentinel - not head of reclamation }
    intrQH^.HorizLink := EHCI_QTD_T; { terminate - no next QH in periodic }
    intrQH^.EPChars   := ehci_make_qh_epchars(0, 0, EHCI_QH_EPS_HIGH, 8,
                                                false, false, false, 0);
    intrQH^.EPCaps    := ehci_make_qh_epcaps(0, 0, 0, 0, 1);
    intrQH^.CurqTD    := 0;
    intrQH^.OvlNextqTD := EHCI_QTD_T;
    intrQH^.OvlAltNext := EHCI_QTD_T;
    intrQH^.OvlToken   := 0;
    intrQH^.SWNext     := nil;
    intrQH^.SWTransfer := nil;
    intrQH^.SWFirstqTD := nil;

    { Fill periodic frame list: all entries point to the interrupt sentinel QH }
    framePtr := PUint32(priv^.FrameList);
    for i := 0 to EHCI_FL_SIZE - 1 do begin
        PUint32(uint32(framePtr) + (i * 4))^ :=
            vtop(uint32(intrQH)) OR EHCI_FL_TYPE_QH;
    end;

    { Create async schedule head QH (circular, reclamation head) }
    asyncQH := ehci_alloc_qh;
    if asyncQH = nil then begin
        syslog.logln('EHCI', 'Failed to allocate async QH!');
        pop_trace;
        exit;
    end;
    priv^.AsyncQH := asyncQH;

    { Configure async head: H=1, points to self, empty overlay }
    asyncQH^.HorizLink := vtop(uint32(asyncQH)) OR EHCI_FL_TYPE_QH;
    asyncQH^.EPChars   := ehci_make_qh_epchars(0, 0, EHCI_QH_EPS_HIGH, 64,
                                                 false, true, false, 0);
    asyncQH^.EPCaps    := ehci_make_qh_epcaps(0, 0, 0, 0, 1);
    asyncQH^.CurqTD    := 0;
    asyncQH^.OvlNextqTD := EHCI_QTD_T;
    asyncQH^.OvlAltNext := EHCI_QTD_T;
    asyncQH^.OvlToken   := 0; { Not active = halted, HC will not process }
    asyncQH^.SWNext     := nil;
    asyncQH^.SWTransfer := nil;
    asyncQH^.SWFirstqTD := nil;

    { Program the schedule base addresses }
    ehci_writel(priv^.OpBase, EHCI_OP_PERIODICLISTBASE, vtop(uint32(priv^.FrameList)));
    ehci_writel(priv^.OpBase, EHCI_OP_ASYNCLISTADDR, vtop(uint32(asyncQH)));

    syslog.logln('EHCI', 'Schedule configured.');
    pop_trace;
end;

{ ========================= Start ========================= }

function ehci_start(hc : PUSBHCDriver) : boolean;
var
    priv   : PEHCI_PrivData;
    opbase : uint32;
    cmd    : uint32;
    loops  : uint32;
    port   : uint32;
begin
    push_trace('EHCI.ehci_start');
    ehci_start := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PEHCI_PrivData(hc^.PrivData);
    opbase := priv^.OpBase;

    { Set CONFIGFLAG to route all ports to EHCI }
    ehci_writel(opbase, EHCI_OP_CONFIGFLAG, EHCI_CF_FLAG);

    { Small delay for port routing to settle }
    loops := 0;
    while loops < 50000 do inc(loops);

    { Build command: run + async schedule enable + periodic schedule enable }
    { Use 1024-element frame list, ITC = 8 micro-frames (1ms) }
    cmd := EHCI_CMD_RS
        OR EHCI_CMD_ASE
        OR EHCI_CMD_PSE
        OR EHCI_CMD_FLS_1024
        OR EHCI_CMD_ITC_8;
    ehci_writel(opbase, EHCI_OP_USBCMD, cmd);

    { Wait until controller is not halted }
    loops := 0;
    while loops < 100000 do begin
        if (ehci_readl(opbase, EHCI_OP_USBSTS) AND EHCI_STS_HCHALTED) = 0 then
            break;
        inc(loops);
    end;

    if (ehci_readl(opbase, EHCI_OP_USBSTS) AND EHCI_STS_HCHALTED) <> 0 then begin
        syslog.logln('EHCI', 'Controller failed to start (still halted).');
        pop_trace;
        exit;
    end;

    { Power on all ports (if PPC is supported) }
    if (priv^.HCSPARAMS AND EHCI_HCS_PPC) <> 0 then begin
        for port := 0 to priv^.NumPorts - 1 do begin
            ehci_writel(opbase, EHCI_OP_PORTSC + (port * 4), EHCI_PORTSC_PP);
        end;
        { Wait for power to stabilize }
        loops := 0;
        while loops < 100000 do inc(loops);
    end;

    syslog.logln('EHCI', 'Controller started (operational).');
    ehci_start := true;
    pop_trace;
end;

{ ========================= Stop ========================= }

procedure ehci_stop(hc : PUSBHCDriver);
var
    priv   : PEHCI_PrivData;
    opbase : uint32;
    cmd    : uint32;
begin
    push_trace('EHCI.ehci_stop');
    if (hc <> nil) and (hc^.PrivData <> nil) then begin
        priv := PEHCI_PrivData(hc^.PrivData);
        opbase := priv^.OpBase;
        cmd := ehci_readl(opbase, EHCI_OP_USBCMD);
        cmd := cmd AND (NOT EHCI_CMD_RS);
        cmd := cmd AND (NOT EHCI_CMD_ASE);
        cmd := cmd AND (NOT EHCI_CMD_PSE);
        ehci_writel(opbase, EHCI_OP_USBCMD, cmd);
        syslog.logln('EHCI', 'Controller stopped.');
    end;
    pop_trace;
end;

{ ========================= Port Status ========================= }

function ehci_port_status(hc : PUSBHCDriver; port : uint8) : uint32;
var
    priv : PEHCI_PrivData;
begin
    push_trace('EHCI.ehci_port_status');
    ehci_port_status := 0;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PEHCI_PrivData(hc^.PrivData);
    if port >= priv^.NumPorts then begin
        pop_trace;
        exit;
    end;
    ehci_port_status := ehci_readl(priv^.OpBase, EHCI_OP_PORTSC + (uint32(port) * 4));
    pop_trace;
end;

{ ========================= Port Reset ========================= }

function ehci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean;
var
    priv   : PEHCI_PrivData;
    opbase : uint32;
    regOfs : uint32;
    status : uint32;
    loops  : uint32;
begin
    push_trace('EHCI.ehci_port_reset');
    ehci_port_reset := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := PEHCI_PrivData(hc^.PrivData);
    opbase := priv^.OpBase;
    if port >= priv^.NumPorts then begin
        pop_trace;
        exit;
    end;
    regOfs := EHCI_OP_PORTSC + (uint32(port) * 4);

    status := ehci_readl(opbase, regOfs);

    { Check if device is connected }
    if (status AND EHCI_PORTSC_CCS) = 0 then begin
        pop_trace;
        exit;
    end;

    { Check line status: if K-state (low-speed), release to companion }
    if (status AND EHCI_PORTSC_LS_MASK) = EHCI_PORTSC_LS_KSTATE then begin
        syslog.log('EHCI', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' low-speed device -> companion.');
        { Set port owner to companion HC }
        status := status AND (NOT EHCI_PORTSC_WC_BITS);
        ehci_writel(opbase, regOfs, status OR EHCI_PORTSC_PO);
        pop_trace;
        exit;
    end;

    { Clear the enable bit before reset (per EHCI spec 4.2.2) }
    status := ehci_readl(opbase, regOfs);
    status := status AND (NOT EHCI_PORTSC_WC_BITS);
    status := status AND (NOT EHCI_PORTSC_PE);
    ehci_writel(opbase, regOfs, status);

    { Assert port reset }
    status := ehci_readl(opbase, regOfs);
    status := status AND (NOT EHCI_PORTSC_WC_BITS);
    status := status OR EHCI_PORTSC_PRST;
    ehci_writel(opbase, regOfs, status);

    { Hold reset for ~50ms (USB 2.0 spec 7.1.7.5) }
    loops := 0;
    while loops < 500000 do inc(loops);

    { De-assert port reset }
    status := ehci_readl(opbase, regOfs);
    status := status AND (NOT EHCI_PORTSC_WC_BITS);
    status := status AND (NOT EHCI_PORTSC_PRST);
    ehci_writel(opbase, regOfs, status);

    { Wait for reset to complete (PRST bit must be 0 and PE must be 1) }
    loops := 0;
    while loops < 200000 do begin
        status := ehci_readl(opbase, regOfs);
        if (status AND EHCI_PORTSC_PRST) = 0 then break;
        inc(loops);
    end;

    if (status AND EHCI_PORTSC_PRST) <> 0 then begin
        syslog.log('EHCI', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' reset timeout.');
        pop_trace;
        exit;
    end;

    { Wait for port to be enabled }
    loops := 0;
    while loops < 100000 do begin
        status := ehci_readl(opbase, regOfs);
        if (status AND EHCI_PORTSC_PE) <> 0 then break;
        inc(loops);
    end;

    if (status AND EHCI_PORTSC_PE) = 0 then begin
        { Port not enabled after reset = full/low-speed device, release to companion }
        syslog.log('EHCI', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' not enabled -> companion.');
        status := status AND (NOT EHCI_PORTSC_WC_BITS);
        ehci_writel(opbase, regOfs, status OR EHCI_PORTSC_PO);
        pop_trace;
        exit;
    end;

    { Clear any change bits after reset }
    status := ehci_readl(opbase, regOfs);
    ehci_writel(opbase, regOfs, status OR EHCI_PORTSC_CSC OR EHCI_PORTSC_PEC);

    syslog.log('EHCI', 'Port ');
    syslog.writeint(port);
    syslog.writestringln(' reset and enabled (high-speed).');
    ehci_port_reset := true;
    pop_trace;
end;

{ ========================= Async QH Insertion/Removal ========================= }

{ Insert a QH into the async schedule (after the head) }
procedure ehci_insert_async_qh(priv : PEHCI_PrivData; qh : PEHCI_QH);
var
    head : PEHCI_QH;
begin
    if (priv = nil) or (priv^.AsyncQH = nil) or (qh = nil) then exit;
    head := priv^.AsyncQH;
    { New QH links to whatever head used to link to }
    qh^.HorizLink   := head^.HorizLink;
    qh^.SWNext      := head^.SWNext;
    { Head now links to new QH }
    head^.HorizLink  := vtop(uint32(qh)) OR EHCI_FL_TYPE_QH;
    head^.SWNext     := qh;
end;

{ Remove a QH from the async schedule }
procedure ehci_remove_async_qh(priv : PEHCI_PrivData; target : PEHCI_QH);
var
    prev, cur : PEHCI_QH;
begin
    if (priv = nil) or (priv^.AsyncQH = nil) or (target = nil) then exit;
    prev := priv^.AsyncQH;
    cur := prev^.SWNext;
    while cur <> nil do begin
        if cur = target then begin
            prev^.HorizLink := cur^.HorizLink;
            prev^.SWNext    := cur^.SWNext;
            exit;
        end;
        prev := cur;
        cur := cur^.SWNext;
    end;
end;

{ Insert a QH into the periodic (interrupt) schedule }
procedure ehci_insert_intr_qh(priv : PEHCI_PrivData; qh : PEHCI_QH);
var
    head : PEHCI_QH;
begin
    if (priv = nil) or (priv^.IntrQH = nil) or (qh = nil) then exit;
    head := priv^.IntrQH;
    qh^.HorizLink   := head^.HorizLink;
    qh^.SWNext      := head^.SWNext;
    head^.HorizLink  := vtop(uint32(qh)) OR EHCI_FL_TYPE_QH;
    head^.SWNext     := qh;
end;

{ Remove a QH from the periodic (interrupt) schedule }
procedure ehci_remove_intr_qh(priv : PEHCI_PrivData; target : PEHCI_QH);
var
    prev, cur : PEHCI_QH;
begin
    if (priv = nil) or (priv^.IntrQH = nil) or (target = nil) then exit;
    prev := priv^.IntrQH;
    cur := prev^.SWNext;
    while cur <> nil do begin
        if cur = target then begin
            prev^.HorizLink := cur^.HorizLink;
            prev^.SWNext    := cur^.SWNext;
            exit;
        end;
        prev := cur;
        cur := cur^.SWNext;
    end;
end;

{ ========================= Submit Transfer ========================= }

function ehci_submit_control(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var
    priv     : PEHCI_PrivData;
    dev      : PUSBDevice;
    qh       : PEHCI_QH;
    qtd      : PEHCI_qTD;
    firstqTD : PEHCI_qTD;
    prevqTD  : PEHCI_qTD;
    devAddr  : uint8;
    maxPkt   : uint16;
    speedBits : uint32;
    remaining : uint32;
    offset   : uint32;
    pktLen   : uint16;
    toggle   : boolean;
    pid      : uint32;
    isCtrlEP : boolean;
begin
    push_trace('EHCI.ehci_submit_control');
    ehci_submit_control := false;
    priv := PEHCI_PrivData(hc^.PrivData);
    dev := transfer^.Device;
    devAddr := dev^.Address;
    maxPkt := dev^.MaxPacket0;
    if maxPkt = 0 then maxPkt := 8;

    case dev^.Speed of
        USB_SPEED_LOW:  speedBits := EHCI_QH_EPS_LOW;
        USB_SPEED_FULL: speedBits := EHCI_QH_EPS_FULL;
    else
        speedBits := EHCI_QH_EPS_HIGH;
    end;

    { Control endpoints on non-high-speed devices need the C bit }
    isCtrlEP := (dev^.Speed <> USB_SPEED_HIGH);

    firstqTD := nil;
    prevqTD := nil;

    { SETUP qTD }
    qtd := ehci_alloc_qtd;
    if qtd = nil then begin pop_trace; exit; end;
    firstqTD := qtd;
    qtd^.Token := ehci_make_qtd_token(EHCI_QTD_PID_SETUP, false, 8, false, 3);
    ehci_fill_qtd_buffers(qtd, @transfer^.Setup, 8);
    qtd^.NextqTD    := EHCI_QTD_T;
    qtd^.AltNextqTD := EHCI_QTD_T;
    qtd^.SWTransfer := Pointer(transfer);
    qtd^.SWNext     := nil;
    prevqTD := qtd;

    { DATA qTDs }
    toggle := true; { DATA1 after SETUP }
    remaining := transfer^.BufferLen;
    offset := 0;

    while remaining > 0 do begin
        qtd := ehci_alloc_qtd;
        if qtd = nil then begin pop_trace; exit; end;

        if remaining > maxPkt then
            pktLen := maxPkt
        else
            pktLen := remaining;

        if (transfer^.Setup.bmRequestType AND $80) <> 0 then
            pid := EHCI_QTD_PID_IN
        else
            pid := EHCI_QTD_PID_OUT;

        qtd^.Token := ehci_make_qtd_token(pid, toggle, pktLen, false, 3);
        ehci_fill_qtd_buffers(qtd, Pointer(uint32(transfer^.Buffer) + offset), pktLen);
        qtd^.NextqTD    := EHCI_QTD_T;
        qtd^.AltNextqTD := EHCI_QTD_T;
        qtd^.SWTransfer := Pointer(transfer);
        qtd^.SWNext     := nil;

        { Link to previous }
        prevqTD^.NextqTD := vtop(uint32(qtd));
        prevqTD^.SWNext  := qtd;
        prevqTD := qtd;

        toggle := NOT toggle;
        offset := offset + pktLen;
        remaining := remaining - pktLen;
    end;

    { STATUS qTD (opposite direction, DATA1) }
    qtd := ehci_alloc_qtd;
    if qtd = nil then begin pop_trace; exit; end;

    if (transfer^.Setup.bmRequestType AND $80) <> 0 then
        pid := EHCI_QTD_PID_OUT
    else
        pid := EHCI_QTD_PID_IN;

    qtd^.Token := ehci_make_qtd_token(pid, true, 0, true, 3);
    qtd^.NextqTD    := EHCI_QTD_T;
    qtd^.AltNextqTD := EHCI_QTD_T;
    qtd^.SWTransfer := Pointer(transfer);
    qtd^.SWNext     := nil;

    prevqTD^.NextqTD := vtop(uint32(qtd));
    prevqTD^.SWNext  := qtd;

    { Build QH }
    qh := ehci_alloc_qh;
    if qh = nil then begin pop_trace; exit; end;

    qh^.EPChars  := ehci_make_qh_epchars(devAddr, 0, speedBits, maxPkt,
                                           true, false, isCtrlEP, 4);
    qh^.EPCaps   := ehci_make_qh_epcaps(0, 0, 0, 0, 1);

    { For full/low-speed devices behind a hub: set hub addr/port for split transactions }
    if (dev^.Speed <> USB_SPEED_HIGH) and (dev^.ParentHub <> nil) then begin
        qh^.EPCaps := ehci_make_qh_epcaps(
            $01, { S-mask: micro-frame 0 }
            $1C, { C-mask: micro-frames 2,3,4 }
            dev^.ParentHub^.Address,
            dev^.ParentPort,
            1);
    end;

    qh^.CurqTD     := 0;
    qh^.OvlNextqTD  := vtop(uint32(firstqTD));
    qh^.OvlAltNext  := EHCI_QTD_T;
    qh^.OvlToken    := 0;
    qh^.SWNext      := nil;
    qh^.SWTransfer  := Pointer(transfer);
    qh^.SWFirstqTD  := firstqTD;

    transfer^.HCPriv := Pointer(qh);
    transfer^.Status := tsInProgress;

    { Insert into async schedule }
    ehci_insert_async_qh(priv, qh);

    ehci_submit_control := true;
    pop_trace;
end;

function ehci_submit_async(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var
    priv     : PEHCI_PrivData;
    dev      : PUSBDevice;
    qh       : PEHCI_QH;
    qtd      : PEHCI_qTD;
    firstqTD : PEHCI_qTD;
    prevqTD  : PEHCI_qTD;
    devAddr  : uint8;
    epNum    : uint8;
    maxPkt   : uint16;
    speedBits : uint32;
    remaining : uint32;
    offset   : uint32;
    pktLen   : uint16;
    toggle   : boolean;
    pid      : uint32;
begin
    push_trace('EHCI.ehci_submit_async');
    ehci_submit_async := false;
    priv := PEHCI_PrivData(hc^.PrivData);
    dev := transfer^.Device;
    devAddr := dev^.Address;
    epNum := transfer^.Endpoint^.Address;
    maxPkt := transfer^.Endpoint^.MaxPacket;
    if maxPkt = 0 then maxPkt := 8;

    case dev^.Speed of
        USB_SPEED_LOW:  speedBits := EHCI_QH_EPS_LOW;
        USB_SPEED_FULL: speedBits := EHCI_QH_EPS_FULL;
    else
        speedBits := EHCI_QH_EPS_HIGH;
    end;

    if transfer^.Direction = dirIn then
        pid := EHCI_QTD_PID_IN
    else
        pid := EHCI_QTD_PID_OUT;

    toggle := (transfer^.Endpoint^.Toggle <> 0);

    firstqTD := nil;
    prevqTD := nil;
    remaining := transfer^.BufferLen;
    offset := 0;

    repeat
        qtd := ehci_alloc_qtd;
        if qtd = nil then begin pop_trace; exit; end;

        if firstqTD = nil then firstqTD := qtd;

        if remaining > maxPkt then
            pktLen := maxPkt
        else if remaining > 0 then
            pktLen := remaining
        else
            pktLen := 0;

        qtd^.Token := ehci_make_qtd_token(pid, toggle, pktLen, false, 3);
        if pktLen > 0 then
            ehci_fill_qtd_buffers(qtd, Pointer(uint32(transfer^.Buffer) + offset), pktLen);
        qtd^.NextqTD    := EHCI_QTD_T;
        qtd^.AltNextqTD := EHCI_QTD_T;
        qtd^.SWTransfer := Pointer(transfer);
        qtd^.SWNext     := nil;

        if prevqTD <> nil then begin
            prevqTD^.NextqTD := vtop(uint32(qtd));
            prevqTD^.SWNext  := qtd;
        end;
        prevqTD := qtd;

        toggle := NOT toggle;

        if remaining > maxPkt then begin
            offset := offset + maxPkt;
            remaining := remaining - maxPkt;
        end else begin
            offset := offset + remaining;
            remaining := 0;
        end;
    until remaining = 0;

    { Mark last qTD with IOC }
    if prevqTD <> nil then
        prevqTD^.Token := prevqTD^.Token OR EHCI_QTD_IOC;

    { Update endpoint toggle }
    if toggle then
        transfer^.Endpoint^.Toggle := 1
    else
        transfer^.Endpoint^.Toggle := 0;

    { Build QH }
    qh := ehci_alloc_qh;
    if qh = nil then begin pop_trace; exit; end;

    qh^.EPChars := ehci_make_qh_epchars(devAddr, epNum, speedBits, maxPkt,
                                          true, false, false, 4);
    qh^.EPCaps  := ehci_make_qh_epcaps(0, 0, 0, 0, 1);

    { For full/low-speed behind hub: split transaction info }
    if (dev^.Speed <> USB_SPEED_HIGH) and (dev^.ParentHub <> nil) then begin
        qh^.EPCaps := ehci_make_qh_epcaps(
            $01,
            $1C,
            dev^.ParentHub^.Address,
            dev^.ParentPort,
            1);
    end;

    { For interrupt transfers, set S-mask for periodic scheduling }
    if transfer^.PipeType = ptInterrupt then begin
        qh^.EPCaps := (qh^.EPCaps AND (NOT EHCI_QH_SMASK_MASK)) OR $01;
        if dev^.Speed = USB_SPEED_HIGH then
            qh^.EPCaps := qh^.EPCaps AND (NOT EHCI_QH_CMASK_MASK)
        else
            qh^.EPCaps := (qh^.EPCaps AND (NOT EHCI_QH_CMASK_MASK))
                            OR ($1C SHL EHCI_QH_CMASK_SHIFT);
    end;

    qh^.CurqTD     := 0;
    qh^.OvlNextqTD  := vtop(uint32(firstqTD));
    qh^.OvlAltNext  := EHCI_QTD_T;
    qh^.OvlToken    := 0;
    qh^.SWNext      := nil;
    qh^.SWTransfer  := Pointer(transfer);
    qh^.SWFirstqTD  := firstqTD;

    transfer^.HCPriv := Pointer(qh);
    transfer^.Status := tsInProgress;

    { Insert into appropriate schedule }
    if transfer^.PipeType = ptInterrupt then
        ehci_insert_intr_qh(priv, qh)
    else
        ehci_insert_async_qh(priv, qh);

    ehci_submit_async := true;
    pop_trace;
end;

function ehci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
begin
    push_trace('EHCI.ehci_submit');
    ehci_submit := false;
    if (hc = nil) or (transfer = nil) or (transfer^.Device = nil) then begin
        pop_trace;
        exit;
    end;

    case transfer^.PipeType of
        ptControl:
            ehci_submit := ehci_submit_control(hc, transfer);
        ptBulk, ptInterrupt:
            ehci_submit := ehci_submit_async(hc, transfer);
    else
        syslog.logln('EHCI', 'Unsupported pipe type for submit.');
    end;
    pop_trace;
end;

{ ========================= Poll / Completion ========================= }

procedure ehci_free_qtd_chain(first : PEHCI_qTD);
var
    qtd, next : PEHCI_qTD;
begin
    qtd := first;
    while qtd <> nil do begin
        next := qtd^.SWNext;
        ehci_free_qtd(qtd);
        qtd := next;
    end;
end;

{ Check if all qTDs in a chain are complete (no ACTIVE bits) }
function ehci_transfer_done(qh : PEHCI_QH) : boolean;
var
    qtd    : PEHCI_qTD;
    status : uint8;
begin
    ehci_transfer_done := false;
    qtd := qh^.SWFirstqTD;
    while qtd <> nil do begin
        status := ehci_qtd_status(qtd);
        if (status AND EHCI_QTD_STS_ACTIVE) <> 0 then
            exit;
        if (status AND EHCI_QTD_STS_HALTED) <> 0 then begin
            ehci_transfer_done := true;
            exit;
        end;
        qtd := qtd^.SWNext;
    end;
    ehci_transfer_done := true;
end;

{ Determine the overall transfer status from a qTD chain }
function ehci_transfer_status(qh : PEHCI_QH) : TUSBTransferStatus;
var
    qtd    : PEHCI_qTD;
    status : uint8;
begin
    ehci_transfer_status := tsSuccess;
    qtd := qh^.SWFirstqTD;
    while qtd <> nil do begin
        status := ehci_qtd_status(qtd);
        if (status AND (EHCI_QTD_STS_HALTED OR EHCI_QTD_STS_BUFERR OR
                         EHCI_QTD_STS_BABBLE OR EHCI_QTD_STS_XACTERR)) <> 0 then begin
            ehci_transfer_status := ehci_status_to_usb(status);
            exit;
        end;
        qtd := qtd^.SWNext;
    end;
end;

{ ========================= Interrupt-Driven Completion ========================= }

const
    EHCI_MAX_INSTANCES = 4;

var
    EHCIInstances     : array[0..EHCI_MAX_INSTANCES-1] of PUSBHCDriver;
    EHCIInstanceCount : uint32;

{ ISR handler — registered on the PCI interrupt line. }
procedure ehci_isr;
var
    i      : uint32;
    hc     : PUSBHCDriver;
    priv   : PEHCI_PrivData;
    usbsts : uint32;
begin
    for i := 0 to EHCIInstanceCount - 1 do begin
        hc := EHCIInstances[i];
        if hc = nil then continue;
        priv := PEHCI_PrivData(hc^.PrivData);
        if priv = nil then continue;

        { Check if this controller has pending status bits }
        usbsts := ehci_readl(priv^.OpBase, EHCI_OP_USBSTS);
        if (usbsts AND $3F) = 0 then continue;

        { Acknowledge interrupt status NOW to de-assert level-triggered PCI line.
          Must happen before ehci_poll, because PollBusy guard may skip the
          acknowledge inside poll — leaving the line asserted = interrupt storm. }
        ehci_writel(priv^.OpBase, EHCI_OP_USBSTS, usbsts AND $3F);

        { Process completions (walks QH lists) }
        ehci_poll(hc);
    end;
    usbcore.fire_completion_hooks;
end;

{ Enable hardware interrupts: USB INT, USB Error INT, Port Change, Host System Error. }
procedure ehci_enable_interrupts(hc : PUSBHCDriver);
var
    priv : PEHCI_PrivData;
begin
    if (hc = nil) or (hc^.PrivData = nil) then exit;
    priv := PEHCI_PrivData(hc^.PrivData);
    ehci_writel(priv^.OpBase, EHCI_OP_USBINTR,
        EHCI_STS_USBINT OR EHCI_STS_USBERRINT OR EHCI_STS_PCD OR EHCI_STS_HSE);
    syslog.logln('EHCI', 'Hardware interrupts enabled.');
end;

procedure ehci_poll(hc : PUSBHCDriver);
var
    priv     : PEHCI_PrivData;
    opbase   : uint32;
    usbsts   : uint32;
    qh       : PEHCI_QH;
    nextQH   : PEHCI_QH;
    transfer : PUSBTransfer;
    head     : PEHCI_QH;
    listIdx  : uint32;
begin
    if (hc = nil) or (hc^.PrivData = nil) then exit;
    priv := PEHCI_PrivData(hc^.PrivData);

    { Re-entrancy guard }
    if priv^.PollBusy then exit;
    priv^.PollBusy := true;

    opbase := priv^.OpBase;

    { Acknowledge status bits }
    usbsts := ehci_readl(opbase, EHCI_OP_USBSTS);
    if usbsts <> 0 then
        ehci_writel(opbase, EHCI_OP_USBSTS, usbsts AND $3F);

    if (usbsts AND EHCI_STS_HSE) <> 0 then begin
        syslog.logln('EHCI', 'Host System Error detected!');
    end;

    { Walk async and interrupt schedules }
    for listIdx := 0 to 1 do begin
        case listIdx of
            0: head := priv^.AsyncQH;
            1: head := priv^.IntrQH;
        else
            head := nil;
        end;
        if head = nil then continue;

        qh := head^.SWNext;
        while qh <> nil do begin
            nextQH := qh^.SWNext;
            if qh^.SWTransfer <> nil then begin
                transfer := PUSBTransfer(qh^.SWTransfer);
                if transfer^.Status = tsInProgress then begin
                    if ehci_transfer_done(qh) then begin
                        transfer^.Status := ehci_transfer_status(qh);
                        transfer^.ActualLen := transfer^.BufferLen;
                        { Remove QH from schedule and free qTD chain }
                        if listIdx = 0 then
                            ehci_remove_async_qh(priv, qh)
                        else
                            ehci_remove_intr_qh(priv, qh);
                        ehci_free_qtd_chain(qh^.SWFirstqTD);
                        ehci_free_qh(qh);
                    end;
                end;
            end;
            qh := nextQH;
        end;
    end;
    priv^.PollBusy := false;
end;

{ ========================= Load / Init ========================= }

function load : boolean;
var
    devices  : TDeviceArray;
    count    : uint32;
    i        : uint32;
    priv     : PEHCI_PrivData;
    hc       : TUSBHCDriver;
    hcEntry  : PUSBHCDriver;
    mmioBase : uint32;
    opBase   : uint32;
    block    : uint32;
    capLen   : uint8;
    hcsparams : uint32;
    hccparams : uint32;
    hciver   : uint16;
begin
    push_trace('EHCI.load');
    load := false;
    EHCIInstanceCount := 0;

    devices := PCI.getDeviceInfo($0C, $03, $20, count);
    syslog.log('EHCI', 'Found ');
    syslog.writeint(count);
    syslog.writestringln(' EHCI controller(s).');

    if count = 0 then begin
        load := true;
        pop_trace;
        exit;
    end;

    for i := 0 to count - 1 do begin
        syslog.log('EHCI', 'Controller[');
        syslog.writeint(i);
        syslog.writestring(']: VID=');
        syslog.writehex(devices[i].vendor_id);
        syslog.writestring(' DID=');
        syslog.writehex(devices[i].device_id);
        syslog.writestring(' BAR0=');
        syslog.writehexln(devices[i].address0);

        mmioBase := devices[i].address0 AND $FFFFFFF0;
        if mmioBase = 0 then begin
            syslog.logln('EHCI', 'Invalid MMIO base (BAR0=0), skipping.');
            continue;
        end;

        { Map the MMIO region into the identity-mapped address space }
        block := mmioBase SHR 22;
        force_alloc_block(block, 0);
        map_page(block, block);

        { Enable bus mastering for DMA }
        PCI.setBusMaster(devices[i].bus, devices[i].slot, devices[i].func, true);

        { Read capability registers }
        capLen := ehci_readb(mmioBase, EHCI_CAP_CAPLENGTH);
        hciver := ehci_readw(mmioBase, EHCI_CAP_HCIVERSION);
        hcsparams := ehci_readl(mmioBase, EHCI_CAP_HCSPARAMS);
        hccparams := ehci_readl(mmioBase, EHCI_CAP_HCCPARAMS);
        opBase := mmioBase + capLen;

        syslog.log('EHCI', 'HCI Version: ');
        syslog.writehexln(hciver);
        syslog.log('EHCI', 'CAPLENGTH=');
        syslog.writehex(capLen);
        syslog.writestring(' HCSPARAMS=');
        syslog.writehex(hcsparams);
        syslog.writestring(' HCCPARAMS=');
        syslog.writehexln(hccparams);

        { Allocate private data }
        priv := PEHCI_PrivData(kalloc(sizeof(TEHCI_PrivData)));
        if priv = nil then begin
            syslog.logln('EHCI', 'Failed to allocate private data!');
            continue;
        end;
        memset(uint32(priv), 0, sizeof(TEHCI_PrivData));
        priv^.MMIOBase   := mmioBase;
        priv^.OpBase     := opBase;
        priv^.HCSPARAMS  := hcsparams;
        priv^.HCCPARAMS  := hccparams;
        priv^.NumPorts   := uint8(hcsparams AND EHCI_HCS_N_PORTS_MASK);
        priv^.NumCC      := uint8((hcsparams AND EHCI_HCS_N_CC_MASK) SHR EHCI_HCS_N_CC_SHIFT);
        priv^.PortsPerCC := uint8((hcsparams AND EHCI_HCS_N_PCC_MASK) SHR EHCI_HCS_N_PCC_SHIFT);
        priv^.Has64Bit   := (hccparams AND EHCI_HCC_64BIT) <> 0;
        priv^.PCIBus     := devices[i].bus;
        priv^.PCISlot    := devices[i].slot;
        priv^.PCIFunc    := devices[i].func;

        syslog.log('EHCI', 'Ports=');
        syslog.writeint(priv^.NumPorts);
        syslog.writestring(' CC=');
        syslog.writeint(priv^.NumCC);
        syslog.writestring(' PPC=');
        syslog.writeintln(priv^.PortsPerCC);

        { Take over from BIOS if needed }
        ehci_bios_handoff(priv, devices[i]);

        { Set up HC driver record }
        usb_hc_init_record(@hc);
        hc.Name         := 'EHCI';
        hc.HCType       := USB_HC_EHCI;
        hc.NumPorts     := priv^.NumPorts;
        hc.PCIDev       := devices[i];
        hc.BaseAddr     := mmioBase;
        hc.PrivData     := Pointer(priv);
        hc.Devices      := LL_New(sizeof(TUSBDevice));
        hc.NextAddress  := 1;
        hc.fnReset      := TUSBHCReset(@ehci_reset);
        hc.fnStart      := TUSBHCStart(@ehci_start);
        hc.fnStop       := TUSBHCStop(@ehci_stop);
        hc.fnSubmit     := TUSBHCSubmit(@ehci_submit);
        hc.fnPoll       := TUSBHCPoll(@ehci_poll);
        hc.fnPortReset  := TUSBHCPortReset(@ehci_port_reset);
        hc.fnPortStatus := TUSBHCPortStatus(@ehci_port_status);

        { Reset the controller }
        if not ehci_reset(@hc) then begin
            syslog.logln('EHCI', 'Reset failed, skipping controller.');
            kfree(void(priv));
            continue;
        end;

        { Set up the schedule (frame list, async QH, interrupt QH) }
        ehci_setup_schedule(@hc);

        { Start the controller }
        if not ehci_start(@hc) then begin
            syslog.logln('EHCI', 'Start failed, skipping controller.');
            if priv^.FrameList <> nil then kfree_aligned(priv^.FrameList);
            if priv^.AsyncQH <> nil then ehci_free_qh(priv^.AsyncQH);
            if priv^.IntrQH <> nil then ehci_free_qh(priv^.IntrQH);
            kfree(void(priv));
            continue;
        end;

        { Register with USB core and scan ports }
        hcEntry := usbcore.register_hc(@hc);

        if hcEntry <> nil then begin
            { Track instance for ISR dispatch }
            if EHCIInstanceCount < EHCI_MAX_INSTANCES then begin
                EHCIInstances[EHCIInstanceCount] := hcEntry;
                inc(EHCIInstanceCount);
            end;

            { Register ISR on PCI interrupt line }
            syslog.log('EHCI', 'Registering ISR on IRQ ');
            syslog.writeintln(devices[i].interrupt_line);
            isrmanager.registerISR(32 + devices[i].interrupt_line, @ehci_isr);

            { Enable hardware interrupts }
            ehci_enable_interrupts(hcEntry);

            { Scan for connected devices }
            usbcore.scan_ports(hcEntry);
        end else
            syslog.logln('EHCI', 'Failed to register HC with USB core.');

        syslog.logln('EHCI', 'Controller initialized and registered.');
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
            syslog.logln('EHCI', msg);
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
        syslog.logln('EHCI', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

var
    epchars  : uint32;
    epcaps   : uint32;
    token    : uint32;
    qh       : PEHCI_QH;
    qtd      : PEHCI_qTD;
begin
    passed := 0;
    failed := 0;
    syslog.logln('EHCI', 'Unit tests starting...');

    { --- Structure Size Tests --- }
    Assert(sizeof(TEHCI_qTD) = 48, 'sizeof qTD=48');
    Assert(sizeof(TEHCI_QH) = 64, 'sizeof QH=64');

    { --- QH EPChars Construction Tests --- }
    epchars := ehci_make_qh_epchars(0, 0, EHCI_QH_EPS_HIGH, 64, true, true, false, 4);
    Assert((epchars AND EHCI_QH_DEVADDR_MASK) = 0, 'qh addr=0');
    Assert(((epchars SHR EHCI_QH_ENDPT_SHIFT) AND $0F) = 0, 'qh ep=0');
    Assert((epchars AND EHCI_QH_EPS_MASK) = EHCI_QH_EPS_HIGH, 'qh speed=HIGH');
    Assert(((epchars SHR EHCI_QH_MPL_SHIFT) AND $7FF) = 64, 'qh mpl=64');
    Assert((epchars AND EHCI_QH_DTC) <> 0, 'qh DTC set');
    Assert((epchars AND EHCI_QH_H) <> 0, 'qh H set');
    Assert((epchars AND EHCI_QH_C) = 0, 'qh C not set');
    Assert(((epchars SHR EHCI_QH_RL_SHIFT) AND $0F) = 4, 'qh RL=4');

    epchars := ehci_make_qh_epchars(5, 3, EHCI_QH_EPS_FULL, 8, false, false, true, 0);
    Assert((epchars AND EHCI_QH_DEVADDR_MASK) = 5, 'qh addr=5');
    Assert(((epchars SHR EHCI_QH_ENDPT_SHIFT) AND $0F) = 3, 'qh ep=3');
    Assert((epchars AND EHCI_QH_EPS_MASK) = EHCI_QH_EPS_FULL, 'qh speed=FULL');
    Assert(((epchars SHR EHCI_QH_MPL_SHIFT) AND $7FF) = 8, 'qh mpl=8');
    Assert((epchars AND EHCI_QH_DTC) = 0, 'qh DTC not set');
    Assert((epchars AND EHCI_QH_H) = 0, 'qh H not set');
    Assert((epchars AND EHCI_QH_C) <> 0, 'qh C set');

    epchars := ehci_make_qh_epchars(127, 15, EHCI_QH_EPS_LOW, 1023, true, false, false, 15);
    Assert((epchars AND EHCI_QH_DEVADDR_MASK) = 127, 'qh addr=127');
    Assert(((epchars SHR EHCI_QH_ENDPT_SHIFT) AND $0F) = 15, 'qh ep=15');
    Assert((epchars AND EHCI_QH_EPS_MASK) = EHCI_QH_EPS_LOW, 'qh speed=LOW');
    Assert(((epchars SHR EHCI_QH_MPL_SHIFT) AND $7FF) = 1023, 'qh mpl=1023');
    Assert(((epchars SHR EHCI_QH_RL_SHIFT) AND $0F) = 15, 'qh RL=15');

    { --- QH EPCaps Construction Tests --- }
    epcaps := ehci_make_qh_epcaps($01, $1C, 2, 3, 1);
    Assert((epcaps AND EHCI_QH_SMASK_MASK) = $01, 'qh smask=$01');
    Assert(((epcaps SHR EHCI_QH_CMASK_SHIFT) AND $FF) = $1C, 'qh cmask=$1C');
    Assert(((epcaps SHR EHCI_QH_HUBADDR_SHIFT) AND $7F) = 2, 'qh hubaddr=2');
    Assert(((epcaps SHR EHCI_QH_HUBPORT_SHIFT) AND $3F) = 3, 'qh hubport=3');
    Assert(((epcaps SHR EHCI_QH_MULT_SHIFT) AND $03) = 1, 'qh mult=1');

    epcaps := ehci_make_qh_epcaps(0, 0, 0, 0, 3);
    Assert((epcaps AND EHCI_QH_SMASK_MASK) = 0, 'qh smask=0');
    Assert(((epcaps SHR EHCI_QH_MULT_SHIFT) AND $03) = 3, 'qh mult=3');

    { --- qTD Token Construction Tests --- }
    token := ehci_make_qtd_token(EHCI_QTD_PID_SETUP, false, 8, false, 3);
    Assert((token AND EHCI_QTD_STS_ACTIVE) <> 0, 'qtd active set');
    Assert((token AND EHCI_QTD_PID_MASK) = EHCI_QTD_PID_SETUP, 'qtd pid=SETUP');
    Assert((token AND EHCI_QTD_DT) = 0, 'qtd DT=0 (DATA0)');
    Assert(((token SHR EHCI_QTD_TOTALBYTES_SHIFT) AND $7FFF) = 8, 'qtd bytes=8');
    Assert((token AND EHCI_QTD_IOC) = 0, 'qtd IOC not set');
    Assert(((token SHR EHCI_QTD_CERR_SHIFT) AND $03) = 3, 'qtd cerr=3');

    token := ehci_make_qtd_token(EHCI_QTD_PID_IN, true, 512, true, 2);
    Assert((token AND EHCI_QTD_PID_MASK) = EHCI_QTD_PID_IN, 'qtd pid=IN');
    Assert((token AND EHCI_QTD_DT) <> 0, 'qtd DT=1 (DATA1)');
    Assert(((token SHR EHCI_QTD_TOTALBYTES_SHIFT) AND $7FFF) = 512, 'qtd bytes=512');
    Assert((token AND EHCI_QTD_IOC) <> 0, 'qtd IOC set');
    Assert(((token SHR EHCI_QTD_CERR_SHIFT) AND $03) = 2, 'qtd cerr=2');

    token := ehci_make_qtd_token(EHCI_QTD_PID_OUT, true, 0, true, 0);
    Assert((token AND EHCI_QTD_PID_MASK) = EHCI_QTD_PID_OUT, 'qtd pid=OUT');
    Assert(((token SHR EHCI_QTD_TOTALBYTES_SHIFT) AND $7FFF) = 0, 'qtd bytes=0');

    { --- Status Mapping Tests --- }
    Assert(ehci_status_to_usb(EHCI_QTD_STS_ACTIVE) = tsInProgress, 'sts ACTIVE->tsInProgress');
    Assert(ehci_status_to_usb(EHCI_QTD_STS_HALTED) = tsStall, 'sts HALTED->tsStall');
    Assert(ehci_status_to_usb(EHCI_QTD_STS_HALTED OR EHCI_QTD_STS_BABBLE) = tsBabble, 'sts BABBLE->tsBabble');
    Assert(ehci_status_to_usb(EHCI_QTD_STS_HALTED OR EHCI_QTD_STS_BUFERR) = tsDataBufferError, 'sts BUFERR->tsDataBufferError');
    Assert(ehci_status_to_usb(EHCI_QTD_STS_HALTED OR EHCI_QTD_STS_XACTERR) = tsCRCError, 'sts XACTERR->tsCRCError');
    Assert(ehci_status_to_usb(0) = tsSuccess, 'sts 0->tsSuccess');

    { --- Allocation / Alignment Tests --- }
    qh := ehci_alloc_qh;
    Assert(qh <> nil, 'alloc_qh not nil');
    Assert((uint32(qh) AND $1F) = 0, 'alloc_qh 32-byte aligned');
    Assert(qh^.HorizLink = 0, 'alloc_qh zeroed HorizLink');
    Assert(qh^.EPChars = 0, 'alloc_qh zeroed EPChars');
    Assert(qh^.OvlToken = 0, 'alloc_qh zeroed OvlToken');
    ehci_free_qh(qh);

    qtd := ehci_alloc_qtd;
    Assert(qtd <> nil, 'alloc_qtd not nil');
    Assert((uint32(qtd) AND $1F) = 0, 'alloc_qtd 32-byte aligned');
    Assert(qtd^.Token = 0, 'alloc_qtd zeroed Token');
    Assert(qtd^.NextqTD = 0, 'alloc_qtd zeroed NextqTD');
    Assert(qtd^.Buffer[0] = 0, 'alloc_qtd zeroed Buffer[0]');
    ehci_free_qtd(qtd);

    { --- Register Offset Constant Tests --- }
    Assert(EHCI_CAP_CAPLENGTH = $00, 'CAP_CAPLENGTH=$00');
    Assert(EHCI_CAP_HCSPARAMS = $04, 'CAP_HCSPARAMS=$04');
    Assert(EHCI_CAP_HCCPARAMS = $08, 'CAP_HCCPARAMS=$08');
    Assert(EHCI_OP_USBCMD = $00, 'OP_USBCMD=$00');
    Assert(EHCI_OP_USBSTS = $04, 'OP_USBSTS=$04');
    Assert(EHCI_OP_PERIODICLISTBASE = $14, 'OP_PERIODICLISTBASE=$14');
    Assert(EHCI_OP_ASYNCLISTADDR = $18, 'OP_ASYNCLISTADDR=$18');
    Assert(EHCI_OP_CONFIGFLAG = $40, 'OP_CONFIGFLAG=$40');
    Assert(EHCI_OP_PORTSC = $44, 'OP_PORTSC=$44');

    { --- Command / Status Bit Tests --- }
    Assert(EHCI_CMD_RS = $01, 'CMD_RS=$01');
    Assert(EHCI_CMD_HCRESET = $02, 'CMD_HCRESET=$02');
    Assert(EHCI_CMD_ASE = $20, 'CMD_ASE=$20');
    Assert(EHCI_CMD_PSE = $10, 'CMD_PSE=$10');
    Assert(EHCI_STS_HCHALTED = $1000, 'STS_HCHALTED=$1000');
    Assert(EHCI_STS_USBINT = $01, 'STS_USBINT=$01');
    Assert(EHCI_STS_HSE = $10, 'STS_HSE=$10');

    { --- Port Status Bit Tests --- }
    Assert(EHCI_PORTSC_CCS = $01, 'PORTSC_CCS=$01');
    Assert(EHCI_PORTSC_PE = $04, 'PORTSC_PE=$04');
    Assert(EHCI_PORTSC_PRST = $100, 'PORTSC_PRST=$100');
    Assert(EHCI_PORTSC_PP = $1000, 'PORTSC_PP=$1000');
    Assert(EHCI_PORTSC_PO = $2000, 'PORTSC_PO=$2000');

    { --- Frame List / qTD / QH Constants --- }
    Assert(EHCI_FL_SIZE = 1024, 'FL_SIZE=1024');
    Assert(EHCI_FL_BYTES = 4096, 'FL_BYTES=4096');
    Assert(EHCI_FL_T = $01, 'FL_T=$01');
    Assert(EHCI_FL_TYPE_QH = $02, 'FL_TYPE_QH=$02');
    Assert(EHCI_QTD_T = $01, 'QTD_T=$01');
    Assert(EHCI_QH_ALIGN = 32, 'QH_ALIGN=32');
    Assert(EHCI_QTD_ALIGN = 32, 'QTD_ALIGN=32');

    { --- HCSPARAMS Extraction Tests --- }
    Assert((EHCI_HCS_N_PORTS_MASK AND $0F) = $0F, 'HCS N_PORTS mask');
    Assert(EHCI_HCS_N_CC_SHIFT = 12, 'HCS N_CC shift=12');
    Assert(EHCI_HCS_N_PCC_SHIFT = 8, 'HCS N_PCC shift=8');

    { --- CONFIGFLAG --- }
    Assert(EHCI_CF_FLAG = $01, 'CF_FLAG=$01');

    PrintSummary;
end;

end.