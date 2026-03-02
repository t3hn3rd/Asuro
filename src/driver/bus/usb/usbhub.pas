{
    Driver->Bus->USB->USBHub - USB Hub Class Driver.

    Implements the USB Hub class driver (bDeviceClass=$09) for both
    root-hub-attached external hubs and multi-level hub topologies.
    Handles hub descriptor retrieval, port power, port status monitoring,
    port reset, downstream device enumeration, and status change polling.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit usbhub;

interface

uses
    tracer,
    syslog,
    util,
    lmemorymanager,
    drivertypes,
    drivermanagement,
    usbtypes,
    usbcore,
    strings,
    lists;

function load(ptr : void) : boolean;
procedure init;
procedure poll_hubs;
procedure UnitTest;

implementation

{ ========================= Hub Constants ========================= }

const
    { Hub Class Feature Selectors (USB 2.0 spec Table 11-17) }
    HUB_FEAT_C_HUB_LOCAL_POWER  = 0;
    HUB_FEAT_C_HUB_OVER_CURRENT = 1;

    { Port Feature Selectors }
    HUB_FEAT_PORT_CONNECTION     = 0;
    HUB_FEAT_PORT_ENABLE         = 1;
    HUB_FEAT_PORT_SUSPEND        = 2;
    HUB_FEAT_PORT_OVER_CURRENT   = 3;
    HUB_FEAT_PORT_RESET          = 4;
    HUB_FEAT_PORT_POWER          = 8;
    HUB_FEAT_PORT_LOW_SPEED      = 9;
    HUB_FEAT_C_PORT_CONNECTION   = 16;
    HUB_FEAT_C_PORT_ENABLE       = 17;
    HUB_FEAT_C_PORT_SUSPEND      = 18;
    HUB_FEAT_C_PORT_OVER_CURRENT = 19;
    HUB_FEAT_C_PORT_RESET        = 20;

    { Hub Class Request Codes }
    HUB_REQ_GET_STATUS           = $00;
    HUB_REQ_CLEAR_FEATURE        = $01;
    HUB_REQ_SET_FEATURE          = $03;
    HUB_REQ_GET_DESCRIPTOR       = $06;
    HUB_REQ_SET_DESCRIPTOR       = $07;
    HUB_REQ_CLEAR_TT_BUFFER      = $08;
    HUB_REQ_RESET_TT             = $09;
    HUB_REQ_GET_TT_STATE         = $0A;
    HUB_REQ_STOP_TT              = $0B;

    { Hub Port Status bits (wPortStatus) }
    HUB_PORT_STAT_CONNECTION     = $0001;
    HUB_PORT_STAT_ENABLE         = $0002;
    HUB_PORT_STAT_SUSPEND        = $0004;
    HUB_PORT_STAT_OVER_CURRENT   = $0008;
    HUB_PORT_STAT_RESET          = $0010;
    HUB_PORT_STAT_POWER          = $0100;
    HUB_PORT_STAT_LOW_SPEED      = $0200;
    HUB_PORT_STAT_HIGH_SPEED     = $0400;

    { Hub Port Status Change bits (wPortChange) }
    HUB_PORT_STAT_C_CONNECTION   = $0001;
    HUB_PORT_STAT_C_ENABLE       = $0002;
    HUB_PORT_STAT_C_SUSPEND      = $0004;
    HUB_PORT_STAT_C_OVER_CURRENT = $0008;
    HUB_PORT_STAT_C_RESET        = $0010;

    { Maximum hub depth (to prevent infinite recursion) }
    HUB_MAX_DEPTH                = 5;

    { Maximum ports per hub (USB spec allows 255, but 15 is practical) }
    HUB_MAX_PORTS                = 15;

{ ========================= Hub Types ========================= }

type
    { Port status result from GET_PORT_STATUS (4 bytes) }
    PUSBHubPortStatus = ^TUSBHubPortStatus;
    TUSBHubPortStatus = packed record
        wPortStatus : uint16;
        wPortChange : uint16;
    end;

    { Hub instance state }
    PUSBHubData = ^TUSBHubData;
    TUSBHubData = record
        Device      : PUSBDevice;        { The hub device itself }
        NumPorts    : uint8;             { From hub descriptor }
        PwrOn2PwrGood : uint8;           { Power-on to power-good (in 2ms units) }
        Depth       : uint8;             { Topology depth (0 = root-attached) }
        HubDesc     : TUSBHubDescriptor; { Cached hub descriptor }
        IntrEP      : TUSBEndpoint;      { Interrupt IN endpoint for status changes }
        HasIntrEP   : boolean;           { Whether we found the interrupt endpoint }
        StatusBuf   : Pointer;           { Buffer for interrupt transfer }
        StatusXfer  : PUSBTransfer;      { Active interrupt transfer (for polling) }
        PortDevices : array[0..HUB_MAX_PORTS-1] of PUSBDevice; { Downstream devices }
    end;

{ ========================= Hub List ========================= }

var
    HubList : PLinkedListBase;

{ ========================= Hub Class Requests ========================= }

{ GET_PORT_STATUS: returns 4 bytes (wPortStatus + wPortChange) }
function hub_get_port_status(dev : PUSBDevice; port : uint8; ps : PUSBHubPortStatus) : boolean;
var
    status : TUSBTransferStatus;
begin
    push_trace('usbhub.hub_get_port_status');
    hub_get_port_status := false;
    ps^.wPortStatus := 0;
    ps^.wPortChange := 0;

    status := usb_control_msg(
        dev,
        USB_REQTYPE_DIR_IN OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_OTHER,
        HUB_REQ_GET_STATUS,
        0,
        port,       { wIndex = port number (1-based) }
        ps,
        4
    );

    hub_get_port_status := (status = tsSuccess);
    pop_trace;
end;

{ SET_FEATURE on a port }
function hub_set_port_feature(dev : PUSBDevice; port : uint8; feature : uint16) : boolean;
var
    status : TUSBTransferStatus;
begin
    push_trace('usbhub.hub_set_port_feature');
    status := usb_control_msg(
        dev,
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_OTHER,
        HUB_REQ_SET_FEATURE,
        feature,
        port,       { wIndex = port number (1-based) }
        nil,
        0
    );
    hub_set_port_feature := (status = tsSuccess);
    pop_trace;
end;

{ CLEAR_FEATURE on a port }
function hub_clear_port_feature(dev : PUSBDevice; port : uint8; feature : uint16) : boolean;
var
    status : TUSBTransferStatus;
begin
    push_trace('usbhub.hub_clear_port_feature');
    status := usb_control_msg(
        dev,
        USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_OTHER,
        HUB_REQ_CLEAR_FEATURE,
        feature,
        port,       { wIndex = port number (1-based) }
        nil,
        0
    );
    hub_clear_port_feature := (status = tsSuccess);
    pop_trace;
end;

{ GET_HUB_DESCRIPTOR }
function hub_get_descriptor(dev : PUSBDevice; buf : Pointer; len : uint16) : boolean;
var
    status : TUSBTransferStatus;
begin
    push_trace('usbhub.hub_get_descriptor');
    { Hub descriptors use class-specific GET_DESCRIPTOR.
      wValue = (descriptor type << 8) | descriptor index.
      USB_DESC_HUB = $29 for USB 2.0 hubs. }
    status := usb_control_msg(
        dev,
        USB_REQTYPE_DIR_IN OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_DEVICE,
        HUB_REQ_GET_DESCRIPTOR,
        (uint16(USB_DESC_HUB) SHL 8) OR 0,
        0,
        buf,
        len
    );
    hub_get_descriptor := (status = tsSuccess);
    pop_trace;
end;

{ ========================= Port Reset ========================= }

{ Reset a downstream port via SET_FEATURE(PORT_RESET), wait for C_PORT_RESET,
  then CLEAR_FEATURE(C_PORT_RESET). Returns true if port is enabled after reset. }
function hub_port_reset(dev : PUSBDevice; port : uint8) : boolean;
var
    ps    : TUSBHubPortStatus;
    loops : uint32;
begin
    push_trace('usbhub.hub_port_reset');
    hub_port_reset := false;

    { Issue port reset }
    if not hub_set_port_feature(dev, port, HUB_FEAT_PORT_RESET) then begin
        syslog.log('USBHub', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' reset SET_FEATURE failed.');
        pop_trace;
        exit;
    end;

    { Wait for reset to complete (C_PORT_RESET bit set in wPortChange) }
    loops := 0;
    while loops < 200 do begin
        if not hub_get_port_status(dev, port, @ps) then begin
            pop_trace;
            exit;
        end;
        if (ps.wPortChange AND HUB_PORT_STAT_C_RESET) <> 0 then
            break;
        { Small delay: busy-wait loop }
        inc(loops);
    end;

    if (ps.wPortChange AND HUB_PORT_STAT_C_RESET) = 0 then begin
        syslog.log('USBHub', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' reset timeout.');
        pop_trace;
        exit;
    end;

    { Clear the C_PORT_RESET change bit }
    hub_clear_port_feature(dev, port, HUB_FEAT_C_PORT_RESET);

    { Check that the port is now enabled }
    if not hub_get_port_status(dev, port, @ps) then begin
        pop_trace;
        exit;
    end;

    if (ps.wPortStatus AND HUB_PORT_STAT_ENABLE) <> 0 then begin
        syslog.log('USBHub', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' reset and enabled.');
        hub_port_reset := true;
    end else begin
        syslog.log('USBHub', 'Port ');
        syslog.writeint(port);
        syslog.writestringln(' reset but not enabled.');
    end;

    pop_trace;
end;

{ ========================= Port Speed Detection ========================= }

function hub_port_speed(ps : TUSBHubPortStatus) : uint8;
begin
    if (ps.wPortStatus AND HUB_PORT_STAT_HIGH_SPEED) <> 0 then
        hub_port_speed := USB_SPEED_HIGH
    else if (ps.wPortStatus AND HUB_PORT_STAT_LOW_SPEED) <> 0 then
        hub_port_speed := USB_SPEED_LOW
    else
        hub_port_speed := USB_SPEED_FULL;
end;

{ ========================= Hub Initialization ========================= }

{ Configure a hub device: read hub descriptor, power on ports, enumerate downstream devices }
function hub_configure(dev : PUSBDevice; depth : uint8) : boolean;
var
    hub     : PUSBHubData;
    hubDesc : TUSBHubDescriptor;
    ps      : TUSBHubPortStatus;
    port    : uint8;
    speed   : uint8;
    loops   : uint32;
    childDev : PUSBDevice;
    epIdx   : uint8;
    hubEntry : PUSBHubData;
begin
    push_trace('usbhub.hub_configure');
    hub_configure := false;

    if dev = nil then begin
        pop_trace;
        exit;
    end;

    { Prevent infinite nesting }
    if depth > HUB_MAX_DEPTH then begin
        syslog.logln('USBHub', 'Maximum hub depth exceeded, skipping.');
        pop_trace;
        exit;
    end;

    syslog.log('USBHub', 'Configuring hub at address ');
    syslog.writeint(dev^.Address);
    syslog.writestring(' depth=');
    syslog.writeintln(depth);

    { Step 1: Get hub descriptor }
    memset(uint32(@hubDesc), 0, sizeof(TUSBHubDescriptor));
    if not hub_get_descriptor(dev, @hubDesc, sizeof(TUSBHubDescriptor)) then begin
        syslog.logln('USBHub', 'Failed to get hub descriptor.');
        pop_trace;
        exit;
    end;

    if hubDesc.bNbrPorts = 0 then begin
        syslog.logln('USBHub', 'Hub reports 0 ports.');
        pop_trace;
        exit;
    end;

    if hubDesc.bNbrPorts > HUB_MAX_PORTS then
        hubDesc.bNbrPorts := HUB_MAX_PORTS;

    syslog.log('USBHub', 'Hub has ');
    syslog.writeint(hubDesc.bNbrPorts);
    syslog.writestring(' port(s), PwrOn2PwrGood=');
    syslog.writeint(hubDesc.bPwrOn2PwrGood);
    syslog.writestringln('.');

    { Step 2: Allocate hub state }
    hub := PUSBHubData(kalloc(sizeof(TUSBHubData)));
    if hub = nil then begin
        syslog.logln('USBHub', 'Failed to allocate hub data.');
        pop_trace;
        exit;
    end;
    memset(uint32(hub), 0, sizeof(TUSBHubData));
    hub^.Device       := dev;
    hub^.NumPorts     := hubDesc.bNbrPorts;
    hub^.PwrOn2PwrGood := hubDesc.bPwrOn2PwrGood;
    hub^.Depth        := depth;
    hub^.HubDesc      := hubDesc;
    hub^.HasIntrEP    := false;
    hub^.StatusBuf    := nil;
    hub^.StatusXfer   := nil;

    { Step 3: Find interrupt IN endpoint for status change notification }
    for epIdx := 0 to dev^.NumEndpoints - 1 do begin
        if (dev^.Endpoints[epIdx].PipeType = ptInterrupt) and
           (dev^.Endpoints[epIdx].Direction = dirIn) then begin
            hub^.IntrEP := dev^.Endpoints[epIdx];
            hub^.HasIntrEP := true;
            break;
        end;
    end;

    { Step 4: Power on all ports }
    for port := 1 to hub^.NumPorts do begin
        hub_set_port_feature(dev, port, HUB_FEAT_PORT_POWER);
    end;

    { Wait for power good delay (bPwrOn2PwrGood * 2ms).
      We use a busy-wait loop as an approximation. }
    loops := 0;
    while loops < uint32(hub^.PwrOn2PwrGood) * 40000 do inc(loops);

    { Step 5: Register hub in list for polling }
    if HubList <> nil then begin
        hubEntry := PUSBHubData(LL_Add(HubList));
        if hubEntry <> nil then
            memcpy(uint32(hub), uint32(hubEntry), sizeof(TUSBHubData));
    end;

    { Step 6: Scan ports for connected devices }
    for port := 1 to hub^.NumPorts do begin
        if not hub_get_port_status(dev, port, @ps) then continue;

        if (ps.wPortStatus AND HUB_PORT_STAT_CONNECTION) <> 0 then begin
            syslog.log('USBHub', 'Device on port ');
            syslog.writeintln(port);

            { Clear C_PORT_CONNECTION if set }
            if (ps.wPortChange AND HUB_PORT_STAT_C_CONNECTION) <> 0 then
                hub_clear_port_feature(dev, port, HUB_FEAT_C_PORT_CONNECTION);

            { Reset the port }
            if not hub_port_reset(dev, port) then continue;

            { Re-read port status after reset to determine speed }
            if not hub_get_port_status(dev, port, @ps) then continue;
            speed := hub_port_speed(ps);

            { Enumerate the downstream device.
              The HC's port_reset won't be called again — we already did it via the hub.
              We pass the hub device and port for topology tracking. }
            childDev := enumerate_device(dev^.HC, port, speed, dev, port);
            if childDev <> nil then begin
                hub^.PortDevices[port - 1] := childDev;

                { If the child is also a hub, recursively configure it }
                if childDev^.DevDesc.bDeviceClass = USB_CLASS_HUB then begin
                    hub_configure(childDev, depth + 1);
                end;
            end;
        end;
    end;

    { Step 7: Start status change polling via interrupt endpoint }
    if hub^.HasIntrEP then begin
        { Allocate a small buffer: 1 byte for up to 7 ports, 2 bytes for 8-15 ports }
        if hub^.NumPorts > 7 then
            hub^.StatusBuf := Pointer(kalloc(2))
        else
            hub^.StatusBuf := Pointer(kalloc(1));

        { Submit the interrupt transfer (will be polled in poll_hubs) }
        hub^.StatusXfer := usb_interrupt_transfer(
            dev,
            @hub^.IntrEP,
            hub^.StatusBuf,
            1 + (hub^.NumPorts DIV 8)
        );
    end;

    kfree(void(hub));    { Local copy freed; the LL entry persists }
    hub_configure := true;

    syslog.log('USBHub', 'Hub at address ');
    syslog.writeint(dev^.Address);
    syslog.writestringln(' configured.');

    pop_trace;
end;

{ ========================= Hub Status Change Polling ========================= }

{ Process a status change bitmap from an interrupt IN transfer.
  Bit 0 = hub status change, bits 1..N = port 1..N status change. }
procedure hub_process_status_change(hub : PUSBHubData);
var
    bitmap : uint8;
    port   : uint8;
    ps     : TUSBHubPortStatus;
    speed  : uint8;
    childDev : PUSBDevice;
begin
    push_trace('usbhub.hub_process_status_change');
    if (hub = nil) or (hub^.StatusBuf = nil) then begin
        pop_trace;
        exit;
    end;

    bitmap := PUint8(hub^.StatusBuf)^;

    { Check each port (bits 1..N) }
    for port := 1 to hub^.NumPorts do begin
        if port > 7 then break; { Only first byte for now }

        if (bitmap AND (1 SHL port)) <> 0 then begin
            { Port has a status change — read it }
            if not hub_get_port_status(hub^.Device, port, @ps) then continue;

            { Handle connection change }
            if (ps.wPortChange AND HUB_PORT_STAT_C_CONNECTION) <> 0 then begin
                hub_clear_port_feature(hub^.Device, port, HUB_FEAT_C_PORT_CONNECTION);

                if (ps.wPortStatus AND HUB_PORT_STAT_CONNECTION) <> 0 then begin
                    { New device connected }
                    syslog.log('USBHub', 'New device on port ');
                    syslog.writeintln(port);

                    if not hub_port_reset(hub^.Device, port) then continue;

                    if not hub_get_port_status(hub^.Device, port, @ps) then continue;
                    speed := hub_port_speed(ps);

                    childDev := enumerate_device(hub^.Device^.HC, port, speed,
                                                 hub^.Device, port);
                    if childDev <> nil then begin
                        hub^.PortDevices[port - 1] := childDev;
                        if childDev^.DevDesc.bDeviceClass = USB_CLASS_HUB then
                            hub_configure(childDev, hub^.Depth + 1);
                    end;
                end else begin
                    { Device disconnected }
                    syslog.log('USBHub', 'Device removed from port ');
                    syslog.writeintln(port);
                    { TODO: Device cleanup/removal path }
                    hub^.PortDevices[port - 1] := nil;
                end;
            end;

            { Handle enable change (usually an error) }
            if (ps.wPortChange AND HUB_PORT_STAT_C_ENABLE) <> 0 then
                hub_clear_port_feature(hub^.Device, port, HUB_FEAT_C_PORT_ENABLE);

            { Handle overcurrent change }
            if (ps.wPortChange AND HUB_PORT_STAT_C_OVER_CURRENT) <> 0 then begin
                hub_clear_port_feature(hub^.Device, port, HUB_FEAT_C_PORT_OVER_CURRENT);
                syslog.log('USBHub', 'Overcurrent on port ');
                syslog.writeintln(port);
            end;

            { Handle suspend change }
            if (ps.wPortChange AND HUB_PORT_STAT_C_SUSPEND) <> 0 then
                hub_clear_port_feature(hub^.Device, port, HUB_FEAT_C_PORT_SUSPEND);
        end;
    end;

    pop_trace;
end;

{ Poll all registered hubs for status changes }
procedure poll_hubs;
var
    i    : uint32;
    hub  : PUSBHubData;
begin
    if HubList = nil then exit;

    for i := 0 to LL_Size(HubList) - 1 do begin
        hub := PUSBHubData(LL_Get(HubList, i));
        if hub = nil then continue;
        if not hub^.HasIntrEP then continue;
        if hub^.StatusXfer = nil then continue;

        { Poll the HC for this transfer }
        if (hub^.Device <> nil) and (hub^.Device^.HC <> nil) and
           (hub^.Device^.HC^.fnPoll <> nil) then
            hub^.Device^.HC^.fnPoll(hub^.Device^.HC);

        { Check if the interrupt transfer completed }
        if hub^.StatusXfer^.Status = tsSuccess then begin
            { Process the status change bitmap }
            hub_process_status_change(hub);

            { Resubmit the interrupt transfer for continuous polling }
            hub^.StatusXfer := usb_interrupt_transfer(
                hub^.Device,
                @hub^.IntrEP,
                hub^.StatusBuf,
                1 + (hub^.NumPorts DIV 8)
            );
        end else if (hub^.StatusXfer^.Status <> tsInProgress) and
                    (hub^.StatusXfer^.Status <> tsNotStarted) then begin
            { Transfer failed (NAK is normal - no status change) }
            if hub^.StatusXfer^.Status <> tsNAK then begin
                syslog.log('USBHub', 'Interrupt transfer error on hub addr ');
                syslog.writeintln(hub^.Device^.Address);
            end;

            { Resubmit }
            kfree(void(hub^.StatusXfer));
            hub^.StatusXfer := usb_interrupt_transfer(
                hub^.Device,
                @hub^.IntrEP,
                hub^.StatusBuf,
                1 + (hub^.NumPorts DIV 8)
            );
        end;
        { else: still in progress, keep waiting }
    end;
end;

{ ========================= Driver Load Callback ========================= }

{ Called by drivermanagement when a USB device with class $09 is found }
function load(ptr : void) : boolean;
var
    dev   : PUSBDevice;
    depth : uint8;
begin
    push_trace('usbhub.load');
    load := false;

    dev := PUSBDevice(ptr);
    if dev = nil then begin
        pop_trace;
        exit;
    end;

    { Determine depth from parent chain }
    depth := 0;
    if dev^.ParentHub <> nil then begin
        { Walk up the parent chain - approximate depth }
        depth := 1;
        { For now, simple depth. With topology in TUSBDevice, this is sufficient. }
    end;

    load := hub_configure(dev, depth);
    pop_trace;
end;

{ ========================= Init ========================= }

procedure init;
var
    HubID : TDeviceIdentifier;
begin
    push_trace('usbhub.init');
    syslog.logln('USBHub', 'INIT BEGIN.');

    HubList := LL_New(sizeof(TUSBHubData));

    { Register as a USB class driver matching hub devices (class $09) }
    HubID.Bus := biUSB;
    HubID.id0 := idANY;           { Any VID:PID }
    HubID.id1 := USB_CLASS_HUB;   { bDeviceClass = $09 }
    HubID.id2 := USB_CLASS_HUB;   { bInterfaceClass = $09 }
    HubID.id3 := $FFFFFFFF;       { Any subclass }
    HubID.id4 := $FFFFFFFF;       { Any protocol }
    HubID.ex  := nil;

    drivermanagement.register_driver('USB Hub Driver', @HubID, @load);

    syslog.logln('USBHub', 'INIT END.');
    pop_trace;
end;

{ ========================= Unit Tests ========================= }

procedure UnitTest;
var
    passed, failed : uint32;
    ps : TUSBHubPortStatus;

    procedure Assert(condition : boolean; testName : pchar);
    var
        msg : pchar;
    begin
        if condition then begin
            inc(passed);
        end else begin
            inc(failed);
            msg := stringConcat('FAIL: ', testName);
            syslog.logln('USBHub', msg);
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
        syslog.logln('USBHub', msg);
        kfree(void(msg));
        kfree(void(pStr));
        kfree(void(fStr));
    end;

begin
    passed := 0;
    failed := 0;
    syslog.logln('USBHub', 'Unit tests starting...');

    { === Structure Sizes === }
    Assert(sizeof(TUSBHubDescriptor) = 7, 'sizeof HubDesc=7');
    Assert(sizeof(TUSBHubPortStatus) = 4, 'sizeof HubPortStatus=4');

    { === Port Feature Constants === }
    Assert(HUB_FEAT_PORT_CONNECTION = 0, 'FEAT_PORT_CONNECTION=0');
    Assert(HUB_FEAT_PORT_ENABLE = 1, 'FEAT_PORT_ENABLE=1');
    Assert(HUB_FEAT_PORT_RESET = 4, 'FEAT_PORT_RESET=4');
    Assert(HUB_FEAT_PORT_POWER = 8, 'FEAT_PORT_POWER=8');
    Assert(HUB_FEAT_PORT_LOW_SPEED = 9, 'FEAT_PORT_LOW_SPEED=9');
    Assert(HUB_FEAT_C_PORT_CONNECTION = 16, 'FEAT_C_PORT_CONNECTION=16');
    Assert(HUB_FEAT_C_PORT_ENABLE = 17, 'FEAT_C_PORT_ENABLE=17');
    Assert(HUB_FEAT_C_PORT_RESET = 20, 'FEAT_C_PORT_RESET=20');

    { === Port Status Bit Constants === }
    Assert(HUB_PORT_STAT_CONNECTION = $0001, 'PORT_STAT_CONNECTION=$0001');
    Assert(HUB_PORT_STAT_ENABLE = $0002, 'PORT_STAT_ENABLE=$0002');
    Assert(HUB_PORT_STAT_SUSPEND = $0004, 'PORT_STAT_SUSPEND=$0004');
    Assert(HUB_PORT_STAT_OVER_CURRENT = $0008, 'PORT_STAT_OVER_CURRENT=$0008');
    Assert(HUB_PORT_STAT_RESET = $0010, 'PORT_STAT_RESET=$0010');
    Assert(HUB_PORT_STAT_POWER = $0100, 'PORT_STAT_POWER=$0100');
    Assert(HUB_PORT_STAT_LOW_SPEED = $0200, 'PORT_STAT_LOW_SPEED=$0200');
    Assert(HUB_PORT_STAT_HIGH_SPEED = $0400, 'PORT_STAT_HIGH_SPEED=$0400');

    { === Port Change Bit Constants === }
    Assert(HUB_PORT_STAT_C_CONNECTION = $0001, 'PORT_C_CONNECTION=$0001');
    Assert(HUB_PORT_STAT_C_ENABLE = $0002, 'PORT_C_ENABLE=$0002');
    Assert(HUB_PORT_STAT_C_SUSPEND = $0004, 'PORT_C_SUSPEND=$0004');
    Assert(HUB_PORT_STAT_C_OVER_CURRENT = $0008, 'PORT_C_OVER_CURRENT=$0008');
    Assert(HUB_PORT_STAT_C_RESET = $0010, 'PORT_C_RESET=$0010');

    { === Hub Request Constants === }
    Assert(HUB_REQ_GET_STATUS = $00, 'REQ_GET_STATUS=$00');
    Assert(HUB_REQ_CLEAR_FEATURE = $01, 'REQ_CLEAR_FEATURE=$01');
    Assert(HUB_REQ_SET_FEATURE = $03, 'REQ_SET_FEATURE=$03');
    Assert(HUB_REQ_GET_DESCRIPTOR = $06, 'REQ_GET_DESCRIPTOR=$06');

    { === Hub Limits === }
    Assert(HUB_MAX_DEPTH = 5, 'MAX_DEPTH=5');
    Assert(HUB_MAX_PORTS = 15, 'MAX_PORTS=15');

    { === Speed Detection from Port Status === }
    ps.wPortStatus := HUB_PORT_STAT_CONNECTION OR HUB_PORT_STAT_ENABLE OR HUB_PORT_STAT_POWER;
    ps.wPortChange := 0;
    Assert(hub_port_speed(ps) = USB_SPEED_FULL, 'speed full-speed');

    ps.wPortStatus := HUB_PORT_STAT_CONNECTION OR HUB_PORT_STAT_ENABLE OR
                      HUB_PORT_STAT_POWER OR HUB_PORT_STAT_LOW_SPEED;
    Assert(hub_port_speed(ps) = USB_SPEED_LOW, 'speed low-speed');

    ps.wPortStatus := HUB_PORT_STAT_CONNECTION OR HUB_PORT_STAT_ENABLE OR
                      HUB_PORT_STAT_POWER OR HUB_PORT_STAT_HIGH_SPEED;
    Assert(hub_port_speed(ps) = USB_SPEED_HIGH, 'speed high-speed');

    { === Hub Descriptor Type Constant === }
    Assert(USB_DESC_HUB = $29, 'USB_DESC_HUB=$29');
    Assert(USB_CLASS_HUB = $09, 'USB_CLASS_HUB=$09');

    { === Port Status Parsing === }
    { Simulate: connected, enabled, powered, full speed, with connection change }
    ps.wPortStatus := HUB_PORT_STAT_CONNECTION OR HUB_PORT_STAT_ENABLE OR HUB_PORT_STAT_POWER;
    ps.wPortChange := HUB_PORT_STAT_C_CONNECTION;
    Assert((ps.wPortStatus AND HUB_PORT_STAT_CONNECTION) <> 0, 'parse: connected');
    Assert((ps.wPortStatus AND HUB_PORT_STAT_ENABLE) <> 0, 'parse: enabled');
    Assert((ps.wPortStatus AND HUB_PORT_STAT_POWER) <> 0, 'parse: powered');
    Assert((ps.wPortStatus AND HUB_PORT_STAT_LOW_SPEED) = 0, 'parse: not low-speed');
    Assert((ps.wPortStatus AND HUB_PORT_STAT_HIGH_SPEED) = 0, 'parse: not high-speed');
    Assert((ps.wPortChange AND HUB_PORT_STAT_C_CONNECTION) <> 0, 'parse: C_CONNECTION set');
    Assert((ps.wPortChange AND HUB_PORT_STAT_C_RESET) = 0, 'parse: C_RESET not set');

    { Simulate: not connected, powered, overcurrent change }
    ps.wPortStatus := HUB_PORT_STAT_POWER OR HUB_PORT_STAT_OVER_CURRENT;
    ps.wPortChange := HUB_PORT_STAT_C_OVER_CURRENT;
    Assert((ps.wPortStatus AND HUB_PORT_STAT_CONNECTION) = 0, 'parse: disconnected');
    Assert((ps.wPortStatus AND HUB_PORT_STAT_OVER_CURRENT) <> 0, 'parse: overcurrent');
    Assert((ps.wPortChange AND HUB_PORT_STAT_C_OVER_CURRENT) <> 0, 'parse: C_OVER_CURRENT set');

    { Print summary }
    PrintSummary;
end;

end.
