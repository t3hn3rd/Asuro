//  Copyright 2021 Kieron Morris
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
	DriverManagement - Driver Initialization & Management Interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit drivermanagement;

interface

uses
    console, util, strings, lmemorymanager, terminal, tracer;

const
    idANY = $FFFFFFFF;

type
    PDevEx = ^TDevEx;
    TDevEx = record
        idN : uInt32;
        ex  : PDevEx;
    end;

    TBusIdentifier = (biUnknown, biPCI, biUSB, bii2c, biPCIe, biANY);

    PDeviceIdentifier = ^TDeviceIdentifier;
    TDeviceIdentifier = record 
        Bus : TBusIdentifier;
        id0 : uInt32;
        id1 : uInt32;
        id2 : uInt32;
        id3 : uint32; 
        id4 : uint32;
        ex  : PDevEx;  
    end;

    TDriverLoadCallback = function(ptr : void) : boolean;

    PDriverRegistration = ^TDriverRegistration;
    TDriverRegistration = record
        Driver_Name : PChar;
        Identifier  : PDeviceIdentifier;
        Driver_Load : TDriverLoadCallback;
        Loaded      : Boolean;
        Next        : PDriverRegistration;
    end;

    PDeviceRegistration = ^TDeviceRegistration;
    TDeviceRegistration = record
        Device_Name   : PChar;
        Identifier    : PDeviceIdentifier;
        Driver_Loaded : Boolean;
        Driver        : PDriverRegistration;
        Next          : PDeviceRegistration;
    end;

procedure init;
procedure register_driver(Driver_Name : PChar; DeviceID : PDeviceIdentifier; Load_Callback : TDriverLoadCallback);
procedure register_driver_ex(Driver_Name : PChar; DeviceID : PDeviceIdentifier; Load_Callback : TDriverLoadCallback; force_load : boolean);
procedure register_device(Device_Name : PChar; DeviceID : PDeviceIdentifier; ptr : void);

var
    Root : PDriverRegistration = nil;
    Dev  : PDeviceRegistration = nil;

implementation

procedure writeBusType(Bus : TBusIdentifier; WND : HWND);
begin
    case Bus of
        biUnknown : console.writestringWND('Unknown', WND);
        biANY     : console.writestringWND('ANY', WND);
        bii2c     : console.writestringWND('i2c', WND);
        biPCI     : console.writestringWND('PCI', WND);
        biPCIe    : console.writestringWND('PCIe', WND);
        biUSB     : console.writestringWND('USB', WND);
    end;
end;

{ Terminal Commands }

procedure terminal_command_drivers(Params : PParamList);
var
    Drv : PDriverRegistration;
    ex  : PDevEx;
    i   : uint32;

begin
    push_trace('driver_management.terminal_command_drivers');
    Drv:= Root;
    i:= 1;
    while Drv <> nil do begin
        if Drv^.Loaded then begin
            console.writeintWND(i, getTerminalHWND);
            console.writestringWND(') ', getTerminalHWND);
            console.writestringWND(Drv^.Driver_Name, getTerminalHWND);
            console.writestringWND(' - Bus: ', getTerminalHWND);
            writeBusType(Drv^.Identifier^.Bus, getTerminalHWND);
            console.writestringlnWND(' ', getTerminalHWND);
            console.writestringWND('   [', getTerminalHWND);
            console.writeHexWND(Drv^.Identifier^.id0, getTerminalHWND);
            console.writestringWND('-', getTerminalHWND);
            console.writeHexWND(Drv^.Identifier^.id1, getTerminalHWND);
            console.writestringWND('-', getTerminalHWND);
            console.writeHexWND(Drv^.Identifier^.id2, getTerminalHWND);
            console.writestringWND('-', getTerminalHWND);
            console.writeHexWND(Drv^.Identifier^.id3, getTerminalHWND);
            console.writestringWND('-', getTerminalHWND);
            console.writeHexWND(Drv^.Identifier^.id4, getTerminalHWND);
            ex:= Drv^.Identifier^.ex;
            while ex <> nil do begin
                console.writestringWND('-', getTerminalHWND);
                console.writeHexWND(ex^.idN, getTerminalHWND);
                ex:= ex^.ex;   
            end;
            console.writestringlnWND(']', getTerminalHWND);
            i:= i + 1;
        end;
        Drv:= Drv^.Next;
    end;
    pop_trace;
