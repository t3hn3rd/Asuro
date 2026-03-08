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
	Drivers->Storage->ATAPI - ATAPI Driver.

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!! CURRENTLY NOT FUNCTIONAL !!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	
	@author(Aaron Hance <ah@aaronhance.me>)
}

unit driver.storage.ctl.ide.atapi;

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
    function get_device_size(var device : TIDE_Device) : uint32;
    procedure ide_irq();


implementation
uses
    driver.storage.ctl.ide.ata,
    driver.storage.ctl.ide;


procedure ide_irq();
begin
    console.writestringln('driver.storage.ctl.ide IRQ Handler');
    console.redrawWindows();
end;

//print status of the device, alt status register
procedure print_status(device : TIDE_Device);
begin
    get_status(device);

    console.writestring('Status: ');
    // console.writeintln(uint32(device.status));

    console.writestring('Busy: ');
    console.writeintln(uint32(device.status.Busy));
    console.writestring('Ready: ');
    console.writeintln(uint32(device.status.Ready));
    console.writestring('Fault: ');
    console.writeintln(uint32(device.status.Fault));
    console.writestring('Seek: ');
    console.writeintln(uint32(device.status.Seek));
    console.writestring('DRQ: ');
    console.writeintln(uint32(device.status.DRQ));
    console.writestring('CORR: ');
    console.writeintln(uint32(device.status.CORR));
    console.writestring('IDDEX: ');
    console.writeintln(uint32(device.status.IDDEX));
    console.writestring('ERROR: ');
    console.writeintln(uint32(device.status.ERROR));
    
end;

procedure outb(port : uint16; value : uint8); 
begin
    arch.x86.util.outb(port, value);
    psleep(1);
    // get_status(primaryDevices[0]);
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

    // outb(ATA_PRIMARY_BASE1, $04); 
    // outb(ATA_SECONDARY_BASE1, $04);
    // sleep(1);

    status := get_status(device);

    outb(device.base + ATA_REG_SECCOUNT, 0);
    outb(device.base + ATA_REG_LBA0, 0);
    outb(device.base + ATA_REG_LBA1, 0);
    outb(device.base + ATA_REG_LBA2, 0);

    psleep(1);

    outb(device.base + ATA_REG_COMMAND, ATA_CMD_IDENTIFY_PACKET);

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

    console.writestringln('ATAPI Device identified: ');

    for i:=0 to 255 do begin
        buffer[i] := inw(device.base + ATA_REG_DATA);
        console.writestring('[');
        console.writehexpair(buffer[i]);
        console.writestring('] ');
        if (i mod 4) = 0 then begin
            console.writestringln('');
        end;
    end;

    //bits 14 and 15 of word 0
    {
     00h
 01h
 Direct-access device
 Sequential-access device
 02h
 03h
 Printer device
 Processor device
 04h
 05h
 Write-once device
 CD-ROM device
 06h
 07h
 Scanner device
 Optical memory device
 08h
 09h
 Medium changer device
 Communications device
 0A-0Bh
 0Ch
 Reserved for ACS IT8 (Graphic arts pre-press devices)
 Array controller device
 0Dh
 0Eh
 Enclosure services device
 Reduced block command devices
 0Fh
 10-1Eh
 Optical card reader/writer device
 Reserved
 1Fh
 Unknown or no device type}

    //print device type
    console.writestring('Device Type: ');
    case (buffer[0] shr 8) and $3 of
        0: console.writestringln('Direct-access device');
        1: console.writestringln('Sequential-access device');
        2: console.writestringln('Printer device');
        3: console.writestringln('Processor device');
        4: console.writestringln('Write-once device');
        5: console.writestringln('CD-ROM device');
        6: console.writestringln('Scanner device');
        7: console.writestringln('Optical memory device');
        8: console.writestringln('Medium changer device');
        9: console.writestringln('Communications device');
        10: console.writestringln('Reserved for ACS IT8 (Graphic arts pre-press devices)');
        11: console.writestringln('Array controller device');
        12: console.writestringln('Reserved');
        13: console.writestringln('Enclosure services device');
        14: console.writestringln('Reduced block command devices');
        15: console.writestringln('Unknown or no device type');
    end;

    outb(ATA_PRIMARY_BASE1, $04); 
    outb(ATA_SECONDARY_BASE1, $04);
    sleep(10);

    device.info := @buffer;

    identify_device := true;
