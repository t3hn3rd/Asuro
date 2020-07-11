{ ************************************************
  * Asuro
  * Unit: Drivers/storage/IDE
  * Description: IDE ATA Driver
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }
unit IDE;

interface

uses
    util,
    drivertypes,
    console,
    terminal,
    drivermanagement,
    vmemorymanager,
    lmemorymanager,
    storagemanagement,
    strings,
    tracer;

type 
    TPortMode = (P_READ, P_WRITE);

    TIdentResponse = array[0..255] of uint16;

    TIDE_Channel_Registers = record
        base    : uint16;
        ctrl    : uint16;
        bmide   : uint16;
        noInter : uint8
    end;

    TIDE_Device = record
        exists       : boolean;
        isPrimary    : boolean;
        isMaster     : boolean;
        isATAPI      : boolean;
        info         : TIdentResponse;
    end;

    TIDE_Status = bitpacked record 
        Busy  : Boolean;
        Ready : Boolean;
        Fault : Boolean;
        Seek  : Boolean;
        DRQ   : Boolean;
        CORR  : Boolean;
        IDDEX : Boolean;
        ERROR : Boolean;
    end;
    PIDE_Status = ^TIDE_Status;


const
    ATA_SR_BUSY = $80; //BUSY
    ATA_SR_DRDY = $40; //DRIVE READY
    ATA_SR_DF   = $20; //DRIVE WRITE FAULT
    ATA_SR_DSC  = $10; //DRIVE SEEK COMPLETE
    ATA_SR_DRQ  = $08; //DATA REQUEST READY
    ATA_SR_CORR = $04; //CORRECTED DATA
    ATA_SR_IDX  = $02; //INLEX
    ATA_SR_ERR  = $01; //ERROR

    ATA_ER_BBK   = $80; //BAD SECTOR
    ATA_ER_UNC   = $40; //UNCORRECTABLE DATA
    ATA_ER_MC    = $20; //NO MEDIA
    ATA_ER_IDNF  = $10; //ID MARK NOT FOUND
    ATA_ER_MCR   = $08; //NO MEDIA
    ATA_ER_ABRT  = $04; //COMMAND ABORTED
    ATA_ER_TK0NF = $02; //TRACK 0 NOT FOUND
    ATA_ER_AMNF  = $01; //NO ADDRESS MARK

    ATA_CMD_READ_PIO        = $20; 
    ATA_CMD_READ_PIO_EXT    = $24; 
    ATA_CMD_READ_DMA        = $C8; 
    ATA_CMD_READ_DMA_EXT    = $25; 
    ATA_CMD_WRITE_PIO       = $30; 
    ATA_CMD_WRITE_PIO_EXT   = $34; 
    ATA_CMD_WRITE_DMA       = $CA; 
    ATA_CMD_WRITE_DMA_EXT   = $35; 
    ATA_CMD_CACHE_FLUSH     = $E7; 
    ATA_CMD_CACHE_FLUSH_EXT = $EA; 
    ATA_CMD_PACKET          = $A0; 
    ATA_CMD_IDENTIFY_PACKET = $A1; 
    ATA_CMD_IDENTIFY        = $EC; 

    ATAPI_CMD_READ  = $A8;
    ATAPI_CMD_EJECT = $1B;

    ATA_IDENT_DEVICETYPE   = $0;    
    ATA_IDENT_CYLINDERS    = $2;    
    ATA_IDENT_HEADS        = $6;    
    ATA_IDENT_SECOTRS      = $12;    
    ATA_IDENT_SERIAL       = $20;    
    ATA_IDENT_MODEL        = $54;    
    ATA_IDENT_CAPABILITIES = $98;    
    ATA_IDENT_FIELDVALID   = $106;   
    ATA_IDENT_MAX_LBA      = $120;   
    ATA_IDENT_COMMANDSETS  = $164;       
    ATA_IDENT_MAX_LBA_EXT  = $200;

    ATA_REG_DATA       = $00;
    ATA_REG_ERROR      = $01;
    ATA_REG_FEATURES   = $01;
    ATA_REG_SECCOUNT  = $02;
    ATA_REG_LBA0       = $03;
    ATA_REG_LBA1       = $04;
    ATA_REG_LBA2       = $05;
    ATA_REG_HDDEVSEL   = $06;
    ATA_REG_COMMAND    = $07;
    ATA_REG_STATUS     = $07;
    ATA_REG_SECCOUNT1  = $08;
    ATA_REG_LBA3       = $09;
    ATA_REG_LBA4       = $0A;
    ATA_REG_LBA5       = $0B;
    ATA_REG_CONTROL    = $0C;
    ATA_REG_ALTSTATUS  = $0C;
    ATA_REG_DEVADDRESS = $0D; 

    ATA_DEVICE_MASTER = $A0;
    ATA_DEVICE_SLAVE = $B0;

    ATA_PRIMARY_BASE = $1F0;

var
    controller : PPCI_Device;

    bar0 : uint32;
    bar1 : uint32;
    bar4 : uint32;

    IDEDevices : array[0..3] of TIDE_Device;

    buffer : Puint32;

