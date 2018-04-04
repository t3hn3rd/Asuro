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
    util, strings;

type
    PDevEx = ^TDevEx;
    TDevEx = record
        idN : uInt32;
        ex  : PDevEx;
    end;

    TBusIdentifier = (biUnknown, biPCI, biUSB, bii2c, biPCIe);

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
        Identifier  : TDeviceIdentifier;
        Driver_Load : TDriverLoadCallback;
        Loaded      : Boolean;
        Next        : PDriverRegistration;
    end;

procedure register_driver(DeviceID : PDeviceIdentifier; Load_Callback : TDriverLoadCallback);
procedure register_device(DeviceID : PDeviceIdentifier);

var
    Root : PDriverRegistration = nil;

implementation

procedure register_driver(DeviceID : PDeviceIdentifier; Load_Callback : TDriverLoadCallback);
begin
    
end;

procedure register_device(DeviceID : PDeviceIdentifier);
begin

end;

end.