{ ************************************************
  * Asuro
  * Unit: Driver_Management
  * Description: Manages Driver Loading
  ************************************************
  * Author: K Morris
  * Contributors:
  ************************************************ }
unit drivermanagement;

interface

uses
    console, util, strings, lmemorymanager;

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

procedure register_driver(Driver_Name : PChar; DeviceID : PDeviceIdentifier; Load_Callback : TDriverLoadCallback);
procedure register_device(Device_Name : PChar; DeviceID : PDeviceIdentifier; ptr : void);

var
    Root : PDriverRegistration = nil;
    Dev  : PDeviceRegistration = nil;

implementation

function copy_identifier(DeviceID : PDeviceIdentifier) : PDeviceIdentifier;
var
    New_DevID : PDeviceIdentifier;
    root_ex, 
    param_ex, 
    new_ex: PDevEx;

begin
    New_DevID:= PDeviceIdentifier(kalloc(sizeof(TDeviceIdentifier)));
    New_DevID^.Bus:= DeviceID^.Bus;
    New_DevID^.id0:= DeviceID^.id0;
    New_DevID^.id1:= DeviceID^.id1;
    New_DevID^.id2:= DeviceID^.id2;
    New_DevID^.id3:= DeviceID^.id3;
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
end;

function identifiers_match(i1, i2 : PDeviceIdentifier) : boolean;
var
    ll1, ll2 : PDevEx;
    b1, b2 : boolean;

begin
    identifiers_match:= true;
    identifiers_match:= identifiers_match and ((i1^.Bus = i2^.Bus) OR (i1^.Bus = biANY) OR (i2^.Bus = biANY));
    identifiers_match:= identifiers_match and ((i1^.id0 = i2^.id0) OR (i1^.id0 = $FFFFFFFF) OR (i2^.id0 = $FFFFFFFF));
    identifiers_match:= identifiers_match and ((i1^.id1 = i2^.id1) OR (i1^.id1 = $FFFFFFFF) OR (i2^.id1 = $FFFFFFFF));
    identifiers_match:= identifiers_match and ((i1^.id2 = i2^.id2) OR (i1^.id2 = $FFFFFFFF) OR (i2^.id2 = $FFFFFFFF));
    identifiers_match:= identifiers_match and ((i1^.id3 = i2^.id3) OR (i1^.id3 = $FFFFFFFF) OR (i2^.id3 = $FFFFFFFF));
    ll1:= i1^.ex;
    ll2:= i2^.ex;
    while true do begin
        b1:= ll1 <> nil;
        b2:= ll2 <> nil;
        identifiers_match:= identifiers_match and (b1 = b2);
        if not (b1 and b2) then exit;
        if b1 = b2 then begin
            identifiers_match:= identifiers_match and ((ll1^.idN = ll2^.idN) OR (ll1^.idN = $FFFFFFFF) OR (ll2^.idN = $FFFFFFFF));    
        end else begin
            identifiers_match:= false;
            exit;
        end;
        ll1:= ll1^.ex;
        ll2:= ll2^.ex;
    end;
end;

procedure register_driver(Driver_Name : PChar; DeviceID : PDeviceIdentifier; Load_Callback : TDriverLoadCallback);
var
    NewReg : PDriverRegistration; 
    RegList : PDriverRegistration;

begin
    if DeviceID = nil then exit;
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
end;

procedure register_device(Device_Name : PChar; DeviceID : PDeviceIdentifier; ptr : void);
var
    drv : PDriverRegistration;
    new_dev : PDeviceRegistration;
    dev_list : PDeviceRegistration;

begin
    drv:= Root;
    new_dev:= PDeviceRegistration(kalloc(sizeof(TDeviceRegistration)));
    new_dev^.Device_Name:= stringCopy(Device_Name);
    new_dev^.Identifier:= copy_identifier(DeviceID);
    new_dev^.Driver_Loaded:= false;
    new_dev^.Driver:= nil;
    new_dev^.next:= nil;
    while drv <> nil do begin
        if identifiers_match(drv^.Identifier, DeviceID) then begin
            if drv^.Driver_Load(ptr) then begin
                drv^.Loaded:= true;
                new_dev^.Driver_Loaded:= true;
                new_dev^.Driver:= drv;
                exit;
            end;
        end;
        drv:= drv^.Next;
    end;
    if Dev = nil then begin
        Dev:= new_dev;
    end else begin
        dev_list:= Dev;
        While dev_list^.Next <> nil do begin
            dev_list:= dev_list^.Next;
        end;
        dev_list^.Next:= new_dev;
    end;
end;

end.