//  Copyright 2021 Aaron Hance
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
	Driver->Storage->driver.storage.ctl.ide->driver.storage.ctl.ide.types - driver.storage.ctl.ide device core.types and constants.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.ctl.ide.types;

interface

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
    ATA_CMD_READ_FPDMA_QUEUED  = $60;
    ATA_CMD_WRITE_PIO       = $30; 
    ATA_CMD_WRITE_PIO_EXT   = $34; 
    ATA_CMD_WRITE_DMA       = $CA; 
    ATA_CMD_WRITE_DMA_EXT   = $35; 
    ATA_CMD_WRITE_FPDMA_QUEUED = $61;
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
    ATA_REG_CONTROL    = $0C; //1FC on some systems, 3F6 on all
    ATA_REG_ALTSTATUS  = $0C;
    ATA_REG_DEVADDRESS = $0D; 

    ATA_DEVICE_MASTER = $A0;
    ATA_DEVICE_SLAVE = $B0;

    ATA_PRIMARY_BASE = $1F0;
    ATA_PRIMARY_BASE1 = $3F6;
    ATA_SECONDARY_BASE = $170; //todo check this
    ATA_SECONDARY_BASE1 = $376; //todo check this

    ATA_INTERRUPT_PRIMARY = $3F6;
    ATA_INTERRUPT_SECONDARY = $376;

type
    TPortMode = (P_READ, P_WRITE);

    TIdentResponse = array[0..255] of uint16;
    PIdentResponse = ^TIdentResponse;

    TIDE_Channel_Registers = record
        base    : uint16;
        ctrl    : uint16;
        bmide   : uint16;
        noInter : uint8;
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

    TIDE_Device = record
        exists       : boolean;
        isPrimary    : boolean;
        isMaster     : boolean;
        isATAPI      : boolean;
        status       : TIDE_Status;
        base         : uint16;
        blockSize    : uint32;
        info         : PIdentResponse;
    end;

    TIDE_PACKET = record
        command : uint8;
        lba     : uint32;
        count   : uint8;
        buffer  : puint16;
    end;


implementation
  
end.