end;

function read_PIO28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
var
    i, j : uint16;
    status : TIDE_Status;
    ready : boolean;
    packet : array[0..11] of uint8;
begin
    push_trace('read_PIO28()');

    if not device.isATAPI then begin
        console.writestringln('[ATAPI] Device is not an ATAPI device!');
        read_PIO28 := false;
        exit;
    end;

    select_device(device);
    no_interrupt(device.isPrimary);

    // Step 1: Send PACKET command
    outb(device.base + ATA_REG_FEATURES, 0);     // No special features
    outb(device.base + ATA_REG_SECCOUNT, 0);     // ATAPI requires this to be 0
    outb(device.base + ATA_REG_LBA0, (2048 shr 0) and $FF);  // Byte size of transfer (2048 for CDs)
    outb(device.base + ATA_REG_LBA1, (2048 shr 8) and $FF);
    outb(device.base + ATA_REG_LBA2, 0);         // Reserved
    outb(device.base + ATA_REG_COMMAND, ATA_CMD_PACKET);

    // Step 2: Wait for DRQ=1 (drive wants a command packet)
    ready := wait_for_device(device, false);
    if not ready then begin
        console.writestringln('[ATAPI] Timeout waiting for PACKET DRQ!');
        read_PIO28 := false;
        exit;
    end;

    // Step 3: Prepare 12-byte SCSI CDB (Read Sectors Command 0xA8)
    packet[0] := $A8;  // ATAPI READ (10) command
    packet[1] := 0;    // Reserved
    packet[2] := (lba shr 24) and $FF; // LBA high byte
    packet[3] := (lba shr 16) and $FF;
    packet[4] := (lba shr 8) and $FF;
    packet[5] := (lba shr 0) and $FF;
    packet[6] := 0;    // Reserved
    packet[7] := count; // Number of sectors to read
    packet[8] := 0;    // Reserved
    packet[9] := 0;    // Control
    packet[10] := 0;   // Reserved
    packet[11] := 0;   // Reserved

    // Step 4: Send the command packet
    for i := 0 to 5 do
        outw(device.base + ATA_REG_DATA, (packet[i*2] or (packet[i*2+1] shl 8)));

    // Step 6: Read the data (count * 2048 bytes)
    for i := 0 to (count) - 1 do begin
        for j := 0 to 1023 do begin

            ready := wait_for_device(device, false);
            if not ready then begin
                console.writestringln('[ATAPI] Timeout waiting for data DRQ!');
                read_PIO28 := false;
                exit;
            end;

            buffer[i * 256 + j] := inw(device.base + ATA_REG_DATA);
        end;
    end;

    // Success
    read_PIO28 := true;
    pop_trace();
end;


function write_pio28(device : TIDE_Device; lba : uint32; count : uint8; buffer : puint16) : boolean;
var
    i : uint16;
    ii : uint16;
    status : TIDE_Status;
    ready : boolean;
begin
    write_pio28 := false;
end;

function get_device_size(var device: TIDE_Device): uint32;
var
  i: uint8;
  ready: boolean;
  packet: puint16;        // Will hold our 10-byte CDB (as 5 words)
  response: puint16;      // Will hold the 8-byte capacity response
  xferCount: uint16;
  temp: uInt32;
  data: uint16;