end;

procedure terminal_command_driversex(Params : PParamList);
var
    Drv : PDriverRegistration;
    ex  : PDevEx;
    i   : uint32;

begin
    push_trace('driver_management.terminal_command_driversex');
    Drv:= Root;
    i:= 1;
    while Drv <> nil do begin
        console.writeintWND(i, getTerminalHWND);
        console.writestringWND(') ', getTerminalHWND);
        console.writestringWND(Drv^.Driver_Name, getTerminalHWND);
        console.writestringWND(' - Bus: ', getTerminalHWND);
        writeBusType(Drv^.Identifier^.Bus, getTerminalHWND);
        console.writestringWND(' - Loaded: ', getTerminalHWND);
        if Drv^.Loaded then console.writestringlnWND('true', getTerminalHWND) else console.writestringlnWND('false', getTerminalHWND);
        console.writestringWND('   [', getTerminalHWND);
        console.writeHexWND(Drv^.Identifier^.id0, getTerminalHWND);
        console.writestringWND('-', getTerminalHWND);
        console.writeHexWND(Drv^.Identifier^.id1, getTerminalHWND);
        console.writestringWND('-', getTerminalHWND);
        console.writeHexWND(Drv^.Identifier^.id2, getTerminalHWND);
        console.writestringWND('-', getTerminalHWND);
        console.writeHexWND(Drv^.Identifier^.id3, getTerminalHWND);
        console.writestringWND('-', getTerminalHWND);
        console.writeHexWND(Drv^.Identifier^.id4, getTerminalHWND);
        ex:= Drv^.Identifier^.ex;
        while ex <> nil do begin
            console.writestringWND('-', getTerminalHWND);
            console.writeHexWND(ex^.idN, getTerminalHWND);
            ex:= ex^.ex;   
        end;
        console.writestringlnWND(']', getTerminalHWND);
        i:= i + 1;
        Drv:= Drv^.Next;
    end;
    pop_trace;
end;

procedure terminal_command_devices(Params : PParamList);
var
    Dv : PDeviceRegistration;
    ex : PDevEx;
    i  : uint32;

begin
    push_trace('driver_management.terminal_command_devices');
    Dv:= Dev;
    i:= 1;
    while Dv <> nil do begin
        console.writeintWND(i, getTerminalHWND);
        console.writestringWND(') ', getTerminalHWND);
        console.writestringWND(Dv^.Device_Name, getTerminalHWND);
        console.writestringWND(' - Bus: ', getTerminalHWND);
        writeBusType(Dv^.Identifier^.Bus, getTerminalHWND);
        console.writestringlnWND(' ', getTerminalHWND);
        console.writestringWND('   [', getTerminalHWND);
        console.writeHexWND(Dv^.Identifier^.id0, getTerminalHWND);
        console.writestringWND('-', getTerminalHWND);
        console.writeHexWND(Dv^.Identifier^.id1, getTerminalHWND);
        console.writestringWND('-', getTerminalHWND);
        console.writeHexWND(Dv^.Identifier^.id2, getTerminalHWND);
        console.writestringWND('-', getTerminalHWND);
        console.writeHexWND(Dv^.Identifier^.id3, getTerminalHWND);
        console.writestringWND('-', getTerminalHWND);
        console.writeHexWND(Dv^.Identifier^.id4, getTerminalHWND);
        ex:= Dv^.Identifier^.ex;
        while ex <> nil do begin
            console.writestringWND('-', getTerminalHWND);
            console.writeHexWND(ex^.idN, getTerminalHWND);
            ex:= ex^.ex;   
        end;
        console.writestringlnWND(']', getTerminalHWND);
        if Dv^.Driver_Loaded then begin
            console.writestringWND('   Driver Loaded: ', getTerminalHWND);
            if Dv^.Driver <> nil then begin
                console.writestringlnWND(Dv^.Driver^.Driver_Name, getTerminalHWND);
            end else begin
                console.writestringlnWND('Unknown', getTerminalHWND)
            end;
        end;
        i:= i + 1;
        Dv:= Dv^.Next; 
    end;
    pop_trace;
end;

procedure terminal_command_dev(Params : PParamList);
var
    p1 : pchar;

