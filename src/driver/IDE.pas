{ ************************************************
  * Asuro
  * Unit: Drivers/IDE
  * Description: IDE Driver
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }
unit IDE;

interface

uses
    util,
    PCI,
    console;

type 

var 
    SATA1 = uint32;
    SATA2 = uint32;
    SATA3 = uint32;
    SATA4 = uint32;
    BUS_MASTER = uint32;
    

procedure init(TPCI_Device : device);

begin
    
end;

implementation

procedure init(TPCI_Device : device) begin
    SATA1 = device.address0;
    SATA2 = device.address1;
    SATA3 = device.address2;
    SATA4 = device.address3;
    BUS_MASTER = device.address4;
end;

end.