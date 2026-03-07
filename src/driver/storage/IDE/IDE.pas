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
	Drivers->Storage->ide - IDE Driver.

    NOT FINSIHED NEEDS WORK
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit ide;

interface

uses
    ata,
    atapi,
    console,
    drivermanagement,
    drivertypes,
    idetypes,
    isrmanager,
    lmemorymanager,
    storagetypes,
    strings,
    terminal,
    tracer,
    util,
    vmemorymanager;

 
var
    primaryDevices: array[0..1] of TIDE_Device = (
        (exists: false; isPrimary: true; isMaster: true; isATAPI: false; 
         status: (Busy: false; Ready: false; Fault: false; Seek: false; DRQ: false; CORR: false; IDDEX: false; ERROR: false);
         base: ATA_PRIMARY_BASE; blockSize: 0; info: nil),

        (exists: false; isPrimary: true; isMaster: false; isATAPI: false; 
         status: (Busy: false; Ready: false; Fault: false; Seek: false; DRQ: false; CORR: false; IDDEX: false; ERROR: false);
         base: ATA_PRIMARY_BASE; blockSize: 0; info: nil)
    );

    secondaryDevices: array[0..1] of TIDE_Device = (
        (exists: false; isPrimary: false; isMaster: true; isATAPI: false; 
         status: (Busy: false; Ready: false; Fault: false; Seek: false; DRQ: false; CORR: false; IDDEX: false; ERROR: false);
         base: ATA_SECONDARY_BASE; blockSize: 0; info: nil),

        (exists: false; isPrimary: false; isMaster: false; isATAPI: false; 
         status: (Busy: false; Ready: false; Fault: false; Seek: false; DRQ: false; CORR: false; IDDEX: false; ERROR: false);
         base: ATA_SECONDARY_BASE; blockSize: 0; info: nil)
    );


    function load(ptr: void) : boolean;
    procedure init();
    function get_status(var device : TIDE_Device) : TIDE_Status;
    function wait_for_device(device : TIDE_Device; ioop : boolean) : boolean;
    procedure no_interrupt(isPrimary : boolean);
    procedure enable_interrupt(isPrimary : boolean);
    procedure reset_device(device : TIDE_Device);
    procedure select_device(device : TIDE_Device);

implementation

{
    Disable interrupts on the IDE bus
    @param(isPrimary The bus to disable interrupts on)
}
procedure no_interrupt(isPrimary : boolean);
begin
    if isPrimary then begin
        outb(ATA_INTERRUPT_PRIMARY, inb(ATA_INTERRUPT_PRIMARY) or (1 shl 1));
    end else begin
        outb(ATA_INTERRUPT_SECONDARY, inb(ATA_INTERRUPT_SECONDARY) or (1 shl 1));
    end;
end;

procedure enable_interrupt(isPrimary : boolean);
var
    reg : uint8;
begin
    if isPrimary then begin
        reg := inb(ATA_INTERRUPT_PRIMARY);
        reg := reg and not (1 shl 1);
        outb(ATA_INTERRUPT_PRIMARY, reg);
    end else begin
        reg := inb(ATA_INTERRUPT_SECONDARY);
        reg := reg and not (1 shl 1);
        outb(ATA_INTERRUPT_SECONDARY, reg);
    end;
end;

//soft reset
procedure reset_device(device : TIDE_Device);
var
    reg : uint8;
begin
    if device.isPrimary then begin
        reg := inb(ATA_INTERRUPT_PRIMARY);
        reg := reg and  (1 shl 2);
        outb(ATA_INTERRUPT_PRIMARY, reg);
    end else begin
        reg := inb(ATA_INTERRUPT_SECONDARY);
        reg := reg and  (1 shl 2);
        outb(ATA_INTERRUPT_SECONDARY, reg);
    end;

    sleep(20);

    if device.isPrimary then begin
        reg := inb(ATA_INTERRUPT_PRIMARY);
        reg := reg and not (1 shl 2);
        outb(ATA_INTERRUPT_PRIMARY, reg);
    end else begin
        reg := inb(ATA_INTERRUPT_SECONDARY);
        reg := reg and not (1 shl 2);
        outb(ATA_INTERRUPT_SECONDARY, reg);
    end;

    
