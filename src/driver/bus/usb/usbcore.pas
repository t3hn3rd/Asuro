{
    Driver->Bus->USB->USBCore - USB Core Enumeration, Transfer API & HC Management.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit usbcore;

interface

uses
    usbtypes,
    util,
    lmemorymanager,
    lists,
    drivertypes,
    drivermanagement,
    tracer,
    syslog,
    strings;

{ ========================= HC Management ========================= }

{ Register a host controller with the USB core. Called by each HC driver after init.
  Returns the stable heap-allocated pointer to the HC record (not the caller's stack copy). }
function register_hc(hc : PUSBHCDriver) : PUSBHCDriver;

{ Unregister a host controller. }
procedure unregister_hc(hc : PUSBHCDriver);

{ Get the number of registered host controllers. }
function get_hc_count : uint32;

{ ========================= Port Scanning ========================= }

{ Scan all ports on a host controller for connected devices. }
procedure scan_ports(hc : PUSBHCDriver);

{ ========================= Polling ========================= }

{ Poll all registered host controllers. Called from timer/scheduler. }
procedure poll_all;

{ ========================= Transfer API ========================= }

{ Submit a control transfer. Blocking-style (polls until complete or timeout). }
function usb_control_msg(dev : PUSBDevice;
                         bmRequestType, bRequest : uint8;
                         wValue, wIndex : uint16;
                         buffer : Pointer;
                         wLength : uint16) : TUSBTransferStatus;

{ Convenience: GET_DESCRIPTOR }
function usb_get_descriptor(dev : PUSBDevice;
                            descType, descIndex : uint8;
                            buffer : Pointer;
                            wLength : uint16) : TUSBTransferStatus;

{ Convenience: SET_ADDRESS }
function usb_set_address(dev : PUSBDevice; addr : uint8) : TUSBTransferStatus;

{ Convenience: SET_CONFIGURATION }
function usb_set_configuration(dev : PUSBDevice; config : uint8) : TUSBTransferStatus;

{ Submit an interrupt transfer (non-blocking, must poll for completion). }
function usb_interrupt_transfer(dev : PUSBDevice;
                                ep : PUSBEndpoint;
                                buffer : Pointer;
                                len : uint16) : PUSBTransfer;

{ Submit a bulk transfer (non-blocking, must poll for completion). }
function usb_bulk_transfer(dev : PUSBDevice;
                           ep : PUSBEndpoint;
                           buffer : Pointer;
                           len : uint32) : PUSBTransfer;

{ ========================= Descriptor Parsing ========================= }

{ Find the first interface descriptor in a raw config descriptor buffer.
  configBuf: pointer to the full config descriptor data.
  totalLen:  wTotalLength from the config descriptor header.
  Returns nil if no interface descriptor found. }
function usb_find_interface(configBuf : Pointer; totalLen : uint16) : PUSBInterfaceDescriptor;

{ Find the Nth interface descriptor (0-based index) in a raw config descriptor buffer. }
function usb_find_interface_n(configBuf : Pointer; totalLen : uint16; index : uint8) : PUSBInterfaceDescriptor;

{ Count the number of endpoint descriptors following an interface descriptor
  until the next interface descriptor or end of buffer. 
  ifaceOffset: byte offset of the interface descriptor within configBuf. }
function usb_count_endpoints(configBuf : Pointer; totalLen : uint16; ifaceOffset : uint32) : uint8;

{ Find the Nth endpoint descriptor (0-based) following an interface descriptor.
  ifaceOffset: byte offset of the interface descriptor within configBuf. }
function usb_find_endpoint(configBuf : Pointer; totalLen : uint16; ifaceOffset : uint32; index : uint8) : PUSBEndpointDescriptor;

{ ========================= Device Enumeration ========================= }

{ Enumerate a newly connected device on the given HC and port.
  speed: USB_SPEED_LOW / USB_SPEED_FULL / etc.
  parentHub: nil for root-hub attached devices.
  parentPort: port number on parent hub (or root hub port). }
function enumerate_device(hc : PUSBHCDriver;
                          port : uint8;
                          speed : uint8;
                          parentHub : PUSBDevice;
                          parentPort : uint8) : PUSBDevice;

{ Initialize the USB core. }
procedure init;

{ Unit Tests }
procedure UnitTest;

implementation

{ ========================= Globals ========================= }

var
    HCList : PLinkedListBase;

{ ========================= HC Management ========================= }

function register_hc(hc : PUSBHCDriver) : PUSBHCDriver;
var
    entry : PUSBHCDriver;
begin
    push_trace('usbcore.register_hc');
    register_hc := nil;
    if (hc <> nil) and (HCList <> nil) then begin
        entry := PUSBHCDriver(LL_Add(HCList));
        if entry <> nil then begin
            memcpy(uint32(hc), uint32(entry), sizeof(TUSBHCDriver));
            syslog.log('USB Core', 'Registered HC: ');
            syslog.writestringln(hc^.Name);
            register_hc := entry;
        end;
    end;
    pop_trace;
end;

procedure unregister_hc(hc : PUSBHCDriver);
var
    i     : uint32;
    entry : PUSBHCDriver;
begin
    push_trace('usbcore.unregister_hc');
    if (hc <> nil) and (HCList <> nil) then begin
        for i := 0 to LL_Size(HCList) - 1 do begin
            entry := PUSBHCDriver(LL_Get(HCList, i));
            if (entry <> nil) and (entry^.BaseAddr = hc^.BaseAddr) and (entry^.HCType = hc^.HCType) then begin
                LL_Delete(HCList, i);
                syslog.log('USB Core', 'Unregistered HC: ');
                syslog.writestringln(hc^.Name);
                break;
            end;
        end;
    end;
    pop_trace;
end;

function get_hc_count : uint32;
begin
    if HCList <> nil then
        get_hc_count := LL_Size(HCList)
    else
        get_hc_count := 0;
end;

{ ========================= Port Scanning ========================= }

procedure scan_ports(hc : PUSBHCDriver);
var
    port     : uint8;
    status   : uint32;
    speed    : uint8;
begin
    push_trace('usbcore.scan_ports');
    if hc = nil then begin
        pop_trace;
        exit;
    end;
    syslog.log('USB Core', 'Scanning ports on HC: ');
    syslog.writestringln(hc^.Name);
    for port := 0 to hc^.NumPorts - 1 do begin
        if hc^.fnPortStatus <> nil then begin
            status := hc^.fnPortStatus(hc, port);
            { Bit 0 = connected (convention across all HCs) }
            if (status AND $01) <> 0 then begin
                syslog.log('USB Core', 'Device detected on port ');
                syslog.writeintln(port);
                { Determine speed from status bits - HC specific, 
                  default to full-speed for now }
                speed := USB_SPEED_FULL;
                enumerate_device(hc, port, speed, nil, port);
            end;
        end;
    end;
    pop_trace;
end;

{ ========================= Polling ========================= }

procedure poll_all;
var
    i     : uint32;
    entry : PUSBHCDriver;
begin
    push_trace('usbcore.poll_all');
    if HCList = nil then begin pop_trace; exit; end;
    if LL_Size(HCList) = 0 then begin pop_trace; exit; end;
    for i := 0 to LL_Size(HCList) - 1 do begin
        entry := PUSBHCDriver(LL_Get(HCList, i));
        if (entry <> nil) and (entry^.fnPoll <> nil) then
            entry^.fnPoll(entry);
    end;
    pop_trace;
end;

{ ========================= Transfer API ========================= }

function usb_control_msg(dev : PUSBDevice;
                         bmRequestType, bRequest : uint8;
                         wValue, wIndex : uint16;
                         buffer : Pointer;
                         wLength : uint16) : TUSBTransferStatus;
var
    transfer : TUSBTransfer;
    ep0      : TUSBEndpoint;
    polls    : uint32;
begin
    push_trace('usbcore.usb_control_msg');
    usb_control_msg := tsTimeout;

    if (dev = nil) or (dev^.HC = nil) or (dev^.HC^.fnSubmit = nil) then begin
        pop_trace;
        exit;
    end;

    { Setup EP0 }
    ep0.Address   := 0;
    ep0.Direction := dirSetup;
    ep0.PipeType  := ptControl;
    ep0.MaxPacket := dev^.MaxPacket0;
    ep0.Interval  := 0;
    ep0.Toggle    := 0;

    { Build transfer }
    transfer.Device    := dev;
    transfer.Endpoint  := @ep0;
    transfer.Direction := dirSetup;
    transfer.PipeType  := ptControl;
    transfer.Buffer    := buffer;
    transfer.BufferLen := wLength;
    transfer.ActualLen := 0;
    transfer.Status    := tsNotStarted;
    transfer.Setup     := make_setup_packet(bmRequestType, bRequest, wValue, wIndex, wLength);
    transfer.HCPriv    := nil;

    { Submit }
    if not dev^.HC^.fnSubmit(dev^.HC, @transfer) then begin
        usb_control_msg := tsTimeout;
        pop_trace;
        exit;
    end;

    { Poll until complete (with timeout) }
    polls := 0;
    while (transfer.Status = tsInProgress) or (transfer.Status = tsNotStarted) do begin
        if dev^.HC^.fnPoll <> nil then
            dev^.HC^.fnPoll(dev^.HC);
        inc(polls);
        if polls > 100000 then begin
            usb_control_msg := tsTimeout;
            pop_trace;
            exit;
        end;
    end;

    usb_control_msg := transfer.Status;
    pop_trace;
end;

function usb_get_descriptor(dev : PUSBDevice;
                            descType, descIndex : uint8;
                            buffer : Pointer;
                            wLength : uint16) : TUSBTransferStatus;
begin
    push_trace('usbcore.usb_get_descriptor');
    usb_get_descriptor := usb_control_msg(
        dev,
        USB_REQTYPE_DIR_IN OR USB_REQTYPE_TYPE_STANDARD OR USB_REQTYPE_REC_DEVICE,
        USB_REQ_GET_DESCRIPTOR,
        (uint16(descType) SHL 8) OR descIndex,
        0,
        buffer,
        wLength
    );
    pop_trace;
end;

function usb_set_address(dev : PUSBDevice; addr : uint8) : TUSBTransferStatus;
begin
    push_trace('usbcore.usb_set_address');
    usb_set_address := usb_control_msg(
        dev,
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_STANDARD OR USB_REQTYPE_REC_DEVICE,
        USB_REQ_SET_ADDRESS,
        addr,
        0,
        nil,
        0
    );
    pop_trace;
end;

function usb_set_configuration(dev : PUSBDevice; config : uint8) : TUSBTransferStatus;
begin
    push_trace('usbcore.usb_set_configuration');
    usb_set_configuration := usb_control_msg(
        dev,
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_STANDARD OR USB_REQTYPE_REC_DEVICE,
        USB_REQ_SET_CONFIGURATION,
        config,
        0,
        nil,
        0
    );
    pop_trace;
end;

function usb_interrupt_transfer(dev : PUSBDevice;
                                ep : PUSBEndpoint;
                                buffer : Pointer;
                                len : uint16) : PUSBTransfer;
var
    transfer : PUSBTransfer;
begin
    push_trace('usbcore.usb_interrupt_transfer');
    usb_interrupt_transfer := nil;

    if (dev = nil) or (ep = nil) or (dev^.HC = nil) or (dev^.HC^.fnSubmit = nil) then begin
        pop_trace;
        exit;
    end;

    transfer := PUSBTransfer(kalloc(sizeof(TUSBTransfer)));

    transfer^.Device    := dev;
    transfer^.Endpoint  := ep;
    transfer^.Direction := ep^.Direction;
    transfer^.PipeType  := ptInterrupt;
    transfer^.Buffer    := buffer;
    transfer^.BufferLen := len;
    transfer^.ActualLen := 0;
    transfer^.Status    := tsNotStarted;
    transfer^.HCPriv    := nil;

    if dev^.HC^.fnSubmit(dev^.HC, transfer) then
        usb_interrupt_transfer := transfer
    else begin
        kfree(void(transfer));
        usb_interrupt_transfer := nil;
    end;
    pop_trace;
end;

function usb_bulk_transfer(dev : PUSBDevice;
                           ep : PUSBEndpoint;
                           buffer : Pointer;
                           len : uint32) : PUSBTransfer;
var
    transfer : PUSBTransfer;
begin
    push_trace('usbcore.usb_bulk_transfer');
    usb_bulk_transfer := nil;

    if (dev = nil) or (ep = nil) or (dev^.HC = nil) or (dev^.HC^.fnSubmit = nil) then begin
        pop_trace;
        exit;
    end;

    transfer := PUSBTransfer(kalloc(sizeof(TUSBTransfer)));
    transfer^.Device    := dev;
    transfer^.Endpoint  := ep;
    transfer^.Direction := ep^.Direction;
    transfer^.PipeType  := ptBulk;
    transfer^.Buffer    := buffer;
    transfer^.BufferLen := len;
    transfer^.ActualLen := 0;
    transfer^.Status    := tsNotStarted;
    transfer^.HCPriv    := nil;

    if dev^.HC^.fnSubmit(dev^.HC, transfer) then
        usb_bulk_transfer := transfer
    else begin
        kfree(void(transfer));
        usb_bulk_transfer := nil;
    end;
    pop_trace;
end;

{ ========================= Descriptor Parsing ========================= }

function usb_find_interface(configBuf : Pointer; totalLen : uint16) : PUSBInterfaceDescriptor;
begin
    usb_find_interface := usb_find_interface_n(configBuf, totalLen, 0);
end;

function usb_find_interface_n(configBuf : Pointer; totalLen : uint16; index : uint8) : PUSBInterfaceDescriptor;
var
    offset : uint32;
    bLen   : uint8;
    bType  : uint8;
    count  : uint8;
begin
    usb_find_interface_n := nil;
    if configBuf = nil then exit;
    offset := sizeof(TUSBConfigDescriptor);
    count := 0;
    while offset < totalLen do begin
        bLen := PUint8(uint32(configBuf) + offset)^;
        if bLen = 0 then exit; { corrupt }
        bType := PUint8(uint32(configBuf) + offset + 1)^;
        if bType = USB_DESC_INTERFACE then begin
            if count = index then begin
                usb_find_interface_n := PUSBInterfaceDescriptor(uint32(configBuf) + offset);
                exit;
            end;
            inc(count);
        end;
        offset := offset + bLen;
    end;
end;

function usb_count_endpoints(configBuf : Pointer; totalLen : uint16; ifaceOffset : uint32) : uint8;
var
    offset : uint32;
    bLen   : uint8;
    bType  : uint8;
    count  : uint8;
begin
    usb_count_endpoints := 0;
    if configBuf = nil then exit;
    { Skip past the interface descriptor itself }
    bLen := PUint8(uint32(configBuf) + ifaceOffset)^;
    if bLen = 0 then exit;
    offset := ifaceOffset + bLen;
    count := 0;
    while offset < totalLen do begin
        bLen := PUint8(uint32(configBuf) + offset)^;
        if bLen = 0 then break;
        bType := PUint8(uint32(configBuf) + offset + 1)^;
        { Stop at next interface descriptor }
        if bType = USB_DESC_INTERFACE then break;
        if bType = USB_DESC_ENDPOINT then
            inc(count);
        offset := offset + bLen;
    end;
    usb_count_endpoints := count;
end;

function usb_find_endpoint(configBuf : Pointer; totalLen : uint16; ifaceOffset : uint32; index : uint8) : PUSBEndpointDescriptor;
var
    offset : uint32;
    bLen   : uint8;
    bType  : uint8;
    count  : uint8;
begin
    usb_find_endpoint := nil;
    if configBuf = nil then exit;
    { Skip past the interface descriptor itself }
    bLen := PUint8(uint32(configBuf) + ifaceOffset)^;
    if bLen = 0 then exit;
    offset := ifaceOffset + bLen;
    count := 0;
    while offset < totalLen do begin
        bLen := PUint8(uint32(configBuf) + offset)^;
        if bLen = 0 then break;
        bType := PUint8(uint32(configBuf) + offset + 1)^;
        if bType = USB_DESC_INTERFACE then break;
        if bType = USB_DESC_ENDPOINT then begin
            if count = index then begin
                usb_find_endpoint := PUSBEndpointDescriptor(uint32(configBuf) + offset);
                exit;
            end;
            inc(count);
        end;
        offset := offset + bLen;
    end;
end;

{ ========================= Device Enumeration ========================= }

function enumerate_device(hc : PUSBHCDriver;
                          port : uint8;
                          speed : uint8;
                          parentHub : PUSBDevice;
                          parentPort : uint8) : PUSBDevice;
var
    dev      : PUSBDevice;
    status   : TUSBTransferStatus;
    devDesc  : TUSBDeviceDescriptor;
    cfgDesc  : TUSBConfigDescriptor;
    cfgBuf   : Pointer;
    ifDesc   : PUSBInterfaceDescriptor;
    epDesc   : PUSBEndpointDescriptor;
    offset   : uint32;
    totalLen : uint16;
    addr     : uint8;
    i        : uint32;
    DevID    : PDeviceIdentifier;
begin
    push_trace('usbcore.enumerate_device');
    enumerate_device := nil;

    if hc = nil then begin
        pop_trace;
        exit;
    end;

    { Step 1: Port reset (skip for hub-attached devices — hub already did the reset) }
    if parentHub = nil then begin
        if hc^.fnPortReset <> nil then begin
            if not hc^.fnPortReset(hc, port) then begin
                syslog.logln('USB Core', 'Port reset failed.');
                pop_trace;
                exit;
            end;
        end;
    end;

    { Step 2: Create device at address 0 }
    dev := PUSBDevice(kalloc(sizeof(TUSBDevice)));
    dev^.Address     := 0;
    dev^.Speed       := speed;
    dev^.MaxPacket0  := 8;  { Default, will be updated from descriptor }
    dev^.HC          := hc;
    dev^.HCPort      := port;
    dev^.ParentHub   := parentHub;
    dev^.ParentPort  := parentPort;
    dev^.NumEndpoints := 0;
    dev^.Configured  := false;

    { Step 3: Get first 8 bytes of device descriptor to learn MaxPacketSize0 }
    status := usb_get_descriptor(dev, USB_DESC_DEVICE, 0, @devDesc, 8);
    if status <> tsSuccess then begin
        syslog.logln('USB Core', 'Failed to get device descriptor (8 bytes).');
        kfree(void(dev));
        pop_trace;
        exit;
    end;
    dev^.MaxPacket0 := devDesc.bMaxPacketSize0;

    { Step 4: Assign address }
    addr := hc^.NextAddress;
    if addr > USB_MAX_DEVICES then begin
        syslog.logln('USB Core', 'No available USB addresses.');
        kfree(void(dev));
        pop_trace;
        exit;
    end;

    status := usb_set_address(dev, addr);
    if status <> tsSuccess then begin
        syslog.logln('USB Core', 'SET_ADDRESS failed.');
        kfree(void(dev));
        pop_trace;
        exit;
    end;
    dev^.Address := addr;
    hc^.NextAddress := hc^.NextAddress + 1;

    { Small delay after SET_ADDRESS (spec says 2ms recovery) }
    { TODO: proper delay mechanism }

    { Step 5: Get full device descriptor }
    status := usb_get_descriptor(dev, USB_DESC_DEVICE, 0, @devDesc, sizeof(TUSBDeviceDescriptor));
    if status <> tsSuccess then begin
        syslog.logln('USB Core', 'Failed to get full device descriptor.');
        kfree(void(dev));
        pop_trace;
        exit;
    end;
    dev^.DevDesc := devDesc;

    syslog.log('USB Core', 'Device: VID=');
    syslog.writehex(devDesc.idVendor);
    syslog.writestring(' PID=');
    syslog.writehex(devDesc.idProduct);
    syslog.writestring(' Class=');
    syslog.writehex(devDesc.bDeviceClass);
    syslog.writestring(' Addr=');
    syslog.writeintln(addr);

    { Step 6: Get configuration descriptor (header first, then full) }
    status := usb_get_descriptor(dev, USB_DESC_CONFIGURATION, 0, @cfgDesc, sizeof(TUSBConfigDescriptor));
    if status <> tsSuccess then begin
        syslog.logln('USB Core', 'Failed to get config descriptor.');
        kfree(void(dev));
        pop_trace;
        exit;
    end;

    totalLen := cfgDesc.wTotalLength;
    cfgBuf := Pointer(kalloc(totalLen));

    status := usb_get_descriptor(dev, USB_DESC_CONFIGURATION, 0, cfgBuf, totalLen);
    if status <> tsSuccess then begin
        syslog.logln('USB Core', 'Failed to get full config descriptor.');
        kfree(void(cfgBuf));
        kfree(void(dev));
        pop_trace;
        exit;
    end;

    { Step 7: Parse interface and endpoint descriptors }
    offset := sizeof(TUSBConfigDescriptor);
    dev^.NumEndpoints := 0;
    while offset < totalLen do begin
        { Read descriptor length and type }
        if PUint8(uint32(cfgBuf) + offset)^ = 0 then break; { Safety: zero-length = corrupt }

        if PUint8(uint32(cfgBuf) + offset + 1)^ = USB_DESC_ENDPOINT then begin
            if dev^.NumEndpoints < USB_MAX_ENDPOINTS then begin
                epDesc := PUSBEndpointDescriptor(uint32(cfgBuf) + offset);
                dev^.Endpoints[dev^.NumEndpoints].Address   := usb_ep_number(epDesc^.bEndpointAddress);
                dev^.Endpoints[dev^.NumEndpoints].Direction  := usb_ep_direction(epDesc^.bEndpointAddress);
                dev^.Endpoints[dev^.NumEndpoints].PipeType   := usb_ep_pipe_type(epDesc^.bmAttributes);
                dev^.Endpoints[dev^.NumEndpoints].MaxPacket  := epDesc^.wMaxPacketSize;
                dev^.Endpoints[dev^.NumEndpoints].Interval   := epDesc^.bInterval;
                dev^.Endpoints[dev^.NumEndpoints].Toggle     := 0;
                dev^.NumEndpoints := dev^.NumEndpoints + 1;
            end;
        end;

        { Advance by bLength }
        offset := offset + PUint8(uint32(cfgBuf) + offset)^;
    end;

    { Step 8: SET_CONFIGURATION }
    status := usb_set_configuration(dev, cfgDesc.bConfigurationValue);
    if status <> tsSuccess then begin
        syslog.logln('USB Core', 'SET_CONFIGURATION failed.');
        kfree(void(cfgBuf));
        kfree(void(dev));
        pop_trace;
        exit;
    end;
    dev^.Configured := true;

    { Step 9: Register with drivermanagement using biUSB }
    { Find the first interface descriptor for class/subclass/protocol }
    offset := sizeof(TUSBConfigDescriptor);
    ifDesc := nil;
    while offset < totalLen do begin
        if PUint8(uint32(cfgBuf) + offset)^ = 0 then break;
        if PUint8(uint32(cfgBuf) + offset + 1)^ = USB_DESC_INTERFACE then begin
            ifDesc := PUSBInterfaceDescriptor(uint32(cfgBuf) + offset);
            break;
        end;
        offset := offset + PUint8(uint32(cfgBuf) + offset)^;
    end;

    DevID := PDeviceIdentifier(kalloc(sizeof(TDeviceIdentifier)));
    DevID^.Bus := biUSB;
    DevID^.id0 := (uint32(devDesc.idVendor) SHL 16) OR devDesc.idProduct;
    DevID^.id1 := devDesc.bDeviceClass;
    if ifDesc <> nil then begin
        DevID^.id2 := ifDesc^.bInterfaceClass;
        DevID^.id3 := ifDesc^.bInterfaceSubClass;
        DevID^.id4 := ifDesc^.bInterfaceProtocol;
    end else begin
        DevID^.id2 := 0;
        DevID^.id3 := 0;
        DevID^.id4 := 0;
    end;
    DevID^.ex := nil;

    drivermanagement.register_device('USB Device', DevID, void(dev));
    kfree(void(DevID));

    kfree(void(cfgBuf));

    syslog.log('USB Core', 'Device enumerated at address ');
    syslog.writeintln(addr);

    enumerate_device := dev;
    pop_trace;
end;

{ ========================= Init ========================= }

procedure init;
begin
    push_trace('usbcore.init');
    syslog.logln('USB Core', 'INIT BEGIN.');
    HCList := LL_New(sizeof(TUSBHCDriver));
    syslog.logln('USB Core', 'INIT END.');
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
            syslog.logln('USBCORE', msg);
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
        syslog.logln('USBCORE', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

var
    setup  : TUSBSetupPacket;
    cfgBuf : Pointer;
    ifDesc : PUSBInterfaceDescriptor;
    epDesc : PUSBEndpointDescriptor;
begin
    passed := 0;
    failed := 0;
    syslog.logln('USBCORE', 'Unit tests starting...');

    { === HC list management === }
    Assert(get_hc_count >= 0, 'hc_count non-negative');

    { === Control message setup packet building (via make_setup_packet) === }
    { GET_DESCRIPTOR for device descriptor }
    setup := make_setup_packet(
        USB_REQTYPE_DIR_IN OR USB_REQTYPE_TYPE_STANDARD OR USB_REQTYPE_REC_DEVICE,
        USB_REQ_GET_DESCRIPTOR,
        (uint16(USB_DESC_DEVICE) SHL 8) OR 0,
        0,
        18
    );
    Assert(setup.bmRequestType = $80, 'get_desc bmRequestType=$80');
    Assert(setup.bRequest = $06, 'get_desc bRequest=$06');
    Assert(setup.wValue = $0100, 'get_desc wValue=$0100');
    Assert(setup.wIndex = 0, 'get_desc wIndex=0');
    Assert(setup.wLength = 18, 'get_desc wLength=18');

    { GET_DESCRIPTOR for configuration descriptor }
    setup := make_setup_packet(
        USB_REQTYPE_DIR_IN OR USB_REQTYPE_TYPE_STANDARD OR USB_REQTYPE_REC_DEVICE,
        USB_REQ_GET_DESCRIPTOR,
        (uint16(USB_DESC_CONFIGURATION) SHL 8) OR 0,
        0,
        9
    );
    Assert(setup.wValue = $0200, 'get_config_desc wValue=$0200');

    { SET_ADDRESS }
    setup := make_setup_packet(
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_STANDARD OR USB_REQTYPE_REC_DEVICE,
        USB_REQ_SET_ADDRESS,
        5,
        0,
        0
    );
    Assert(setup.bmRequestType = $00, 'set_addr bmRequestType=$00');
    Assert(setup.bRequest = $05, 'set_addr bRequest=$05');
    Assert(setup.wValue = 5, 'set_addr wValue=5');

    { SET_CONFIGURATION }
    setup := make_setup_packet(
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_STANDARD OR USB_REQTYPE_REC_DEVICE,
        USB_REQ_SET_CONFIGURATION,
        1,
        0,
        0
    );
    Assert(setup.bmRequestType = $00, 'set_config bmRequestType=$00');
    Assert(setup.bRequest = $09, 'set_config bRequest=$09');
    Assert(setup.wValue = 1, 'set_config wValue=1');

    { HID SET_PROTOCOL (class request to interface) }
    setup := make_setup_packet(
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_INTERFACE,
        $0B, { SET_PROTOCOL }
        0,   { Boot protocol }
        0,   { Interface 0 }
        0
    );
    Assert(setup.bmRequestType = $21, 'set_protocol bmRequestType=$21');
    Assert(setup.bRequest = $0B, 'set_protocol bRequest=$0B');
    Assert(setup.wValue = 0, 'set_protocol wValue=0 (boot)');

    { CLEAR_FEATURE ENDPOINT_HALT }
    setup := make_setup_packet(
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_STANDARD OR USB_REQTYPE_REC_ENDPOINT,
        USB_REQ_CLEAR_FEATURE,
        USB_FEATURE_ENDPOINT_HALT,
        $81, { EP1 IN }
        0
    );
    Assert(setup.bmRequestType = $02, 'clear_halt bmRequestType=$02');
    Assert(setup.bRequest = $01, 'clear_halt bRequest=$01');
    Assert(setup.wValue = 0, 'clear_halt wValue=0 (ENDPOINT_HALT)');
    Assert(setup.wIndex = $81, 'clear_halt wIndex=$81 (EP1 IN)');

    { === Descriptor Parsing Helpers === }
    { Build a synthetic config descriptor buffer:
      Config(9) + Interface(9, class=$03, 2 EPs) + Endpoint(7, EP1 IN INT) + Endpoint(7, EP2 OUT BULK)
      + Interface(9, class=$08, 1 EP) + Endpoint(7, EP3 IN BULK) = 48 bytes total }
    cfgBuf := Pointer(kalloc(48));
    memset(uint32(cfgBuf), 0, 48);

    { Config descriptor header at offset 0 }
    PUint8(uint32(cfgBuf) + 0)^ := 9;  { bLength }
    PUint8(uint32(cfgBuf) + 1)^ := USB_DESC_CONFIGURATION; { bDescriptorType }
    PUint8(uint32(cfgBuf) + 2)^ := 48; { wTotalLength low }
    PUint8(uint32(cfgBuf) + 3)^ := 0;  { wTotalLength high }
    PUint8(uint32(cfgBuf) + 4)^ := 2;  { bNumInterfaces }
    PUint8(uint32(cfgBuf) + 5)^ := 1;  { bConfigurationValue }

    { Interface 0 at offset 9: class=$03 (HID), 2 endpoints }
    PUint8(uint32(cfgBuf) + 9)^  := 9;  { bLength }
    PUint8(uint32(cfgBuf) + 10)^ := USB_DESC_INTERFACE;
    PUint8(uint32(cfgBuf) + 11)^ := 0;  { bInterfaceNumber }
    PUint8(uint32(cfgBuf) + 13)^ := 2;  { bNumEndpoints }
    PUint8(uint32(cfgBuf) + 14)^ := USB_CLASS_HID; { bInterfaceClass }
    PUint8(uint32(cfgBuf) + 15)^ := $01; { bInterfaceSubClass (boot) }
    PUint8(uint32(cfgBuf) + 16)^ := $01; { bInterfaceProtocol (keyboard) }

    { Endpoint at offset 18: EP1 IN Interrupt, maxpacket=8, interval=10 }
    PUint8(uint32(cfgBuf) + 18)^ := 7;  { bLength }
    PUint8(uint32(cfgBuf) + 19)^ := USB_DESC_ENDPOINT;
    PUint8(uint32(cfgBuf) + 20)^ := $81; { bEndpointAddress: EP1 IN }
    PUint8(uint32(cfgBuf) + 21)^ := USB_EP_ATTR_INTERRUPT; { bmAttributes }
    PUint8(uint32(cfgBuf) + 22)^ := 8;  { wMaxPacketSize low }
    PUint8(uint32(cfgBuf) + 23)^ := 0;  { wMaxPacketSize high }
    PUint8(uint32(cfgBuf) + 24)^ := 10; { bInterval }

    { Endpoint at offset 25: EP2 OUT Bulk, maxpacket=64 }
    PUint8(uint32(cfgBuf) + 25)^ := 7;  { bLength }
    PUint8(uint32(cfgBuf) + 26)^ := USB_DESC_ENDPOINT;
    PUint8(uint32(cfgBuf) + 27)^ := $02; { bEndpointAddress: EP2 OUT }
    PUint8(uint32(cfgBuf) + 28)^ := USB_EP_ATTR_BULK; { bmAttributes }
    PUint8(uint32(cfgBuf) + 29)^ := 64; { wMaxPacketSize low }
    PUint8(uint32(cfgBuf) + 30)^ := 0;  { wMaxPacketSize high }
    PUint8(uint32(cfgBuf) + 31)^ := 0;  { bInterval }

    { Interface 1 at offset 32: class=$08 (mass storage), 1 endpoint }
    PUint8(uint32(cfgBuf) + 32)^ := 9;  { bLength }
    PUint8(uint32(cfgBuf) + 33)^ := USB_DESC_INTERFACE;
    PUint8(uint32(cfgBuf) + 34)^ := 1;  { bInterfaceNumber }
    PUint8(uint32(cfgBuf) + 36)^ := 1;  { bNumEndpoints }
    PUint8(uint32(cfgBuf) + 37)^ := USB_CLASS_MASS_STORAGE; { bInterfaceClass }

    { Endpoint at offset 41: EP3 IN Bulk, maxpacket=512 }
    PUint8(uint32(cfgBuf) + 41)^ := 7;  { bLength }
    PUint8(uint32(cfgBuf) + 42)^ := USB_DESC_ENDPOINT;
    PUint8(uint32(cfgBuf) + 43)^ := $83; { bEndpointAddress: EP3 IN }
    PUint8(uint32(cfgBuf) + 44)^ := USB_EP_ATTR_BULK; { bmAttributes }
    PUint8(uint32(cfgBuf) + 45)^ := 0;  { wMaxPacketSize low = 512 = $0200 }
    PUint8(uint32(cfgBuf) + 46)^ := 2;  { wMaxPacketSize high }
    PUint8(uint32(cfgBuf) + 47)^ := 0;  { bInterval }

    { --- usb_find_interface (first interface) --- }
    ifDesc := usb_find_interface(cfgBuf, 48);
    Assert(ifDesc <> nil, 'find_iface not nil');
    Assert(ifDesc^.bInterfaceNumber = 0, 'find_iface num=0');
    Assert(ifDesc^.bInterfaceClass = USB_CLASS_HID, 'find_iface class=HID');
    Assert(ifDesc^.bNumEndpoints = 2, 'find_iface numEPs=2');

    { --- usb_find_interface_n (second interface) --- }
    ifDesc := usb_find_interface_n(cfgBuf, 48, 1);
    Assert(ifDesc <> nil, 'find_iface_n(1) not nil');
    Assert(ifDesc^.bInterfaceNumber = 1, 'find_iface_n(1) num=1');
    Assert(ifDesc^.bInterfaceClass = USB_CLASS_MASS_STORAGE, 'find_iface_n(1) class=MSC');

    { --- usb_find_interface_n out of range --- }
    ifDesc := usb_find_interface_n(cfgBuf, 48, 2);
    Assert(ifDesc = nil, 'find_iface_n(2) nil (OOB)');

    { --- usb_count_endpoints for interface 0 at offset 9 --- }
    Assert(usb_count_endpoints(cfgBuf, 48, 9) = 2, 'count_eps iface0=2');

    { --- usb_count_endpoints for interface 1 at offset 32 --- }
    Assert(usb_count_endpoints(cfgBuf, 48, 32) = 1, 'count_eps iface1=1');

    { --- usb_find_endpoint: iface 0, EP index 0 (EP1 IN INT) --- }
    epDesc := usb_find_endpoint(cfgBuf, 48, 9, 0);
    Assert(epDesc <> nil, 'find_ep(0,0) not nil');
    Assert(epDesc^.bEndpointAddress = $81, 'find_ep(0,0) addr=$81');
    Assert(epDesc^.bmAttributes = USB_EP_ATTR_INTERRUPT, 'find_ep(0,0) attr=INT');
    Assert(epDesc^.wMaxPacketSize = 8, 'find_ep(0,0) maxpkt=8');
    Assert(epDesc^.bInterval = 10, 'find_ep(0,0) interval=10');

    { --- usb_find_endpoint: iface 0, EP index 1 (EP2 OUT BULK) --- }
    epDesc := usb_find_endpoint(cfgBuf, 48, 9, 1);
    Assert(epDesc <> nil, 'find_ep(0,1) not nil');
    Assert(epDesc^.bEndpointAddress = $02, 'find_ep(0,1) addr=$02');
    Assert(epDesc^.bmAttributes = USB_EP_ATTR_BULK, 'find_ep(0,1) attr=BULK');
    Assert(epDesc^.wMaxPacketSize = 64, 'find_ep(0,1) maxpkt=64');

    { --- usb_find_endpoint: iface 0, EP index 2 (out of range) --- }
    epDesc := usb_find_endpoint(cfgBuf, 48, 9, 2);
    Assert(epDesc = nil, 'find_ep(0,2) nil (OOB)');

    { --- usb_find_endpoint: iface 1, EP index 0 (EP3 IN BULK) --- }
    epDesc := usb_find_endpoint(cfgBuf, 48, 32, 0);
    Assert(epDesc <> nil, 'find_ep(1,0) not nil');
    Assert(epDesc^.bEndpointAddress = $83, 'find_ep(1,0) addr=$83');
    Assert(epDesc^.bmAttributes = USB_EP_ATTR_BULK, 'find_ep(1,0) attr=BULK');
    Assert(epDesc^.wMaxPacketSize = 512, 'find_ep(1,0) maxpkt=512');

    { --- nil buffer safety --- }
    Assert(usb_find_interface(nil, 48) = nil, 'find_iface nil buf');
    Assert(usb_count_endpoints(nil, 48, 9) = 0, 'count_eps nil buf');
    Assert(usb_find_endpoint(nil, 48, 9, 0) = nil, 'find_ep nil buf');

    kfree(void(cfgBuf));

    { Print summary }
    PrintSummary;
end;

end.
