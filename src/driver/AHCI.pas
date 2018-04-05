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

    THBAptr = ^THBA_MEM;

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

var
    //constants
    //SATA_SIG_ATA   := $101;
    //SATA_SIG_ATAPI := $EB140101;
    //STA_SIG_SEMB  := $C33C0101;
    //STAT_SIG_PM    := $96690101;
    AHCI_BASE: uint32 = $400000;

    //other 
    ahciController     : PuInt32;
    hba                : THBAptr;

    sataStorageDevices     : array[0..31] of PuInt32;
    sataStorageDeviceCount : uint8;

    

procedure init();
procedure check_ports();
procedure enable_cmd(port : uint8);
procedure disable_cmd(port : uint8);
procedure port_rebase(port : uint8);
function load(ptr:void): boolean;
function read(port : uint8; startl : uint32; starth : uint32; count : uint32; buf : PuInt16) : boolean;
function write(port : uint8; startl : uint32; starth : uint32; count : uint32; buf : PuInt16) : boolean;
function find_cmd_slot(port : uint8) : uint32;

implementation 

procedure init();
var
    devID : TDeviceIdentifier;
begin
    console.writestringln('AHCI: STARTING INIT');
    devID.bus:= biPCI;
    devID.id0:= idANY;
    devID.id1:= $00000001;
    devID.id2:= $00000006;
    devID.id3:= $00000001;
    devID.ex:= nil;
    drivermanagement.register_driver('AHCI Controller', @devID, @load);
end;

function load(ptr : void) : boolean;
begin
    ahciController := ptr;
    hba := THBAptr(PPCI_Device(ahciController)^.address5);
    new_page_at_address(uint32(hba));
    check_ports();
    load:= true;
    exit;
end;

procedure check_ports();
var
    d : uint32;
    i : uint32;
    activePorts : array[0..32] of uint32;

begin
    d:= 1;
    for i:= 0 to 31 do begin
        if (d > 0) and (hba^.port_implemented <> 0) then begin // port connected
            if hba^.ports[i].ssts = 259 then begin // port in use and active
                if hba^.ports[i].sig = 1 then begin //device is sata
                    sataStorageDevices[sataStorageDeviceCount - 1] := @hba^.ports[i];
                    sataStorageDeviceCount += 1;
                    port_rebase(i);
                end;
                //TODO implement other types
            end;
        end;
        d := d shl 1;
    end;
end;

procedure enable_cmd(port : uint8);
begin
    while (hba^.ports[port].cmd and $8000) <> 0 do begin end;
    hba^.ports[port].cmd := hba^.ports[port].cmd or $0010;
    hba^.ports[port].cmd := hba^.ports[port].cmd or $0001;
end;

procedure disable_cmd(port : uint8);
begin 
    hba^.ports[port].cmd := hba^.ports[port].cmd and $0001;
    while (hba^.ports[port].cmd and $4000) <> 0 do begin end;
    hba^.ports[port].cmd := hba^.ports[port].cmd and $0010;
end;

procedure port_rebase(port : uint8);
var
    cmdHeader : PCMDHeader;
    i : uint16;
begin
    disable_cmd(port);
    hba^.ports[port].clb := AHCI_BASE + (port shl 10);
    hba^.ports[port].clbu := 0;
    memset(hba^.ports[port].clb, 0, 1024);

    hba^.ports[port].fb := AHCI_BASE + (32 shl 10) + (port shl 8);
    hba^.ports[port].fbu := 0;
    memset(hba^.ports[port].fb, 0, 256);

    cmdheader := PCMDHeader(hba^.ports[port].clb);
    for i:= 0 to 31 do begin
        cmdHeader[i].PRDTL := 8; // no of prdt entries per cmd table
        cmdheader[i].ctba := AHCI_BASE + (40 shl 10) + (port shl 13) + (i shl 8);
        cmdheader[i].CTBAU := 0;
        memset(cmdheader[i].ctba, 0, 256);
    end;
    enable_cmd(port);
