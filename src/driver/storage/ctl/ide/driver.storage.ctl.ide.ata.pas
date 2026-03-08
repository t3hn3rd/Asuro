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
	Drivers->Storage->ATA - ATA Driver.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.ctl.ide.ata;

interface

uses
    console,
    driver.mgr,
    driver.types,
    driver.storage.ctl.ide.types,
    memory.heap,
    driver.storage.types,
    core.strings,
    terminal,
    debug.tracer,
    core.util, arch.x86.util,
    arch.x86.memory.virtual;

var

    test : uint32;

    function identify_device(var device : TIDE_Device) : Boolean;
    function read_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
    function write_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;


implementation
uses
    driver.storage.ctl.ide;


    procedure outb(port : uint16; value : uint8); 
    begin
        arch.x86.util.outb(port, value);
        psleep(1);
        // get_status(primaryDevices[0]);
    end;

{ 
    ensure the address is a valid 28 bit address

    @param(addr The address to validate)
    @returns(@True if the address is valid, @False otherwise)
}
function validate_28bit_address(addr : uint32) : boolean;
begin
    validate_28bit_address := (addr and $F0000000) = 0;
end;

{ 
    Identify the device on the driver.storage.ctl.ide bus

    @param(device The device to identify)
    @returns(@True if the device is identified, @False otherwise)
}
function identify_device(var device : TIDE_Device) : Boolean;
var
    i : uint8;
    status : TIDE_Status;
    buffer : TIdentResponse;
    ready : boolean;
begin
    select_device(device);
    no_interrupt(device.isPrimary);

    status := get_status(device);

    outb(device.base + ATA_REG_SECCOUNT, 0);
    outb(device.base + ATA_REG_LBA0, 0);
    outb(device.base + ATA_REG_LBA1, 0);
    outb(device.base + ATA_REG_LBA2, 0);

    outb(device.base + ATA_REG_COMMAND, ATA_CMD_IDENTIFY);

    status := get_status(device);

    if status.ERROR then begin
        console.writestringln('Error identifying device, maybe'); //todo
    end;

    ready := wait_for_device(device, false);

    if not ready then begin
        console.writestringln('Device not ready in time!');
        //teapot time
        // BSOD('Device not ready in time!', 'ATA DEVICE NOT READY IN TIME FOR IDENT');
        exit(false);
    end;

    for i:=0 to 255 do begin
        buffer[i] := inw(device.base + ATA_REG_DATA);
    end;

    device.info := @buffer;

    identify_device := true;
end;

procedure set_lba_mode(device : TIDE_Device; lba : uint32);
begin
    // if device.isPrimary then begin
        if device.isMaster then begin
            outb(device.base + ATA_REG_HDDEVSEL, $E0 or ((lba and $0F000000) shr 24));
        end else begin
            outb(device.base + ATA_REG_HDDEVSEL, $F0 or ((lba and $0F000000) shr 24));
        end;
    // end else begin //TODO 
        // if device.isMaster then begin
        //     outb(device.base + ATA_REG_HDDEVSEL, $A0);
        // end else begin
        //     outb(device.base + ATA_REG_HDDEVSEL, $B0);
        // end;
    // end;
end;

function read_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
var
    i : uint16;
    ii : uint16;
    status : TIDE_Status;
    ready : boolean;
begin
    push_trace('driver.storage.ctl.ide.ata.read_pio28()');

    if not validate_28bit_address(lba) then begin
        console.writestringln('Invalid address for 28 bit read');
        read_pio28 := false;
        exit;
    end;

    select_device(device);
    psleep(50);
    no_interrupt(device.isPrimary);
    psleep(50);
    set_lba_mode(device, lba);
    psleep(50);

    outb(device.base + ATA_REG_SECCOUNT, count);
    psleep(50);

    outb(device.base + ATA_REG_LBA0, (lba and $000000FF));
    psleep(50);
    outb(device.base + ATA_REG_LBA1, (lba and $0000FF00) shr 8);
    psleep(50);
    outb(device.base + ATA_REG_LBA2, (lba and $00FF0000) shr 16);
    psleep(50);

    outb(device.base + ATA_REG_COMMAND, ATA_CMD_READ_PIO);
    psleep(50);

    ready := wait_for_device(device, false);

    if not ready then begin
        console.writestringln('Device not ready in time!');
        BSOD('Device not ready in time!', 'ATA DEVICE NOT READY IN TIME FOR READ COMMAND');
    end;

    for i:=0 to count-1 do begin
        ii:=0;
        while ii < 256 do begin
            buffer[ii+(i*256)] := inw(device.base + ATA_REG_DATA);
            ii := ii + 1;
            psleep(50);
        end;
    end;

    read_pio28 := true;
    pop_trace();
end;

function write_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
var
    i : uint16;
    ii : uint16;
    status : TIDE_Status;
    ready : boolean;
begin
    push_trace('driver.storage.ctl.ide.ata.write_pio28()');

    if not validate_28bit_address(lba) then begin
        console.writestringln('Invalid address for 28 bit write');
        write_pio28 := false;
        exit;
    end;

    select_device(device);
    no_interrupt(device.isPrimary); //maybe not?
    set_lba_mode(device, lba);


    outb(device.base + ATA_REG_SECCOUNT, count);
    outb(device.base + ATA_REG_LBA0, (lba and $000000FF));
    outb(device.base + ATA_REG_LBA1, (lba and $0000FF00) shr 8);
    outb(device.base + ATA_REG_LBA2, (lba and $00FF0000) shr 16);
    outb(device.base + ATA_REG_COMMAND, ATA_CMD_WRITE_PIO);

    ready := wait_for_device(device, false);

    if not ready then begin
        console.writestringln('Device not ready in time!');
        BSOD('Device not ready in time!', 'ATA DEVICE NOT READY IN TIME FOR WRITE COMMAND');
    end;

    for i:=0 to count-1 do begin
        ii:=0;
        while ii < 256 do begin
            outw(ATA_PRIMARY_BASE + ATA_REG_DATA, buffer[ii+(i*256)]);
            ii := ii + 1;
            psleep(50);
        end;

            psleep(50); //todo check
            outb(device.base + ATA_REG_COMMAND, ATA_CMD_CACHE_FLUSH);
            ready := wait_for_device(device, false);

        if not ready then begin
            console.writestringln('Device not ready in time!');
        BSOD('Device not ready in time!', 'ATA DEVICE NOT READY IN TIME FOR WRITE');
    end;
    end;


    // if not ready then begin
    //     console.writestringln('Device not ready in time!');
    //     BSOD('Device not ready in time!', 'ATA DEVICE NOT READY IN TIME FOR CACHE FLUSH');
    // end;

    write_pio28 := true;
    pop_trace();
end;

end.