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
    dataPort         : array[0..1] of uint16;
    errorPort        : array[0..1] of uint8; 
    sectorCountPort  : array[0..1] of uint8;
    lbaLowPort       : array[0..1] of uint8;
    lbaMidPort       : array[0..1] of uint8;
    lbaHiPort        : array[0..1] of uint8;
    devicePort       : array[0..1] of uint8;
    commandPort      : array[0..1] of uint8;
    controlPort      : array[0..1] of uint8;

    bytes_per_sector : uint16 = 512;

    controller : TPCI_device;

procedure init(device : TPCI_device);
procedure identify(drive : uint8; bus : uint8); 
procedure read28(sector : uint32);
procedure write28(sector : uint32; data : intptr; count : uint32);
procedure flush();

implementation

procedure init(device : TPCI_device);
begin
    
    controller := device;
    controller.address0 := $1f0;
    // 0x1f0, 0x170
    console.writehexln(controller.address0);
    dataPort[0] := controller.address0;
    errorPort[0] := controller.address0 + 1;
    sectorCountPort[0] := controller.address0 + 2;
    lbaLowPort[0] := controller.address0 + 3;
    lbaMidPort[0] := controller.address0 + 4;
    lbaHiPort[0] := controller.address0 + 5;
    devicePort[0] := controller.address0 + 6;
    commandPort[0] := controller.address0 + 7;
    controlPort[0] := controller.address0 + $206;

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

    busNo := 0;
    if bus = $A0 then busNo := 0;

    outb(devicePort[busNo], drive);
    outb(controlPort[busNo], 0);
    outb(devicePort[busNo], bus);
    status := inb(commandPort[busNo]);

    if status <> $FF then begin
        outb(devicePort[busNo], drive);
        outb(sectorCountPort[busNo], 0);
        outb(lbaLowPort[busNo], 0);
        outb(lbaMidPort[busNo], 0);
        outb(lbaHiPort[busNo], 0);
        outb(commandPort[busNo], $EC);
        status := inb(commandPort[busNo]);

        if status = 0 then exit;

        while((status and $08 = 08) and (status and $01 <> 1)) do begin
            status := inb(commandPort[busNo])
        end; 
        status := inb(commandPort[busNo]);

        if status and $01 = 1 then begin
            console.writestringln('ATA DEVICE ERROR');
        end else begin
            for i:=0 to 265 do begin 
                data[i] := inw(dataPort[busNo]);
                console.writestringln(pchar(@data[i]));
                //console.writeint(data[i]);
                psleep(10);
             end;
         end;
        
    end else begin
        console.writestringln('no device');
    end;

end;

procedure read28(sector : uint32); begin
 end;

procedure write28(sector : uint32; data : intptr; count : uint32); begin
 end;

procedure flush(); begin
 end;


end.