end;

{ 
    Wait for the device to be ready on the IDE bus

    @param(device The device to wait for)
    @returns(@True if the device is ready, @False otherwise)
}
function wait_for_device(device : TIDE_Device; ioop : boolean) : boolean;
var
    status : TIDE_Status;
    i : uint32;
begin
    push_trace('ide.wait_for_device()');

    i := 0;

    while (i < 50000) do begin
        status := get_status(device);

        if (status.BUSY = false) and (status.DRQ or (not ioop)) then begin //todo test
            wait_for_device := true;
            pop_trace();
            exit;
        end;

        i := i + 1;
    end;

    wait_for_device := false;
    pop_trace();
end;

{ 
    Select the active device on the IDE bus 
    @param(device The device to select)

    Function can set the device to either master or slave,
    one device per bus/channel can be active at a time.
}
procedure select_device(device : TIDE_Device);
var
    dev : uint8;
    reg : uint8;
begin
    push_trace('ide.select_device()');

    dev := ATA_DEVICE_SLAVE;

    if device.isMaster then begin
        dev := ATA_DEVICE_MASTER;
    end;

    reg := inb(device.base + ATA_REG_HDDEVSEL);
    reg := (reg and $F0) or dev;

    outb(device.base + ATA_REG_HDDEVSEL, reg);

    pop_trace();
end;

{ 
    Get the status of the device on the IDE bus

    @param(device The device to get the status of)
    @returns(@TIDE_Device The status of the device on the IDE bus)
}
function get_status(var device : TIDE_Device) : TIDE_Status;
var
    status : TIDE_Status;
    errorReg : uint8;
begin
    push_trace('ide.get_status()');

    // select_device(device);

    status := TIDE_Status(inb(device.base + ATA_REG_STATUS));

    device.status := status;

    if status.ERROR then begin
        errorReg := inb(device.base + ATA_REG_ERROR);
        
        console.writestringln('[IDE] ERROR detected!');
        console.writestring('[IDE] ERROR REGISTER: ');
        console.writebin8ln(errorReg);

        if (errorReg and $04) <> 0 then console.writestringln('[IDE] ERROR: Aborted Command');
        if (errorReg and $10) <> 0 then console.writestringln('[IDE] ERROR: ID Not Found');
        if (errorReg and $40) <> 0 then console.writestringln('[IDE] ERROR: Uncorrectable Data');
        if (errorReg and $80) <> 0 then console.writestringln('[IDE] ERROR: Bad Block');

        console.redrawWindows();
    end;

end;

{ 
    Check if the device is present on the IDE bus

    @param(device The device to check)
    @returns(@True if the device is present, @False otherwise)
}
function is_device_present(var device : TIDE_Device) : boolean;
begin
    push_trace('ide.is_device_present()');

    get_status(device);

    if (uInt8(device.status) = $FF) then begin //TODO make this more robust
        is_device_present := false;
    end else begin
        is_device_present := true;
    end;

end;

{ 
    Check if the device is an ATAPI device

    @param(device The device to check)
    @returns(@True if the device is an ATAPI device, @False otherwise)
}
function check_device_type(var device : TIDE_Device) : boolean;
var
    sec, lba0, lba1, lba2 : uint8;
