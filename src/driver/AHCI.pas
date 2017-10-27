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
    drivertypes;

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

    // TFIS_PIO_Setup = bitpacked record
    // end;

    // TFIS_DMA_Setup = bitpacked record
    // end;

    // THBA_Memory = bitpacked record
    // end;

    // THBA_Port = bitpacked record
    // end;

    // THBA_FIS = bitpacked record
    // end;

var
    PCI_Devices : TDeviceArray;

procedure init();

implementation 

procedure init();
var
    count : uint16;
begin
    //PCI_Devices := PCI.getDeviceInfo(1, 6, @count);
end;

end.