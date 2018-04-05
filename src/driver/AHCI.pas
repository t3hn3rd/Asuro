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
    console;

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

    TCommand_Table = bitpacked record
        cfis : array[0..64] of uint8;
        acmd : array[0..16] of uint8;
        rsv  : array[0..48] of uint8;
        prdt : array[0..1] of TPRD_Entry;
    end;

var
    //constants
    //SATA_SIG_ATA   := $101;
    //SATA_SIG_ATAPI := $EB140101;
    //STA_SIG_SEMB  := $C33C0101;
    //STAT_SIG_PM    := $96690101;
    //other 
    ahciController     : PuInt32;
    hba                : THBAptr;

    sataStorageDevices     : array[0..31] of PuInt32;
    sataStorageDeviceCount : uint8;

    

procedure init();
procedure check_ports();
function load(ptr:void): boolean;

implementation 

procedure init();
var
    count : uint16;
begin
    console.writestringln('AHCI: STARTING INIT');
    //PCI_Devices := PCI.getDeviceInfo(1, 6, 0, count);
    drivermanagement.register_driver($010600, @load)
end;

function load(ptr : void) : boolean;
begin
    ahciController := ptr;
    hba := THBAptr(PPCI_Device(ahciController)^.address5);
    check_ports();
    load:= true;
    exit;
end;

procedure check_ports();
var
    d : uint32;
    i : uint32;
    ii : uint32;
    activePorts : array[0..32] of uint32;

begin
    d:= 1;
    for i:= 0 to 31 do begin
        if (d > 0) and (hba^.port_implemented <> 0) then begin // port connected
            if hba^.ports[i].ssts = 259 then begin // port in use and active
                if hba^.ports[i].sig = 1 then begin //device is sata
                    sataStorageDevices[sataStorageDeviceCount - 1] := @hba^.ports[i];
                    sataStorageDeviceCount += 1;
                end;
                //TODO implement other types
            end;
        end;
        d := d shl 1;
    end;
end;


end.