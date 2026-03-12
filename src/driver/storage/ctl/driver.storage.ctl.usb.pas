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
    Driver->Bus->driver.bus.usb->USB_Storage - driver.bus.usb Mass Storage Class Driver (stub).

    Registers with driver.mgr as a driver.bus.usb class driver matching
    mass storage devices (class $08, subclass $06 SCSI, protocol $50 BBB).
    Currently a skeleton that recognises the device but performs no I/O —
    full Bulk-Only Transport support is planned.

    @author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.ctl.usb;

interface

uses
    boot.mgr,
    driver.mgr,
    memory.heap,
    driver.storage.types,
    io.syslog,
    debug.tracer,
    driver.bus.usb.core,
    driver.bus.usb.types,
    core.util, arch.x86.util;

procedure init;

implementation

{ ========================= Constants ========================= }

const
    USB_CLASS_MASS_STORAGE = $08;
    USB_SC_SCSI            = $06;   { SCSI transparent command set }
    USB_PROTO_BBB          = $50;   { Bulk-Only (BBB) transport }

{ ========================= Class driver callback ========================= }

{ Called by driver.mgr when a mass-storage interface is matched.
  For now we just log it. }
function load(ptr : void) : boolean;
begin
    push_trace('driver.storage.ctl.usb.load');
    io.syslog.logln('driver.bus.usb-Storage', 'Mass-storage device detected (stub - no I/O yet).');

    { TODO: read Max LUN, set up Bulk-Only endpoints, register with
      driver.storage.mgr via driver.storage.mgr.register_device. }

    load := true;
    pop_trace;
end;

{ ========================= Init ========================= }

procedure init;
var
    MSID : TDeviceIdentifier;
begin
    push_trace('driver.storage.ctl.usb.init');
    io.syslog.logln('driver.bus.usb-Storage', 'INIT BEGIN.');

    MSID.Bus := biUSB;
    MSID.id0 := idANY;                { Any VID:PID }
    MSID.id1 := $FFFFFFFF;            { Any device class }
    MSID.id2 := USB_CLASS_MASS_STORAGE;{ bInterfaceClass = $08 }
    MSID.id3 := USB_SC_SCSI;          { bInterfaceSubClass = $06 }
    MSID.id4 := USB_PROTO_BBB;        { bInterfaceProtocol = $50 }
    MSID.ex  := nil;

    driver.mgr.register_driver('driver.bus.usb Storage Driver', @MSID, @load);

    io.syslog.logln('driver.bus.usb-Storage', 'INIT END.');
    pop_trace;
end;

initialization
    boot.mgr.registerBoot('driver.storage.ctl.usb', @init, 'USB Mass Storage Driver', BOOT_MGR_BARRIER_DEVICE);

end.
