//  Copyright 2021 Aaron Hance
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
    Driver->Bus->USB->USB_Storage - USB Mass Storage Class Driver (stub).

    Registers with drivermanagement as a USB class driver matching
    mass storage devices (class $08, subclass $06 SCSI, protocol $50 BBB).
    Currently a skeleton that recognises the device but performs no I/O —
    full Bulk-Only Transport support is planned.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit usb_storage;

interface

uses
    drivermanagement,
    lmemorymanager,
    storagetypes,
    syslog,
    tracer,
    usbcore,
    usbtypes,
    util;

procedure init;

implementation

{ ========================= Constants ========================= }

const
    USB_CLASS_MASS_STORAGE = $08;
    USB_SC_SCSI            = $06;   { SCSI transparent command set }
    USB_PROTO_BBB          = $50;   { Bulk-Only (BBB) transport }

{ ========================= Class driver callback ========================= }

{ Called by drivermanagement when a mass-storage interface is matched.
  For now we just log it. }
function load(ptr : void) : boolean;
begin
    push_trace('usb_storage.load');
    syslog.logln('USB-Storage', 'Mass-storage device detected (stub - no I/O yet).');

    { TODO: read Max LUN, set up Bulk-Only endpoints, register with
      storagemanager via storagemanager.register_device. }

    load := true;
    pop_trace;
end;

{ ========================= Init ========================= }

procedure init;
var
    MSID : TDeviceIdentifier;
begin
    push_trace('usb_storage.init');
    syslog.logln('USB-Storage', 'INIT BEGIN.');

    MSID.Bus := biUSB;
    MSID.id0 := idANY;                { Any VID:PID }
    MSID.id1 := $FFFFFFFF;            { Any device class }
    MSID.id2 := USB_CLASS_MASS_STORAGE;{ bInterfaceClass = $08 }
    MSID.id3 := USB_SC_SCSI;          { bInterfaceSubClass = $06 }
    MSID.id4 := USB_PROTO_BBB;        { bInterfaceProtocol = $50 }
    MSID.ex  := nil;

    drivermanagement.register_driver('USB Storage Driver', @MSID, @load);

    syslog.logln('USB-Storage', 'INIT END.');
    pop_trace;
end;

end.