procedure init();
function load(ptr : void) : boolean;
function identify_device(bus : uint8; device : uint8) : TIdentResponse;

// procedure flush();
procedure readPIO28(drive : uint8; LBA : uint32; buffer : puint8);
procedure writePIO28(drive : uint8; LBA : uint32; buffer : puint8);
//read/write must be capable of reading/writting any amknt of data upto disk size

procedure read(device : PStorage_device; LBA : uint32; sectorCount : uint32; buffer : puint32);
procedure write(device : PStorage_device; LBA : uint32; sectorCount : uint32; buffer : puint32);

implementation 

function port_read(register : uint8) : uint8;
begin
    port_read:= inb(ATA_PRIMARY_BASE + register);
end;

procedure port_write(register : uint8; data : uint8);
var
    i : uint8;
begin
    outb(ATA_PRIMARY_BASE + register, data);
    util.psleep(1);
    if register = ATA_REG_COMMAND then begin
        for i:= 0 to 5 do begin 
            port_read(ATA_REG_STATUS);
        end;
    end;
end;

procedure no_interrupt(device : uint8);
begin
    outb($3F6, inb($3f6) or (1 shl 1));
end;

procedure device_select(device : uint8);
begin
    outb($1F6, device); //TODO clean
end;

function is_ready() : boolean;
var 
    status : uint8;
    i : uint32;
begin
    //wait for drive to be ready
    while true do begin 
        status := port_read(ATA_REG_COMMAND);

        if(status and ATA_SR_ERR) = ATA_SR_ERR then begin
            console.writestringln('[IDE] (IDENTIFY_DEVICE) DRIVE ERROR!');
            console.redrawWindows();
            is_ready := false;
            break;
        end;

        if (status and ATA_SR_BUSY) <> ATA_SR_BUSY then begin
            is_ready := true;
            break;
        end;
    end;
end;

function validate_28bit_address(addr : uint32) : boolean;
begin
    validate_28bit_address := (addr and $F0000000) = 0;
end;

function identify_device(bus : uint8; device : uint8) : TIdentResponse;
var
    status : uint8;
    identResponse : TIdentResponse;
    i : uint8;
begin 
    device_select(device);
    no_interrupt(device);
    port_write(ATA_REG_CONTROL, 0);

    //check if bus is floating
    status := port_read(ATA_REG_COMMAND);
    if status = $FF then exit;

    port_write(ATA_REG_SECCOUNT, 0);
    port_write(ATA_REG_LBA0, 0);
    port_write(ATA_REG_LBA1, 0);
    port_write(ATA_REG_LBA2, 0);

    port_write(ATA_REG_COMMAND, ATA_CMD_IDENTIFY);

    //check if drive is present
    status := port_read(ATA_REG_COMMAND);
    if status = $00 then exit;

    if not is_ready() then exit;

    for i:=0 to 255 do begin
        identResponse[i] := inw(ATA_PRIMARY_BASE + ATA_REG_DATA);
    end;

    identify_device := identResponse; 
end;

procedure init();  
var
    devID : TDeviceIdentifier;
begin
    push_trace('ide.init');
    console.writestringln('[IDE] (INIT) BEGIN');
    devID.bus:= biPCI;
    devID.id0:= idANY;
    devID.id1:= $00000001;
    devID.id2:= $00000001;
    devID.id3:= idANY;
    devID.id4:= idANY;
    devID.ex:= nil;
    drivermanagement.register_driver('IDE ATA Driver', @devID, @load);
    //terminal.registerCommand('IDE', @test_command, 'TEST IDE DRIVER');
    buffer := Puint32(kalloc(1024*2));
    console.writestringln('[IDE] (INIT) END');
    pop_trace();
end;

function load(ptr : void) : boolean;
var
    controller : PPCI_Device;
    masterDevice : TStorage_Device;
    slaveDevice : TStorage_Device;
    buffer : puint8;
    i : uint8;
begin
    push_trace('ide.load');
    console.writestringln('[IDE] (LOAD) BEGIN');
    //controller := PPCI_Device(ptr);
    controller := PPCI_Device(ptr);

    console.writestringln('[IDE] (INIT) CHECK FLOATING BUS');
    //check if bus is floating and identify device
    if inb($1F7) <> $FF then begin
        //outb($3F6, inb($3f6) or (1 shl 1)); // disable interrupts
        IDEDevices[0].isMaster:= true;
        IDEDevices[0].info := identify_device(0, ATA_DEVICE_MASTER);

        masterDevice.controller := ControllerIDE;
        masterDevice.controllerId0:= 0;
        masterDevice.maxSectorCount:= (IDEDevices[0].info[60] or (IDEDevices[0].info[61] shl 16) ); //LBA28 SATA
        
        if IDEDevices[0].info[1] = 0 then begin
            console.writestringln('[IDE] (INIT) ERROR: DEVICE IDENT FAILED!');
            exit;
        end;

        masterDevice.hpc:= uint32(IDEDevices[0].info[3] DIV IDEDevices[0].info[1]);

        masterDevice.sectorSize:= 512;
        if masterDevice.maxSectorCount <> 0 then begin
            IDEDevices[0].exists:= true;
            masterDevice.readCallback:= @read;
            masterDevice.writeCallback:= @write;
            storagemanagement.register_device(@masterDevice);
        end;

    end;

    console.writestringln('[IDE] (LOAD) END');
    pop_trace();
