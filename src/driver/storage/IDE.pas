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
    isr76,
    drivermanagement,
    vmemorymanager,
    lmemorymanager,
    storagemanagement;

type 
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
    ATA_REG_SECCOUNT0  = $02;
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

var
    controller : PPCI_Device;

    bar0 : uint32;
    bar1 : uint32;
    bar4 : uint32;

    IDEDevices : array[0..3] of TIDE_Device;

    buffer : Puint32;

procedure init();
function load(ptr : void) : boolean;
function identify_device(bus : uint8; drive : uint8) : TIdentResponse;
procedure readPIO28(drive : uint8; LBA : uint32; sectorCount : uint8; buffer : puint32);
procedure writePIO28(drive : uint8; LBA : uint32; sectorCount : uint8; buffer : Puint32);
//read/write must be capable of reading/writting any amknt of data upto disk size

implementation 

procedure test_command(params : PParamList);
var
    secotrs : uint32;
    cpacityMB : uint32;
    buffer : puint32;
    i : uint8;
begin
    secotrs := IDEDevices[0].info[60];
    secotrs := secotrs or (IDEDevices[0].info[61] shl 16);

    cpacityMB :=  (secotrs * 512) DIV 1000 DIV 1000;

    console.writestring('HHD_Primary_MASTER -');
    console.writestring(' Capacity: ');
    console.writeint(cpacityMB);
    console.writestringln('MB');

    buffer := puint32(kalloc(1024));
    //buffer^:= secotrs;

    for i:=0 to 20 do begin
        puint32(buffer + (i div 2))^:= $10010110;
    end;

    writePIO28(0, 2, 1, buffer);
    //buffer^:= $FFFF;
    for i:=0 to 20 do begin
        puint32(buffer + (i div 2))^:= $FFFFFFFF;
    end;
    
    readPIO28(0, 2, 1, buffer);

    for i:=0 to 20 do begin
        if puint32(buffer + (i div 2))^ <> $10010110 then begin
            console.writestringln('Tests failed!');
            exit;
       end;
    end;

   // if uint32(buffer^) = secotrs then begin
        console.writestringln('Tests successful!');
    // end
    // else begin
    //     console.writestringln('Tests failed!');
    //     console.writehexln($01101001);
    //     console.writehexln(uint32(buffer^));
    // end;
end;

procedure init();  
var
    devID : TDeviceIdentifier;
begin
    console.writestringln('IDE ATA Driver: Init()');
    devID.bus:= biPCI;
    devID.id0:= idANY;
    devID.id1:= $00000001;
    devID.id2:= $00000001;
    devID.id3:= idANY;
    devID.id4:= idANY;
    devID.ex:= nil;
    drivermanagement.register_driver('IDE ATA Driver', @devID, @load);
    terminal.registerCommand('IDE', @test_command, 'TEST IDE DRIVER');
    buffer := Puint32(kalloc(1024*2));
end;

function load(ptr : void) : boolean;
var
    storageDevice : TStorage_Device;
    storageDevice1 : TStorage_Device;
begin
    //controller := PPCI_Device(ptr);


    //check if bus is floating and identify device
    if inb($1F7) <> $FF then begin
        outb($3F6, inb($3f6) or (1 shl 1)); // disable interrupts
        IDEDevices[0].isMaster:= true;
        IDEDevices[0].info := identify_device(0, $A0);

        storageDevice.controller := ControllerIDE;
        storageDevice.controllerId0:= 0;
        storageDevice.maxSectorCount:= (IDEDevices[0].info[60] or (IDEDevices[0].info[61] shl 16) ); //LBA28 SATA
        storageDevice.sectorSize:= 512;
        if storageDevice.maxSectorCount <> 0 then begin
            IDEDevices[0].exists:= true;
            storagemanagement.register_device(@storageDevice);
        end;
    end;

    if inb($1F7) <> $FF then begin
        IDEDevices[1].isMaster:= false;
        IDEDevices[1].info := identify_device(0, $B0);

        storageDevice1.controller := ControllerIDE;
        storageDevice1.controllerId0:= 0;
        storageDevice1.maxSectorCount:= (IDEDevices[1].info[60] or (IDEDevices[1].info[61] shl 16) ); //LBA28 SATA
        storageDevice1.sectorSize:= 512;
        if storageDevice1.maxSectorCount <> 0 then begin
            IDEDevices[1].exists:= true;
            storagemanagement.register_device(@storageDevice1);
        end;
    end 

end;

function identify_device(bus : uint8; drive : uint8) : TIdentResponse;
var 
    i : uint8;
    identResponse : TIdentResponse;
    t : uint32 = 0;
