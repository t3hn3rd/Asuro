{ ************************************************
  * Asuro
  * Unit: Drivers/storage/IDE
  * Description: IDE ATA Driver
  * 
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }
unit ATA;

interface

uses
    util,
    drivertypes,
    console,
    terminal,
    isr76,
    drivermanagment,
    vmemorymanager,
    util;

type 

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
        signature    : uint16;
        capabilities : uint16;
        commandSets  : uint32;
        size         : uint32;
        model        : array[0..40] of uint8;
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
    controller : TPCI_Device;

    bar0 : uint32;
    bar1 : uint32;
    bar2 : uint32;
    bar3 : uint32;
    bar4 : uint32;

    IDEDevices : array[0..3] of TIDE_Device;

procedure init;
function load(ptr : void) : boolean;

implementation 

procedure init;  
var
    devID : PDeviceIdentifier;
begin
    console.writestringln('IDE ATA Driver: Init()');
    devID.bus:= biPCI;
    devID.id0:= idANY;
    devID.id1:= $00000001;
    devID.id2:= $00000001;
    devID.id3:= idANY;
    devID.id4:= idANY;
    devID.ex:= nil;
    drivermanagment.register_driver('IDE ATA Driver', @devID, @load);
end;

function load(ptr : void) : boolean;
begin
    controller := PPCI_Device(ptr);

    bar0 := controller^.address0;
    bar1 := controller^.address1;
    bar2 := controller^.address2;
    bar3 := controller^.address3;
    bar4 := controller^.address4;

    //setup channels
end;


end.