begin
    push_trace('ide.check_device_type()');

    select_device(device);

    //TODO make sure dvice signture is set at this time, else reset it
    //reset any device signature
{
Write 0x04 to the Control Register (0x3F6 for primary bus, 0x376 for secondary).
Wait ~5 microseconds.
Write 0x00 back to Control Register to complete reset.
// }
    outb(ATA_PRIMARY_BASE1, $04);
    outb(ATA_SECONDARY_BASE1, $04);
    sleep(1);
    // outb(ATA_PRIMARY_BASE1, $00);
    // outb(ATA_SECONDARY_BASE1, $00);
    select_device(device);

    sleep(1);

    //read all bytes of LBA address
    sec := inb(device.base + ATA_REG_SECCOUNT);
    lba0 := inb(device.base + ATA_REG_LBA0);
    lba1 := inb(device.base + ATA_REG_LBA1);
    lba2 := inb(device.base + ATA_REG_LBA2);

    console.writestring('[IDE] (check_device_type) SEC: ');
    console.writehexln(sec);
    console.writestring('[IDE] (check_device_type) LBA0: ');
    console.writehexln(lba0);
    console.writestring('[IDE] (check_device_type) LBA1: ');
    console.writehexln(lba1);
    console.writestring('[IDE] (check_device_type) LBA2: ');
    console.writehexln(lba2);


    //check if the device is an ATAPI device
    if ((sec = 3) or (lba2 = $EB)) then begin
        check_device_type := true;
        device.isATAPI := true;
    end else if sec = 1 then begin
        check_device_type := true;
        device.isATAPI := false;
    end else begin
        check_device_type := false;
    end;
end;

{ 
    Load the device on the IDE bus

    @param(device The device to load)
    @returns(@True if the device is loaded, @False otherwise)
}
procedure load_device(var device : TIDE_Device);
var
    i : uint8;
    buffer : puint8;
    storageDevice : PStorage_device;
    success : boolean;
    size : uint32;
begin
    push_trace('ide.load_device()');
    success := check_device_type(device);

    if (is_device_present(device) and success) then begin
        console.writestringln('[IDE] (load_device) Device is present');

        if (device.isATAPI) then begin
            console.writestringln('[IDE] (load_device) Device is ATAPI');
            //todo load device info
            success := atapi.identify_device(device);

            device.exists := true;
            device.isATAPI := true;

        end else begin
            console.writestringln('[IDE] (load_device) Device is ATA');
            success:= ata.identify_device(device);

            //check if atapi device using info from identify_device
            console.writestringln('[IDE] (load_device) Device info: ');
            console.writecharln(char(puint8(device.info)[252]));
            console.writecharln(char(puint8(device.info)[253]));

            if (puint8(device.info)[253] = $FF) then begin
                console.writestringln('[IDE] (load_device) Device is ATAPI');
                device.isATAPI := true;
                device.exists := true;

                success := atapi.identify_device(device);
            end;

        end;

        if not success then begin
            console.writestringln('[IDE] (load_device) Error identifying device'); //todo 
            device.exists := false;
            exit;
        end;

        device.exists := true;

        storageDevice := PStorage_Device(kalloc(sizeof(TStorage_Device)));
        memset(uint32(storageDevice), 0, sizeof(TStorage_Device));

        if (device.isATAPI) then begin
            storageDevice^.controller := TControllerType.ControllerATAPI;
            storageDevice^.writable := false; //TODO atapi
            size := atapi.get_device_size(device);
            storageDevice^.maxSectorCount := size;
            storageDevice^.sectorSize := device.blockSize;

            if (device.isMaster) then begin
                storageDevice^.controllerId0 := 0;
            end else begin
                storageDevice^.controllerId0 := 1;
            end;

            //read and print first sector
            buffer := puint8(kalloc(2048));
            memset(uint32(buffer), 11, 2048);
            atapi.read_pio28(device, 11, 1, puint16(buffer));

            console.writestringln('[IDE] (load_device) First sector of ATAPI device: ');
            for i:=0 to 16 do begin
                console.writehexln(buffer[i]);
            end;

            memset(uint32(buffer), 0, 2048);

            atapi.read_pio28(device, 5200, 1, puint16(buffer));

            console.writestringln('[IDE] (load_device) First sector of ATAPI device: ');
            for i:=0 to 16 do begin
                console.writehexln(buffer[i]);
            end;


        end else begin
            storageDevice^.controller := TControllerType.ControllerATA;
            storageDevice^.writable := true;

            storageDevice^.maxSectorCount := (device.info^[61] shl 16) or device.info^[60];
            storageDevice^.sectorSize := 512; //todo
            
            if (device.isMaster) then begin
                storageDevice^.controllerId0 := 0;
            end else begin
                storageDevice^.controllerId0 := 1;
            end;

            //if secotorcount is 0, then the device is not present
            if (storageDevice^.maxSectorCount = 0) then begin
                device.exists := false;
                exit;
            end;

            // //wrtie test, 1F2F1F2F repeated
            // buffer := puint8(kalloc(1024));
            // memset(uint32(buffer), $02, 1024);

            // uint8(buffer[0]) := $1F;
            // uint8(buffer[1]) := $2F;
            // uint8(buffer[2]) := $3F;
            // uint8(buffer[3]) := $4F;
            // uint8(buffer[4]) := $5F;
            // uint8(buffer[5]) := $6F;
            // uint8(buffer[6]) := $7F;
            // uint8(buffer[7]) := $8F;
  
            // //write to the first sector
            // ata.write_pio28(device, 10, 2, puint16(buffer));

            // //read the first sector
            // memset(uint32(buffer), 0, 512);
            // ata.read_pio28(device, 10, 1, puint16(buffer));

            // //check if the data is the same
            // for i:=0 to 10 do begin
            //    console.writehexln(buffer[i]);
            // end;
        end;

        //register the device TODO
        // drivemanager.register_device(storageDevice);

    end else begin
        console.writestringln('[IDE] (load_device) Device is not present');
        device.exists := false;
    end;

    pop_trace();
end;


function load(ptr: void) : boolean;
var 
    pciDevice : PPCI_Device;
    buffer : puint8;
    i : uint8;
begin
    push_trace('ide.load()');
    console.writestringln('[IDE] (load) Loading IDE Devices');
    console.redrawWindows();
    registerISR(14, @atapi.ide_irq);
    registerISR(15, @atapi.ide_irq);
    console.writestringln('[IDE] (load) Loading IDE Devices 2');
    console.redrawWindows();
    pciDevice := PPCI_Device(ptr);

    load_device(primaryDevices[0]);
    load_device(primaryDevices[1]);
    load_device(secondaryDevices[0]);
    load_device(secondaryDevices[1]);

    pop_trace();
    load := true;

    console.writestringln('[IDE] (load) IDE Device Loading Finished');

    i := 0;

    if (primaryDevices[0].exists) then begin
        console.writestringln('[IDE] (load) FOUND Primary Master Device 0');
        i := i + 1;
    end;

    if (primaryDevices[1].exists) then begin
        console.writestringln('[IDE] (load) FOUND Primary Slave Device 1');
        i := i + 1;
    end;

    if (secondaryDevices[0].exists) then begin
        console.writestringln('[IDE] (load) FOUND Secondary Master Device 2');
        i := i + 1;
    end;

    if (secondaryDevices[1].exists) then begin
        console.writestringln('[IDE] (load) FOUND Secondary Slave Device 3');
        i := i + 1;
    end;

    // console.writestringln('[IDE] (load) Found ' + i + ' IDE Devices');

end;

procedure init();  
var
    devID : TDeviceIdentifier;
begin
    push_trace('ide.init');
    console.writestringln('[IDE] (INIT) BEGIN');
    devID.bus:= biPCI;
    devID.id0:= idANY;
    devID.id1:= $00000001;
    devID.id2:= $00000001;
    devID.id3:= idANY;
    devID.id4:= idANY;
    devID.ex:= nil;
    drivermanagement.register_driver('IDE ATA/ATAPI Driver', @devID, @load);
    console.writestringln('[IDE] (INIT) END');
end;

end.