begin
    if bus = 0 then begin
        outb($1F6, drive); //drive select

        outw($1F2, 0); //clear sector count and lba
        outw($1F3, 0);
        outw($1F4, 0);
        outw($1F5, 0); 

        outw($1F7, ATA_CMD_IDENTIFY); //send identify command
            console.writeint(1);

        while true do begin
            if (inw($1f7) and (1 shl 7)) = 0 then break; //Wait until drive not busy 
        end;

        while true do begin
            if (inw($1f7) and (1 shl 3)) <> 0 then break;
            if (inw($1F7) and 1) <> 0 then exit; //drive error
            if t > 100000 then exit; //todo return false
            t +=1;
        end;

        for i:=0 to 254 do begin
            identResponse[i] := inw($1F0); //read all bits
        end;

        identify_device:= identResponse;
        exit;
    end; 
end;

procedure writePIO28(drive : uint8; LBA : uint32; sectorCount : uint8; buffer : Puint32);
var
    i : uint8;
    ii : uint8;
    iii : uint32;
begin 
    if IDEDevices[drive].isMaster then begin
        outb($1F7, $E0 or ((LBA shr 24) and $0F)); //LBA command primary master
    end
    else begin
        outb($1F7, $F0 or ((LBA shr 24) and $0F)); //LBA command primary slave
    end;

    outb($1F2, sectorCount);
    outb($1F3, LBA);
    outb($1F4, LBA shr 8);
    outb($1F5, LBA shr 16);
    outb($1F7, $30); //write command

    for i:=0 to sectorCount do begin
        
        //poll status
        while true do if (inw($1f7) and (1 shl 7)) = 0 then break; //Wait until drive not busy 

        while true do begin
            if (inw($1f7) and (1 shl 3)) <> 0 then break;
            if (inw($1F7) and 1) <> 0 then begin
                console.writestringln('write error');
                exit;
            end; //drive error
        end;

        for ii:=0 to 127 do begin //read data
            outw($1F0, Puint32(buffer + ((i * 512) + (ii * 16) DIV 32) )^);
            while true do if (inw($1f7) and (1 shl 7)) = 0 then break; //Wait until drive not busy 
            outb($1F7, $E7);
            if ii <> 127 then begin
                outw($1F0, Puint32(buffer + ((i * 512) + (ii * 16) DIV 32) )^ shr 16);
                while true do if (inw($1f7) and (1 shl 7)) = 0 then break; //Wait until drive not busy 
                outb($1F7, $E7);
            end;

        end;
    end;
end;

procedure readPIO28(drive : uint8; LBA : uint32; sectorCount : uint8; buffer : puint32);
var
    i : uint8;
    ii : uint8;
    iii : uint32;
begin 
    if IDEDevices[drive].isMaster then begin
        outb($1F7, $E0 or ((LBA shr 24) and $0F)); //read command primary master
    end
    else begin
        outb($1F7, $F0 or ((LBA shr 24) and $0F)); //read command primary slave
    end;

    outb($1F2, sectorCount);
    outb($1F3, LBA);
    outb($1F4, LBA shr 8);
    outb($1F5, LBA shr 16);
    outb($1F7, $20); //read command

    for i:=0 to sectorCount do begin

        //poll status
        while true do if (inw($1f7) and (1 shl 7)) = 0 then break; //Wait until drive not busy 

        while true do begin
            if (inw($1f7) and (1 shl 3)) <> 0 then break;
            if (inw($1F7) and 1) <> 0 then begin
                console.writestringln('IDE read ERROR');
                exit;
            end; //drive error
        end;

        for ii:=0 to 127 do begin //read data
            Puint32(buffer + ((i * 512) + (ii * 16) DIV 32))^ := uint32(inw($1F0)); //wrong
            for iii:=0 to 1000 do if(ii = iii) then begin  end;
            if ii <> 127 then begin
                Puint32(buffer + ((i * 512) + (ii * 16) DIV 32))^ := ((uint32(inw($1F0)) shl 16) or Puint32(buffer + ((i * 512) + (ii * 16) DIV 32))^); //wrong
                for iii:=0 to 1000 do if(ii = iii) then begin  end
            end;
        end;
    end;
end;

procedure readPIOPI(drive : uint8; LBA : uint32; buffer : Puint32);
var
    i : uint16;
begin 
    if IDEDevices[drive].isMaster then begin
        outb($1F7, $E0 or ((LBA shr 24) and $0F)); // command primary master
    end
    else begin
        outb($1F7, $F0 or ((LBA shr 24) and $0F)); // command primary slave
    end;

    outb($1F2, 1);
    outb($1F3, LBA);
    outb($1F4, LBA shr 8);
    outb($1F5, LBA shr 16);
    outb($1F7, ATAPI_CMD_READ); //read command

    //poll status
    while true do if (inw($1f7) and (1 shl 7)) = 0 then break; //Wait until drive not busy 

    while true do begin
        if (inw($1f7) and (1 shl 3)) <> 0 then break;
        if (inw($1F7) and 1) <> 0 then begin
            console.writestringln('IDE read ERROR');
            exit;
        end; //drive error
    end;

    // for i:=0 to 1023 do begin
    //         Puint32(buffer + (i * 1))^ := inw($1F0);
    // end;

end;

end.