end;

function read(port : uint8; startl : uint32; starth : uint32; count : uint32; buf : PuInt16) : boolean;
var
    pport : PHBA_PORT;
    slot : uint32;
    cmdHeader : PCMDHeader;
    cmdTable : PCommand_Table;
    cmdFis : PFIS_REG_H2D;
    i : uint32;
    spin : uint32 = 0;
begin
    console.writestringln('1');
    pport := @hba^.ports[port];
    new_page_at_address(uint32(pport));
    pport^.istat := $ffff;
    slot := find_cmd_slot(port);
    if slot = -1 then exit(false);

    console.writestringln('2');
    cmdHeader := @pport^.clb;
    new_page_at_address(uint32(cmdHeader));
    cmdHeader += slot;
    cmdHeader^.w := false;
    cmdHeader^.PRDTL := uint16(((count - 1) shr 4) + 1);

    console.writestringln('3');
    cmdTable := @cmdheader^.ctba;
    new_page_at_address(uint32(cmdTable));
    memset(uint32(cmdTable), 0, sizeof(TCommand_Table) + (cmdheader^.PRDTL-1) * sizeof(TPRD_Entry));

    console.writestringln('4');
    for i:= 0 to cmdHeader^.PRDTL do begin
        cmdTable^.prdt[i].data_base_address := uint32(buf);
        cmdTable^.prdt[i].data_byte_count := 8*1024-1;
        cmdTable^.prdt[i].interrupt_oc := true;
        buf += 4*1024;
        count -= 16;
    end;

    console.writestringln('5');
    cmdTable^.prdt[i].data_base_address := uint32(buf);
    cmdTable^.prdt[i].data_byte_count := (count shl 9)-1;
    cmdTable^.prdt[i].interrupt_oc := true;

    console.writestringln('6');
    //setup command
    cmdfis            := @cmdTable^.cfis;
    new_page_at_address(uint32(cmdfis));
    cmdfis^.coc       := true;
    cmdfis^.command   := $25;
    cmdfis^.lba0      := uint8(startl);
    cmdfis^.lba1      := uint8(startl shr 8);
    cmdfis^.lba2      := uint8(startl shr 16);
    cmdfis^.device    := 1 shl 6;
    cmdfis^.lba3      := uint8(startl shr 24);
    cmdfis^.lba4      := uint8(starth);
    cmdfis^.lba3      := uint8(starth shr 8);
    cmdfis^.count_low := count and $FF;
    cmdfis^.count_high:= (count shr 8) and $FF;

    console.writestringln('7');
    while (pport^.tfd and $88) and spin < 1000000 do begin
        spin += 1;
    end;

    console.writestringln('8');
    if spin = 1000000 then begin
        console.writestringln('AHCI controller: port is hung!');
        read:= false;
        exit;
    end;

    console.writestringln('9');
    pport^.ci := 1 shl slot;

    console.writestringln('10');
    while true do begin
        if(pport^.ci and (1 shl slot)) = (1 shl slot) then break;
        if(pport^.istat and (1 shl 30)) = (1 shl 30) then begin
            console.writestringln('AHCI controller: Disk read error!');
            read:= false;
            exit;
        end;
    end;

    console.writestringln('11');
    if(pport^.istat and (1 shl 30)) = (1 shl 30) then begin
        console.writestringln('AHCI controller: Disk read error!');
        read:= false;
        exit;
    end;

    console.writestringln('12');
    read:= true;
    exit;
end;

function write(port : uint8; startl : uint32; starth : uint32; count : uint32; buf : PuInt16) : boolean;
var
    pport : PHBA_PORT;
    slot : uint32;
    cmdHeader : PCMDHeader;
    cmdTable : PCommand_Table;
    cmdFis : PFIS_REG_H2D;
    i : uint32;
    spin : uint32 = 0;
