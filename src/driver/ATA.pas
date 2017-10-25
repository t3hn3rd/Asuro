{ ************************************************
  * Asuro
  * Unit: Drivers/ATA
  * Description: ATA DMA Driver
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
    terminal;

type 

    charptr = ^char;

    ATA_Device = record 
        primary : boolean;
        Command_Register : uint32;
        Status_Register  : uint32;
        PRDT_Address_Reg : uint32;
    end;

    Physical_Region_Descriptor = bitpacked record 
        empty0       : 0..1;
        MRPB_Address : 1..32;
        Byte_Count   : 32..47;
        empty1       : 47..63;
        EOT          : 63..64;
        empty2       : 64..65;
    end;

    ATA_Command_Buffer bitpacked record
        start_stop_bit : 0..1;
        read_write_bit : 3..4;
    end;

var 
    devices : array[0..4] of ATA_Device;
    PRG_Table : array[0..10] of Physical_Region_Descriptor; // up 64K r/w each, upto 8000 supported per table.
    controller : TPCI_device;

procedure init(_controller : TPCI_device);

implementation

procedure init(_controller : TPCI_device);
begin
    controller := _controller;
    devices[0].primary := true;
    devices[0].Command_Register := controller.address4;
    devices[0].Status_Register := controller.address4 + 2;
    devices[0].PRDT_Address_Reg := controller.address4 + 4;

end;


end.