begin
    if paramCount(Params) > 0 then begin
        p1:= getParam(0, Params);
        if StringEquals(p1, 'drivers') then begin
            terminal_command_drivers(Params);
        end;
        if StringEquals(p1, 'devices') then begin
            terminal_command_devices(Params);
        end;
        if StringEquals(p1, 'driverex') then begin
            terminal_command_driversex(Params);
        end;    
    end else begin
        writeStringlnWND('Driver Management Interface', getTerminalHWND);
        writeStringlnWND(' ', getTerminalHWND);
        writeStringlnWND('An interface to the drivermanagement portion of the kernel.', getTerminalHWND);
        writeStringlnWND(' ', getTerminalHWND);
        writeStringlnWND('Usage: ', getTerminalHWND);
        writeStringlnWND('      dev drivers  - Print a list of loaded drivers.', getTerminalHWND);
        writeStringlnWND('      dev devices  - Print a list of registered devices.', getTerminalHWND);
        writeStringlnWND('      dev driverex - Print a list of all available drivers.', getTerminalHWND);
        writeStringlnWND(' ', getTerminalHWND)
    end;
end;

{ Main Functions }

function copy_identifier(DeviceID : PDeviceIdentifier) : PDeviceIdentifier;
var
    New_DevID : PDeviceIdentifier;
    root_ex, 
    param_ex, 
    new_ex: PDevEx;

begin
    push_trace('driver_management.copy_identifier');
    New_DevID:= PDeviceIdentifier(kalloc(sizeof(TDeviceIdentifier)));
    New_DevID^.Bus:= DeviceID^.Bus;
    New_DevID^.id0:= DeviceID^.id0;
    New_DevID^.id1:= DeviceID^.id1;
    New_DevID^.id2:= DeviceID^.id2;
    New_DevID^.id3:= DeviceID^.id3;
    New_DevID^.id4:= DeviceID^.id4;
    root_ex:= nil;
    if DeviceID^.ex <> nil then begin
        root_ex:= PDevEx(kalloc(sizeof(TDevEx)));
        param_ex:= DeviceID^.ex;
        new_ex:= root_ex;
        new_ex^.idN:= param_ex^.idN;
        new_ex^.ex:= nil;
        param_ex:= param_ex^.ex;
        while param_ex <> nil do begin
            new_ex^.ex:= PDevEx(kalloc(sizeof(TDevEx)));
            new_ex:= new_ex^.ex;
            new_ex^.idN:= param_ex^.idN;
            param_ex:= param_ex^.ex;
        end;
    end;
    New_DevID^.ex:= root_ex;
    copy_identifier:= New_DevID;
    pop_trace;
end;

function identifiers_match(i1, i2 : PDeviceIdentifier) : boolean;
var
    ll1, ll2 : PDevEx;
    b1, b2 : boolean;

begin
    push_trace('driver_management.identifiers_match');
    identifiers_match:= true;
    identifiers_match:= identifiers_match and ((i1^.Bus = i2^.Bus) OR (i1^.Bus = biANY) OR (i2^.Bus = biANY));
    identifiers_match:= identifiers_match and ((i1^.id0 = i2^.id0) OR (i1^.id0 = $FFFFFFFF) OR (i2^.id0 = $FFFFFFFF));
    identifiers_match:= identifiers_match and ((i1^.id1 = i2^.id1) OR (i1^.id1 = $FFFFFFFF) OR (i2^.id1 = $FFFFFFFF));
    identifiers_match:= identifiers_match and ((i1^.id2 = i2^.id2) OR (i1^.id2 = $FFFFFFFF) OR (i2^.id2 = $FFFFFFFF));
    identifiers_match:= identifiers_match and ((i1^.id3 = i2^.id3) OR (i1^.id3 = $FFFFFFFF) OR (i2^.id3 = $FFFFFFFF));
    identifiers_match:= identifiers_match and ((i1^.id4 = i2^.id4) OR (i1^.id4 = $FFFFFFFF) OR (i2^.id4 = $FFFFFFFF));
    ll1:= i1^.ex;
    ll2:= i2^.ex;
    while true do begin
        b1:= ll1 <> nil;
        b2:= ll2 <> nil;
        identifiers_match:= identifiers_match and (b1 = b2);
        if not (b1 and b2) then begin
            break;
        end; 
        if b1 = b2 then begin
            identifiers_match:= identifiers_match and ((ll1^.idN = ll2^.idN) OR (ll1^.idN = $FFFFFFFF) OR (ll2^.idN = $FFFFFFFF));    
        end else begin
            identifiers_match:= false;
            break;
        end;
        ll1:= ll1^.ex;
        ll2:= ll2^.ex;
    end;
    pop_trace;
