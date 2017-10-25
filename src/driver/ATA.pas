{ ************************************************
  * Asuro
  * Unit: Drivers/ATA
  * Description: ATA Driver
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
    intptr = ^uint32;

    ATA_Device = record 

    end;

var 
    //0 = primary, 1 = secondary
    dataPort         : array[0..3] of uint16;
    errorPort        : array[0..3] of uint8; 
    sectorCountPort  : array[0..3] of uint8;
    lbaLowPort       : array[0..3] of uint8;
    lbaMidPort       : array[0..3] of uint8;
    lbaHiPort        : array[0..3] of uint8;
    devicePort       : array[0..3] of uint8;
    commandPort      : array[0..3] of uint8;
    controlPort      : array[0..3] of uint8;

    bytes_per_sector : uint16 = 512;

    controller : TPCI_device;

procedure init();
procedure identify(drive : uint8; bus : uint8); 
procedure read28(sector : uint32);
procedure write28(sector : uint32; data : intptr; count : uint32);
procedure flush();

implementation

procedure init();
begin
    
    //controller := device;
    controller.address0 := $3F6;
    controller.address1 := $376;
    // 0x1f0, 0x170, 0x3F6, 0x376
    console.writehexln(controller.address0);
    dataPort[0] := controller.address0;
    errorPort[0] := controller.address0 + 1;
    sectorCountPort[0] := controller.address0 + 2;
    lbaLowPort[0] := controller.address0 + 3;
    lbaMidPort[0] := controller.address0 + 4;
    lbaHiPort[0] := controller.address0 + 5;
    devicePort[0] := controller.address0 + 6;
    commandPort[0] := controller.address0 + 7;
    controlPort[0] := controller.address1 + 2;

    console.writestringln('Checking for ATA devices:');

    identify($A0, $A0);
    identify($B0, $A0);
end;

procedure identify(drive : uint8; bus : uint8); 
var
    status : uint8;
    busNo : uint8;
    i : uint16;
    data : array[0..265] of uint16;
begin

    outb(controlPort[0], 2);

    busNo := 1;
    if bus = $A0 then busNo := 0;


    outb(devicePort[busNo], drive);
    outb(controlPort[busNo], 0);
    //psleep(1);

    outb(devicePort[busNo], drive);
    status := inb(commandPort[busNo]);

    if status = $FF then begin
        console.writestringln('No drives on bus');
        exit;
    end;

    outb(devicePort[busNo], drive);
    //psleep(1);
    outb(sectorCountPort[busNo], 0);
    //psleep(1);
    outb(lbaLowPort[busNo], 0);
    //psleep(1);
    outb(lbaMidPort[busNo], 0);
    //psleep(1);
    outb(lbaHiPort[busNo], 0);
    //psleep(1);

    outb(commandPort[busNo], $EC);
    //psleep(1);

    status := inb(commandPort[busNo]);

    if status = $0 then begin
        console.writestring('No drive found');
        exit;
    end;

    while (status and $80 = $80) and (status and $08 <> $08) do begin
        status := inb(commandPort[busNo]);
        console.writehexln(status);
    end;
    console.writehexln(status);
    console.writestringln('Drive found!');

end;

procedure read28(sector : uint32); begin
 end;

procedure write28(sector : uint32; data : intptr; count : uint32); begin
 end;

procedure flush(); begin
 end;


end.