end;

// procedure flush();
// begin
//     port_write(ATA_CMD_CACHE_FLUSH);
//     if not is_ready() then exit;
// end;

procedure readPIO28(drive : uint8; LBA : uint32; buffer : puint8);
var
    status : uint8;
    i: uint16;
    device: uint8;
    data: uint16;
begin 
       if not validate_28bit_address(LBA) then begin
        console.writestringln('IDE (writePIO28) ERROR: Invalid LBA!');
    end;

    //Add last 4 bits of LBA to device port
    if IDEDevices[drive].isMaster then begin
        device:= ATA_DEVICE_MASTER;
        device_select($E0 or ((LBA and $0F000000) shr 24)); //LBA primary master
    end
    else begin
        device:= ATA_DEVICE_SLAVE;
        device_select($F0 or ((LBA and $0F000000) shr 24)); //LBA primary slave
    end;

    no_interrupt(device);
    port_write(ATA_REG_ERROR, 0);

    //Write sector count and LBA
    port_write(ATA_REG_SECCOUNT, 1);
    port_write(ATA_REG_LBA0, (LBA and $000000FF));
    port_write(ATA_REG_LBA1, (LBA and $0000FF00) shr 8);
    port_write(ATA_REG_LBA2, (LBA and $00FF0000) shr 16);

    //send read command
    port_write(ATA_REG_COMMAND, ATA_CMD_READ_PIO); 
    if not is_ready() then exit;

    i:=0;
    while i < 512 do begin
        // if not is_ready() then exit;

        data:= inw(ATA_PRIMARY_BASE + ATA_REG_DATA);

        buffer[i+1] := uint8($00ff and (data shr 8));
        buffer[i] := uint8($00ff and data);

        i:= i + 2;
    end;
end;

procedure writePIO28(drive : uint8; LBA : uint32; buffer : puint8);
var
    status : uint8;
    i: uint16;
    device: uint8;
begin 
    if not validate_28bit_address(LBA) then begin
        console.writestringln('IDE (writePIO28) ERROR: Invalid LBA!');
    end;

    //Add last 4 bits of LBA to device port
    if IDEDevices[drive].isMaster then begin
        device:= ATA_DEVICE_MASTER;
        device_select($E0 or ((LBA and $0F000000) shr 24)); //LBA primary master
    end
    else begin
        device:= ATA_DEVICE_SLAVE;
        device_select($F0 or ((LBA and $0F000000) shr 24)); //LBA primary slave
    end;

    no_interrupt(device);
    port_write(ATA_REG_ERROR, 0);
    port_write(ATA_REG_CONTROL, 0);

    //check if bus is floating
    status := port_read(ATA_REG_COMMAND);
    if status = $FF then exit;

    //Write sector count and LBA
    port_write(ATA_REG_SECCOUNT, 1);
    port_write(ATA_REG_LBA0, (LBA and $000000FF));
    port_write(ATA_REG_LBA1, (LBA and $0000FF00) shr 8);
    port_write(ATA_REG_LBA2, (LBA and $00FF0000) shr 16);

    //send write command
    port_write(ATA_REG_COMMAND, ATA_CMD_WRITE_PIO); 

    console.writestringln('ide write sttart');
    console.redrawWindows();

    //write data
    i:=0;
    while i < 512 do begin
        outw(ATA_PRIMARY_BASE + ATA_REG_DATA, uint16(buffer[i] or (buffer[i+1] shl 8)));
        i:= i + 2;
    end;

    console.writestringln('ise write stop');
    console.redrawWindows();

    //flush drive cache
    psleep(1);
    port_write(ATA_REG_COMMAND, ATA_CMD_CACHE_FLUSH);
    psleep(1);
    if not is_ready() then exit;

    console.writestringln('ide write end');
    console.redrawWindows();

end;

procedure read(device : PStorage_device; LBA : uint32; sectorCount : uint32; buffer : Puint32);
var
    i : uint16;
begin
    // for i:=0 to sectorCount-1 do begin
    //     readPIO28(device^.controllerId0, LBA, puint8(@buffer[512*i])); 
    // end;

    readPIO28(device^.controllerId0, LBA, puint8(buffer)); 

end;

procedure write(device : PStorage_device; LBA : uint32; sectorCount : uint32; buffer : Puint32);
var
    i : uint16;
begin
    // for i:=0 to sectorCount-1 do begin
    //     writePIO28(device^.controllerId0, LBA, puint8(@buffer[512*i]));
    // end;
     writePIO28(device^.controllerId0, LBA, puint8(buffer));
end;

end.