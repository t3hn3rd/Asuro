{
    Driver->Bus->USB->OHCI - Open Host Controller Interface Driver.

    Implements the OHCI (USB 1.1) host controller for MMIO-based controllers.
    OHCI uses Endpoint Descriptors (ED), Transfer Descriptors (TD), and a
    Host Controller Communication Area (HCCA) for scheduling and completion.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit ohci;

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

{ ========================= OHCI Register Offsets (from MMIO Base) ========================= }

const
    { Operational Registers }
    OHCI_REG_REVISION          = $00;  { HcRevision }
    OHCI_REG_CONTROL           = $04;  { HcControl }
    OHCI_REG_CMDSTATUS         = $08;  { HcCommandStatus }
    OHCI_REG_INTSTATUS         = $0C;  { HcInterruptStatus }
    OHCI_REG_INTENABLE         = $10;  { HcInterruptEnable }
    OHCI_REG_INTDISABLE        = $14;  { HcInterruptDisable }
    OHCI_REG_HCCA              = $18;  { HcHCCA }
    OHCI_REG_PERIOD_CURRENT_ED = $1C;  { HcPeriodCurrentED }
    OHCI_REG_CONTROL_HEAD_ED   = $20;  { HcControlHeadED }
    OHCI_REG_CONTROL_CURRENT_ED= $24;  { HcControlCurrentED }
    OHCI_REG_BULK_HEAD_ED      = $28;  { HcBulkHeadED }
    OHCI_REG_BULK_CURRENT_ED   = $2C;  { HcBulkCurrentED }
    OHCI_REG_DONE_HEAD         = $30;  { HcDoneHead }
    OHCI_REG_FM_INTERVAL       = $34;  { HcFmInterval }
    OHCI_REG_FM_REMAINING      = $38;  { HcFmRemaining }
    OHCI_REG_FM_NUMBER         = $3C;  { HcFmNumber }
    OHCI_REG_PERIODIC_START    = $40;  { HcPeriodicStart }
    OHCI_REG_LS_THRESHOLD      = $44;  { HcLSThreshold }
    OHCI_REG_RH_DESCRIPTORA    = $48;  { HcRhDescriptorA }
    OHCI_REG_RH_DESCRIPTORB    = $4C;  { HcRhDescriptorB }
    OHCI_REG_RH_STATUS         = $50;  { HcRhStatus }
    OHCI_REG_RH_PORT_STATUS    = $54;  { HcRhPortStatus[0] - each port is +4 }

    { HcControl bits }
    OHCI_CTRL_CBSR_MASK        = $00000003; { ControlBulkServiceRatio (bits 1:0) }
    OHCI_CTRL_PLE              = $00000004; { PeriodicListEnable }
    OHCI_CTRL_IE               = $00000008; { IsochronousEnable }
    OHCI_CTRL_CLE              = $00000010; { ControlListEnable }
    OHCI_CTRL_BLE              = $00000020; { BulkListEnable }
    OHCI_CTRL_HCFS_MASK        = $000000C0; { HostControllerFunctionalState }
    OHCI_CTRL_HCFS_RESET       = $00000000; { USBReset }
    OHCI_CTRL_HCFS_RESUME      = $00000040; { USBResume }
    OHCI_CTRL_HCFS_OPERATIONAL = $00000080; { USBOperational }
    OHCI_CTRL_HCFS_SUSPEND     = $000000C0; { USBSuspend }
    OHCI_CTRL_IR               = $00000100; { InterruptRouting }
    OHCI_CTRL_RWC              = $00000200; { RemoteWakeupConnected }
    OHCI_CTRL_RWE              = $00000400; { RemoteWakeupEnable }

    { HcCommandStatus bits }
    OHCI_CMD_HCR               = $00000001; { HostControllerReset }
    OHCI_CMD_CLF               = $00000002; { ControlListFilled }
    OHCI_CMD_BLF               = $00000004; { BulkListFilled }
    OHCI_CMD_OCR               = $00000008; { OwnershipChangeRequest }

    { HcInterruptStatus / Enable / Disable bits }
    OHCI_INT_SO                = $00000001; { SchedulingOverrun }
    OHCI_INT_WDH               = $00000002; { WritebackDoneHead }
    OHCI_INT_SF                = $00000004; { StartOfFrame }
    OHCI_INT_RD                = $00000008; { ResumeDetected }
    OHCI_INT_UE                = $00000010; { UnrecoverableError }
    OHCI_INT_FNO               = $00000020; { FrameNumberOverflow }
    OHCI_INT_RHSC              = $00000040; { RootHubStatusChange }
    OHCI_INT_OC                = $40000000; { OwnershipChange }
    OHCI_INT_MIE               = $80000000; { MasterInterruptEnable }

    { HcRhDescriptorA bits }
    OHCI_RHA_NDP_MASK          = $000000FF; { NumberDownstreamPorts }
    OHCI_RHA_PSM               = $00000100; { PowerSwitchingMode }
    OHCI_RHA_NPS               = $00000200; { NoPowerSwitching }
    OHCI_RHA_DT                = $00000400; { DeviceType (compound) }
    OHCI_RHA_OCPM              = $00000800; { OverCurrentProtectionMode }
    OHCI_RHA_NOCP              = $00001000; { NoOverCurrentProtection }
    OHCI_RHA_POTPGT_SHIFT      = 24;        { PowerOnToPowerGoodTime (bits 31:24) }

    { HcRhStatus bits }
    OHCI_RHS_LPS               = $00000001; { LocalPowerStatus (read) / ClearGlobalPower (write) }
    OHCI_RHS_OCI               = $00000002; { OverCurrentIndicator }
    OHCI_RHS_DRWE              = $00008000; { DeviceRemoteWakeupEnable (write: set) }
    OHCI_RHS_LPSC              = $00010000; { LocalPowerStatusChange (read) / SetGlobalPower (write) }
    OHCI_RHS_OCIC              = $00020000; { OverCurrentIndicatorChange }
    OHCI_RHS_CRWE              = $80000000; { ClearRemoteWakeupEnable (write) }

    { HcRhPortStatus bits }
    OHCI_PORT_CCS              = $00000001; { CurrentConnectStatus }
    OHCI_PORT_PES              = $00000002; { PortEnableStatus }
    OHCI_PORT_PSS              = $00000004; { PortSuspendStatus }
    OHCI_PORT_POCI             = $00000008; { PortOverCurrentIndicator }
    OHCI_PORT_PRS              = $00000010; { PortResetStatus }
    OHCI_PORT_PPS              = $00000100; { PortPowerStatus }
    OHCI_PORT_LSDA             = $00000200; { LowSpeedDeviceAttached }
    OHCI_PORT_CSC              = $00010000; { ConnectStatusChange }
    OHCI_PORT_PESC             = $00020000; { PortEnableStatusChange }
    OHCI_PORT_PSSC             = $00040000; { PortSuspendStatusChange }
    OHCI_PORT_OCIC             = $00080000; { PortOverCurrentIndicatorChange }
    OHCI_PORT_PRSC             = $00100000; { PortResetStatusChange }

    { Endpoint Descriptor (ED) control dword bits }
    OHCI_ED_FA_SHIFT           = 0;   { FunctionAddress (bits 6:0) }
    OHCI_ED_EN_SHIFT           = 7;   { EndpointNumber (bits 10:7) }
    OHCI_ED_DIR_MASK           = $00001800; { Direction (bits 12:11) }
    OHCI_ED_DIR_FROM_TD        = $00000000; { Get direction from TD }
    OHCI_ED_DIR_OUT            = $00000800; { OUT }
    OHCI_ED_DIR_IN             = $00001000; { IN }
    OHCI_ED_SPEED_FULL         = $00000000; { Full speed }
    OHCI_ED_SPEED_LOW          = $00002000; { Low speed (bit 13) }
    OHCI_ED_SKIP               = $00004000; { sKip (bit 14) }
    OHCI_ED_FORMAT_GENERAL     = $00000000; { General TD (bit 15 = 0) }
    OHCI_ED_FORMAT_ISO         = $00008000; { Isochronous TD (bit 15 = 1) }
    OHCI_ED_MPS_SHIFT          = 16;  { MaximumPacketSize (bits 26:16) }

    { Transfer Descriptor (TD) control dword bits }
    OHCI_TD_R                  = $00040000; { BufferRounding (bit 18) }
    OHCI_TD_DP_MASK            = $00180000; { DirectionPID (bits 20:19) }
    OHCI_TD_DP_SETUP           = $00000000; { SETUP }
    OHCI_TD_DP_OUT             = $00080000; { OUT }
    OHCI_TD_DP_IN              = $00100000; { IN }
    OHCI_TD_DI_MASK            = $00E00000; { DelayInterrupt (bits 23:21) }
    OHCI_TD_DI_NONE            = $00E00000; { No interrupt (111b = no interrupt) }
    OHCI_TD_DI_IMMEDIATE       = $00000000; { Interrupt immediately (frame N) }
    OHCI_TD_DT_MASK            = $03000000; { DataToggle (bits 25:24) }
    OHCI_TD_DT_FROM_ED         = $00000000; { Toggle from ED toggleCarry }
    OHCI_TD_DT_DATA0           = $02000000; { Force DATA0 }
    OHCI_TD_DT_DATA1           = $03000000; { Force DATA1 }
    OHCI_TD_EC_MASK            = $0C000000; { ErrorCount (bits 27:26) }
    OHCI_TD_CC_MASK            = $F0000000; { ConditionCode (bits 31:28) }
    OHCI_TD_CC_SHIFT           = 28;

    { Condition Codes }
    OHCI_CC_NO_ERROR           = $0;
    OHCI_CC_CRC                = $1;
    OHCI_CC_BIT_STUFFING       = $2;
    OHCI_CC_DATA_TOGGLE        = $3;
    OHCI_CC_STALL              = $4;
    OHCI_CC_DEVICE_NOT_RESP    = $5;
    OHCI_CC_PID_CHECK_FAIL     = $6;
    OHCI_CC_UNEXPECTED_PID     = $7;
    OHCI_CC_DATA_OVERRUN       = $8;
    OHCI_CC_DATA_UNDERRUN      = $9;
    OHCI_CC_BUFFER_OVERRUN     = $C;
    OHCI_CC_BUFFER_UNDERRUN    = $D;
    OHCI_CC_NOT_ACCESSED       = $F;

    { HCCA size and alignment }
    OHCI_HCCA_SIZE             = 256;  { 256 bytes }
    OHCI_HCCA_ALIGN            = 256;  { 256-byte aligned }
    OHCI_HCCA_INTR_TABLE_SIZE  = 32;   { 32 interrupt ED pointers }

    { ED/TD alignment requirements }
    OHCI_ED_ALIGN              = 16;   { 16-byte aligned }
    OHCI_TD_ALIGN              = 16;   { 16-byte aligned }

    { Max TDs per transfer }
    OHCI_MAX_TDS_PER_TRANSFER  = 128;

    { FmInterval default: 11999 bit times per frame (1ms), FSLargestDataPacket }
    OHCI_FM_INTERVAL_DEFAULT   = $27782EDF;
    { PeriodicStart: ~90% of FrameInterval = 0x2A2F }
    OHCI_PERIODIC_START_DEFAULT = $00002A2F;

{ ========================= OHCI Data Structures ========================= }

type
    { Host Controller Communication Area (HCCA) - 256 bytes, 256-byte aligned }
    POHCI_HCCA = ^TOHCI_HCCA;
    TOHCI_HCCA = packed record
        HccaInterruptTable : array[0..31] of uint32;  { 32 interrupt ED pointers }
        HccaFrameNumber    : uint16;                   { Current frame number }
        HccaPad1           : uint16;                   { When HC updates frame, it sets this to 0 }
        HccaDoneHead       : uint32;                   { Writeback done head pointer }
        HccaReserved       : array[0..29] of uint32;   { Reserved for HC use }
    end;

    { Endpoint Descriptor (ED) - 16 bytes, 16-byte aligned }
    POHCI_ED = ^TOHCI_ED;
    TOHCI_ED = packed record
        Control  : uint32; { FA, EN, D, S, K, F, MPS }
        TailP    : uint32; { Tail pointer (physical addr of last TD + 1 sentinel) }
        HeadP    : uint32; { Head pointer (physical addr of first TD) | toggleCarry(bit 1) | Halted(bit 0) }
        NextED   : uint32; { Next ED in list (physical addr, or 0 for end) }
        { Software fields - beyond the 16 bytes the HC reads }
        SWNext   : POHCI_ED;  { Software linked list for traversal }
        SWTransfer : Pointer; { Back-pointer to owning TUSBTransfer }
        SWPad1   : uint32;
        SWPad2   : uint32;
    end;

    { General Transfer Descriptor (TD) - 16 bytes, 16-byte aligned }
    POHCI_TD = ^TOHCI_TD;
    TOHCI_TD = packed record
        Control  : uint32; { R, DP, DI, DT, EC, CC }
        CBP      : uint32; { CurrentBufferPointer (physical) }
        NextTD   : uint32; { Next TD (physical addr, or 0) }
        BE       : uint32; { BufferEnd (physical addr of last byte) }
        { Software fields }
        SWNext   : POHCI_TD;  { Software linked list }
        SWTransfer : Pointer; { Back-pointer to owning TUSBTransfer }
        SWED     : POHCI_ED;  { Owning ED }
        SWPad    : uint32;
    end;

    { Private data for an OHCI host controller instance }
    POHCI_PrivData = ^TOHCI_PrivData;
    TOHCI_PrivData = record
        MMIOBase    : uint32;     { MMIO base address (virtual = physical, identity mapped) }
        HCCA        : POHCI_HCCA; { 256-byte aligned HCCA }
        EDControl   : POHCI_ED;   { Head of control ED list }
        EDBulk      : POHCI_ED;   { Head of bulk ED list }
        EDInterrupt : POHCI_ED;   { Dummy head for interrupt ED list }
        NumPorts    : uint8;      { Number of downstream ports }
        PollBusy    : boolean;    { Re-entrancy guard for poll }
        PCIBus      : uint8;      { PCI address }
        PCISlot     : uint8;
        PCIFunc     : uint8;
    end;

{ ========================= MMIO Helpers ========================= }

procedure ohci_write(base : uint32; reg : uint32; val : uint32);
begin
    PUint32(base + reg)^ := val;
end;

function ohci_read(base : uint32; reg : uint32) : uint32;
begin
    ohci_read := PUint32(base + reg)^;
end;

{ ========================= ED/TD Construction Helpers ========================= }

{ Allocate an ED (16-byte aligned) }
function ohci_alloc_ed : POHCI_ED;
begin
    ohci_alloc_ed := POHCI_ED(kalloc_aligned(sizeof(TOHCI_ED), OHCI_ED_ALIGN));
    if ohci_alloc_ed <> nil then
        memset(uint32(ohci_alloc_ed), 0, sizeof(TOHCI_ED));
end;

{ Free an ED }
procedure ohci_free_ed(ed : POHCI_ED);
begin
    if ed <> nil then
        kfree_aligned(ed);
end;

{ Allocate a TD (16-byte aligned) }
function ohci_alloc_td : POHCI_TD;
begin
    ohci_alloc_td := POHCI_TD(kalloc_aligned(sizeof(TOHCI_TD), OHCI_TD_ALIGN));
    if ohci_alloc_td <> nil then
        memset(uint32(ohci_alloc_td), 0, sizeof(TOHCI_TD));
end;

{ Free a TD }
procedure ohci_free_td(td : POHCI_TD);
begin
    if td <> nil then
        kfree_aligned(td);
end;

{ Build an ED control dword.
  funcAddr: USB device address (0-127)
  ep:       endpoint number (0-15)
  dir:      OHCI_ED_DIR_FROM_TD / _OUT / _IN
  speed:    OHCI_ED_SPEED_FULL or OHCI_ED_SPEED_LOW
  maxPkt:   max packet size
  isIso:    true for isochronous EDs }
function ohci_make_ed_control(funcAddr : uint8; ep : uint8; dir : uint32;
                               speed : uint32; maxPkt : uint16;
                               isIso : boolean) : uint32;
begin
    ohci_make_ed_control :=
        (uint32(funcAddr AND $7F) SHL OHCI_ED_FA_SHIFT)
        OR (uint32(ep AND $0F) SHL OHCI_ED_EN_SHIFT)
        OR (dir AND OHCI_ED_DIR_MASK)
        OR speed
        OR (uint32(maxPkt AND $07FF) SHL OHCI_ED_MPS_SHIFT);
    if isIso then
        ohci_make_ed_control := ohci_make_ed_control OR OHCI_ED_FORMAT_ISO;
end;

{ Build a TD control dword.
  direction:  OHCI_TD_DP_SETUP / _IN / _OUT
  toggle:     OHCI_TD_DT_FROM_ED / _DATA0 / _DATA1
  delayInt:   OHCI_TD_DI_NONE or OHCI_TD_DI_IMMEDIATE
  rounding:   true to enable buffer rounding (short packets OK) }
function ohci_make_td_control(direction : uint32; toggle : uint32;
                               delayInt : uint32; rounding : boolean) : uint32;
begin
    ohci_make_td_control :=
        (direction AND OHCI_TD_DP_MASK)
        OR (toggle AND OHCI_TD_DT_MASK)
        OR (delayInt AND OHCI_TD_DI_MASK)
        OR (OHCI_CC_NOT_ACCESSED SHL OHCI_TD_CC_SHIFT);
    if rounding then
        ohci_make_td_control := ohci_make_td_control OR OHCI_TD_R;
end;

{ Extract the condition code from a completed TD }
function ohci_td_cc(td : POHCI_TD) : uint8;
begin
    ohci_td_cc := uint8((td^.Control AND OHCI_TD_CC_MASK) SHR OHCI_TD_CC_SHIFT);
end;

{ Map OHCI condition code to USB transfer status }
function ohci_cc_to_status(cc : uint8) : TUSBTransferStatus;
begin
    case cc of
        OHCI_CC_NO_ERROR:       ohci_cc_to_status := tsSuccess;
        OHCI_CC_CRC:            ohci_cc_to_status := tsCRCError;
        OHCI_CC_BIT_STUFFING:   ohci_cc_to_status := tsBitStuffError;
        OHCI_CC_STALL:          ohci_cc_to_status := tsStall;
        OHCI_CC_DEVICE_NOT_RESP: ohci_cc_to_status := tsTimeout;
        OHCI_CC_DATA_OVERRUN:   ohci_cc_to_status := tsDataBufferError;
        OHCI_CC_DATA_UNDERRUN:  ohci_cc_to_status := tsSuccess; { short packet, not necessarily an error }
        OHCI_CC_BUFFER_OVERRUN: ohci_cc_to_status := tsDataBufferError;
        OHCI_CC_BUFFER_UNDERRUN: ohci_cc_to_status := tsDataBufferError;
        OHCI_CC_NOT_ACCESSED:   ohci_cc_to_status := tsInProgress;
    else
        ohci_cc_to_status := tsStall;
    end;
end;

{ ========================= HC Callback Implementations ========================= }

{ Forward declarations }
function ohci_reset(hc : PUSBHCDriver) : boolean; forward;
function ohci_start(hc : PUSBHCDriver) : boolean; forward;
procedure ohci_stop(hc : PUSBHCDriver); forward;
function ohci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean; forward;
procedure ohci_poll(hc : PUSBHCDriver); forward;
function ohci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean; forward;
function ohci_port_status(hc : PUSBHCDriver; port : uint8) : uint32; forward;

{ ========================= Reset ========================= }

function ohci_reset(hc : PUSBHCDriver) : boolean;
var
    priv   : POHCI_PrivData;
    base   : uint32;
    loops  : uint32;
    fmival : uint32;
begin
    push_trace('OHCI.ohci_reset');
    ohci_reset := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := POHCI_PrivData(hc^.PrivData);
    base := priv^.MMIOBase;

    { Save FmInterval before reset (it gets cleared) }
    fmival := ohci_read(base, OHCI_REG_FM_INTERVAL);

    { If the controller is in the USBOperational state, move to USBReset first }
    if (ohci_read(base, OHCI_REG_CONTROL) AND OHCI_CTRL_HCFS_MASK) <> OHCI_CTRL_HCFS_RESET then begin
        ohci_write(base, OHCI_REG_CONTROL, OHCI_CTRL_HCFS_RESET);
        { Wait ~10ms for USB reset signaling }
        loops := 0;
        while loops < 100000 do inc(loops);
    end;

    { Issue a software reset }
    ohci_write(base, OHCI_REG_CMDSTATUS, OHCI_CMD_HCR);

    { Wait for reset to complete (bit should self-clear within 10us) }
    loops := 0;
    while (loops < 100000) and ((ohci_read(base, OHCI_REG_CMDSTATUS) AND OHCI_CMD_HCR) <> 0) do
        inc(loops);

    if (ohci_read(base, OHCI_REG_CMDSTATUS) AND OHCI_CMD_HCR) <> 0 then begin
        syslog.logln('OHCI', 'HC reset timeout!');
        pop_trace;
        exit;
    end;

    { After reset, HC is in USBSuspend state. We're now in a 2ms window to set it up. }

    { Restore FmInterval. If it was zero/invalid, use the default. }
    if (fmival AND $3FFF) = 0 then
        fmival := OHCI_FM_INTERVAL_DEFAULT;
    { Toggle the FIT bit to indicate we're changing FmInterval }
    fmival := fmival XOR $80000000;
    ohci_write(base, OHCI_REG_FM_INTERVAL, fmival);

    { Set PeriodicStart to ~90% of FrameInterval }
    ohci_write(base, OHCI_REG_PERIODIC_START, OHCI_PERIODIC_START_DEFAULT);

    { Disable all interrupts (we poll) }
    ohci_write(base, OHCI_REG_INTDISABLE, OHCI_INT_MIE OR $7FFFFFFF);

    { Clear any pending interrupt status }
    ohci_write(base, OHCI_REG_INTSTATUS, $FFFFFFFF);

    syslog.logln('OHCI', 'HC reset complete.');
    ohci_reset := true;
    pop_trace;
end;

{ ========================= Schedule Setup ========================= }

procedure ohci_setup_schedule(hc : PUSBHCDriver);
var
    priv : POHCI_PrivData;
    hcca : POHCI_HCCA;
    i    : uint32;
begin
    push_trace('OHCI.ohci_setup_schedule');
    priv := POHCI_PrivData(hc^.PrivData);

    { Allocate HCCA (256-byte aligned) }
    hcca := POHCI_HCCA(kalloc_aligned(OHCI_HCCA_SIZE, OHCI_HCCA_ALIGN));
    if hcca = nil then begin
        syslog.logln('OHCI', 'Failed to allocate HCCA!');
        pop_trace;
        exit;
    end;
    memset(uint32(hcca), 0, OHCI_HCCA_SIZE);
    priv^.HCCA := hcca;

    { Allocate dummy/sentinel EDs for each list head }
    priv^.EDControl   := ohci_alloc_ed;
    priv^.EDBulk      := ohci_alloc_ed;
    priv^.EDInterrupt := ohci_alloc_ed;

    if (priv^.EDControl = nil) or (priv^.EDBulk = nil) or (priv^.EDInterrupt = nil) then begin
        syslog.logln('OHCI', 'Failed to allocate sentinel EDs!');
        pop_trace;
        exit;
    end;

    { Mark sentinel EDs as skip so the HC ignores them.
      They serve as stable list heads for easy insertion/removal. }
    priv^.EDControl^.Control   := OHCI_ED_SKIP;
    priv^.EDControl^.TailP     := 0;
    priv^.EDControl^.HeadP     := 0;
    priv^.EDControl^.NextED    := 0;
    priv^.EDControl^.SWNext    := nil;

    priv^.EDBulk^.Control      := OHCI_ED_SKIP;
    priv^.EDBulk^.TailP        := 0;
    priv^.EDBulk^.HeadP        := 0;
    priv^.EDBulk^.NextED       := 0;
    priv^.EDBulk^.SWNext       := nil;

    priv^.EDInterrupt^.Control := OHCI_ED_SKIP;
    priv^.EDInterrupt^.TailP   := 0;
    priv^.EDInterrupt^.HeadP   := 0;
    priv^.EDInterrupt^.NextED  := 0;
    priv^.EDInterrupt^.SWNext  := nil;

    { Fill all 32 HCCA interrupt table entries with our interrupt sentinel ED (physical) }
    for i := 0 to OHCI_HCCA_INTR_TABLE_SIZE - 1 do
        hcca^.HccaInterruptTable[i] := vtop(uint32(priv^.EDInterrupt));

    { Set HC's HCCA pointer (physical) }
    ohci_write(priv^.MMIOBase, OHCI_REG_HCCA, vtop(uint32(hcca)));

    { Set control and bulk list heads (physical) }
    ohci_write(priv^.MMIOBase, OHCI_REG_CONTROL_HEAD_ED, vtop(uint32(priv^.EDControl)));
    ohci_write(priv^.MMIOBase, OHCI_REG_BULK_HEAD_ED, vtop(uint32(priv^.EDBulk)));

    syslog.logln('OHCI', 'Schedule configured.');
    pop_trace;
end;

{ ========================= Start ========================= }

function ohci_start(hc : PUSBHCDriver) : boolean;
var
    priv    : POHCI_PrivData;
    base    : uint32;
    ctrl    : uint32;
    rha     : uint32;
    loops   : uint32;
    port    : uint32;
begin
    push_trace('OHCI.ohci_start');
    ohci_start := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := POHCI_PrivData(hc^.PrivData);
    base := priv^.MMIOBase;

    { Transition to USBOperational, enable control + bulk lists }
    ctrl := OHCI_CTRL_HCFS_OPERATIONAL
        OR OHCI_CTRL_CLE
        OR OHCI_CTRL_BLE
        OR OHCI_CTRL_PLE
        OR (OHCI_CTRL_CBSR_MASK AND $03); { 4:1 control-bulk ratio }
    ohci_write(base, OHCI_REG_CONTROL, ctrl);

    { Read HcRhDescriptorA to get number of downstream ports }
    rha := ohci_read(base, OHCI_REG_RH_DESCRIPTORA);
    priv^.NumPorts := uint8(rha AND OHCI_RHA_NDP_MASK);
    hc^.NumPorts := priv^.NumPorts;

    syslog.log('OHCI', 'Root hub has ');
    syslog.writeint(priv^.NumPorts);
    syslog.writestringln(' port(s).');

    { Power on all ports.
      If NPS (NoPowerSwitching) is set, ports are always powered.
      Otherwise we need to set global or per-port power. }
    if (rha AND OHCI_RHA_NPS) = 0 then begin
        { Set global power via HcRhStatus }
        ohci_write(base, OHCI_REG_RH_STATUS, OHCI_RHS_LPSC);

        { Wait for power good delay (POTPGT * 2ms) }
        loops := 0;
        while loops < 200000 do inc(loops);

        { Also set per-port power just in case }
        for port := 0 to priv^.NumPorts - 1 do begin
            ohci_write(base, OHCI_REG_RH_PORT_STATUS + (port * 4), OHCI_PORT_PPS);
        end;

        { Wait for port power to stabilize }
        loops := 0;
        while loops < 200000 do inc(loops);
    end;

    { Verify HC is operational }
    ctrl := ohci_read(base, OHCI_REG_CONTROL);
    if (ctrl AND OHCI_CTRL_HCFS_MASK) <> OHCI_CTRL_HCFS_OPERATIONAL then begin
        syslog.logln('OHCI', 'Controller failed to enter operational state.');
        pop_trace;
        exit;
    end;

    syslog.logln('OHCI', 'Controller started (operational).');
    ohci_start := true;
    pop_trace;
end;

{ ========================= Stop ========================= }

procedure ohci_stop(hc : PUSBHCDriver);
var
    priv : POHCI_PrivData;
begin
    push_trace('OHCI.ohci_stop');
    if (hc <> nil) and (hc^.PrivData <> nil) then begin
        priv := POHCI_PrivData(hc^.PrivData);
        { Put HC into USB Reset state }
        ohci_write(priv^.MMIOBase, OHCI_REG_CONTROL, OHCI_CTRL_HCFS_RESET);
        syslog.logln('OHCI', 'Controller stopped.');
    end;
    pop_trace;
end;

{ ========================= Port Status ========================= }

function ohci_port_status(hc : PUSBHCDriver; port : uint8) : uint32;
var
    priv : POHCI_PrivData;
begin
    push_trace('OHCI.ohci_port_status');
    ohci_port_status := 0;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := POHCI_PrivData(hc^.PrivData);
    if port >= priv^.NumPorts then begin
        pop_trace;
        exit;
    end;
    ohci_port_status := ohci_read(priv^.MMIOBase, OHCI_REG_RH_PORT_STATUS + (uint32(port) * 4));
    pop_trace;
end;

{ ========================= Port Reset ========================= }

function ohci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean;
var
    priv   : POHCI_PrivData;
    base   : uint32;
    regOfs : uint32;
    status : uint32;
    loops  : uint32;
begin
    push_trace('OHCI.ohci_port_reset');
    ohci_port_reset := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := POHCI_PrivData(hc^.PrivData);
    base := priv^.MMIOBase;
    if port >= priv^.NumPorts then begin
        pop_trace;
        exit;
    end;
    regOfs := OHCI_REG_RH_PORT_STATUS + (uint32(port) * 4);

    { Assert port reset }
    ohci_write(base, regOfs, OHCI_PORT_PRS);

    { Wait for port reset to complete (PRSC bit will be set by HC) }
    loops := 0;
    while loops < 200000 do begin
        status := ohci_read(base, regOfs);
        if (status AND OHCI_PORT_PRSC) <> 0 then break;
        inc(loops);
    end;

    if (status AND OHCI_PORT_PRSC) = 0 then begin
        syslog.log('OHCI', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' reset timeout.');
        pop_trace;
        exit;
    end;

    { Clear the reset status change bit by writing 1 to it }
    ohci_write(base, regOfs, OHCI_PORT_PRSC);

    { Small delay for device to respond after reset }
    loops := 0;
    while loops < 50000 do inc(loops);

    { Check that port is now enabled }
    status := ohci_read(base, regOfs);
    if (status AND OHCI_PORT_PES) <> 0 then begin
        syslog.log('OHCI', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' reset and enabled.');
        ohci_port_reset := true;
    end else begin
        syslog.log('OHCI', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' reset failed (not enabled).');
    end;
    pop_trace;
end;

{ ========================= Submit Transfer ========================= }

{ Insert an ED at the head of a list (after the sentinel) }
procedure ohci_insert_ed(sentinel : POHCI_ED; ed : POHCI_ED);
begin
    if (sentinel = nil) or (ed = nil) then exit;
    ed^.NextED       := sentinel^.NextED;
    ed^.SWNext       := sentinel^.SWNext;
    sentinel^.NextED := vtop(uint32(ed));
    sentinel^.SWNext := ed;
end;

{ Build a control transfer: SETUP TD, optional DATA TDs, STATUS TD, all on a new ED }
function ohci_submit_control(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var
    priv     : POHCI_PrivData;
    dev      : PUSBDevice;
    ed       : POHCI_ED;
    td       : POHCI_TD;
    firstTD  : POHCI_TD;
    prevTD   : POHCI_TD;
    tailTD   : POHCI_TD;
    devAddr  : uint8;
    maxPkt   : uint16;
    speedBit : uint32;
    remaining : uint32;
    offset   : uint32;
    pktLen   : uint16;
    toggle   : uint32;
    dirPID   : uint32;
begin
    push_trace('OHCI.ohci_submit_control');
    ohci_submit_control := false;
    priv := POHCI_PrivData(hc^.PrivData);
    dev := transfer^.Device;
    devAddr := dev^.Address;
    maxPkt := dev^.MaxPacket0;
    if maxPkt = 0 then maxPkt := 8;
    if dev^.Speed = USB_SPEED_LOW then
        speedBit := OHCI_ED_SPEED_LOW
    else
        speedBit := OHCI_ED_SPEED_FULL;

    firstTD := nil;
    prevTD := nil;

    { === SETUP TD === }
    td := ohci_alloc_td;
    if td = nil then begin pop_trace; exit; end;
    firstTD := td;

    td^.Control := ohci_make_td_control(OHCI_TD_DP_SETUP, OHCI_TD_DT_DATA0,
                                         OHCI_TD_DI_NONE, false);
    td^.CBP     := vtop(uint32(@transfer^.Setup));
    td^.BE      := vtop(uint32(@transfer^.Setup) + 7);
    td^.NextTD  := 0;
    td^.SWTransfer := Pointer(transfer);
    td^.SWNext  := nil;
    prevTD := td;

    { === DATA TDs === }
    toggle := OHCI_TD_DT_DATA1; { First data packet after SETUP uses DATA1 }
    remaining := transfer^.BufferLen;
    offset := 0;

    while remaining > 0 do begin
        td := ohci_alloc_td;
        if td = nil then begin pop_trace; exit; end;

        if remaining > maxPkt then
            pktLen := maxPkt
        else
            pktLen := remaining;

        { Direction: if bmRequestType bit 7 set, data stage is IN, else OUT }
        if (transfer^.Setup.bmRequestType AND $80) <> 0 then
            dirPID := OHCI_TD_DP_IN
        else
            dirPID := OHCI_TD_DP_OUT;

        td^.Control := ohci_make_td_control(dirPID, toggle,
                                             OHCI_TD_DI_NONE, true);
        td^.CBP     := vtop(uint32(transfer^.Buffer) + offset);
        if pktLen > 0 then
            td^.BE := vtop(uint32(transfer^.Buffer) + offset + uint32(pktLen) - 1)
        else
            td^.BE := 0;
        td^.NextTD  := 0;
        td^.SWTransfer := Pointer(transfer);
        td^.SWNext  := nil;

        { Link previous TD (NextTD = physical) }
        prevTD^.NextTD := vtop(uint32(td));
        prevTD^.SWNext := td;
        prevTD := td;

        { Alternate toggle }
        if toggle = OHCI_TD_DT_DATA1 then
            toggle := OHCI_TD_DT_DATA0
        else
            toggle := OHCI_TD_DT_DATA1;

        offset := offset + pktLen;
        remaining := remaining - pktLen;
    end;

    { === STATUS TD === }
    td := ohci_alloc_td;
    if td = nil then begin pop_trace; exit; end;

    { Status stage direction is opposite of data stage }
    if (transfer^.Setup.bmRequestType AND $80) <> 0 then
        dirPID := OHCI_TD_DP_OUT
    else
        dirPID := OHCI_TD_DP_IN;

    td^.Control := ohci_make_td_control(dirPID, OHCI_TD_DT_DATA1,
                                         OHCI_TD_DI_IMMEDIATE, false);
    td^.CBP     := 0; { Zero-length status stage }
    td^.BE      := 0;
    td^.NextTD  := 0;
    td^.SWTransfer := Pointer(transfer);
    td^.SWNext  := nil;

    prevTD^.NextTD := vtop(uint32(td));
    prevTD^.SWNext := td;

    { Allocate a dummy/sentinel TD for the tail pointer (OHCI requires HeadP <> TailP to process) }
    tailTD := ohci_alloc_td;
    if tailTD = nil then begin pop_trace; exit; end;
    td^.NextTD := vtop(uint32(tailTD));
    td^.SWNext := tailTD;

    { === Create ED === }
    ed := ohci_alloc_ed;
    if ed = nil then begin pop_trace; exit; end;

    ed^.Control := ohci_make_ed_control(devAddr, 0, OHCI_ED_DIR_FROM_TD,
                                         speedBit, maxPkt, false);
    ed^.HeadP   := vtop(uint32(firstTD));   { First real TD (physical) }
    ed^.TailP   := vtop(uint32(tailTD));    { Sentinel past last TD (physical) }
    ed^.NextED   := 0;
    ed^.SWTransfer := Pointer(transfer);
    ed^.SWPad1  := uint32(firstTD);  { Virtual firstTD for cleanup }
    ed^.SWPad2  := uint32(tailTD);   { Virtual tailTD for cleanup }

    { Store ED in transfer for cleanup and poll }
    transfer^.HCPriv := Pointer(ed);
    transfer^.Status := tsInProgress;

    { Insert ED into control list }
    ohci_insert_ed(priv^.EDControl, ed);

    { Tell HC the control list has new work }
    ohci_write(priv^.MMIOBase, OHCI_REG_CMDSTATUS, OHCI_CMD_CLF);

    ohci_submit_control := true;
    pop_trace;
end;

{ Build TDs for an interrupt or bulk transfer on a new ED }
function ohci_submit_async(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var
    priv     : POHCI_PrivData;
    dev      : PUSBDevice;
    ed       : POHCI_ED;
    td       : POHCI_TD;
    firstTD  : POHCI_TD;
    prevTD   : POHCI_TD;
    tailTD   : POHCI_TD;
    devAddr  : uint8;
    epNum    : uint8;
    maxPkt   : uint16;
    speedBit : uint32;
    remaining : uint32;
    offset   : uint32;
    pktLen   : uint16;
    toggle   : uint32;
    dirPID   : uint32;
    edDir    : uint32;
begin
    push_trace('OHCI.ohci_submit_async');
    ohci_submit_async := false;

    priv := POHCI_PrivData(hc^.PrivData);
    dev := transfer^.Device;
    devAddr := dev^.Address;
    epNum := transfer^.Endpoint^.Address;
    maxPkt := transfer^.Endpoint^.MaxPacket;
    if maxPkt = 0 then maxPkt := 8;
    if dev^.Speed = USB_SPEED_LOW then
        speedBit := OHCI_ED_SPEED_LOW
    else
        speedBit := OHCI_ED_SPEED_FULL;

    if transfer^.Direction = dirIn then begin
        dirPID := OHCI_TD_DP_IN;
        edDir  := OHCI_ED_DIR_IN;
    end else begin
        dirPID := OHCI_TD_DP_OUT;
        edDir  := OHCI_ED_DIR_OUT;
    end;

    { Determine initial toggle from endpoint state }
    if transfer^.Endpoint^.Toggle = 0 then
        toggle := OHCI_TD_DT_DATA0
    else
        toggle := OHCI_TD_DT_DATA1;

    firstTD := nil;
    prevTD := nil;
    remaining := transfer^.BufferLen;
    offset := 0;

    { Build TD chain }
    repeat
        td := ohci_alloc_td;
        if td = nil then begin pop_trace; exit; end;

        if firstTD = nil then firstTD := td;

        if remaining > maxPkt then
            pktLen := maxPkt
        else if remaining > 0 then
            pktLen := remaining
        else
            pktLen := 0;

        td^.Control := ohci_make_td_control(dirPID, toggle,
                                             OHCI_TD_DI_NONE, true);
        td^.CBP := vtop(uint32(transfer^.Buffer) + offset);
        if pktLen > 0 then
            td^.BE := vtop(uint32(transfer^.Buffer) + offset + uint32(pktLen) - 1)
        else
            td^.BE := 0;
        td^.NextTD := 0;
        td^.SWTransfer := Pointer(transfer);
        td^.SWNext := nil;

        if prevTD <> nil then begin
            prevTD^.NextTD := vtop(uint32(td));
            prevTD^.SWNext := td;
        end;
        prevTD := td;

        { Alternate toggle }
        if toggle = OHCI_TD_DT_DATA1 then
            toggle := OHCI_TD_DT_DATA0
        else
            toggle := OHCI_TD_DT_DATA1;

        if remaining > maxPkt then begin
            offset := offset + maxPkt;
            remaining := remaining - maxPkt;
        end else begin
            offset := offset + remaining;
            remaining := 0;
        end;
    until remaining = 0;

    { Mark last TD with immediate interrupt }
    if prevTD <> nil then
        prevTD^.Control := (prevTD^.Control AND (NOT OHCI_TD_DI_MASK)) OR OHCI_TD_DI_IMMEDIATE;

    { Update endpoint toggle }
    if toggle = OHCI_TD_DT_DATA1 then
        transfer^.Endpoint^.Toggle := 1
    else
        transfer^.Endpoint^.Toggle := 0;

    { Allocate tail sentinel TD }
    tailTD := ohci_alloc_td;
    if tailTD = nil then begin pop_trace; exit; end;
    prevTD^.NextTD := vtop(uint32(tailTD));
    prevTD^.SWNext := tailTD;

    { Create ED }
    ed := ohci_alloc_ed;
    if ed = nil then begin pop_trace; exit; end;

    ed^.Control := ohci_make_ed_control(devAddr, epNum, edDir,
                                         speedBit, maxPkt, false);
    ed^.HeadP   := vtop(uint32(firstTD));
    ed^.TailP   := vtop(uint32(tailTD));
    ed^.NextED   := 0;
    ed^.SWTransfer := Pointer(transfer);
    ed^.SWPad1  := uint32(firstTD);  { Virtual firstTD for cleanup }
    ed^.SWPad2  := uint32(tailTD);   { Virtual tailTD for cleanup }

    transfer^.HCPriv := Pointer(ed);
    transfer^.Status := tsInProgress;

    { Insert into appropriate list }
    if transfer^.PipeType = ptInterrupt then
        ohci_insert_ed(priv^.EDInterrupt, ed)
    else begin
        ohci_insert_ed(priv^.EDBulk, ed);
        { Tell HC the bulk list has new work }
        ohci_write(priv^.MMIOBase, OHCI_REG_CMDSTATUS, OHCI_CMD_BLF);
    end;

    ohci_submit_async := true;
    pop_trace;
end;

function ohci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
begin
    push_trace('OHCI.ohci_submit');
    ohci_submit := false;
    if (hc = nil) or (transfer = nil) or (transfer^.Device = nil) then begin
        pop_trace;
        exit;
    end;

    case transfer^.PipeType of
        ptControl:
            ohci_submit := ohci_submit_control(hc, transfer);
        ptInterrupt, ptBulk:
            ohci_submit := ohci_submit_async(hc, transfer);
    else
        syslog.logln('OHCI', 'Unsupported pipe type for submit.');
    end;
    pop_trace;
end;

{ ========================= Poll / Completion ========================= }

{ Remove a completed ED from a list }
procedure ohci_remove_ed(sentinel : POHCI_ED; target : POHCI_ED);
var
    prev, cur : POHCI_ED;
begin
    if (sentinel = nil) or (target = nil) then exit;
    prev := sentinel;
    cur := sentinel^.SWNext;
    while cur <> nil do begin
        if cur = target then begin
            prev^.NextED := cur^.NextED;
            prev^.SWNext := cur^.SWNext;
            exit;
        end;
        prev := cur;
        cur := cur^.SWNext;
    end;
end;

{ Free all TDs in an ED's chain via SWNext pointers }
procedure ohci_free_td_chain(firstTD : POHCI_TD);
var
    td, next : POHCI_TD;
begin
    td := firstTD;
    while td <> nil do begin
        next := td^.SWNext;
        ohci_free_td(td);
        td := next;
    end;
end;

{ ========================= Interrupt-Driven Completion ========================= }

const
    OHCI_MAX_INSTANCES = 4;

var
    OHCIInstances     : array[0..OHCI_MAX_INSTANCES-1] of PUSBHCDriver;
    OHCIInstanceCount : uint32;

{ ISR handler — registered on the PCI interrupt line. }
procedure ohci_isr;
var
    i      : uint32;
    hc     : PUSBHCDriver;
    priv   : POHCI_PrivData;
    intSts : uint32;
begin
    for i := 0 to OHCIInstanceCount - 1 do begin
        hc := OHCIInstances[i];
        if hc = nil then continue;
        priv := POHCI_PrivData(hc^.PrivData);
        if priv = nil then continue;

        { Check if this controller has pending interrupt status }
        intSts := ohci_read(priv^.MMIOBase, OHCI_REG_INTSTATUS);
        if intSts = 0 then continue;

        { Acknowledge interrupt status NOW to de-assert level-triggered PCI line.
          Must happen before ohci_poll, because PollBusy guard may skip the
          acknowledge inside poll — leaving the line asserted = interrupt storm. }
        ohci_write(priv^.MMIOBase, OHCI_REG_INTSTATUS, intSts);

        { Process completions (walks ED lists) }
        ohci_poll(hc);

        { Hotplug: if RootHubStatusChange, flag for deferred processing }
        if ((intSts AND OHCI_INT_RHSC) <> 0) and hc^.HotplugArmed then
            hc^.PortChangePending := true;
    end;
    usbcore.fire_completion_hooks;
end;

{ Enable hardware interrupts: WritebackDoneHead, RootHubStatusChange, UnrecoverableError + MIE. }
procedure ohci_enable_interrupts(hc : PUSBHCDriver);
var
    priv : POHCI_PrivData;
begin
    if (hc = nil) or (hc^.PrivData = nil) then exit;
    priv := POHCI_PrivData(hc^.PrivData);
    ohci_write(priv^.MMIOBase, OHCI_REG_INTENABLE,
        OHCI_INT_WDH OR OHCI_INT_RHSC OR OHCI_INT_UE OR OHCI_INT_MIE);
    syslog.logln('OHCI', 'Hardware interrupts enabled.');
end;

procedure ohci_poll(hc : PUSBHCDriver);
var
    priv     : POHCI_PrivData;
    base     : uint32;
    intSts   : uint32;
    sentinel : POHCI_ED;
    ed       : POHCI_ED;
    nextED   : POHCI_ED;
    td       : POHCI_TD;
    transfer : PUSBTransfer;
    cc       : uint8;
    listIdx  : uint32;
    firstTD  : POHCI_TD;
begin
    if (hc = nil) or (hc^.PrivData = nil) then exit;
    priv := POHCI_PrivData(hc^.PrivData);

    { Re-entrancy guard }
    if priv^.PollBusy then exit;
    priv^.PollBusy := true;

    base := priv^.MMIOBase;

    { Read and acknowledge interrupt status }
    intSts := ohci_read(base, OHCI_REG_INTSTATUS);
    if intSts <> 0 then
        ohci_write(base, OHCI_REG_INTSTATUS, intSts);

    { Check for unrecoverable error }
    if (intSts AND OHCI_INT_UE) <> 0 then begin
        syslog.logln('OHCI', 'Unrecoverable error detected!');
    end;

    { Walk all three ED lists (control, bulk, interrupt) and check for completed transfers }
    for listIdx := 0 to 2 do begin
        case listIdx of
            0: sentinel := priv^.EDControl;
            1: sentinel := priv^.EDBulk;
            2: sentinel := priv^.EDInterrupt;
        else
            sentinel := nil;
        end;
        if sentinel = nil then continue;

        ed := sentinel^.SWNext;
        while ed <> nil do begin
            nextED := ed^.SWNext;
            if ed^.SWTransfer <> nil then begin
                transfer := PUSBTransfer(ed^.SWTransfer);
                if transfer^.Status = tsInProgress then begin
                    { HeadP and TailP are physical addresses (set via vtop).
                      When HeadP equals TailP (ignoring low bits), the ED is done. }
                    if (ed^.HeadP AND $FFFFFFF0) = (ed^.TailP AND $FFFFFFF0) then begin
                        { All TDs consumed — walk chain via virtual SWNext to check CCs }
                        transfer^.Status := tsSuccess;
                        transfer^.ActualLen := transfer^.BufferLen;
                        td := POHCI_TD(ed^.SWPad1); { Virtual firstTD }
                        while td <> nil do begin
                            cc := ohci_td_cc(td);
                            if (cc <> OHCI_CC_NO_ERROR) and (cc <> OHCI_CC_NOT_ACCESSED) then begin
                                transfer^.Status := ohci_cc_to_status(cc);
                                break;
                            end;
                            td := td^.SWNext;
                        end;
                        ohci_remove_ed(sentinel, ed);
                        ohci_free_td_chain(POHCI_TD(ed^.SWPad1));
                        ohci_free_ed(ed);
                    end else if (ed^.HeadP AND $01) <> 0 then begin
                        { ED is halted — walk virtual chain to find the error CC }
                        transfer^.Status := tsStall;
                        td := POHCI_TD(ed^.SWPad1); { Virtual firstTD }
                        while td <> nil do begin
                            cc := ohci_td_cc(td);
                            if (cc <> OHCI_CC_NO_ERROR) and (cc <> OHCI_CC_NOT_ACCESSED) then begin
                                transfer^.Status := ohci_cc_to_status(cc);
                                break;
                            end;
                            td := td^.SWNext;
                        end;
                        ohci_remove_ed(sentinel, ed);
                        ohci_free_td_chain(POHCI_TD(ed^.SWPad1));
                        ohci_free_ed(ed);
                    end;
                    { else: still in progress, leave it }
                end;
            end;
            ed := nextED;
        end;
    end;
    priv^.PollBusy := false;
end;

{ ========================= Load / Init ========================= }

function load : boolean;
var
    devices : TDeviceArray;
    count   : uint32;
    i       : uint32;
    priv    : POHCI_PrivData;
    hc      : TUSBHCDriver;
    hcEntry : PUSBHCDriver;
    mmioBase : uint32;
    block   : uint32;
begin
    push_trace('OHCI.load');
    load := false;
    OHCIInstanceCount := 0;

    devices := PCI.getDeviceInfo($0C, $03, $10, count);
    syslog.log('OHCI', 'Found ');
    syslog.writeint(count);
    syslog.writestringln(' OHCI controller(s).');

    if count = 0 then begin
        load := true;
        pop_trace;
        exit;
    end;

    for i := 0 to count - 1 do begin
        syslog.log('OHCI', 'Controller[');
        syslog.writeint(i);
        syslog.writestring(']: VID=');
        syslog.writehex(devices[i].vendor_id);
        syslog.writestring(' DID=');
        syslog.writehex(devices[i].device_id);
        syslog.writestring(' BAR0=');
        syslog.writehexln(devices[i].address0);

        { BAR0 is MMIO base for OHCI. Mask off type bits (lower 4 bits for MMIO). }
        mmioBase := devices[i].address0 AND $FFFFFFF0;
        if mmioBase = 0 then begin
            syslog.logln('OHCI', 'Invalid MMIO base (BAR0=0), skipping.');
            continue;
        end;

        { Identity-map the MMIO region so we can access it }
        block := mmioBase SHR 22;
        force_alloc_block(block, 0);
        map_page(block, block);

        { Enable PCI bus mastering }
        PCI.setBusMaster(devices[i].bus, devices[i].slot, devices[i].func, true);

        { Allocate private data }
        priv := POHCI_PrivData(kalloc(sizeof(TOHCI_PrivData)));
        if priv = nil then begin
            syslog.logln('OHCI', 'Failed to allocate private data!');
            continue;
        end;
        memset(uint32(priv), 0, sizeof(TOHCI_PrivData));
        priv^.MMIOBase  := mmioBase;
        priv^.PCIBus    := devices[i].bus;
        priv^.PCISlot   := devices[i].slot;
        priv^.PCIFunc   := devices[i].func;

        { Log the revision register }
        syslog.log('OHCI', 'Revision: ');
        syslog.writehexln(ohci_read(mmioBase, OHCI_REG_REVISION));

        { Initialize HC driver record }
        usb_hc_init_record(@hc);
        hc.Name         := 'OHCI';
        hc.HCType       := USB_HC_OHCI;
        hc.NumPorts     := 0; { Will be filled in by ohci_start }
        hc.PCIDev       := devices[i];
        hc.BaseAddr     := mmioBase;
        hc.PrivData     := Pointer(priv);
        hc.Devices      := LL_New(sizeof(TUSBDevice));
        hc.NextAddress  := 1;
        hc.fnReset      := TUSBHCReset(@ohci_reset);
        hc.fnStart      := TUSBHCStart(@ohci_start);
        hc.fnStop       := TUSBHCStop(@ohci_stop);
        hc.fnSubmit     := TUSBHCSubmit(@ohci_submit);
        hc.fnPoll       := TUSBHCPoll(@ohci_poll);
        hc.fnPortReset  := TUSBHCPortReset(@ohci_port_reset);
        hc.fnPortStatus := TUSBHCPortStatus(@ohci_port_status);

        { Reset the controller }
        if not ohci_reset(@hc) then begin
            syslog.logln('OHCI', 'Reset failed, skipping controller.');
            kfree(void(priv));
            continue;
        end;

        { Setup the schedule (HCCA + ED lists) }
        ohci_setup_schedule(@hc);

        { Start the controller }
        if not ohci_start(@hc) then begin
            syslog.logln('OHCI', 'Start failed, skipping controller.');
            if priv^.HCCA <> nil then kfree_aligned(priv^.HCCA);
            if priv^.EDControl <> nil then ohci_free_ed(priv^.EDControl);
            if priv^.EDBulk <> nil then ohci_free_ed(priv^.EDBulk);
            if priv^.EDInterrupt <> nil then ohci_free_ed(priv^.EDInterrupt);
            kfree(void(priv));
            continue;
        end;

        { Register with USB core — get back the stable heap pointer }
        hcEntry := usbcore.register_hc(@hc);

        { Scan ports for connected devices (use the stable pointer, not stack-local @hc) }
        if hcEntry <> nil then begin
            { Track instance for ISR dispatch }
            if OHCIInstanceCount < OHCI_MAX_INSTANCES then begin
                OHCIInstances[OHCIInstanceCount] := hcEntry;
                inc(OHCIInstanceCount);
            end;

            { Register ISR on PCI interrupt line }
            syslog.log('OHCI', 'Registering ISR on IRQ ');
            syslog.writeintln(devices[i].interrupt_line);
            isrmanager.registerISR(32 + devices[i].interrupt_line, @ohci_isr);

            { Enable hardware interrupts }
            ohci_enable_interrupts(hcEntry);

            { Scan for connected devices }
            usbcore.scan_ports(hcEntry);
        end else
            syslog.logln('OHCI', 'Failed to register HC with USB core.');

        syslog.logln('OHCI', 'Controller initialized and registered.');
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
            syslog.logln('OHCI', msg);
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
        syslog.logln('OHCI', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

var
    edCtrl : uint32;
    tdCtrl : uint32;
    ed     : POHCI_ED;
    td     : POHCI_TD;
    hcca   : POHCI_HCCA;
begin
    passed := 0;
    failed := 0;
    syslog.logln('OHCI', 'Unit tests starting...');

    { === Structure Sizes === }
    Assert(sizeof(TOHCI_HCCA) = 256, 'sizeof HCCA=256');
    Assert(sizeof(TOHCI_ED) = 32, 'sizeof ED=32');
    Assert(sizeof(TOHCI_TD) = 32, 'sizeof TD=32');

    { === ED Control Building === }
    { Addr 0, EP0, direction from TD, full speed, maxPkt 8, general }
    edCtrl := ohci_make_ed_control(0, 0, OHCI_ED_DIR_FROM_TD, OHCI_ED_SPEED_FULL, 8, false);
    Assert((edCtrl AND $7F) = 0, 'ed addr=0');
    Assert(((edCtrl SHR 7) AND $0F) = 0, 'ed ep=0');
    Assert((edCtrl AND OHCI_ED_DIR_MASK) = OHCI_ED_DIR_FROM_TD, 'ed dir=FROM_TD');
    Assert((edCtrl AND OHCI_ED_SPEED_LOW) = 0, 'ed speed=full');
    Assert(((edCtrl SHR OHCI_ED_MPS_SHIFT) AND $7FF) = 8, 'ed mps=8');
    Assert((edCtrl AND OHCI_ED_FORMAT_ISO) = 0, 'ed format=general');

    { Addr 5, EP3, IN, low speed, maxPkt 64 }
    edCtrl := ohci_make_ed_control(5, 3, OHCI_ED_DIR_IN, OHCI_ED_SPEED_LOW, 64, false);
    Assert((edCtrl AND $7F) = 5, 'ed addr=5');
    Assert(((edCtrl SHR 7) AND $0F) = 3, 'ed ep=3');
    Assert((edCtrl AND OHCI_ED_DIR_MASK) = OHCI_ED_DIR_IN, 'ed dir=IN');
    Assert((edCtrl AND OHCI_ED_SPEED_LOW) <> 0, 'ed speed=low');
    Assert(((edCtrl SHR OHCI_ED_MPS_SHIFT) AND $7FF) = 64, 'ed mps=64');

    { Addr 127, EP15, OUT, full speed, maxPkt 1023, isochronous }
    edCtrl := ohci_make_ed_control(127, 15, OHCI_ED_DIR_OUT, OHCI_ED_SPEED_FULL, 1023, true);
    Assert((edCtrl AND $7F) = 127, 'ed addr=127');
    Assert(((edCtrl SHR 7) AND $0F) = 15, 'ed ep=15');
    Assert((edCtrl AND OHCI_ED_DIR_MASK) = OHCI_ED_DIR_OUT, 'ed dir=OUT');
    Assert(((edCtrl SHR OHCI_ED_MPS_SHIFT) AND $7FF) = 1023, 'ed mps=1023');
    Assert((edCtrl AND OHCI_ED_FORMAT_ISO) <> 0, 'ed format=iso');

    { === TD Control Building === }
    { SETUP, DATA0, no interrupt, no rounding }
    tdCtrl := ohci_make_td_control(OHCI_TD_DP_SETUP, OHCI_TD_DT_DATA0,
                                    OHCI_TD_DI_NONE, false);
    Assert((tdCtrl AND OHCI_TD_DP_MASK) = OHCI_TD_DP_SETUP, 'td dp=SETUP');
    Assert((tdCtrl AND OHCI_TD_DT_MASK) = OHCI_TD_DT_DATA0, 'td dt=DATA0');
    Assert((tdCtrl AND OHCI_TD_DI_MASK) = OHCI_TD_DI_NONE, 'td di=NONE');
    Assert((tdCtrl AND OHCI_TD_R) = 0, 'td rounding=off');
    Assert(((tdCtrl SHR OHCI_TD_CC_SHIFT) AND $F) = OHCI_CC_NOT_ACCESSED, 'td cc=NOT_ACCESSED');

    { IN, DATA1, immediate interrupt, rounding }
    tdCtrl := ohci_make_td_control(OHCI_TD_DP_IN, OHCI_TD_DT_DATA1,
                                    OHCI_TD_DI_IMMEDIATE, true);
    Assert((tdCtrl AND OHCI_TD_DP_MASK) = OHCI_TD_DP_IN, 'td dp=IN');
    Assert((tdCtrl AND OHCI_TD_DT_MASK) = OHCI_TD_DT_DATA1, 'td dt=DATA1');
    Assert((tdCtrl AND OHCI_TD_DI_MASK) = OHCI_TD_DI_IMMEDIATE, 'td di=IMMEDIATE');
    Assert((tdCtrl AND OHCI_TD_R) <> 0, 'td rounding=on');

    { OUT, from ED toggle, no interrupt, no rounding }
    tdCtrl := ohci_make_td_control(OHCI_TD_DP_OUT, OHCI_TD_DT_FROM_ED,
                                    OHCI_TD_DI_NONE, false);
    Assert((tdCtrl AND OHCI_TD_DP_MASK) = OHCI_TD_DP_OUT, 'td dp=OUT');
    Assert((tdCtrl AND OHCI_TD_DT_MASK) = OHCI_TD_DT_FROM_ED, 'td dt=FROM_ED');

    { === Condition Code Mapping === }
    Assert(ohci_cc_to_status(OHCI_CC_NO_ERROR) = tsSuccess, 'cc NO_ERROR->tsSuccess');
    Assert(ohci_cc_to_status(OHCI_CC_CRC) = tsCRCError, 'cc CRC->tsCRCError');
    Assert(ohci_cc_to_status(OHCI_CC_BIT_STUFFING) = tsBitStuffError, 'cc BITSTUFF->tsBitStuffError');
    Assert(ohci_cc_to_status(OHCI_CC_STALL) = tsStall, 'cc STALL->tsStall');
    Assert(ohci_cc_to_status(OHCI_CC_DEVICE_NOT_RESP) = tsTimeout, 'cc DNR->tsTimeout');
    Assert(ohci_cc_to_status(OHCI_CC_DATA_OVERRUN) = tsDataBufferError, 'cc OVERRUN->tsDataBufferError');
    Assert(ohci_cc_to_status(OHCI_CC_DATA_UNDERRUN) = tsSuccess, 'cc UNDERRUN->tsSuccess');
    Assert(ohci_cc_to_status(OHCI_CC_NOT_ACCESSED) = tsInProgress, 'cc NOT_ACCESSED->tsInProgress');

    { === ED Allocation & Alignment === }
    ed := ohci_alloc_ed;
    Assert(ed <> nil, 'alloc_ed not nil');
    Assert((uint32(ed) AND $0F) = 0, 'alloc_ed 16-byte aligned');
    Assert(ed^.Control = 0, 'alloc_ed zeroed control');
    Assert(ed^.TailP = 0, 'alloc_ed zeroed tailp');
    Assert(ed^.HeadP = 0, 'alloc_ed zeroed headp');
    Assert(ed^.NextED = 0, 'alloc_ed zeroed nexted');
    ohci_free_ed(ed);

    { === TD Allocation & Alignment === }
    td := ohci_alloc_td;
    Assert(td <> nil, 'alloc_td not nil');
    Assert((uint32(td) AND $0F) = 0, 'alloc_td 16-byte aligned');
    Assert(td^.Control = 0, 'alloc_td zeroed control');
    Assert(td^.CBP = 0, 'alloc_td zeroed cbp');
    Assert(td^.NextTD = 0, 'alloc_td zeroed nexttd');
    Assert(td^.BE = 0, 'alloc_td zeroed be');
    ohci_free_td(td);

    { === HCCA Size / Alignment === }
    Assert(OHCI_HCCA_SIZE = 256, 'HCCA_SIZE=256');
    Assert(OHCI_HCCA_ALIGN = 256, 'HCCA_ALIGN=256');
    hcca := POHCI_HCCA(kalloc_aligned(OHCI_HCCA_SIZE, OHCI_HCCA_ALIGN));
    Assert(hcca <> nil, 'hcca alloc not nil');
    Assert((uint32(hcca) AND $FF) = 0, 'hcca 256-byte aligned');
    kfree_aligned(hcca);

    { === Register offset constants === }
    Assert(OHCI_REG_REVISION = $00, 'REG_REVISION=$00');
    Assert(OHCI_REG_CONTROL = $04, 'REG_CONTROL=$04');
    Assert(OHCI_REG_CMDSTATUS = $08, 'REG_CMDSTATUS=$08');
    Assert(OHCI_REG_HCCA = $18, 'REG_HCCA=$18');
    Assert(OHCI_REG_CONTROL_HEAD_ED = $20, 'REG_CONTROL_HEAD_ED=$20');
    Assert(OHCI_REG_BULK_HEAD_ED = $28, 'REG_BULK_HEAD_ED=$28');
    Assert(OHCI_REG_RH_DESCRIPTORA = $48, 'REG_RH_DESCRIPTORA=$48');
    Assert(OHCI_REG_RH_STATUS = $50, 'REG_RH_STATUS=$50');
    Assert(OHCI_REG_RH_PORT_STATUS = $54, 'REG_RH_PORT_STATUS=$54');

    { === HcControl bits === }
    Assert(OHCI_CTRL_HCFS_RESET = $00, 'CTRL_HCFS_RESET=$00');
    Assert(OHCI_CTRL_HCFS_OPERATIONAL = $80, 'CTRL_HCFS_OPERATIONAL=$80');
    Assert(OHCI_CTRL_CLE = $10, 'CTRL_CLE=$10');
    Assert(OHCI_CTRL_BLE = $20, 'CTRL_BLE=$20');
    Assert(OHCI_CTRL_PLE = $04, 'CTRL_PLE=$04');

    { === Port status bits === }
    Assert(OHCI_PORT_CCS = $00000001, 'PORT_CCS=$01');
    Assert(OHCI_PORT_PES = $00000002, 'PORT_PES=$02');
    Assert(OHCI_PORT_PRS = $00000010, 'PORT_PRS=$10');
    Assert(OHCI_PORT_PPS = $00000100, 'PORT_PPS=$100');
    Assert(OHCI_PORT_LSDA = $00000200, 'PORT_LSDA=$200');
    Assert(OHCI_PORT_PRSC = $00100000, 'PORT_PRSC=$100000');

    { === ED skip bit === }
    Assert(OHCI_ED_SKIP = $00004000, 'ED_SKIP=$4000');

    { === CommandStatus bits === }
    Assert(OHCI_CMD_HCR = $01, 'CMD_HCR=$01');
    Assert(OHCI_CMD_CLF = $02, 'CMD_CLF=$02');
    Assert(OHCI_CMD_BLF = $04, 'CMD_BLF=$04');

    PrintSummary;
end;

end.