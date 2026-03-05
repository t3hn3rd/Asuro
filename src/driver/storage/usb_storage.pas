{
    Driver->Storage->USB_Storage - USB Mass Storage Bulk-Only Transport (BOT) driver.

    Registers with drivermanagement as a USB class driver for mass storage devices
    (class $08, subclass $06 SCSI, protocol $50 BOT).

    Implements CBW/CSW over bulk endpoints, translates SCSI READ(10)/WRITE(10)
    to async storagemanager callbacks.

    The I/O path is interrupt-driven: each BOT phase (CBW, Data, CSW) is submitted
    as a non-blocking bulk transfer whose OnComplete callback advances the state
    machine. The storagemanager completion is fired from ISR context when the CSW
    is validated (or on error).

    Init-time probing (INQUIRY, TEST UNIT READY, READ CAPACITY) uses the async BOT
    path driven by HC polling.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit usb_storage;

interface

uses
    bios_data_area,
    drivermanagement,
    drivertypes,
    lists,
    lmemorymanager,
    storagemanager,
    storagetypes,
    strings,
    syslog,
    tracer,
    usbcore,
    usbtypes,
    util;

procedure init;

implementation

{ ==================== Constants ==================== }

const
    MSC_SUBCLASS_SCSI    = $06;
    MSC_PROTOCOL_BOT     = $50;

    BOT_RESET            = $FF;
    BOT_GET_MAX_LUN      = $FE;

    CBW_SIG              = $43425355;  { 'USBC' little-endian }
    CBW_SIZE             = 31;
    CBW_DIR_OUT          = $00;
    CBW_DIR_IN           = $80;

    CSW_SIG              = $53425355;  { 'USBS' little-endian }
    CSW_SIZE             = 13;
    CSW_OK               = $00;
    CSW_FAIL             = $01;
    CSW_PHASE_ERR        = $02;

    SCSI_OP_TEST_UNIT_READY = $00;
    SCSI_OP_REQUEST_SENSE   = $03;
    SCSI_OP_INQUIRY         = $12;
    SCSI_OP_READ_CAPACITY10 = $25;
    SCSI_OP_READ10          = $28;
    SCSI_OP_WRITE10         = $2A;

    BOT_TIMEOUT_MS       = 5000;

{ ==================== Types ==================== }

type
    PCBW = ^TCBW;
    TCBW = packed record
        Sig     : uint32;
        Tag     : uint32;
        DataLen : uint32;
        Flags   : uint8;
        LUN     : uint8;
        CBLen   : uint8;
        CB      : array[0..15] of uint8;
    end;

    PCSW = ^TCSW;
    TCSW = packed record
        Sig     : uint32;
        Tag     : uint32;
        Residue : uint32;
        Status  : uint8;
    end;

    TBOTPhase = (phIdle, phCBW, phData, phCSW);

    PUSBMSDev = ^TUSBMSDev;
    TUSBMSDev = record
        Dev         : PUSBDevice;
        BulkIn      : TUSBEndpoint;
        BulkOut     : TUSBEndpoint;
        HasIn       : boolean;
        HasOut      : boolean;
        Tag         : uint32;
        SectorSize  : uint32;
        SectorCount : uint32;
        Active      : boolean;

        Phase       : TBOTPhase;
        ActiveXfer  : PUSBTransfer;
        CBW         : TCBW;
        CSW         : TCSW;
        DataBuf     : Pointer;
        DataLen     : uint32;
        Dir         : uint8;
        OnDone      : TStorageCompletion;
        OnDoneUD    : puint32;

        StoreDev    : TStorage_Device;
    end;

{ ==================== Globals ==================== }

var
    Devices : PLinkedListBase;

{ ==================== Forward Declarations ==================== }

procedure bot_phase_done(xfer : PUSBTransfer); forward;
procedure bot_data(sd : PUSBMSDev); forward;
procedure bot_csw(sd : PUSBMSDev); forward;
procedure bot_finish(sd : PUSBMSDev); forward;
procedure bot_fail(sd : PUSBMSDev; msg : pchar); forward;

{ ==================== BOT State Machine ==================== }

function find_dev(xfer : PUSBTransfer) : PUSBMSDev;
var
    i  : uint32;
    sd : PUSBMSDev;
begin
    find_dev := nil;
    if Devices = nil then exit;
    for i := 0 to LL_Size(Devices) - 1 do begin
        sd := PUSBMSDev(LL_Get(Devices, i));
        if (sd <> nil) and (sd^.Dev = xfer^.Device) and (sd^.Phase <> phIdle) then begin
            find_dev := sd;
            exit;
        end;
    end;
end;

function bot_start(sd      : PUSBMSDev;
                   dir     : uint8;
                   cblen   : uint8;
                   cb      : Pointer;
                   databuf : Pointer;
                   datalen : uint32;
                   ondone  : TStorageCompletion;
                   ud      : puint32) : boolean;
var
    i    : uint8;
    xfer : PUSBTransfer;
begin
    bot_start := false;
    if sd^.Phase <> phIdle then begin
        syslog.logln('USBStorage', 'bot_start: device busy');
        exit;
    end;

    sd^.OnDone   := ondone;
    sd^.OnDoneUD := ud;
    sd^.DataBuf  := databuf;
    sd^.DataLen  := datalen;
    sd^.Dir      := dir;

    memset(uint32(@sd^.CBW), 0, CBW_SIZE);
    sd^.CBW.Sig     := CBW_SIG;
    inc(sd^.Tag);
    sd^.CBW.Tag     := sd^.Tag;
    sd^.CBW.DataLen := datalen;
    sd^.CBW.Flags   := dir;
    sd^.CBW.LUN     := 0;
    sd^.CBW.CBLen   := cblen;
    for i := 0 to 15 do sd^.CBW.CB[i] := 0;
    if (cb <> nil) and (cblen > 0) then
        for i := 0 to cblen - 1 do
            sd^.CBW.CB[i] := puint8(uint32(cb) + i)^;

    sd^.Phase := phCBW;

    xfer := usbcore.usb_bulk_transfer_callback(
        sd^.Dev, @sd^.BulkOut, @sd^.CBW, CBW_SIZE, @bot_phase_done);
    if xfer = nil then begin
        sd^.Phase := phIdle;
        syslog.logln('USBStorage', 'bot_start: CBW submit failed');
        exit;
    end;
    sd^.ActiveXfer := xfer;
    bot_start := true;
end;

procedure bot_phase_done(xfer : PUSBTransfer);
var
    sd     : PUSBMSDev;
    status : TUSBTransferStatus;
begin
    sd := find_dev(xfer);

    status := xfer^.Status;
    kfree(void(xfer));
    if sd <> nil then sd^.ActiveXfer := nil;

    if sd = nil then exit;

    if status <> tsSuccess then begin
        if status = tsStall then begin
            if sd^.Dir = CBW_DIR_IN then
                usbcore.usb_clear_halt(sd^.Dev, @sd^.BulkIn)
            else
                usbcore.usb_clear_halt(sd^.Dev, @sd^.BulkOut);
            if sd^.Phase = phData then begin
                bot_csw(sd);
                exit;
            end;
        end;
        bot_fail(sd, 'Transfer error');
        exit;
    end;

    case sd^.Phase of
        phCBW:  if (sd^.DataBuf <> nil) and (sd^.DataLen > 0) then
                    bot_data(sd)
                else
                    bot_csw(sd);
        phData: bot_csw(sd);
        phCSW:  bot_finish(sd);
    else
        bot_fail(sd, 'Unexpected phase');
    end;
end;

procedure bot_data(sd : PUSBMSDev);
var
    ep   : PUSBEndpoint;
    xfer : PUSBTransfer;
begin
    if sd^.Dir = CBW_DIR_IN then ep := @sd^.BulkIn
    else                         ep := @sd^.BulkOut;

    sd^.Phase := phData;
    xfer := usbcore.usb_bulk_transfer_callback(
        sd^.Dev, ep, sd^.DataBuf, sd^.DataLen, @bot_phase_done);
    if xfer = nil then begin
        bot_fail(sd, 'Data phase submit failed');
        exit;
    end;
    sd^.ActiveXfer := xfer;
end;

procedure bot_csw(sd : PUSBMSDev);
var
    xfer : PUSBTransfer;
begin
    memset(uint32(@sd^.CSW), 0, CSW_SIZE);
    sd^.Phase := phCSW;
    xfer := usbcore.usb_bulk_transfer_callback(
        sd^.Dev, @sd^.BulkIn, @sd^.CSW, CSW_SIZE, @bot_phase_done);
    if xfer = nil then begin
        bot_fail(sd, 'CSW submit failed');
        exit;
    end;
    sd^.ActiveXfer := xfer;
end;

procedure bot_finish(sd : PUSBMSDev);
var
    ok : boolean;
begin
    ok := false;
    if sd^.CSW.Sig <> CSW_SIG then
        syslog.logln('USBStorage', 'CSW: bad signature')
    else if sd^.CSW.Tag <> sd^.Tag then
        syslog.logln('USBStorage', 'CSW: tag mismatch')
    else if sd^.CSW.Status = CSW_PHASE_ERR then begin
        syslog.logln('USBStorage', 'CSW: phase error, resetting');
        usbcore.usb_control_msg(sd^.Dev,
            USB_REQTYPE_DIR_OUT or USB_REQTYPE_TYPE_CLASS or USB_REQTYPE_REC_INTERFACE,
            BOT_RESET, 0, 0, nil, 0);
        usbcore.usb_clear_halt(sd^.Dev, @sd^.BulkIn);
        usbcore.usb_clear_halt(sd^.Dev, @sd^.BulkOut);
    end else
        ok := sd^.CSW.Status = CSW_OK;

    sd^.Phase := phIdle;
    if sd^.OnDone <> nil then
        sd^.OnDone(ok, sd^.OnDoneUD);
end;

procedure bot_fail(sd : PUSBMSDev; msg : pchar);
begin
    syslog.logln('USBStorage', msg);
    if sd^.ActiveXfer <> nil then begin
        kfree(void(sd^.ActiveXfer));
        sd^.ActiveXfer := nil;
    end;
    sd^.Phase := phIdle;
    if sd^.OnDone <> nil then
        sd^.OnDone(false, sd^.OnDoneUD);
end;

{ ==================== Synchronous Init Helper ==================== }

procedure bot_sync_done(ok : boolean; state : puint32);
begin
    if ok then state^ := 1 else state^ := 0;
    puint32(uint32(state) + 4)^ := 1;
end;

function bot_sync(sd      : PUSBMSDev;
                  dir     : uint8;
                  cblen   : uint8;
                  cb      : Pointer;
                  databuf : Pointer;
                  datalen : uint32) : boolean;
var
    state : array[0..1] of uint32;
    t0    : uint32;
begin
    bot_sync := false;
    state[0] := 0;
    state[1] := 0;

    if not bot_start(sd, dir, cblen, cb, databuf, datalen,
                     TStorageCompletion(@bot_sync_done), @state[0]) then exit;

    t0 := bios_data_area.Counters.c32;
    repeat
        if (sd^.Dev <> nil) and (sd^.Dev^.HC <> nil) and
           (sd^.Dev^.HC^.fnPoll <> nil) then
            sd^.Dev^.HC^.fnPoll(sd^.Dev^.HC);
        if (bios_data_area.Counters.c32 - t0) > BOT_TIMEOUT_MS then begin
            bot_fail(sd, 'Timeout');
            exit;
        end;
    until state[1] <> 0;

    bot_sync := state[0] <> 0;
end;

{ ==================== SCSI Commands ==================== }

function scsi_test_unit_ready(sd : PUSBMSDev) : boolean;
var cdb : array[0..5] of uint8;
begin
    memset(uint32(@cdb), 0, 6);
    cdb[0] := SCSI_OP_TEST_UNIT_READY;
    scsi_test_unit_ready := bot_sync(sd, CBW_DIR_OUT, 6, @cdb, nil, 0);
end;

function scsi_request_sense(sd : PUSBMSDev; buf : Pointer; len : uint8) : boolean;
var cdb : array[0..5] of uint8;
begin
    memset(uint32(@cdb), 0, 6);
    cdb[0] := SCSI_OP_REQUEST_SENSE;
    cdb[4] := len;
    scsi_request_sense := bot_sync(sd, CBW_DIR_IN, 6, @cdb, buf, len);
end;

function scsi_inquiry(sd : PUSBMSDev; buf : Pointer; len : uint8) : boolean;
var cdb : array[0..5] of uint8;
begin
    memset(uint32(@cdb), 0, 6);
    cdb[0] := SCSI_OP_INQUIRY;
    cdb[4] := len;
    scsi_inquiry := bot_sync(sd, CBW_DIR_IN, 6, @cdb, buf, len);
end;

function scsi_read_capacity(sd        : PUSBMSDev;
                            var lastLBA   : uint32;
                            var blockSize : uint32) : boolean;
var
    cdb : array[0..9] of uint8;
    buf : array[0..7] of uint8;
begin
    memset(uint32(@cdb), 0, 10);
    memset(uint32(@buf), 0, 8);
    cdb[0] := SCSI_OP_READ_CAPACITY10;
    scsi_read_capacity := bot_sync(sd, CBW_DIR_IN, 10, @cdb, @buf, 8);
    if scsi_read_capacity then begin
        lastLBA   := (uint32(buf[0]) shl 24) or (uint32(buf[1]) shl 16)
                   or (uint32(buf[2]) shl  8) or  uint32(buf[3]);
        blockSize := (uint32(buf[4]) shl 24) or (uint32(buf[5]) shl 16)
                   or (uint32(buf[6]) shl  8) or  uint32(buf[7]);
    end else begin
        lastLBA   := 0;
        blockSize := 0;
    end;
end;

{ ==================== Async Storage Callbacks ==================== }

procedure usb_read_async(drive      : PStorage_Device;
                         addr       : uint32;
                         sectors    : uint32;
                         buffer     : puint32;
                         completion : TStorageCompletion;
                         userdata   : puint32);
var
    sd  : PUSBMSDev;
    cdb : array[0..9] of uint8;
begin
    sd := PUSBMSDev(Pointer(drive^.controllerId0));
    if (sd = nil) or not sd^.Active then begin
        if completion <> nil then completion(false, userdata);
        exit;
    end;

    memset(uint32(@cdb), 0, 10);
    cdb[0] := SCSI_OP_READ10;
    cdb[2] := uint8((addr shr 24) and $FF);
    cdb[3] := uint8((addr shr 16) and $FF);
    cdb[4] := uint8((addr shr  8) and $FF);
    cdb[5] := uint8( addr         and $FF);
    cdb[7] := uint8((sectors shr 8) and $FF);
    cdb[8] := uint8( sectors        and $FF);

    if not bot_start(sd, CBW_DIR_IN, 10, @cdb,
                     Pointer(buffer), sectors * sd^.SectorSize,
                     completion, userdata) then
        if completion <> nil then completion(false, userdata);
end;

procedure usb_write_async(drive      : PStorage_Device;
                          addr       : uint32;
                          sectors    : uint32;
                          buffer     : puint32;
                          completion : TStorageCompletion;
                          userdata   : puint32);
var
    sd  : PUSBMSDev;
    cdb : array[0..9] of uint8;
begin
    sd := PUSBMSDev(Pointer(drive^.controllerId0));
    if (sd = nil) or not sd^.Active then begin
        if completion <> nil then completion(false, userdata);
        exit;
    end;

    memset(uint32(@cdb), 0, 10);
    cdb[0] := SCSI_OP_WRITE10;
    cdb[2] := uint8((addr shr 24) and $FF);
    cdb[3] := uint8((addr shr 16) and $FF);
    cdb[4] := uint8((addr shr  8) and $FF);
    cdb[5] := uint8( addr         and $FF);
    cdb[7] := uint8((sectors shr 8) and $FF);
    cdb[8] := uint8( sectors        and $FF);

    if not bot_start(sd, CBW_DIR_OUT, 10, @cdb,
                     Pointer(buffer), sectors * sd^.SectorSize,
                     completion, userdata) then
        if completion <> nil then completion(false, userdata);
end;

{ ==================== Disconnect Handler ==================== }

procedure on_disconnect(dev : PUSBDevice);
var
    i  : uint32;
    sd : PUSBMSDev;
begin
    if Devices = nil then exit;
    i := 0;
    while i < LL_Size(Devices) do begin
        sd := PUSBMSDev(LL_Get(Devices, i));
        if (sd <> nil) and (sd^.Dev = dev) then begin
            syslog.logln('USBStorage', 'Device disconnected.');
            sd^.Active := false;

            if sd^.Phase <> phIdle then begin
                if sd^.ActiveXfer <> nil then begin
                    kfree(void(sd^.ActiveXfer));
                    sd^.ActiveXfer := nil;
                end;
                sd^.Phase := phIdle;
                if sd^.OnDone <> nil then
                    sd^.OnDone(false, sd^.OnDoneUD);
            end;

            sd^.StoreDev.readCallbackAsync  := nil;
            sd^.StoreDev.writeCallbackAsync := nil;
            sd^.StoreDev.readCallback       := nil;
            sd^.StoreDev.writeCallback      := nil;
            sd^.Dev := nil;

            LL_Delete(Devices, i);
        end else
            inc(i);
    end;
end;

{ ==================== HC Poll Hook ==================== }

{ Called from the storagemanager sync bridge spin-loop to drive the HC
  so that BOT completions are delivered even when a dedicated IRQ is not
  firing from the current execution context. }
procedure usb_poll;
var
    i  : uint32;
    sd : PUSBMSDev;
begin
    if Devices = nil then exit;
    for i := 0 to LL_Size(Devices) - 1 do begin
        sd := PUSBMSDev(LL_Get(Devices, i));
        if (sd <> nil) and (sd^.Dev <> nil) and
           (sd^.Dev^.HC <> nil) and (sd^.Dev^.HC^.fnPoll <> nil) then
            sd^.Dev^.HC^.fnPoll(sd^.Dev^.HC);
    end;
end;

{ ==================== Driver Load ==================== }

function load(ptr : void) : boolean;
var
    dev     : PUSBDevice;
    sd      : PUSBMSDev;
    i       : uint32;
    lba     : uint32;
    blksz   : uint32;
    retry   : uint32;
    buf     : Pointer;
begin
    push_trace('usb_storage.load');
    load := false;

    dev := PUSBDevice(ptr);
    if dev = nil then begin pop_trace; exit; end;

    syslog.logln('USBStorage', 'Configuring device...');

    sd := PUSBMSDev(LL_Add(Devices));
    memset(uint32(sd), 0, sizeof(TUSBMSDev));
    sd^.Dev        := dev;
    sd^.SectorSize := 512;
    sd^.Phase      := phIdle;

    { Find bulk IN and OUT endpoints }
    for i := 0 to dev^.NumEndpoints - 1 do begin
        if dev^.Endpoints[i].PipeType = ptBulk then begin
            if (dev^.Endpoints[i].Direction = dirIn) and not sd^.HasIn then begin
                sd^.BulkIn := dev^.Endpoints[i];
                sd^.HasIn  := true;
            end;
            if (dev^.Endpoints[i].Direction = dirOut) and not sd^.HasOut then begin
                sd^.BulkOut := dev^.Endpoints[i];
                sd^.HasOut  := true;
            end;
        end;
    end;

    if (not sd^.HasIn) or (not sd^.HasOut) then begin
        syslog.logln('USBStorage', 'Missing bulk endpoints.');
        LL_Delete(Devices, LL_Size(Devices) - 1);
        pop_trace;
        exit;
    end;

    { INQUIRY }
    buf := Pointer(kalloc(36));
    if buf <> nil then begin
        memset(uint32(buf), 0, 36);
        scsi_inquiry(sd, buf, 36);
        kfree(void(buf));
    end;

    { TEST UNIT READY with retries, REQUEST SENSE on failure }
    retry := 0;
    while retry < 5 do begin
        if scsi_test_unit_ready(sd) then break;
        buf := Pointer(kalloc(18));
        if buf <> nil then begin
            memset(uint32(buf), 0, 18);
            scsi_request_sense(sd, buf, 18);
            kfree(void(buf));
        end;
        util.psleep(200);
        inc(retry);
    end;

    if retry >= 5 then begin
        syslog.logln('USBStorage', 'Device not ready.');
        LL_Delete(Devices, LL_Size(Devices) - 1);
        pop_trace;
        exit;
    end;

    { READ CAPACITY }
    lba := 0;
    blksz := 0;
    if not scsi_read_capacity(sd, lba, blksz) then begin
        syslog.logln('USBStorage', 'READ CAPACITY failed.');
        LL_Delete(Devices, LL_Size(Devices) - 1);
        pop_trace;
        exit;
    end;

    if blksz = 0 then blksz := 512;
    if lba   = 0 then begin
        syslog.logln('USBStorage', 'Zero capacity.');
        LL_Delete(Devices, LL_Size(Devices) - 1);
        pop_trace;
        exit;
    end;

    sd^.SectorSize  := blksz;
    sd^.SectorCount := lba + 1;

    syslog.log('USBStorage', 'Ready: ');
    syslog.writeint(sd^.SectorCount);
    syslog.writestring(' x ');
    syslog.writeint(sd^.SectorSize);
    syslog.writestringln('B');

    { Fill in the TStorage_Device record and register }
    sd^.StoreDev.controller         := ControllerUSB;
    sd^.StoreDev.controllerId0      := uint32(sd);
    sd^.StoreDev.maxSectorCount     := sd^.SectorCount;
    sd^.StoreDev.sectorSize         := sd^.SectorSize;
    sd^.StoreDev.writable           := true;
    sd^.StoreDev.readCallback       := nil;
    sd^.StoreDev.writeCallback      := nil;
    sd^.StoreDev.readCallbackAsync  := PPHIOHookAsync(@usb_read_async);
    sd^.StoreDev.writeCallbackAsync := PPHIOHookAsync(@usb_write_async);
    sd^.StoreDev.pollCallback       := PPPollHook(@usb_poll);

    { Mark active before register_device so volume-detect I/O succeeds }
    sd^.Active := true;
    storagemanager.register_device(@sd^.StoreDev);

    dev^.fnDisconnect := TUSBDisconnectCallback(@on_disconnect);

    syslog.logln('USBStorage', 'Device ready.');
    load := true;
    pop_trace;
end;

{ ==================== Init ==================== }

procedure init;
var
    id : TDeviceIdentifier;
begin
    push_trace('usb_storage.init');
    syslog.logln('USBStorage', 'INIT BEGIN.');

    Devices := LL_New(sizeof(TUSBMSDev));

    id.Bus := biUSB;
    id.id0 := idANY;
    id.id1 := $FFFFFFFF;
    id.id2 := USB_CLASS_MASS_STORAGE;
    id.id3 := MSC_SUBCLASS_SCSI;
    id.id4 := MSC_PROTOCOL_BOT;
    id.ex  := nil;

    drivermanagement.register_driver('USB Storage', @id, @load);

    syslog.logln('USBStorage', 'INIT END.');
    pop_trace;
end;

end.
