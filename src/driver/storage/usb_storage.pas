{
    Driver->Storage->USB_Storage - USB Mass Storage Bulk-Only Transport (BOT) Driver.

    Registers with drivermanagement as a USB class driver matching
    mass storage devices (class $08, subclass $06 SCSI, protocol $50 BOT).
    Implements CBW/CSW over bulk endpoints, translates SCSI READ(10)/WRITE(10)
    to the storagemanagement read/write callbacks.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit usb_storage;

interface

uses
    usbtypes,
    usbcore,
    drivermanagement,
    drivertypes,
    storagemanagement,
    lmemorymanager,
    lists,
    tracer,
    syslog,
    strings,
    util;

procedure init;

implementation

{ ========================= Constants ========================= }

const
    { USB Mass Storage Subclass / Protocol }
    MSC_SUBCLASS_SCSI     = $06;
    MSC_PROTOCOL_BOT      = $50;

    { BOT Class Requests }
    BOT_REQ_RESET         = $FF;
    BOT_REQ_GET_MAX_LUN   = $FE;

    { CBW Constants }
    CBW_SIGNATURE         = $43425355; { 'USBC' little-endian }
    CBW_SIZE              = 31;
    CBW_FLAG_DATA_OUT     = $00;
    CBW_FLAG_DATA_IN      = $80;

    { CSW Constants }
    CSW_SIGNATURE         = $53425355; { 'USBS' little-endian }
    CSW_SIZE              = 13;
    CSW_STATUS_PASSED     = $00;
    CSW_STATUS_FAILED     = $01;
    CSW_STATUS_PHASE_ERR  = $02;

    { SCSI Command Opcodes }
    SCSI_OP_TEST_UNIT_READY  = $00;
    SCSI_OP_REQUEST_SENSE    = $03;
    SCSI_OP_INQUIRY          = $12;
    SCSI_OP_READ_CAPACITY_10 = $25;
    SCSI_OP_READ_10          = $28;
    SCSI_OP_WRITE_10         = $2A;

    { Maximum simultaneous USB storage devices }
    MAX_USB_STORAGE       = 4; { Only used for reference }

    { Transfer timeout in ms }
    BOT_TIMEOUT_MS        = 5000;

{ ========================= Types ========================= }

type
    { CBW - Command Block Wrapper (31 bytes) }
    PCBW = ^TCBW;
    TCBW = packed record
        dCBWSignature          : uint32;
        dCBWTag                : uint32;
        dCBWDataTransferLength : uint32;
        bmCBWFlags             : uint8;
        bCBWLUN                : uint8;
        bCBWCBLength           : uint8;
        CBWCB                  : array[0..15] of uint8;
    end;

    { CSW - Command Status Wrapper (13 bytes) }
    PCSW = ^TCSW;
    TCSW = packed record
        dCSWSignature   : uint32;
        dCSWTag         : uint32;
        dCSWDataResidue : uint32;
        bCSWStatus      : uint8;
    end;

    { SCSI READ CAPACITY (10) Response }
    PSCSI_ReadCapacity = ^TSCSI_ReadCapacity;
    TSCSI_ReadCapacity = packed record
        LastLBA     : uint32;
        BlockLength : uint32;
    end;

    { Per-device state }
    PUSBStorageData = ^TUSBStorageData;
    TUSBStorageData = record
        Device       : PUSBDevice;
        BulkIn       : TUSBEndpoint;
        BulkOut      : TUSBEndpoint;
        HasBulkIn    : boolean;
        HasBulkOut   : boolean;
        Tag          : uint32;
        MaxLUN       : uint8;
        SectorSize   : uint32;
        SectorCount  : uint32;
        StorageDev   : TStorage_Device;
        Active       : boolean;
    end;

{ ========================= Globals ========================= }

var
    StorageList : PLinkedListBase;

{ ========================= Byte Swap Helpers ========================= }

{ Convert uint32 from native (little-endian) to big-endian for SCSI }
function bswap32(v : uint32) : uint32;
begin
    bswap32 := ((v AND $FF) SHL 24) OR
               (((v SHR 8) AND $FF) SHL 16) OR
               (((v SHR 16) AND $FF) SHL 8) OR
               ((v SHR 24) AND $FF);
end;

{ Convert uint16 from native to big-endian }
function bswap16(v : uint16) : uint16;
begin
    bswap16 := ((v AND $FF) SHL 8) OR ((v SHR 8) AND $FF);
end;

{ ========================= BOT Transport ========================= }

{ Send a CBW, optionally transfer data, then receive CSW.
  Returns true if CSW indicates success. }
function bot_transfer(sd : PUSBStorageData;
                      direction : uint8;   { CBW_FLAG_DATA_IN or CBW_FLAG_DATA_OUT }
                      cbLen : uint8;       { Length of SCSI command (6, 10, 12, 16) }
                      cb : Pointer;        { SCSI CDB }
                      dataBuf : Pointer;   { Data buffer (nil if no data phase) }
                      dataLen : uint32;    { Data transfer length }
                      actualLen : puint32  { out: actual bytes transferred, may be nil }
                     ) : boolean;
var
    cbw       : PCBW;
    csw       : PCSW;
    status    : TUSBTransferStatus;
    xferActual : uint32;
    i         : uint8;
    retry     : uint8;
begin
    push_trace('usb_storage.bot_transfer');
    bot_transfer := false;

    cbw := PCBW(kalloc(CBW_SIZE));
    csw := PCSW(kalloc(CSW_SIZE));

    if (cbw = nil) or (csw = nil) then begin
        if cbw <> nil then kfree(void(cbw));
        if csw <> nil then kfree(void(csw));
        pop_trace;
        exit;
    end;

    { Build CBW }
    memset(uint32(cbw), 0, CBW_SIZE);
    cbw^.dCBWSignature := CBW_SIGNATURE;
    inc(sd^.Tag);
    cbw^.dCBWTag := sd^.Tag;
    cbw^.dCBWDataTransferLength := dataLen;
    cbw^.bmCBWFlags := direction;
    cbw^.bCBWLUN := 0;
    cbw^.bCBWCBLength := cbLen;

    { Copy SCSI CDB into CBWCB }
    for i := 0 to 15 do
        cbw^.CBWCB[i] := 0;
    if (cb <> nil) and (cbLen > 0) then begin
        for i := 0 to cbLen - 1 do
            cbw^.CBWCB[i] := PUint8(uint32(cb) + i)^;
    end;

    { Phase 1: Send CBW via bulk OUT }
    status := usbcore.usb_bulk_transfer_wait(
        sd^.Device, @sd^.BulkOut, Pointer(cbw), CBW_SIZE, BOT_TIMEOUT_MS, nil);
    if status <> tsSuccess then begin
        syslog.logln('USBStorage', 'CBW send failed.');
        if status = tsStall then
            usbcore.usb_clear_halt(sd^.Device, @sd^.BulkOut);
        kfree(void(cbw));
        kfree(void(csw));
        pop_trace;
        exit;
    end;

    { Phase 2: Data transfer (if any) }
    if (dataBuf <> nil) and (dataLen > 0) then begin
        xferActual := 0;
        if direction = CBW_FLAG_DATA_IN then begin
            status := usbcore.usb_bulk_transfer_wait(
                sd^.Device, @sd^.BulkIn, dataBuf, dataLen, BOT_TIMEOUT_MS, @xferActual);
        end else begin
            status := usbcore.usb_bulk_transfer_wait(
                sd^.Device, @sd^.BulkOut, dataBuf, dataLen, BOT_TIMEOUT_MS, @xferActual);
        end;
        if status = tsStall then begin
            { Clear stall and try to read CSW anyway }
            if direction = CBW_FLAG_DATA_IN then
                usbcore.usb_clear_halt(sd^.Device, @sd^.BulkIn)
            else
                usbcore.usb_clear_halt(sd^.Device, @sd^.BulkOut);
        end else if status <> tsSuccess then begin
            syslog.logln('USBStorage', 'Data phase failed.');
            kfree(void(cbw));
            kfree(void(csw));
            pop_trace;
            exit;
        end;
        if actualLen <> nil then
            actualLen^ := xferActual;
    end else begin
        if actualLen <> nil then
            actualLen^ := 0;
    end;

    { Phase 3: Receive CSW via bulk IN }
    memset(uint32(csw), 0, CSW_SIZE);
    retry := 0;
    while retry < 2 do begin
        status := usbcore.usb_bulk_transfer_wait(
            sd^.Device, @sd^.BulkIn, Pointer(csw), CSW_SIZE, BOT_TIMEOUT_MS, nil);
        if status = tsStall then begin
            usbcore.usb_clear_halt(sd^.Device, @sd^.BulkIn);
            inc(retry);
            continue;
        end;
        break;
    end;

    if status <> tsSuccess then begin
        syslog.logln('USBStorage', 'CSW receive failed.');
        kfree(void(cbw));
        kfree(void(csw));
        pop_trace;
        exit;
    end;

    { Validate CSW }
    if csw^.dCSWSignature <> CSW_SIGNATURE then begin
        syslog.logln('USBStorage', 'CSW signature mismatch.');
        kfree(void(cbw));
        kfree(void(csw));
        pop_trace;
        exit;
    end;

    if csw^.dCSWTag <> sd^.Tag then begin
        syslog.logln('USBStorage', 'CSW tag mismatch.');
        kfree(void(cbw));
        kfree(void(csw));
        pop_trace;
        exit;
    end;

    if csw^.bCSWStatus = CSW_STATUS_PHASE_ERR then begin
        syslog.logln('USBStorage', 'CSW phase error - issuing BOT reset.');
        { BOT reset }
        usbcore.usb_control_msg(sd^.Device,
            USB_REQTYPE_DIR_OUT OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_INTERFACE,
            BOT_REQ_RESET, 0, 0, nil, 0);
        usbcore.usb_clear_halt(sd^.Device, @sd^.BulkIn);
        usbcore.usb_clear_halt(sd^.Device, @sd^.BulkOut);
        kfree(void(cbw));
        kfree(void(csw));
        pop_trace;
        exit;
    end;

    bot_transfer := (csw^.bCSWStatus = CSW_STATUS_PASSED);

    kfree(void(cbw));
    kfree(void(csw));
    pop_trace;
end;

{ ========================= SCSI Commands ========================= }

function scsi_test_unit_ready(sd : PUSBStorageData) : boolean;
var
    cdb : array[0..5] of uint8;
    i   : uint8;
begin
    push_trace('usb_storage.scsi_test_unit_ready');
    for i := 0 to 5 do cdb[i] := 0;
    cdb[0] := SCSI_OP_TEST_UNIT_READY;
    scsi_test_unit_ready := bot_transfer(sd, CBW_FLAG_DATA_OUT, 6, @cdb[0], nil, 0, nil);
    pop_trace;
end;

function scsi_inquiry(sd : PUSBStorageData; buf : Pointer; len : uint8) : boolean;
var
    cdb : array[0..5] of uint8;
    i   : uint8;
begin
    push_trace('usb_storage.scsi_inquiry');
    for i := 0 to 5 do cdb[i] := 0;
    cdb[0] := SCSI_OP_INQUIRY;
    cdb[4] := len;
    scsi_inquiry := bot_transfer(sd, CBW_FLAG_DATA_IN, 6, @cdb[0], buf, len, nil);
    pop_trace;
end;

function scsi_read_capacity(sd : PUSBStorageData; var lastLBA : uint32; var blockSize : uint32) : boolean;
var
    cdb : array[0..9] of uint8;
    buf : array[0..7] of uint8;
    i   : uint8;
begin
    push_trace('usb_storage.scsi_read_capacity');
    for i := 0 to 9 do cdb[i] := 0;
    for i := 0 to 7 do buf[i] := 0;
    cdb[0] := SCSI_OP_READ_CAPACITY_10;

    scsi_read_capacity := bot_transfer(sd, CBW_FLAG_DATA_IN, 10, @cdb[0], @buf[0], 8, nil);
    if scsi_read_capacity then begin
        { Response is big-endian }
        lastLBA := (uint32(buf[0]) SHL 24) OR (uint32(buf[1]) SHL 16) OR
                   (uint32(buf[2]) SHL 8) OR uint32(buf[3]);
        blockSize := (uint32(buf[4]) SHL 24) OR (uint32(buf[5]) SHL 16) OR
                     (uint32(buf[6]) SHL 8) OR uint32(buf[7]);
    end else begin
        lastLBA := 0;
        blockSize := 0;
    end;
    pop_trace;
end;

function scsi_request_sense(sd : PUSBStorageData; buf : Pointer; len : uint8) : boolean;
var
    cdb : array[0..5] of uint8;
    i   : uint8;
begin
    push_trace('usb_storage.scsi_request_sense');
    for i := 0 to 5 do cdb[i] := 0;
    cdb[0] := SCSI_OP_REQUEST_SENSE;
    cdb[4] := len;
    scsi_request_sense := bot_transfer(sd, CBW_FLAG_DATA_IN, 6, @cdb[0], buf, len, nil);
    pop_trace;
end;

function scsi_read_10(sd : PUSBStorageData; lba : uint32; sectorCount : uint16;
                      buf : Pointer; bufLen : uint32) : boolean;
var
    cdb : array[0..9] of uint8;
    i   : uint8;
begin
    push_trace('usb_storage.scsi_read_10');
    for i := 0 to 9 do cdb[i] := 0;
    cdb[0] := SCSI_OP_READ_10;
    { LBA is big-endian in bytes 2-5 }
    cdb[2] := uint8((lba SHR 24) AND $FF);
    cdb[3] := uint8((lba SHR 16) AND $FF);
    cdb[4] := uint8((lba SHR 8) AND $FF);
    cdb[5] := uint8(lba AND $FF);
    { Transfer length (sectors) in bytes 7-8, big-endian }
    cdb[7] := uint8((sectorCount SHR 8) AND $FF);
    cdb[8] := uint8(sectorCount AND $FF);

    scsi_read_10 := bot_transfer(sd, CBW_FLAG_DATA_IN, 10, @cdb[0], buf, bufLen, nil);
    pop_trace;
end;

function scsi_write_10(sd : PUSBStorageData; lba : uint32; sectorCount : uint16;
                       buf : Pointer; bufLen : uint32) : boolean;
var
    cdb : array[0..9] of uint8;
    i   : uint8;
begin
    push_trace('usb_storage.scsi_write_10');
    for i := 0 to 9 do cdb[i] := 0;
    cdb[0] := SCSI_OP_WRITE_10;
    { LBA is big-endian in bytes 2-5 }
    cdb[2] := uint8((lba SHR 24) AND $FF);
    cdb[3] := uint8((lba SHR 16) AND $FF);
    cdb[4] := uint8((lba SHR 8) AND $FF);
    cdb[5] := uint8(lba AND $FF);
    { Transfer length (sectors) in bytes 7-8, big-endian }
    cdb[7] := uint8((sectorCount SHR 8) AND $FF);
    cdb[8] := uint8(sectorCount AND $FF);

    scsi_write_10 := bot_transfer(sd, CBW_FLAG_DATA_OUT, 10, @cdb[0], buf, bufLen, nil);
    pop_trace;
end;

{ ========================= Storage Callbacks ========================= }

{ Read callback for storagemanagement. }
procedure usb_storage_read(device : PStorage_device; LBA : uint32; sectorCount : uint32; buffer : puint32);
var
    sd      : PUSBStorageData;
    bufLen  : uint32;
begin
    push_trace('usb_storage.usb_storage_read');
    sd := PUSBStorageData(Pointer(device^.controllerId0));
    if (sd = nil) or (not sd^.Active) then begin
        pop_trace;
        exit;
    end;

    bufLen := sectorCount * sd^.SectorSize;
    if not scsi_read_10(sd, LBA, uint16(sectorCount), Pointer(buffer), bufLen) then begin
        syslog.log('USBStorage', 'Read failed at LBA ');
        syslog.writeintln(LBA);
    end;
    pop_trace;
end;

{ Write callback for storagemanagement. }
procedure usb_storage_write(device : PStorage_device; LBA : uint32; sectorCount : uint32; buffer : puint32);
var
    sd      : PUSBStorageData;
    bufLen  : uint32;
begin
    push_trace('usb_storage.usb_storage_write');
    sd := PUSBStorageData(Pointer(device^.controllerId0));
    if (sd = nil) or (not sd^.Active) then begin
        pop_trace;
        exit;
    end;

    bufLen := sectorCount * sd^.SectorSize;
    if not scsi_write_10(sd, LBA, uint16(sectorCount), Pointer(buffer), bufLen) then begin
        syslog.log('USBStorage', 'Write failed at LBA ');
        syslog.writeintln(LBA);
    end;
    pop_trace;
end;

{ ========================= Disconnect Handler ========================= }

procedure unload(dev : PUSBDevice);
var
    i   : uint32;
    sd  : PUSBStorageData;
    cnt : uint32;
begin
    if StorageList = nil then exit;
    cnt := LL_Size(StorageList);
    i := 0;
    while i < cnt do begin
        sd := PUSBStorageData(LL_Get(StorageList, i));
        if (sd <> nil) and (sd^.Device = dev) then begin
            syslog.logln('USBStorage', 'Device disconnected, deactivating.');
            sd^.Active := false;
            sd^.StorageDev.readCallback := nil;
            sd^.StorageDev.writeCallback := nil;
            sd^.Device := nil;
            LL_Delete(StorageList, i);
            dec(cnt);
        end else
            inc(i);
    end;
end;

{ ========================= Driver Load ========================= }

function load(ptr : void) : boolean;
var
    dev       : PUSBDevice;
    sd        : PUSBStorageData;
    status    : TUSBTransferStatus;
    i         : uint32;
    lastLBA   : uint32;
    blockSize : uint32;
    inquiryBuf : Pointer;
    senseBuf  : Pointer;
    retry     : uint32;
begin
    push_trace('usb_storage.load');
    load := false;

    dev := PUSBDevice(ptr);
    if dev = nil then begin
        pop_trace;
        exit;
    end;

    syslog.logln('USBStorage', 'Configuring USB mass storage device...');

    sd := PUSBStorageData(LL_Add(StorageList));
    sd^.Device := dev;
    sd^.HasBulkIn := false;
    sd^.HasBulkOut := false;
    sd^.Active := false;
    sd^.Tag := 0;
    sd^.MaxLUN := 0;
    sd^.SectorSize := 512;
    sd^.SectorCount := 0;

    { Find bulk IN and bulk OUT endpoints }
    for i := 0 to dev^.NumEndpoints - 1 do begin
        if (dev^.Endpoints[i].PipeType = ptBulk) and
           (dev^.Endpoints[i].Direction = dirIn) and
           (not sd^.HasBulkIn) then begin
            sd^.BulkIn := dev^.Endpoints[i];
            sd^.HasBulkIn := true;
        end;
        if (dev^.Endpoints[i].PipeType = ptBulk) and
           (dev^.Endpoints[i].Direction = dirOut) and
           (not sd^.HasBulkOut) then begin
            sd^.BulkOut := dev^.Endpoints[i];
            sd^.HasBulkOut := true;
        end;
    end;

    if not sd^.HasBulkIn then begin
        syslog.logln('USBStorage', 'No bulk IN endpoint found.');
        pop_trace;
        exit;
    end;

    if not sd^.HasBulkOut then begin
        syslog.logln('USBStorage', 'No bulk OUT endpoint found.');
        pop_trace;
        exit;
    end;

    syslog.log('USBStorage', 'Bulk IN EP');
    syslog.writeint(sd^.BulkIn.Address);
    syslog.writestring(' MaxPkt=');
    syslog.writeintln(sd^.BulkIn.MaxPacket);
    syslog.log('USBStorage', 'Bulk OUT EP');
    syslog.writeint(sd^.BulkOut.Address);
    syslog.writestring(' MaxPkt=');
    syslog.writeintln(sd^.BulkOut.MaxPacket);

    { GET_MAX_LUN (optional, many devices STALL this) }
    sd^.MaxLUN := 0;
    status := usbcore.usb_control_msg(dev,
        USB_REQTYPE_DIR_IN OR USB_REQTYPE_TYPE_CLASS OR USB_REQTYPE_REC_INTERFACE,
        BOT_REQ_GET_MAX_LUN, 0, 0, @sd^.MaxLUN, 1);
    if status <> tsSuccess then
        sd^.MaxLUN := 0;

    syslog.log('USBStorage', 'Max LUN: ');
    syslog.writeintln(sd^.MaxLUN);

    { SCSI INQUIRY }
    inquiryBuf := Pointer(kalloc(36));
    if inquiryBuf <> nil then begin
        memset(uint32(inquiryBuf), 0, 36);
        if scsi_inquiry(sd, inquiryBuf, 36) then begin
            syslog.logln('USBStorage', 'INQUIRY succeeded.');
        end else begin
            syslog.logln('USBStorage', 'INQUIRY failed.');
        end;
        kfree(void(inquiryBuf));
    end;

    { Wait for device to become ready with retries }
    retry := 0;
    while retry < 5 do begin
        if scsi_test_unit_ready(sd) then break;
        { Request sense to clear any pending condition }
        senseBuf := Pointer(kalloc(18));
        if senseBuf <> nil then begin
            scsi_request_sense(sd, senseBuf, 18);
            kfree(void(senseBuf));
        end;
        util.psleep(200);
        inc(retry);
    end;

    if retry >= 5 then begin
        syslog.logln('USBStorage', 'Device not ready after retries.');
        pop_trace;
        exit;
    end;

    { READ CAPACITY }
    lastLBA := 0;
    blockSize := 0;
    if not scsi_read_capacity(sd, lastLBA, blockSize) then begin
        syslog.logln('USBStorage', 'READ CAPACITY failed.');
        pop_trace;
        exit;
    end;

    sd^.SectorSize := blockSize;
    sd^.SectorCount := lastLBA + 1;

    syslog.log('USBStorage', 'Capacity: ');
    syslog.writeint(sd^.SectorCount);
    syslog.writestring(' sectors x ');
    syslog.writeint(sd^.SectorSize);
    syslog.writestringln(' bytes');

    if sd^.SectorSize = 0 then sd^.SectorSize := 512;
    if sd^.SectorCount = 0 then begin
        syslog.logln('USBStorage', 'Zero capacity, aborting.');
        pop_trace;
        exit;
    end;

    { Register with storage management }
    sd^.StorageDev.controller := ControllerUSB;
    sd^.StorageDev.controllerId0 := uint32(sd); { pointer to our data }
    sd^.StorageDev.maxSectorCount := sd^.SectorCount;
    sd^.StorageDev.sectorSize := sd^.SectorSize;
    sd^.StorageDev.writable := true;
    sd^.StorageDev.readCallback := @usb_storage_read;
    sd^.StorageDev.writeCallback := @usb_storage_write;
    sd^.StorageDev.hpc := 0;
    sd^.StorageDev.spt := 0;

    storagemanagement.register_device(@sd^.StorageDev);

    { Register disconnect callback }
    dev^.fnDisconnect := TUSBDisconnectCallback(@unload);

    sd^.Active := true;

    syslog.logln('USBStorage', 'USB mass storage device ready.');
    load := true;
    pop_trace;
end;

{ ========================= Init ========================= }

procedure init;
var
    devID : TDeviceIdentifier;
begin
    push_trace('usb_storage.init');
    syslog.logln('USBStorage', 'INIT BEGIN.');

    StorageList := LL_New(sizeof(TUSBStorageData));

    { Register as a USB class driver matching mass storage BOT }
    devID.Bus := biUSB;
    devID.id0 := idANY;               { Any VID:PID }
    devID.id1 := $FFFFFFFF;           { Any device class }
    devID.id2 := USB_CLASS_MASS_STORAGE; { bInterfaceClass = $08 }
    devID.id3 := MSC_SUBCLASS_SCSI;     { bInterfaceSubClass = $06 }
    devID.id4 := MSC_PROTOCOL_BOT;      { bInterfaceProtocol = $50 }
    devID.ex  := nil;

    drivermanagement.register_driver('USB Storage Driver', @devID, @load);

    syslog.logln('USBStorage', 'INIT END.');
    pop_trace;
end;

end.