begin
  get_device_size := 0;

  // 1) Select the device (Master/Slave) - presumably your function
  select_device(device);
  enable_interrupt(device.isPrimary);

  // 2) We set "no special features" for ATAPI
  outb(device.base + ATA_REG_FEATURES, 0);

  // 3) Indicate how many bytes we expect from the drive.
  //    Usually we place "MaxByteCount" in LBA1:LBA2.
  //    We need at least 8 bytes for READ CAPACITY(10).
  //    We'll do 8 => low byte in LBA1, high byte in LBA2.
  outb(device.base + ATA_REG_LBA1, $08);
  outb(device.base + ATA_REG_LBA2, $00);

  // 4) Send the "PACKET" command (0xA0) to start an ATAPI packet transfer
  outb(device.base + ATA_REG_COMMAND, ATA_CMD_PACKET);

  // 5) Build our 10-byte SCSI "READ CAPACITY(10)" command descriptor block (CDB)
  //    We'll store it in 5 words = 10 bytes
  packet := puint16(kalloc(12)); // 5 * 2 = 10 bytes
  memset(uint32(packet), 0, 12);

  // READ CAPACITY(10) = opcode 0x25
  // The rest can be 0 for a basic capacity read
  // We'll store it as little-endian 16-bit words:
  //   packet[0] = 0x0025 means low byte=0x25 (opcode), high byte=0x00
  packet[0] := $0025; // cdb[0..1]
  packet[1] := 0;     // cdb[2..3]
  packet[2] := 0;     // cdb[4..5]
  packet[3] := 0;     // cdb[6..7]
  packet[4] := 0;     // cdb[8..9]
  packet[5] := 0;     // cdb[10..11]

  // 6) Wait for drive to be ready to receive the CDB
  ready := wait_for_device(device, false);
  if not ready then
  begin
    console.writestringln('Device not ready to receive READ CAPACITY(10) CDB.');
    exit;
  end;

  // 7) Write our 5 words (10 bytes) of CDB to the drive
  for i := 0 to 5 do
  begin
    outw(device.base + ATA_REG_DATA, packet[i]);
    psleep(1); // short delay
  end;
  // Free the CDB memory
//   kfree(uint32(packet));

  // 8) Wait for next phase (the data phase). The device should assert DRQ
  //    if it has data to send. We'll poll again.
  ready := wait_for_device(device, false);
  psleep(1);
  if not ready then
  begin
    console.writestringln('Drive not ready after sending the CDB.');
    exit;
  end;

  // 9) The drive indicates how many bytes it’s about to send in LBA1:LBA2
//   xferCount := (inb(device.base + ATA_REG_LBA2) shl 8) or inb(device.base + ATA_REG_LBA1);
//   if xferCount < 8 then
//   begin
//     console.writestringln('Drive is returning less than 8 bytes for capacity!');
//     exit;
//   end;

  // 10) Allocate space for the 8-byte result
  response := puint16(kalloc(8));
  memset(uint32(response), 0, 8);

  // We'll read 4 words = 8 bytes from the data register
  for i := 0 to 3 do
  begin
    ready := wait_for_device(device, false);
    if not ready then
    begin
      console.writestringln('Device got stuck while reading capacity data!');
      exit;
    end;

    psleep(3);

    data := inw(device.base + ATA_REG_DATA);

    response[i] := data;

    psleep(1);
  end;

//   //fix the order of the bytes of each number
    // endiness of device sector count
    temp := puint32(response)[0];
    puint32(response)[0] := 0;
    for i := 0 to 31 do begin
        puint32(response)[0] :=  puint32(response)[0] or ((temp shr i) and 1) shl (31 - i);
    end;

    //endiness of device sector size
    temp := puint32(response)[1];
    puint32(response)[1] := 0;
    for i := 0 to 31 do begin
        puint32(response)[1] :=  puint32(response)[1] or ((temp shr i) and 1) shl (31 - i);
    end;
   
  // 11) Now parse the returned 8 bytes:
  //   - first 4 bytes = last LBA
  //   - next 4 bytes = block size
  console.writestring('Device sector count: ');
  console.writeintln(puint32(response)[0]); // last LBA
  console.writebin32ln(puint32(response)[0]);
  

  console.writestring('Device sector size:  ');
  console.writeintln(puint32(response)[1] ); // block size
  console.writebin32ln(puint32(response)[1]);

  device.blockSize := puint32(response)[1];

  console.writestringln('Device size: ');
    console.writeintln(puint32(response)[0] * (puint32(response)[1]) );

  // Return the LBA as "size" (some drivers do lastLBA+1).
  get_device_size :=  puint32(response)[0];
end;



end.