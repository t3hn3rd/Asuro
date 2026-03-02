{
    Driver->Bus->USB->USBTypes - Shared USB Types, Constants & HC Abstraction.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit usbtypes;

interface

uses
    util,
    lmemorymanager,
    drivertypes,
    lists,
    tracer,
    syslog,
    strings;

{ ========================= Constants ========================= }

const
    { Standard Descriptor Types }
    USB_DESC_DEVICE           = $01;
    USB_DESC_CONFIGURATION    = $02;
    USB_DESC_STRING           = $03;
    USB_DESC_INTERFACE        = $04;
    USB_DESC_ENDPOINT         = $05;
    USB_DESC_DEVICE_QUALIFIER = $06;
    USB_DESC_HUB              = $29;

    { Standard Request Codes }
    USB_REQ_GET_STATUS        = $00;
    USB_REQ_CLEAR_FEATURE     = $01;
    USB_REQ_SET_FEATURE       = $03;
    USB_REQ_SET_ADDRESS       = $05;
    USB_REQ_GET_DESCRIPTOR    = $06;
    USB_REQ_SET_DESCRIPTOR    = $07;
    USB_REQ_GET_CONFIGURATION = $08;
    USB_REQ_SET_CONFIGURATION = $09;
    USB_REQ_GET_INTERFACE     = $0A;
    USB_REQ_SET_INTERFACE     = $0B;
    USB_REQ_SYNCH_FRAME       = $0C;

    { Request Type Bit Fields }
    USB_REQTYPE_DIR_OUT       = $00;
    USB_REQTYPE_DIR_IN        = $80;
    USB_REQTYPE_TYPE_STANDARD = $00;
    USB_REQTYPE_TYPE_CLASS    = $20;
    USB_REQTYPE_TYPE_VENDOR   = $40;
    USB_REQTYPE_REC_DEVICE    = $00;
    USB_REQTYPE_REC_INTERFACE = $01;
    USB_REQTYPE_REC_ENDPOINT  = $02;
    USB_REQTYPE_REC_OTHER     = $03;

    { Endpoint Direction Mask }
    USB_EP_DIR_MASK           = $80;
    USB_EP_DIR_OUT            = $00;
    USB_EP_DIR_IN             = $80;
    USB_EP_NUM_MASK           = $0F;

    { Endpoint Transfer Type Mask (bmAttributes bits 1:0) }
    USB_EP_ATTR_TRANSFER_MASK = $03;
    USB_EP_ATTR_CONTROL       = $00;
    USB_EP_ATTR_ISOCHRONOUS   = $01;
    USB_EP_ATTR_BULK          = $02;
    USB_EP_ATTR_INTERRUPT     = $03;

    { USB Speeds }
    USB_SPEED_LOW             = 0;   { 1.5 Mbps  }
    USB_SPEED_FULL            = 1;   { 12 Mbps   }
    USB_SPEED_HIGH            = 2;   { 480 Mbps  }
    USB_SPEED_SUPER           = 3;   { 5 Gbps    }

    { USB Device Class Codes }
    USB_CLASS_PER_INTERFACE   = $00;
    USB_CLASS_HID             = $03;
    USB_CLASS_MASS_STORAGE    = $08;
    USB_CLASS_HUB             = $09;
    USB_CLASS_VENDOR_SPEC     = $FF;

    { HID Subclass / Protocol }
    USB_HID_SUBCLASS_BOOT    = $01;
    USB_HID_PROTO_KEYBOARD   = $01;
    USB_HID_PROTO_MOUSE      = $02;

    { HC Types }
    USB_HC_UHCI               = 0;
    USB_HC_OHCI               = 1;
    USB_HC_EHCI               = 2;
    USB_HC_XHCI               = 3;

    { Limits }
    USB_MAX_DEVICES           = 127;
    USB_MAX_ENDPOINTS         = 32;

    { Feature Selectors }
    USB_FEATURE_ENDPOINT_HALT = $00;
    USB_FEATURE_REMOTE_WAKEUP = $01;

{ ========================= Types ========================= }

type

    { ---- Standard Descriptors ---- }

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

    { ---- Setup Packet ---- }

    PUSBSetupPacket = ^TUSBSetupPacket;
    TUSBSetupPacket = packed record
        bmRequestType : uint8;
        bRequest      : uint8;
        wValue        : uint16;
        wIndex        : uint16;
        wLength       : uint16;
    end;

    { ---- Transfer Status ---- }

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

    { ---- Direction & Pipe Type ---- }

    TUSBDirection = (dirOut, dirIn, dirSetup);

    TUSBPipeType = (ptControl, ptIsochronous, ptBulk, ptInterrupt);

    { ---- Endpoint State ---- }

    PUSBEndpoint = ^TUSBEndpoint;
    TUSBEndpoint = record
        Address   : uint8;      { Endpoint number (0-15) }
        Direction : TUSBDirection;
        PipeType  : TUSBPipeType;
        MaxPacket : uint16;
        Interval  : uint8;      { Polling interval (interrupt/iso) }
        Toggle    : uint8;      { Data toggle state: 0 or 1 }
    end;

    { ---- Forward Declarations ---- }

    PUSBDevice   = ^TUSBDevice;
    PUSBHCDriver = ^TUSBHCDriver;
    PUSBTransfer = ^TUSBTransfer;

    { ---- Disconnect Callback ---- }
    TUSBDisconnectCallback = procedure(dev : PUSBDevice);

    { ---- Transfer Request ---- }

    TUSBTransfer = record
        Device    : PUSBDevice;
        Endpoint  : PUSBEndpoint;
        Direction : TUSBDirection;
        PipeType  : TUSBPipeType;
        Buffer    : Pointer;
        BufferLen : uint32;
        ActualLen : uint32;      { Bytes actually transferred }
        Status    : TUSBTransferStatus;
        Setup     : TUSBSetupPacket; { For control transfers }
        HCPriv    : Pointer;     { HC-specific data (TD chain, etc.) }
    end;

    { ---- USB Device ---- }

    TUSBDevice = record
        Address      : uint8;       { Assigned USB address (1-127) }
        Speed        : uint8;       { USB_SPEED_* }
        MaxPacket0   : uint8;       { EP0 max packet size }
        HC           : PUSBHCDriver;
        HCPort       : uint8;       { Root hub port (or hub port) }
        ParentHub    : PUSBDevice;  { nil for root-hub-attached devices }
        ParentPort   : uint8;       { Port on parent hub }
        DevDesc      : TUSBDeviceDescriptor;
        Endpoints    : array[0..USB_MAX_ENDPOINTS-1] of TUSBEndpoint;
        NumEndpoints : uint8;
        Configured   : boolean;
        fnDisconnect : TUSBDisconnectCallback; { Called before device is freed on unplug }
    end;

    { ---- HC Driver Abstraction (Function Pointer Types) ---- }

    TUSBHCReset      = function(hc : PUSBHCDriver) : boolean;
    TUSBHCStart      = function(hc : PUSBHCDriver) : boolean;
    TUSBHCStop       = procedure(hc : PUSBHCDriver);
    TUSBHCSubmit     = function(hc : PUSBHCDriver; transfer : PUSBTransfer) : boolean;
    TUSBHCPoll       = procedure(hc : PUSBHCDriver);
    TUSBHCPortReset  = function(hc : PUSBHCDriver; port : uint8) : boolean;
    TUSBHCPortStatus = function(hc : PUSBHCDriver; port : uint8) : uint32;

    { ---- HC Driver Record ---- }

    TUSBHCDriver = record
        Name         : PChar;
        HCType       : uint8;       { USB_HC_UHCI / OHCI / EHCI / XHCI }
        NumPorts     : uint8;
        PCIDev       : TPCI_Device; { Owning PCI device }
        BaseAddr     : uint32;      { I/O base (UHCI) or MMIO base (OHCI/EHCI/xHCI) }
        PrivData     : Pointer;     { HC-specific state }
        Devices      : PLinkedListBase; { List of PUSBDevice attached }
        NextAddress  : uint8;       { Next available USB address (1-127) }
        PortChangePending : boolean; { Set by ISR when port status changes; processed in deferred context }
        HotplugArmed : boolean;     { False during boot; set true after initial scan_ports to ignore spurious RHSC }
        { Operations }
        fnReset      : TUSBHCReset;
        fnStart      : TUSBHCStart;
        fnStop       : TUSBHCStop;
        fnSubmit     : TUSBHCSubmit;
        fnPoll       : TUSBHCPoll;
        fnPortReset  : TUSBHCPortReset;
        fnPortStatus : TUSBHCPortStatus;
    end;

{ ========================= Utility Functions ========================= }

{ Allocate memory with specified alignment. Returns pointer to aligned block.
  The original pointer is stored just before the aligned address for freeing. }
function kalloc_aligned(size : uint32; alignment : uint32) : Pointer;

{ Free a block allocated with kalloc_aligned. }
procedure kfree_aligned(p : Pointer);

{ Build a USB setup packet. Returns a filled record. }
function make_setup_packet(bmRequestType, bRequest : uint8;
                           wValue, wIndex, wLength : uint16) : TUSBSetupPacket;

{ Extract endpoint number from bEndpointAddress. }
function usb_ep_number(bEndpointAddress : uint8) : uint8;

{ Returns true if endpoint direction is IN. }
function usb_ep_is_in(bEndpointAddress : uint8) : boolean;

{ Extract transfer type from bmAttributes. }
function usb_ep_transfer_type(bmAttributes : uint8) : uint8;

{ Returns the TUSBPipeType for a given bmAttributes value. }
function usb_ep_pipe_type(bmAttributes : uint8) : TUSBPipeType;

{ Returns the TUSBDirection for a given bEndpointAddress. }
function usb_ep_direction(bEndpointAddress : uint8) : TUSBDirection;

{ Initialize a TUSBHCDriver record to safe defaults. }
procedure usb_hc_init_record(hc : PUSBHCDriver);

{ Unit Tests }
procedure UnitTest;

implementation

{ ========================= Alignment Helpers ========================= }

function kalloc_aligned(size : uint32; alignment : uint32) : Pointer;
var
    raw      : uint32;
    aligned  : uint32;
    overhead : uint32;
begin
    push_trace('usbtypes.kalloc_aligned');
    if alignment < 4 then alignment := 4;
    overhead := alignment + sizeof(uint32);
    raw := uint32(kalloc(size + overhead));
    if raw = 0 then begin
        kalloc_aligned := nil;
        pop_trace;
        exit;
    end;
    aligned := (raw + sizeof(uint32) + alignment - 1) AND (NOT (alignment - 1));
    { Store original raw pointer just before the aligned address }
    PUint32(aligned - 4)^ := raw;
    kalloc_aligned := Pointer(aligned);
    pop_trace;
end;

procedure kfree_aligned(p : Pointer);
var
    raw : uint32;
begin
    push_trace('usbtypes.kfree_aligned');
    if p <> nil then begin
        raw := PUint32(uint32(p) - 4)^;
        kfree(void(raw));
    end;
    pop_trace;
end;

{ ========================= Setup Packet Builder ========================= }

function make_setup_packet(bmRequestType, bRequest : uint8;
                           wValue, wIndex, wLength : uint16) : TUSBSetupPacket;
begin
    make_setup_packet.bmRequestType := bmRequestType;
    make_setup_packet.bRequest      := bRequest;
    make_setup_packet.wValue        := wValue;
    make_setup_packet.wIndex        := wIndex;
    make_setup_packet.wLength       := wLength;
end;

{ ========================= Endpoint Helpers ========================= }

function usb_ep_number(bEndpointAddress : uint8) : uint8;
begin
    usb_ep_number := bEndpointAddress AND USB_EP_NUM_MASK;
end;

function usb_ep_is_in(bEndpointAddress : uint8) : boolean;
begin
    usb_ep_is_in := (bEndpointAddress AND USB_EP_DIR_MASK) = USB_EP_DIR_IN;
end;

function usb_ep_transfer_type(bmAttributes : uint8) : uint8;
begin
    usb_ep_transfer_type := bmAttributes AND USB_EP_ATTR_TRANSFER_MASK;
end;

function usb_ep_pipe_type(bmAttributes : uint8) : TUSBPipeType;
var
    tt : uint8;
begin
    tt := bmAttributes AND USB_EP_ATTR_TRANSFER_MASK;
    case tt of
        USB_EP_ATTR_CONTROL:     usb_ep_pipe_type := ptControl;
        USB_EP_ATTR_ISOCHRONOUS: usb_ep_pipe_type := ptIsochronous;
        USB_EP_ATTR_BULK:        usb_ep_pipe_type := ptBulk;
        USB_EP_ATTR_INTERRUPT:   usb_ep_pipe_type := ptInterrupt;
    else
        usb_ep_pipe_type := ptControl;
    end;
end;

function usb_ep_direction(bEndpointAddress : uint8) : TUSBDirection;
begin
    if (bEndpointAddress AND USB_EP_DIR_MASK) = USB_EP_DIR_IN then
        usb_ep_direction := dirIn
    else
        usb_ep_direction := dirOut;
end;

{ ========================= HC Init Helper ========================= }

procedure usb_hc_init_record(hc : PUSBHCDriver);
begin
    push_trace('usbtypes.usb_hc_init_record');
    if hc <> nil then begin
        hc^.Name        := nil;
        hc^.HCType      := 0;
        hc^.NumPorts    := 0;
        hc^.BaseAddr    := 0;
        hc^.PrivData    := nil;
        hc^.Devices     := nil;
        hc^.NextAddress := 1;
        hc^.fnReset     := nil;
        hc^.fnStart     := nil;
        hc^.fnStop      := nil;
        hc^.fnSubmit    := nil;
        hc^.fnPoll      := nil;
        hc^.fnPortReset := nil;
        hc^.fnPortStatus := nil;
    end;
    pop_trace;
end;

{ ========================= Unit Tests ========================= }

procedure UnitTest;
var
    passed, failed : uint32;
    p     : Pointer;
    setup : TUSBSetupPacket;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            syslog.logln('USBTYPES', msg);
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
        syslog.logln('USBTYPES', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed := 0;
    failed := 0;
    syslog.logln('USBTYPES', 'Unit tests starting...');

    { === Descriptor Size Constants === }
    Assert(sizeof(TUSBDeviceDescriptor) = 18, 'sizeof DeviceDescriptor=18');
    Assert(sizeof(TUSBConfigDescriptor) = 9, 'sizeof ConfigDescriptor=9');
    Assert(sizeof(TUSBInterfaceDescriptor) = 9, 'sizeof InterfaceDescriptor=9');
    Assert(sizeof(TUSBEndpointDescriptor) = 7, 'sizeof EndpointDescriptor=7');
    Assert(sizeof(TUSBSetupPacket) = 8, 'sizeof SetupPacket=8');
    Assert(sizeof(TUSBHubDescriptor) = 7, 'sizeof HubDescriptor=7');

    { === kalloc_aligned / kfree_aligned === }
    { 16-byte alignment }
    p := kalloc_aligned(32, 16);
    Assert(p <> nil, 'kalloc_aligned(32,16) not nil');
    Assert((uint32(p) AND $0F) = 0, 'kalloc_aligned(32,16) aligned to 16');
    kfree_aligned(p);

    { 256-byte alignment (HCCA) }
    p := kalloc_aligned(256, 256);
    Assert(p <> nil, 'kalloc_aligned(256,256) not nil');
    Assert((uint32(p) AND $FF) = 0, 'kalloc_aligned(256,256) aligned to 256');
    kfree_aligned(p);

    { 4096-byte alignment (frame list) }
    p := kalloc_aligned(4096, 4096);
    Assert(p <> nil, 'kalloc_aligned(4096,4096) not nil');
    Assert((uint32(p) AND $FFF) = 0, 'kalloc_aligned(4096,4096) aligned to 4096');
    kfree_aligned(p);

    { 32-byte alignment (qTD) }
    p := kalloc_aligned(32, 32);
    Assert(p <> nil, 'kalloc_aligned(32,32) not nil');
    Assert((uint32(p) AND $1F) = 0, 'kalloc_aligned(32,32) aligned to 32');
    kfree_aligned(p);

    { kfree_aligned(nil) should not crash }
    kfree_aligned(nil);
    Assert(true, 'kfree_aligned(nil) no crash');

    { === make_setup_packet === }
    setup := make_setup_packet($80, USB_REQ_GET_DESCRIPTOR, $0100, $0000, 18);
    Assert(setup.bmRequestType = $80, 'setup bmRequestType=$80');
    Assert(setup.bRequest = USB_REQ_GET_DESCRIPTOR, 'setup bRequest=GET_DESCRIPTOR');
    Assert(setup.wValue = $0100, 'setup wValue=$0100');
    Assert(setup.wIndex = $0000, 'setup wIndex=$0000');
    Assert(setup.wLength = 18, 'setup wLength=18');

    { SET_ADDRESS setup packet }
    setup := make_setup_packet($00, USB_REQ_SET_ADDRESS, 5, 0, 0);
    Assert(setup.bmRequestType = $00, 'setaddr bmRequestType=$00');
    Assert(setup.bRequest = USB_REQ_SET_ADDRESS, 'setaddr bRequest=SET_ADDRESS');
    Assert(setup.wValue = 5, 'setaddr wValue=5');
    Assert(setup.wLength = 0, 'setaddr wLength=0');

    { SET_CONFIGURATION setup packet }
    setup := make_setup_packet($00, USB_REQ_SET_CONFIGURATION, 1, 0, 0);
    Assert(setup.bRequest = USB_REQ_SET_CONFIGURATION, 'setconfig bRequest=SET_CONFIG');
    Assert(setup.wValue = 1, 'setconfig wValue=1');

    { === Endpoint Helpers === }
    { EP1 IN }
    Assert(usb_ep_number($81) = 1, 'ep_number($81)=1');
    Assert(usb_ep_is_in($81) = true, 'ep_is_in($81)=true');
    Assert(usb_ep_direction($81) = dirIn, 'ep_direction($81)=dirIn');

    { EP2 OUT }
    Assert(usb_ep_number($02) = 2, 'ep_number($02)=2');
    Assert(usb_ep_is_in($02) = false, 'ep_is_in($02)=false');
    Assert(usb_ep_direction($02) = dirOut, 'ep_direction($02)=dirOut');

    { EP0 (control, both directions) }
    Assert(usb_ep_number($00) = 0, 'ep_number($00)=0');
    Assert(usb_ep_number($80) = 0, 'ep_number($80)=0');

    { EP15 IN (max endpoint) }
    Assert(usb_ep_number($8F) = 15, 'ep_number($8F)=15');

    { Transfer type extraction }
    Assert(usb_ep_transfer_type($00) = USB_EP_ATTR_CONTROL, 'transfer_type($00)=CONTROL');
    Assert(usb_ep_transfer_type($01) = USB_EP_ATTR_ISOCHRONOUS, 'transfer_type($01)=ISO');
    Assert(usb_ep_transfer_type($02) = USB_EP_ATTR_BULK, 'transfer_type($02)=BULK');
    Assert(usb_ep_transfer_type($03) = USB_EP_ATTR_INTERRUPT, 'transfer_type($03)=INT');

    { Pipe type extraction }
    Assert(usb_ep_pipe_type($00) = ptControl, 'pipe_type($00)=ptControl');
    Assert(usb_ep_pipe_type($01) = ptIsochronous, 'pipe_type($01)=ptIsochronous');
    Assert(usb_ep_pipe_type($02) = ptBulk, 'pipe_type($02)=ptBulk');
    Assert(usb_ep_pipe_type($03) = ptInterrupt, 'pipe_type($03)=ptInterrupt');

    { Transfer type with upper bits set (sync/usage for iso) }
    Assert(usb_ep_transfer_type($0D) = USB_EP_ATTR_ISOCHRONOUS, 'transfer_type($0D)=ISO with flags');

    { === Constant sanity checks === }
    Assert(USB_DESC_DEVICE = $01, 'USB_DESC_DEVICE=$01');
    Assert(USB_DESC_CONFIGURATION = $02, 'USB_DESC_CONFIGURATION=$02');
    Assert(USB_DESC_INTERFACE = $04, 'USB_DESC_INTERFACE=$04');
    Assert(USB_DESC_ENDPOINT = $05, 'USB_DESC_ENDPOINT=$05');
    Assert(USB_CLASS_HID = $03, 'USB_CLASS_HID=$03');
    Assert(USB_CLASS_HUB = $09, 'USB_CLASS_HUB=$09');
    Assert(USB_CLASS_MASS_STORAGE = $08, 'USB_CLASS_MASS_STORAGE=$08');

    { Print summary }
    PrintSummary;
end;

end.
