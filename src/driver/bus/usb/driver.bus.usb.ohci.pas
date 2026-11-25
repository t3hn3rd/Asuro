//  Copyright 2026 Kieron Morris
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{
    Driver->Bus->driver.bus.usb->driver.bus.usb.ohci - Open Host Controller Interface Driver.

    Implements the driver.bus.usb.ohci (driver.bus.usb 1.1) host controller for MMIO-based controllers.
    driver.bus.usb.ohci uses Endpoint Descriptors (ED), Transfer Descriptors (TD), and a
    Host Controller Communication Area (HCCA) for scheduling and completion.

    @author(Aaron Hance <ah@aaronhance.me>)
    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.bus.usb.ohci;

interface

uses
    debug.tracer,
    io.syslog,
    driver.bus.pci,
    driver.types,
    arch.platform.memory,
    memory.heap,
    core.util, arch.platform.cpu, arch.platform.diagnostics,
    driver.mgr,
    driver.bus.usb.types,
    driver.bus.usb.core,
    arch.platform.interrupts,
    core.ds.lists,
    core.strings;

function load : boolean;
{$ifdef UNIT_TESTS}
function testDMA32(buffer: puint8): boolean;
{$endif}
procedure UnitTest;

implementation

uses
    test.harness, driver.dma;

{ ========================= driver.bus.usb.ohci Register Offsets (from MMIO Base) ========================= }

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

{ ========================= driver.bus.usb.ohci Data Structures ========================= }

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
        SWPad1   : PtrUInt;
        Bounce   : pointer;
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
        Setup    : TUSBSetupPacket;
    end;

    { Private data for an driver.bus.usb.ohci host controller instance }
    POHCI_PrivData = ^TOHCI_PrivData;
    TOHCI_PrivData = record
        MMIOBase    : PtrUInt;     { MMIO base address (virtual = physical, identity mapped) }
        HCCA        : POHCI_HCCA; { 256-byte aligned HCCA }
        EDControl   : POHCI_ED;   { Head of control ED list }
        EDBulk      : POHCI_ED;   { Head of bulk ED list }
        EDInterrupt : POHCI_ED;   { Dummy head for interrupt ED list }
        NumPorts    : uint8;      { Number of downstream ports }
        PollBusy    : boolean;    { Re-entrancy guard for poll }
        PCIBus      : uint8;      { driver.bus.pci address }
        PCISlot     : uint8;
        PCIFunc     : uint8;
    end;

{ ========================= MMIO Helpers ========================= }

procedure ohci_write(base : PtrUInt; reg : uint32; val : uint32);
begin
    PUint32(base + reg)^ := val;
end;

function ohci_read(base : PtrUInt; reg : uint32) : uint32;
begin
    ohci_read := PUint32(base + reg)^;
end;

{ OHCI exposes only 32-bit DMA addresses. Validate every backing page before
  publishing descriptors; a high virtual address is valid when its backing RAM
  is below 4 GiB. Zero-length transfers do not need a buffer. }
function ohci_alloc_ed : POHCI_ED;
begin
    ohci_alloc_ed := driver.dma.allocate(sizeof(TOHCI_ED), OHCI_ED_ALIGN, true);
end;

procedure ohci_free_ed(ed: POHCI_ED);
begin
    driver.dma.release(ed);
end;

function ohci_alloc_td : POHCI_TD;
begin
    ohci_alloc_td := driver.dma.allocate(sizeof(TOHCI_TD), OHCI_TD_ALIGN, true);
end;

procedure ohci_free_td(td: POHCI_TD);
begin
    driver.dma.release(td);
end;

{ Build an ED control dword.
  funcAddr: driver.bus.usb device address (0-127)
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

{ Map driver.bus.usb.ohci condition code to driver.bus.usb transfer status }
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
    base   : PtrUInt;
    loops  : uint32;
    fmival : uint32;
begin
    push_trace('driver.bus.usb.ohci.ohci_reset');
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
        { Wait ~10ms for driver.bus.usb reset signaling }
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
        io.syslog.logln('driver.bus.usb.ohci', 'HC reset timeout!');
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

    io.syslog.logln('driver.bus.usb.ohci', 'HC reset complete.');
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
    push_trace('driver.bus.usb.ohci.ohci_setup_schedule');
    priv := POHCI_PrivData(hc^.PrivData);

    { Allocate HCCA (256-byte aligned) }
    hcca := POHCI_HCCA(driver.dma.allocate(OHCI_HCCA_SIZE, OHCI_HCCA_ALIGN, true));
    if hcca = nil then begin
        io.syslog.logln('driver.bus.usb.ohci', 'Failed to allocate HCCA!');
        pop_trace;
        exit;
    end;
    priv^.HCCA := hcca;

    { Allocate dummy/sentinel EDs for each list head }
    priv^.EDControl   := ohci_alloc_ed;
    priv^.EDBulk      := ohci_alloc_ed;
    priv^.EDInterrupt := ohci_alloc_ed;

    if (priv^.EDControl = nil) or (priv^.EDBulk = nil) or (priv^.EDInterrupt = nil) then begin
        io.syslog.logln('driver.bus.usb.ohci', 'Failed to allocate sentinel EDs!');
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
        hcca^.HccaInterruptTable[i] := arch.platform.memory.physicalAddress(PtrUInt(priv^.EDInterrupt));

    { Set HC's HCCA pointer (physical) }
    ohci_write(priv^.MMIOBase, OHCI_REG_HCCA, arch.platform.memory.physicalAddress(PtrUInt(hcca)));

    { Set control and bulk list heads (physical) }
    ohci_write(priv^.MMIOBase, OHCI_REG_CONTROL_HEAD_ED, arch.platform.memory.physicalAddress(PtrUInt(priv^.EDControl)));
    ohci_write(priv^.MMIOBase, OHCI_REG_BULK_HEAD_ED, arch.platform.memory.physicalAddress(PtrUInt(priv^.EDBulk)));

    io.syslog.logln('driver.bus.usb.ohci', 'Schedule configured.');
    pop_trace;
end;

{ ========================= Start ========================= }

function ohci_start(hc : PUSBHCDriver) : boolean;
var
    priv    : POHCI_PrivData;
    base    : PtrUInt;
    ctrl    : uint32;
    rha     : uint32;
    loops   : uint32;
    port    : uint32;
begin
    push_trace('driver.bus.usb.ohci.ohci_start');
    ohci_start := false;
    if (hc = nil) or (hc^.PrivData = nil) then begin
        pop_trace;
        exit;
    end;
    priv := POHCI_PrivData(hc^.PrivData);
    base := priv^.MMIOBase;

    if (priv^.HCCA = nil) or (priv^.EDControl = nil) or
       (priv^.EDBulk = nil) or (priv^.EDInterrupt = nil) then begin
        pop_trace;
        exit;
    end;

    { Transition to USBOperational, enable control + bulk core.ds.lists }
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

    io.syslog.log('driver.bus.usb.ohci', 'Root hub has ');
    io.syslog.writeint(priv^.NumPorts);
    io.syslog.writestringln(' port(s).');

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
        io.syslog.logln('driver.bus.usb.ohci', 'Controller failed to enter operational state.');
        pop_trace;
        exit;
    end;

    io.syslog.logln('driver.bus.usb.ohci', 'Controller started (operational).');
    ohci_start := true;
    pop_trace;
end;

{ ========================= Stop ========================= }

procedure ohci_stop(hc : PUSBHCDriver);
var
    priv : POHCI_PrivData;
begin
    push_trace('driver.bus.usb.ohci.ohci_stop');
    if (hc <> nil) and (hc^.PrivData <> nil) then begin
        priv := POHCI_PrivData(hc^.PrivData);
        { Put HC into driver.bus.usb Reset state }
        ohci_write(priv^.MMIOBase, OHCI_REG_CONTROL, OHCI_CTRL_HCFS_RESET);
        io.syslog.logln('driver.bus.usb.ohci', 'Controller stopped.');
    end;
    pop_trace;
end;

{ ========================= Port Status ========================= }

function ohci_port_status(hc : PUSBHCDriver; port : uint8) : uint32;
var
    priv : POHCI_PrivData;
begin
    push_trace('driver.bus.usb.ohci.ohci_port_status');
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

function ohci_port_speed(hc : PUSBHCDriver; port : uint8) : uint8;
begin
    if (ohci_port_status(hc, port) AND OHCI_PORT_LSDA) <> 0 then
        ohci_port_speed := USB_SPEED_LOW
    else
        ohci_port_speed := USB_SPEED_FULL;
end;

function ohci_port_reset(hc : PUSBHCDriver; port : uint8) : boolean;
var
    priv   : POHCI_PrivData;
    base   : PtrUInt;
    regOfs : uint32;
    status : uint32;
    loops  : uint32;
begin
    push_trace('driver.bus.usb.ohci.ohci_port_reset');
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
        io.syslog.log('driver.bus.usb.ohci', 'Port ');
        io.syslog.writeint(port);
        io.syslog.writestringln(' reset timeout.');
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
        io.syslog.log('driver.bus.usb.ohci', 'Port ');
        io.syslog.writeint(port);
        io.syslog.writestringln(' reset and enabled.');
        ohci_port_reset := true;
    end else begin
        io.syslog.log('driver.bus.usb.ohci', 'Port ');
        io.syslog.writeint(port);
        io.syslog.writestringln(' reset failed (not enabled).');
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
    sentinel^.NextED := arch.platform.memory.physicalAddress(PtrUInt(ed));
    sentinel^.SWNext := ed;
end;

{ Build a control transfer: SETUP TD, optional DATA TDs, STATUS TD, all on a new ED }
procedure ohci_free_td_chain(firstTD : POHCI_TD); forward;

function ohci_submit_control(hc : PUSBHCDriver; transfer : PUSBTransfer; payload, bounce: pointer) : boolean;
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
    push_trace('driver.bus.usb.ohci.ohci_submit_control');
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
    if td = nil then begin ohci_free_td_chain(firstTD); pop_trace; exit; end;
    firstTD := td;

    td^.Control := ohci_make_td_control(OHCI_TD_DP_SETUP, OHCI_TD_DT_DATA0,
                                         OHCI_TD_DI_NONE, false);
    td^.Setup := transfer^.Setup;
    td^.CBP     := arch.platform.memory.physicalAddress(PtrUInt(@td^.Setup));
    td^.BE      := arch.platform.memory.physicalAddress(PtrUInt(@td^.Setup) + 7);
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
        if td = nil then begin ohci_free_td_chain(firstTD); pop_trace; exit; end;

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
        td^.CBP     := arch.platform.memory.physicalAddress(PtrUInt(payload) + offset);
        if pktLen > 0 then
            td^.BE := arch.platform.memory.physicalAddress(PtrUInt(payload) + offset + uint32(pktLen) - 1)
        else
            td^.BE := 0;
        td^.SWPad := pktLen; { Original data length, excluding SETUP/status }
        td^.NextTD  := 0;
        td^.SWTransfer := Pointer(transfer);
        td^.SWNext  := nil;

        { Link previous TD (NextTD = physical) }
        prevTD^.NextTD := arch.platform.memory.physicalAddress(PtrUInt(td));
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
    if td = nil then begin ohci_free_td_chain(firstTD); pop_trace; exit; end;

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

    prevTD^.NextTD := arch.platform.memory.physicalAddress(PtrUInt(td));
    prevTD^.SWNext := td;

    { Allocate a dummy/sentinel TD for the tail pointer (driver.bus.usb.ohci requires HeadP <> TailP to process) }
    tailTD := ohci_alloc_td;
    if tailTD = nil then begin ohci_free_td_chain(firstTD); pop_trace; exit; end;
    td^.NextTD := arch.platform.memory.physicalAddress(PtrUInt(tailTD));
    td^.SWNext := tailTD;

    { === Create ED === }
    ed := ohci_alloc_ed;
    if ed = nil then begin ohci_free_td_chain(firstTD); pop_trace; exit; end;

    ed^.Control := ohci_make_ed_control(devAddr, 0, OHCI_ED_DIR_FROM_TD,
                                         speedBit, maxPkt, false);
    ed^.HeadP   := arch.platform.memory.physicalAddress(PtrUInt(firstTD));   { First real TD (physical) }
    ed^.TailP   := arch.platform.memory.physicalAddress(PtrUInt(tailTD));    { Sentinel past last TD (physical) }
    ed^.NextED   := 0;
    ed^.SWTransfer := Pointer(transfer);
    ed^.SWPad1  := PtrUInt(firstTD);  { Virtual firstTD for cleanup }
    ed^.Bounce := bounce;

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

{ A general TD covers at most two physical pages. A 4 KiB span is safe
  even for an unaligned buffer; intermediate TDs must end on packet boundaries. }
function ohci_async_length(remaining, maxPkt : uint32; bulk : boolean) : uint32;
var limit : uint32;
begin
    limit := maxPkt;
    if bulk and (maxPkt > 0) and (maxPkt <= 4096) then
        limit := 4096 - (4096 mod maxPkt);
    if remaining < limit then limit := remaining;
    ohci_async_length := limit;
end;

{ Build TDs for an interrupt or bulk transfer on a new ED }
function ohci_submit_async(hc : PUSBHCDriver; transfer : PUSBTransfer; payload, bounce: pointer) : boolean;
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
    push_trace('driver.bus.usb.ohci.ohci_submit_async');
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
        if td = nil then begin ohci_free_td_chain(firstTD); pop_trace; exit; end;

        if firstTD = nil then firstTD := td;

        pktLen := ohci_async_length(remaining, maxPkt, transfer^.PipeType = ptBulk);

        { Hardware advances the carry after every packet in a bulk TD. }
        if transfer^.PipeType = ptBulk then toggle := OHCI_TD_DT_FROM_ED;

        td^.Control := ohci_make_td_control(dirPID, toggle,
                                             OHCI_TD_DI_NONE, transfer^.PipeType <> ptBulk);
        if pktLen > 0 then begin
            td^.CBP := arch.platform.memory.physicalAddress(PtrUInt(payload) + offset);
            td^.BE := arch.platform.memory.physicalAddress(PtrUInt(payload) + offset + uint32(pktLen) - 1)
        end else begin
            td^.CBP := 0;
            td^.BE := 0;
        end;
        td^.SWPad := pktLen; { Original data length }
        td^.NextTD := 0;
        td^.SWTransfer := Pointer(transfer);
        td^.SWNext := nil;

        if prevTD <> nil then begin
            prevTD^.NextTD := arch.platform.memory.physicalAddress(PtrUInt(td));
            prevTD^.SWNext := td;
        end;
        prevTD := td;

        { Alternate toggle }
        if toggle = OHCI_TD_DT_DATA1 then
            toggle := OHCI_TD_DT_DATA0
        else
            toggle := OHCI_TD_DT_DATA1;

        inc(offset, pktLen);
        dec(remaining, pktLen);
    until remaining = 0;

    { Mark last TD with immediate interrupt }
    if prevTD <> nil then
        prevTD^.Control := (prevTD^.Control AND (NOT OHCI_TD_DI_MASK)) OR OHCI_TD_DI_IMMEDIATE;

    { Update endpoint toggle }
    if transfer^.PipeType <> ptBulk then begin
        if toggle = OHCI_TD_DT_DATA1 then
            transfer^.Endpoint^.Toggle := 1
        else
            transfer^.Endpoint^.Toggle := 0;
    end;

    { Allocate tail sentinel TD }
    tailTD := ohci_alloc_td;
    if tailTD = nil then begin ohci_free_td_chain(firstTD); pop_trace; exit; end;
    prevTD^.NextTD := arch.platform.memory.physicalAddress(PtrUInt(tailTD));
    prevTD^.SWNext := tailTD;

    { Create ED }
    ed := ohci_alloc_ed;
    if ed = nil then begin ohci_free_td_chain(firstTD); pop_trace; exit; end;

    ed^.Control := ohci_make_ed_control(devAddr, epNum, edDir,
                                         speedBit, maxPkt, false);
    ed^.HeadP   := arch.platform.memory.physicalAddress(PtrUInt(firstTD));
    if transfer^.PipeType = ptBulk then
        ed^.HeadP := ed^.HeadP or ((uint32(transfer^.Endpoint^.Toggle) and 1) shl 1);
    ed^.TailP   := arch.platform.memory.physicalAddress(PtrUInt(tailTD));
    ed^.NextED   := 0;
    ed^.SWTransfer := Pointer(transfer);
    ed^.SWPad1  := PtrUInt(firstTD);  { Virtual firstTD for cleanup }
    ed^.Bounce := bounce;

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

{ Largest safe bulk submission; class drivers do not know descriptor geometry. }
function ohci_bulk_limit(hc : PUSBHCDriver; ep : PUSBEndpoint; buffer : pointer; length : uint32) : uint32;
var limit : uint32;
begin
    limit := 64 * 4096; { Bounded general-TD chain, below the 128-TD poll limit. }
    if limit > length then limit := length;
    ohci_bulk_limit := limit;
end;

function inbound(transfer: PUSBTransfer): boolean;
begin
    if transfer^.PipeType = ptControl then inbound := (transfer^.Setup.bmRequestType and $80) <> 0
    else inbound := transfer^.Direction = dirIn;
end;

function ohci_submit(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
var payload, bounce: pointer;
begin
    ohci_submit := false;
    if (hc = nil) or (transfer = nil) or (transfer^.Device = nil) then exit;
    if not (transfer^.PipeType in [ptControl, ptBulk, ptInterrupt]) then exit;
    if (transfer^.PipeType <> ptControl) and (transfer^.Endpoint = nil) then exit;
    payload := transfer^.Buffer;
    bounce := nil;
    case driver.dma.reach32(PtrUInt(payload), transfer^.BufferLen) of
        dmaInvalid: exit;
        dmaHigh: begin
            bounce := driver.dma.allocateBounce(transfer^.BufferLen);
            if bounce = nil then exit;
            payload := bounce;
            if not inbound(transfer) then memcpy(PtrUInt(transfer^.Buffer), PtrUInt(payload), transfer^.BufferLen);
        end;
    end;
    case transfer^.PipeType of
        ptControl: ohci_submit := ohci_submit_control(hc, transfer, payload, bounce);
        ptInterrupt, ptBulk: ohci_submit := ohci_submit_async(hc, transfer, payload, bounce);
    end;
    if not ohci_submit then driver.dma.release(bounce);
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

{ ISR handler — registered on the driver.bus.pci interrupt line. }
procedure ohci_isr;
var
    i      : uint32;
    hc     : PUSBHCDriver;
    priv   : POHCI_PrivData;
    intSts : uint32;
begin
    if OHCIInstanceCount = 0 then exit;
    for i := 0 to OHCIInstanceCount - 1 do begin
        hc := OHCIInstances[i];
        if hc = nil then continue;
        priv := POHCI_PrivData(hc^.PrivData);
        if priv = nil then continue;

        { Check if this controller has pending interrupt status }
        intSts := ohci_read(priv^.MMIOBase, OHCI_REG_INTSTATUS);
        if intSts = 0 then continue;

        { Acknowledge interrupt status NOW to de-assert level-triggered driver.bus.pci line.
          Must happen before ohci_poll, because PollBusy guard may skip the
          acknowledge inside poll — leaving the line asserted = interrupt storm. }
        ohci_write(priv^.MMIOBase, OHCI_REG_INTSTATUS, intSts);

        { Process completions (walks ED core.ds.lists) }
        ohci_poll(hc);

        { Hotplug: if RootHubStatusChange, flag for deferred processing }
        if ((intSts AND OHCI_INT_RHSC) <> 0) and hc^.HotplugArmed then
            hc^.PortChangePending := true;
    end;
    driver.bus.usb.core.fire_completion_hooks;
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
    io.syslog.logln('driver.bus.usb.ohci', 'Hardware interrupts enabled.');
end;

{ Data bytes completed by one TD. SWPad excludes SETUP and status bytes. }
function ohci_td_data_length(td : POHCI_TD) : uint32;
var residual : uint32; cc : uint8;
begin
    ohci_td_data_length := 0;
    cc := ohci_td_cc(td);
    if (td^.SWPad = 0) or ((cc <> OHCI_CC_NO_ERROR) and (cc <> OHCI_CC_DATA_UNDERRUN)) then exit;
    residual := 0;
    if td^.CBP <> 0 then begin
        residual := (td^.BE AND $FFF) + 1;
        if (td^.CBP AND $FFFFF000) <> (td^.BE AND $FFFFF000) then inc(residual, 4096);
        residual := residual - (td^.CBP AND $FFF);
    end;
    if residual <= td^.SWPad then ohci_td_data_length := td^.SWPad - residual;
end;

procedure ohci_poll(hc : PUSBHCDriver);
var
    priv     : POHCI_PrivData;
    base     : PtrUInt;
    intSts   : uint32;
    sentinel : POHCI_ED;
    ed       : POHCI_ED;
    nextED   : POHCI_ED;
    td       : POHCI_TD;
    transfer : PUSBTransfer;
    cc       : uint8;
    listIdx  : uint32;
    status   : TUSBTransferStatus;
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
        io.syslog.logln('driver.bus.usb.ohci', 'Unrecoverable error detected!');
    end;

    { Walk all three ED core.ds.lists (control, bulk, interrupt) and check for completed transfers }
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
                    if ((ed^.HeadP and 1) <> 0) or
                       ((ed^.HeadP and $FFFFFFF0) = (ed^.TailP and $FFFFFFF0)) then begin
                        if (ed^.HeadP and 1) <> 0 then status := tsStall
                        else status := tsSuccess;
                        transfer^.ActualLen := 0;
                        td := POHCI_TD(ed^.SWPad1); { Virtual firstTD }
                        while td <> nil do begin
                            cc := ohci_td_cc(td);
                            inc(transfer^.ActualLen, ohci_td_data_length(td));
                            if (cc <> OHCI_CC_NO_ERROR) and (cc <> OHCI_CC_NOT_ACCESSED) then begin
                                status := ohci_cc_to_status(cc);
                                break;
                            end;
                            td := td^.SWNext;
                        end;
                        if transfer^.PipeType = ptBulk then
                            transfer^.Endpoint^.Toggle := (ed^.HeadP shr 1) and 1;
                        if ed^.Bounce <> nil then begin
                            if inbound(transfer) and (transfer^.ActualLen <= transfer^.BufferLen) then
                                memcpy(PtrUInt(ed^.Bounce), PtrUInt(transfer^.Buffer), transfer^.ActualLen);
                            driver.dma.release(ed^.Bounce);
                        end;
                        transfer^.HCPriv := nil;
                        ohci_remove_ed(sentinel, ed);
                        ohci_free_td_chain(POHCI_TD(ed^.SWPad1));
                        ohci_free_ed(ed);
                        transfer^.Status := status;
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
    bar: uint64;
    mmioBase : PtrUInt;
begin
    push_trace('driver.bus.usb.ohci.load');
    load := false;
    OHCIInstanceCount := 0;

    devices := driver.bus.pci.getDeviceInfo($0C, $03, $10, count);
    io.syslog.log('driver.bus.usb.ohci', 'Found ');
    io.syslog.writeint(count);
    io.syslog.writestringln(' driver.bus.usb.ohci controller(s).');

    if count = 0 then begin
        load := true;
        pop_trace;
        exit;
    end;

    for i := 0 to count - 1 do begin
        io.syslog.log('driver.bus.usb.ohci', 'Controller[');
        io.syslog.writeint(i);
        io.syslog.writestring(']: VID=');
        io.syslog.writehex(devices[i].vendor_id);
        io.syslog.writestring(' DID=');
        io.syslog.writehex(devices[i].device_id);
        io.syslog.writestring(' BAR0=');
        io.syslog.writehexln(devices[i].address0);

        bar := driver.bus.pci.memoryBAR(devices[i].address0, devices[i].address1);
        if bar = 0 then begin
            io.syslog.logln('driver.bus.usb.ohci', 'Invalid MMIO base (BAR0=0), skipping.');
            continue;
        end;

        { Map the full physical BAR before accessing controller registers. }
        mmioBase := PtrUInt(arch.platform.memory.mapDevice(bar, 4096));
        if mmioBase = 0 then continue;

        { Enable driver.bus.pci bus mastering }
        driver.bus.pci.setBusMaster(devices[i].bus, devices[i].slot, devices[i].func, true);

        { Allocate private data }
        priv := POHCI_PrivData(kalloc(sizeof(TOHCI_PrivData)));
        if priv = nil then begin
            io.syslog.logln('driver.bus.usb.ohci', 'Failed to allocate private data!');
            continue;
        end;
        memset(PtrUInt(priv), 0, sizeof(TOHCI_PrivData));
        priv^.MMIOBase  := mmioBase;
        priv^.PCIBus    := devices[i].bus;
        priv^.PCISlot   := devices[i].slot;
        priv^.PCIFunc   := devices[i].func;

        { Log the revision register }
        io.syslog.log('driver.bus.usb.ohci', 'Revision: ');
        io.syslog.writehexln(ohci_read(mmioBase, OHCI_REG_REVISION));

        { Initialize HC driver record }
        usb_hc_init_record(@hc);
        hc.Name         := 'driver.bus.usb.ohci';
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
        hc.fnBulkLimit  := @ohci_bulk_limit;
        hc.fnPoll       := TUSBHCPoll(@ohci_poll);
        hc.fnPortReset  := TUSBHCPortReset(@ohci_port_reset);
        hc.fnPortStatus := TUSBHCPortStatus(@ohci_port_status);
        hc.fnPortSpeed := TUSBHCPortSpeed(@ohci_port_speed);

        { Reset the controller }
        if not ohci_reset(@hc) then begin
            io.syslog.logln('driver.bus.usb.ohci', 'Reset failed, skipping controller.');
            kfree(void(priv));
            continue;
        end;

        { Setup the schedule (HCCA + ED core.ds.lists) }
        ohci_setup_schedule(@hc);

        { Start the controller }
        if not ohci_start(@hc) then begin
            io.syslog.logln('driver.bus.usb.ohci', 'Start failed, skipping controller.');
            if priv^.HCCA <> nil then driver.dma.release(priv^.HCCA);
            if priv^.EDControl <> nil then ohci_free_ed(priv^.EDControl);
            if priv^.EDBulk <> nil then ohci_free_ed(priv^.EDBulk);
            if priv^.EDInterrupt <> nil then ohci_free_ed(priv^.EDInterrupt);
            kfree(void(priv));
            continue;
        end;

        { Register with driver.bus.usb core — get back the stable heap pointer }
        hcEntry := driver.bus.usb.core.register_hc(@hc);

        { Scan ports for connected devices (use the stable pointer, not stack-local @hc) }
        if hcEntry <> nil then begin
            { Track instance for ISR dispatch }
            if OHCIInstanceCount < OHCI_MAX_INSTANCES then begin
                OHCIInstances[OHCIInstanceCount] := hcEntry;
                inc(OHCIInstanceCount);
            end;

            { Register ISR on driver.bus.pci interrupt line }
            io.syslog.log('driver.bus.usb.ohci', 'Registering ISR on IRQ ');
            io.syslog.writeintln(devices[i].interrupt_line);
            arch.platform.interrupts.registerIRQ(32 + devices[i].interrupt_line, @ohci_isr);
            arch.platform.interrupts.routePCI(devices[i].interrupt_line, 32 + devices[i].interrupt_line);

            { Enable hardware interrupts }
            ohci_enable_interrupts(hcEntry);

            { Scan for connected devices }
            driver.bus.usb.core.scan_ports(hcEntry);
        end else
            io.syslog.logln('driver.bus.usb.ohci', 'Failed to register HC with driver.bus.usb core.');

        io.syslog.logln('driver.bus.usb.ohci', 'Controller initialized and registered.');
    end;

    load := true;
    pop_trace;
end;

{ ========================= Unit Tests ========================= }

{$ifdef UNIT_TESTS}
function testDMA32(buffer: puint8): boolean;
type
    PFixture = ^TFixture;
    TFixture = record
        priv: TOHCI_PrivData;
        hc: TUSBHCDriver;
        dev: TUSBDevice;
        ep: TUSBEndpoint;
        xfer: TUSBTransfer;
        regs: array[0..15] of uint32;
    end;
var f: PFixture;
    ed: POHCI_ED;
    td: POHCI_TD;
    ok: boolean;
begin
    testDMA32 := false;
    f := PFixture(tryAlloc(sizeof(TFixture)));
    if f = nil then exit;
    f^.hc.PrivData := @f^.priv;
    f^.priv.MMIOBase := PtrUInt(@f^.regs);
    f^.priv.EDBulk := ohci_alloc_ed;
    f^.xfer.Device := @f^.dev;
    f^.xfer.Endpoint := @f^.ep;
    f^.ep.MaxPacket := 64;
    f^.xfer.Buffer := buffer;
    f^.xfer.BufferLen := 64;
    f^.xfer.PipeType := ptBulk;
    f^.xfer.Direction := dirOut;
    buffer[0] := $76;
    ok := (f^.priv.EDBulk <> nil) and ohci_submit(@f^.hc, @f^.xfer);
    if ok then begin
        ed := f^.priv.EDBulk^.SWNext;
        td := POHCI_TD(ed^.SWPad1);
        ok := (ed^.Bounce <> nil) and (puint8(ed^.Bounce)[0] = $76) and
              (td^.CBP = physicalAddress(PtrUInt(ed^.Bounce)));
        td^.Control := td^.Control and $0FFFFFFF;
        td^.CBP := 0;
        ed^.HeadP := ed^.TailP;
        ohci_poll(@f^.hc);
        ok := ok and (f^.xfer.Status = tsSuccess) and (f^.xfer.ActualLen = 64);
    end;
    f^.xfer.Direction := dirIn;
    buffer[8] := $78;
    if ok then ok := ohci_submit(@f^.hc, @f^.xfer);
    if ok then begin
        ed := f^.priv.EDBulk^.SWNext;
        td := POHCI_TD(ed^.SWPad1);
        memset(PtrUInt(ed^.Bounce), $91, 64);
        inc(td^.CBP, 8);
        td^.Control := (td^.Control and $0FFFFFFF) or (uint32(OHCI_CC_DATA_UNDERRUN) shl 28);
        ed^.HeadP := ed^.HeadP or 1;
        ohci_poll(@f^.hc);
        ok := (f^.xfer.Status = tsSuccess) and (f^.xfer.ActualLen = 8) and
              (buffer[7] = $91) and (buffer[8] = $78) and (f^.xfer.HCPriv = nil);
    end;
    ohci_free_ed(f^.priv.EDBulk);
    kfree(void(f));
    testDMA32 := ok;
end;
{$endif}

procedure UnitTest;
var
    context : TTestContext;
    edCtrl : uint32;
    tdCtrl : uint32;
    ed     : POHCI_ED;
    td     : POHCI_TD;
    hcca   : POHCI_HCCA;

begin
    test.harness.Start(@context, 'driver.bus.usb.ohci');

    { === Structure Sizes === }
    test.harness.Assert(@context, (driver.dma.reach32(0, 0) = dmaDirect), 'empty transfer requires no DMA buffer');
    test.harness.Assert(@context, (driver.dma.reach32(0, 16) = dmaInvalid), 'unmapped DMA buffer rejected');
    test.harness.Assert(@context, (driver.dma.reach32(High(PtrUInt) - 7, 16) = dmaInvalid), 'DMA address wrap rejected');
    test.harness.Assert(@context, sizeof(TOHCI_HCCA) = 256, 'sizeof HCCA=256');
    test.harness.Assert(@context, PtrUInt(@POHCI_ED(nil)^.SWNext) = 16, 'ED hardware prefix remains 16 bytes');
    test.harness.Assert(@context, PtrUInt(@POHCI_TD(nil)^.SWNext) = 16, 'TD hardware prefix remains 16 bytes');

    { === ED Control Building === }
    { Addr 0, EP0, direction from TD, full speed, maxPkt 8, general }
    edCtrl := ohci_make_ed_control(0, 0, OHCI_ED_DIR_FROM_TD, OHCI_ED_SPEED_FULL, 8, false);
    test.harness.Assert(@context, (edCtrl AND $7F) = 0, 'ed addr=0');
    test.harness.Assert(@context, ((edCtrl SHR 7) AND $0F) = 0, 'ed ep=0');
    test.harness.Assert(@context, (edCtrl AND OHCI_ED_DIR_MASK) = OHCI_ED_DIR_FROM_TD, 'ed dir=FROM_TD');
    test.harness.Assert(@context, (edCtrl AND OHCI_ED_SPEED_LOW) = 0, 'ed speed=full');
    test.harness.Assert(@context, ((edCtrl SHR OHCI_ED_MPS_SHIFT) AND $7FF) = 8, 'ed mps=8');
    test.harness.Assert(@context, (edCtrl AND OHCI_ED_FORMAT_ISO) = 0, 'ed format=general');

    { Addr 5, EP3, IN, low speed, maxPkt 64 }
    edCtrl := ohci_make_ed_control(5, 3, OHCI_ED_DIR_IN, OHCI_ED_SPEED_LOW, 64, false);
    test.harness.Assert(@context, (edCtrl AND $7F) = 5, 'ed addr=5');
    test.harness.Assert(@context, ((edCtrl SHR 7) AND $0F) = 3, 'ed ep=3');
    test.harness.Assert(@context, (edCtrl AND OHCI_ED_DIR_MASK) = OHCI_ED_DIR_IN, 'ed dir=IN');
    test.harness.Assert(@context, (edCtrl AND OHCI_ED_SPEED_LOW) <> 0, 'ed speed=low');
    test.harness.Assert(@context, ((edCtrl SHR OHCI_ED_MPS_SHIFT) AND $7FF) = 64, 'ed mps=64');

    { Addr 127, EP15, OUT, full speed, maxPkt 1023, isochronous }
    edCtrl := ohci_make_ed_control(127, 15, OHCI_ED_DIR_OUT, OHCI_ED_SPEED_FULL, 1023, true);
    test.harness.Assert(@context, (edCtrl AND $7F) = 127, 'ed addr=127');
    test.harness.Assert(@context, ((edCtrl SHR 7) AND $0F) = 15, 'ed ep=15');
    test.harness.Assert(@context, (edCtrl AND OHCI_ED_DIR_MASK) = OHCI_ED_DIR_OUT, 'ed dir=OUT');
    test.harness.Assert(@context, ((edCtrl SHR OHCI_ED_MPS_SHIFT) AND $7FF) = 1023, 'ed mps=1023');
    test.harness.Assert(@context, (edCtrl AND OHCI_ED_FORMAT_ISO) <> 0, 'ed format=iso');

    { === TD Control Building === }
    { SETUP, DATA0, no interrupt, no rounding }
    tdCtrl := ohci_make_td_control(OHCI_TD_DP_SETUP, OHCI_TD_DT_DATA0,
                                    OHCI_TD_DI_NONE, false);
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_DP_MASK) = OHCI_TD_DP_SETUP, 'td dp=SETUP');
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_DT_MASK) = OHCI_TD_DT_DATA0, 'td dt=DATA0');
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_DI_MASK) = OHCI_TD_DI_NONE, 'td di=NONE');
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_R) = 0, 'td rounding=off');
    test.harness.Assert(@context, ((tdCtrl SHR OHCI_TD_CC_SHIFT) AND $F) = OHCI_CC_NOT_ACCESSED, 'td cc=NOT_ACCESSED');

    { IN, DATA1, immediate interrupt, rounding }
    tdCtrl := ohci_make_td_control(OHCI_TD_DP_IN, OHCI_TD_DT_DATA1,
                                    OHCI_TD_DI_IMMEDIATE, true);
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_DP_MASK) = OHCI_TD_DP_IN, 'td dp=IN');
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_DT_MASK) = OHCI_TD_DT_DATA1, 'td dt=DATA1');
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_DI_MASK) = OHCI_TD_DI_IMMEDIATE, 'td di=IMMEDIATE');
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_R) <> 0, 'td rounding=on');

    { OUT, from ED toggle, no interrupt, no rounding }
    tdCtrl := ohci_make_td_control(OHCI_TD_DP_OUT, OHCI_TD_DT_FROM_ED,
                                    OHCI_TD_DI_NONE, false);
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_DP_MASK) = OHCI_TD_DP_OUT, 'td dp=OUT');
    test.harness.Assert(@context, (tdCtrl AND OHCI_TD_DT_MASK) = OHCI_TD_DT_FROM_ED, 'td dt=FROM_ED');

    test.harness.Assert(@context, ohci_async_length(4096,64,true)=4096, 'bulk page uses one TD, not 64');
    test.harness.Assert(@context, ohci_async_length(8192,64,true)=4096, 'bulk TD bounded to two pages');
    test.harness.Assert(@context, ohci_async_length(31,64,true)=31, 'bulk CBW retains short length');
    test.harness.Assert(@context, ohci_async_length(0,64,true)=0, 'bulk zero length packet');
    test.harness.Assert(@context, ohci_async_length(4096,64,false)=64, 'interrupt packet sizing unchanged');

    { === Condition Code Mapping === }
    test.harness.Assert(@context, ohci_cc_to_status(OHCI_CC_NO_ERROR) = tsSuccess, 'cc NO_ERROR->tsSuccess');
    test.harness.Assert(@context, ohci_cc_to_status(OHCI_CC_CRC) = tsCRCError, 'cc CRC->tsCRCError');
    test.harness.Assert(@context, ohci_cc_to_status(OHCI_CC_BIT_STUFFING) = tsBitStuffError, 'cc BITSTUFF->tsBitStuffError');
    test.harness.Assert(@context, ohci_cc_to_status(OHCI_CC_STALL) = tsStall, 'cc STALL->tsStall');
    test.harness.Assert(@context, ohci_cc_to_status(OHCI_CC_DEVICE_NOT_RESP) = tsTimeout, 'cc DNR->tsTimeout');
    test.harness.Assert(@context, ohci_cc_to_status(OHCI_CC_DATA_OVERRUN) = tsDataBufferError, 'cc OVERRUN->tsDataBufferError');
    test.harness.Assert(@context, ohci_cc_to_status(OHCI_CC_DATA_UNDERRUN) = tsSuccess, 'cc UNDERRUN->tsSuccess');
    test.harness.Assert(@context, ohci_cc_to_status(OHCI_CC_NOT_ACCESSED) = tsInProgress, 'cc NOT_ACCESSED->tsInProgress');

    { === ED Allocation & Alignment === }
    ed := ohci_alloc_ed;
    test.harness.Assert(@context, ed <> nil, 'alloc_ed not nil');
    test.harness.Assert(@context, (PtrUInt(ed) AND $0F) = 0, 'alloc_ed 16-byte aligned');
    if ed <> nil then begin
        ed^.SWPad1 := PtrUInt(ed);
        test.harness.Assert(@context, POHCI_ED(ed^.SWPad1) = ed, 'ED software pointer retains native width');
    end;
    test.harness.Assert(@context, ed^.Control = 0, 'alloc_ed zeroed control');
    test.harness.Assert(@context, ed^.TailP = 0, 'alloc_ed zeroed tailp');
    test.harness.Assert(@context, ed^.HeadP = 0, 'alloc_ed zeroed headp');
    test.harness.Assert(@context, ed^.NextED = 0, 'alloc_ed zeroed nexted');
    ohci_free_ed(ed);

    { === TD Allocation & Alignment === }
    td := ohci_alloc_td;
    test.harness.Assert(@context, td <> nil, 'alloc_td not nil');
    test.harness.Assert(@context, (PtrUInt(td) AND $0F) = 0, 'alloc_td 16-byte aligned');
    test.harness.Assert(@context, td^.Control = 0, 'alloc_td zeroed control');
    test.harness.Assert(@context, td^.CBP = 0, 'alloc_td zeroed cbp');
    test.harness.Assert(@context, td^.NextTD = 0, 'alloc_td zeroed nexttd');
    test.harness.Assert(@context, td^.BE = 0, 'alloc_td zeroed be');
    td^.SWPad := 4096;
    td^.Control := OHCI_CC_NO_ERROR shl OHCI_TD_CC_SHIFT;
    test.harness.Assert(@context, ohci_td_data_length(td)=4096, 'multi-packet TD complete length');
    td^.Control := OHCI_CC_DATA_UNDERRUN shl OHCI_TD_CC_SHIFT;
    td^.CBP := $1200; td^.BE := $1FFF;
    test.harness.Assert(@context, ohci_td_data_length(td)=512, 'multi-packet TD short read length');
    td^.CBP := $1F00; td^.BE := $8EFF;
    test.harness.Assert(@context, ohci_td_data_length(td)=0, 'two noncontiguous pages residual');
    td^.CBP := $8100;
    test.harness.Assert(@context, ohci_td_data_length(td)=512, 'short read across physical page boundary');
    ohci_free_td(td);

    { === HCCA Size / Alignment === }
    test.harness.Assert(@context, OHCI_HCCA_SIZE = 256, 'HCCA_SIZE=256');
    test.harness.Assert(@context, OHCI_HCCA_ALIGN = 256, 'HCCA_ALIGN=256');
    hcca := POHCI_HCCA(driver.dma.allocate(OHCI_HCCA_SIZE, OHCI_HCCA_ALIGN, true));
    test.harness.Assert(@context, hcca <> nil, 'hcca alloc not nil');
    test.harness.Assert(@context, (PtrUInt(hcca) AND $FF) = 0, 'hcca 256-byte aligned');
    driver.dma.release(hcca);

    { === Register offset constants === }
    test.harness.Assert(@context, OHCI_REG_REVISION = $00, 'REG_REVISION=$00');
    test.harness.Assert(@context, OHCI_REG_CONTROL = $04, 'REG_CONTROL=$04');
    test.harness.Assert(@context, OHCI_REG_CMDSTATUS = $08, 'REG_CMDSTATUS=$08');
    test.harness.Assert(@context, OHCI_REG_HCCA = $18, 'REG_HCCA=$18');
    test.harness.Assert(@context, OHCI_REG_CONTROL_HEAD_ED = $20, 'REG_CONTROL_HEAD_ED=$20');
    test.harness.Assert(@context, OHCI_REG_BULK_HEAD_ED = $28, 'REG_BULK_HEAD_ED=$28');
    test.harness.Assert(@context, OHCI_REG_RH_DESCRIPTORA = $48, 'REG_RH_DESCRIPTORA=$48');
    test.harness.Assert(@context, OHCI_REG_RH_STATUS = $50, 'REG_RH_STATUS=$50');
    test.harness.Assert(@context, OHCI_REG_RH_PORT_STATUS = $54, 'REG_RH_PORT_STATUS=$54');

    { === HcControl bits === }
    test.harness.Assert(@context, OHCI_CTRL_HCFS_RESET = $00, 'CTRL_HCFS_RESET=$00');
    test.harness.Assert(@context, OHCI_CTRL_HCFS_OPERATIONAL = $80, 'CTRL_HCFS_OPERATIONAL=$80');
    test.harness.Assert(@context, OHCI_CTRL_CLE = $10, 'CTRL_CLE=$10');
    test.harness.Assert(@context, OHCI_CTRL_BLE = $20, 'CTRL_BLE=$20');
    test.harness.Assert(@context, OHCI_CTRL_PLE = $04, 'CTRL_PLE=$04');

    { === Port status bits === }
    test.harness.Assert(@context, OHCI_PORT_CCS = $00000001, 'PORT_CCS=$01');
    test.harness.Assert(@context, OHCI_PORT_PES = $00000002, 'PORT_PES=$02');
    test.harness.Assert(@context, OHCI_PORT_PRS = $00000010, 'PORT_PRS=$10');
    test.harness.Assert(@context, OHCI_PORT_PPS = $00000100, 'PORT_PPS=$100');
    test.harness.Assert(@context, OHCI_PORT_LSDA = $00000200, 'PORT_LSDA=$200');
    test.harness.Assert(@context, OHCI_PORT_PRSC = $00100000, 'PORT_PRSC=$100000');

    { === ED skip bit === }
    test.harness.Assert(@context, OHCI_ED_SKIP = $00004000, 'ED_SKIP=$4000');

    { === CommandStatus bits === }
    test.harness.Assert(@context, OHCI_CMD_HCR = $01, 'CMD_HCR=$01');
    test.harness.Assert(@context, OHCI_CMD_CLF = $02, 'CMD_CLF=$02');
    test.harness.Assert(@context, OHCI_CMD_BLF = $04, 'CMD_BLF=$04');

    test.harness.Finish(@context);
end;

end.