begin
    console.writestringln('1');
    pport := @hba^.ports[port];
    new_page_at_address(uint32(pport));
    pport^.istat := $ffff;
    slot := find_cmd_slot(port);
    if slot = -1 then exit(false);

    console.writestringln('2');
    cmdHeader := @pport^.clb;
    new_page_at_address(uint32(cmdHeader));
    cmdHeader += slot;
    cmdHeader^.w := false;
    cmdHeader^.PRDTL := uint16(((count - 1) shr 4) + 1);

    console.writestringln('3');
    cmdTable := @cmdheader^.ctba;
    new_page_at_address(uint32(cmdTable));
    memset(uint32(cmdTable), 0, sizeof(TCommand_Table) + (cmdheader^.PRDTL-1) * sizeof(TPRD_Entry));

    console.writestringln('4');
    console.writestring('PRDTL: ');
    console.writeintln(cmdHeader^.PRDTL);
    //psleep(1000);
    for i:= 0 to cmdHeader^.PRDTL do begin
        console.writestringln('4.1');
        cmdTable^.prdt[i].data_base_address := uint32(buf);
        console.writestringln('4.2');
        cmdTable^.prdt[i].data_byte_count := 8*1024-1;
        console.writestringln('4.3');
        cmdTable^.prdt[i].interrupt_oc := true;
        console.writestringln('4.4');
        buf += 4*1024;
        console.writestringln('4.5');
        count -= 16;
        console.writestring('PRDTL: ');
        console.writeintln(cmdHeader^.PRDTL);
        console.writestring('i: ');
        console.writeintln(i);
        //psleep(1000);
    end;

    console.writestringln('5');
    cmdTable^.prdt[i].data_base_address := uint32(buf);
    cmdTable^.prdt[i].data_byte_count := (count shl 9)-1;
    cmdTable^.prdt[i].interrupt_oc := true;

    console.writestringln('6');
    cmdfis            := @cmdTable^.cfis;
    new_page_at_address(uint32(cmdfis));
    cmdfis^.coc       := true;
    cmdfis^.command   := $35;
    cmdfis^.lba0      := uint8(startl);
    cmdfis^.lba1      := uint8(startl shr 8);
    cmdfis^.lba2      := uint8(startl shr 16);
    cmdfis^.device    := 1 shl 6;
    cmdfis^.lba3      := uint8(startl shr 24);
    cmdfis^.lba4      := uint8(starth);
    cmdfis^.lba3      := uint8(starth shr 8);
    cmdfis^.count_low := count and $FF;
    cmdfis^.count_high:= (count shr 8) and $FF;

    console.writestringln('7');
    while (pport^.tfd and $88) and spin < 1000000 do begin
        spin += 1;
    end;

    console.writestringln('8');
    if spin = 1000000 then begin
        console.writestringln('AHCI controller: port is hung!');
        write:= false;
        exit;
    end;

    console.writestringln('9');
    pport^.ci := 1 shl slot;

    console.writestringln('10');
    while true do begin
        if(pport^.ci and (1 shl slot)) = (1 shl slot) then break;
        if(pport^.istat and (1 shl 30)) = (1 shl 30) then begin
            console.writestringln('AHCI controller: Disk write error!');
            write:= false;
            exit;
        end;
    end;

    console.writestringln('11');
    if(pport^.istat and (1 shl 30)) = (1 shl 30) then begin
        console.writestringln('AHCI controller: Disk write error!');
        write:= false;
        exit;
    end;

    console.writestringln('12');
    write:= true;
    exit;
end;

function find_cmd_slot(port : uint8) : uint32;
var
    slots : uint32;
    i     : uint32;
begin
    slots := hba^.ports[port].sact or hba^.ports[port].ci;
    for i:=0 to 31 do begin
        if (slots and 1) = 0 then begin
            exit(i);
        end;
        slots := slots shr 1;
    end;
    console.writestringln('AHCI Controller: Unable to find free command slots!');
    exit(-1);
end;

end.

