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

{ ************************************************
  * Asuro
  * Unit: Drivers/AHCI
  * Description: AHCI SATA Driver
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit AHCI;

interface

uses 
    util,
    PCI,
    drivertypes,
    drivermanagement,
    lmemorymanager,
    console,
    vmemorymanager;

type

//Struct hell

    TFIS_Type = (
        REG_H2D = $27,
        REG_D2H = $34,
        DMA_ACT = $39,
        DMA_SETUP = $41,
        DATA = $46,
        BIST = $58,
        PIO_SETUP = $5F,
        DEV_BITS = $A0
    );

    PFIS_REG_H2D = ^TFIS_REG_H2D;
    TFIS_REG_H2D = bitpacked record
        fis_type     : uint8; 
        port_mult    : UBit4;
        rsv0         : UBit3;
        coc          : boolean;
        command      : uint8;
        feature_low  : uint8;
        lba0         : uint8;
        lba1         : uint8;
        lba2         : uint8;
        device       : uint8;
        lba3         : uint8;
        lba4         : uint8;
        lba5         : uint8;
        feature_high : uint8;
        count_low    : uint8;
        count_high   : uint8;
        icc          : uint8;
        control      : uint8;
        rsvl         : uint32;
    end;         
    
    TFIS_REG_D2H = bitpacked record
        fis_type     : uint8; 
        port_mult    : UBit4;
        rsv0         : UBit2;
        i            : boolean;
        rsvl         : boolean;
        status       : uint8;
        error        : uint8;
        lba0         : uint8;
        lba1         : uint8;
        lba2         : uint8;
        device       : uint8;
        lba3         : uint8;
        lba4         : uint8;
        lba5         : uint8;
        rsv2         : uint8;
        count_low    : uint8;
        count_high   : uint8;
        rsv3         : uint16;
        rsv4         : uint32;
    end;

    TFIS_Data = bitpacked record
        fis_type  : uint8;
        port_mult : UBit4;
        rsv0      : UBit4;
        rsv1      : uint16;
        data      : ^uint32;
    end;

    TFIS_PIO_Setup = bitpacked record
        fis_type : uint8;
        pmport   : UBit4;
        rsv0     : boolean;
        d        : boolean;
        i        : boolean;
        rsv1     : boolean;
        status   : uint8;
        error    : uint8;
        lba0     : uint8;
        lba1     : uint8;
        lba2     : uint8;
        device   : uint8;
        lba3     : uint8;
        lba4     : uint8;
        lba5     : uint8;
        rsv2     : uint8;
        countl   : uint8;
        counth   : uint8;
        rsv3     : uint8;
        e_status : uint8;
        tc       : uint16;
        rsv4     : uint16;
    end;

    // TFIS_DMA_Setup = bitpacked record
    // end;

    // THBA_Memory = bitpacked record
    // end;

    // THBA_Port = bitpacked record
    // end;

    // THBA_FIS = bitpacked record
    // end;

    PHBA_PORT = ^THBA_PORT;
    THBA_PORT = bitpacked record
        clb : uint32;
        clbu : uint32;
        fb : uint32;
        fbu : uint32;
        istat : uint32;
        ie : uint32;
        cmd : uint32;
        rsv0 : uint32;
        tfd : uint32;
        sig : uint32;
        ssts : uint32;
        sctl : uint32;
        serr : uint32;
        sact : uint32;
        ci : uint32;
        sntf : uint32;
        fbs : uint32;
        rsv1 : array[0..11] of uint32;
        vendor : array[0..4] of uint32;
    end; 

    THBA_MEM = bitpacked record 
        cap                 : uint32; //0
        global_host_control : uint32; //4
        interrupt_status    : uint32; //8
        port_implemented    : uint32; //c
        version             : uint32; //10
        ccc_control         : uint32; //14
        ccc_ports           : uint32; //18
        em_location         : uint32; //1c
        em_Control          : uint32; //20
        hcap2               : uint32; //24
        bohc                : uint32; //28
        rsv0                : array[0..210] of boolean;
        ports               : array[0..31] of THBA_Port;
    end;

    PHBA = ^THBA_MEM;

    PCMDHeader = ^ TCommand_Header;
    TCommand_Header = bitpacked record
        cfl    : ubit5;
        a      : boolean;
        w      : boolean;
        p      : boolean;
        r      : boolean;
        b      : boolean;
        c      : boolean;
        rsv0   : boolean;
        pmp    : ubit4;
        PRDTL  : uint16;
        PRDTBC : uint32;
        CTBA   : uint32;
        CTBAU  : uint32;
        rsv1   : array[0..3] of uint32;
    end;

    TPRD_Entry = bitpacked record
        data_base_address   : uint32;
        data_bade_address_U : uint32;
        rsv0                : uint32;
        data_byte_count     : ubit22;
        rsv1                : ubit9;
        interrupt_oc        : boolean;
    end;

    PCommand_Table = ^TCommand_Table;
    TCommand_Table = bitpacked record
        cfis : array[0..64] of uint8;
        acmd : array[0..16] of uint8;
        rsv  : array[0..48] of uint8;
        prdt : array[0..7] of TPRD_Entry;
    end;

    TSataDevice = record
        controller : uint8;
        port : uint8;
    end;

var
    //constants
    //SATA_SIG_ATA   := $101;
    //SATA_SIG_ATAPI := $EB140101;
    //STA_SIG_SEMB  := $C33C0101;
    //STAT_SIG_PM    := $96690101;
    AHCI_BASE: uint32 = $400000; //irrelivent

    //other 
    ahciControllers     : array[0.16] of PuInt32;
    ahciControllerCount : uint8 = 0;
    hba                 : array[0..16] of PHBA;

    sataDevices     : array[0..127] of TSataDevice;
    sataDeviceCount : uint8;

    

procedure init();
procedure check_ports(controller : uint8);
procedure enable_cmd(port : uint8);
procedure disable_cmd(port : uint8);
procedure port_rebase(port : uint8);
function load(ptr:void): boolean;
function read(port : uint8; startl : uint32; starth : uint32; count : uint32; buf : PuInt32) : boolean;
function write(port : uint8; startl : uint32; starth : uint32; count : uint32; buf : PuInt32) : boolean;
function find_cmd_slot(port : uint8) : uint32;

implementation 

procedure init();
var
    devID : TDeviceIdentifier;
begin
    console.writestringln('AHCI: Registering driver');
    devID.bus:= biPCI;
    devID.id0:= idANY;
    devID.id1:= $00000001;
    devID.id2:= $00000006;
    devID.id3:= $00000001;
    devID.id4:= idANY;
    devID.ex:= nil;
    drivermanagement.register_driver('AHCI Driver', @devID, @load);
end;

procedure load(ptr : void);
begin
    console.writestringln('AHCI: initilizing a new controller');
    ahciControllers[ahciControllerCount] := ptr;
    hba[ahciControllerCount] := PPCI_Device(ptr)^.address5;
    new_page_at_address(hba[ahciControllerCount]);

    //here would be any controller setup needed

    check_ports(ahciControllerCount);
    ahciControllerCount += 1;
    exit(true);
end;

procedure check_ports(controller : uint8);
var
    d : uint32 = 1;
    i : uint32;
begin
    for i:=0 to 31 do begin
        if (d > 0) and (hba[controller]^.port_implemented shr i) = 1 then begin
            if (hba[controller]^.ports[i].ssts shr 8) <> 1 and (hba[controller]^.ports[i].ssts and $0F) <> 3 then begin
                if hba[controller]^.ports[i].sig = 1 then begin
                    //device is sata
                    sataDevices[sataDeviceCount].controller := controller;
                    sataDevices[sataDeviceCount].port := i;
                    sataDeviceCount += 1;
                end;
                //TODO implement ATAPI
            end;
        end;
    end;
end;