end;

procedure init;
begin
    push_trace('driver_management.init');
    terminal.registerCommand('DEV', @terminal_command_dev, 'Driver Management Interface.');
    //terminal.registerCommand('DRIVERSEX', @terminal_command_driversex, 'List all available drivers.');
    //terminal.registerCommand('DRIVERS', @terminal_command_drivers, 'List loaded drivers.');
    //terminal.registerCommand('DEVICES', @terminal_command_devices, 'List devices.');
    pop_trace;
end;

procedure register_driver(Driver_Name : PChar; DeviceID : PDeviceIdentifier; Load_Callback : TDriverLoadCallback);
begin
    push_trace('driver_management.register_driver');
    register_driver_ex(Driver_Name, DeviceID, Load_Callback, false);
    pop_trace;
end;

procedure register_driver_ex(Driver_Name : PChar; DeviceID : PDeviceIdentifier; Load_Callback : TDriverLoadCallback; force_load : boolean);
var
    NewReg : PDriverRegistration; 
    RegList : PDriverRegistration;

begin
    push_trace('driver_management.register_driver_ex');
    if DeviceID <> nil then begin;
        NewReg:= PDriverRegistration(kalloc(sizeof(TDriverRegistration)));
        NewReg^.Driver_Name:= stringCopy(Driver_Name);
        NewReg^.Identifier:= copy_identifier(DeviceID);
        NewReg^.Loaded:= false;
        NewReg^.Driver_Load:= Load_Callback;
        NewReg^.Next:= nil;
        if Root = nil then begin
            Root:= NewReg;
        end else begin
            RegList:= Root;
            While RegList^.Next <> nil do begin
                RegList:= RegList^.Next;
            end;
            RegList^.Next:= NewReg;
        end;
        console.output('Driver Management', 'New Driver Registered: ');
        console.writestringln(NewReg^.Driver_Name);
        if force_load then begin
            console.output('Driver Management', 'Driver (');
            console.writestring(NewReg^.Driver_Name);
            console.writestringln(') forced to load.');
            NewReg^.Loaded:= True;
            NewReg^.Driver_Load(nil);
        end;
    end;
    pop_trace;
end;

procedure register_device(Device_Name : PChar; DeviceID : PDeviceIdentifier; ptr : void);
var
    drv : PDriverRegistration;
    new_dev : PDeviceRegistration;
    dev_list : PDeviceRegistration;

begin
    push_trace('driver_management.register_device');
    drv:= Root;
    new_dev:= PDeviceRegistration(kalloc(sizeof(TDeviceRegistration)));
    new_dev^.Device_Name:= stringCopy(Device_Name);
    new_dev^.Identifier:= copy_identifier(DeviceID);
    new_dev^.Driver_Loaded:= false;
    new_dev^.Driver:= nil;
    new_dev^.next:= nil;
    if Dev = nil then begin
        Dev:= new_dev;
    end else begin    
        dev_list:= Dev;
        While dev_list^.Next <> nil do begin
            dev_list:= dev_list^.Next;
        end;
        dev_list^.Next:= new_dev;
    end;
    console.output('Driver Management', 'New Device Registered: ');
    console.writestringln(new_dev^.Device_Name);
    while drv <> nil do begin
        if identifiers_match(drv^.Identifier, DeviceID) then begin
            console.output('Driver Management', 'Device/Driver Match: ');
            console.writestring(new_dev^.Device_Name);
            console.writestring('->');
            console.writestringln(drv^.Driver_Name);
            if drv^.Driver_Load(ptr) then begin
                console.output('Driver Management', 'Driver (');
                console.writestring(drv^.Driver_Name);
                console.writestringln(') successfully loaded.');
                drv^.Loaded:= true;
                new_dev^.Driver_Loaded:= true;
                new_dev^.Driver:= drv;
                break;
            end;
        end;
        drv:= drv^.Next;
    end;
    pop_trace;
end;

end.