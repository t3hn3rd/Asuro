
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
	Drivers->Storage->AHCI->AHCI - AHCI Driver.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit AHCI;

interface

uses
    AHCITypes,
    console,
    drivermanagement,
    drivertypes,
    idetypes,
    ioapic,
    isrmanager,
    lists,
    lmemorymanager,
    PCI,
    storagemanager,
    storagetypes,
    util,
    vmemorymanager,
    volumemanager;

var
    ahciControllers : PDList;
    page_base : puint32;

procedure init();
function load(ptr : void) : boolean;
procedure check_ports(controller : PAHCI_Controller);
procedure identify_device(controller : PAHCI_Controller; portIndex : uint32; isATAPI : boolean);
procedure ahci_isr();
function find_cmd_slot(device : PAHCI_Device) : uint32;

{ Async primitives — return immediately after issuing the command.
  completion is called from IRQ context when the slot clears.
  completion may be nil if no callback is needed (e.g. init-time polling). }
function send_read_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;
function send_write_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;
function read_atapi_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;

{ Storage-manager async callback wrappers }
procedure ahci_read_hook_async(drive : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32; completion : TStorageCompletion; userdata : puint32);
procedure ahci_write_hook_async(drive : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32; completion : TStorageCompletion; userdata : puint32);
procedure ahci_atapi_read_hook_async(drive : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32; completion : TStorageCompletion; userdata : puint32);

{ Poll hook — drives ahci_isr inline when the PIC does not deliver the IRQ }
procedure ahci_poll_hook();

function send_read_capacity(device : PAHCI_Device; sectorCount : puint32; blockSize : puint32) : boolean;


implementation

procedure init();
var
    devID : TDeviceIdentifier;
begin
    console.writestringln('AHCI: Registering driver');
    devID.bus:= biPCI;
    devID.id0:= idANY;
    devID.id1:= $00000001;
    devID.id2:= $00000006;
    devID.id3:= $00000001;
    devID.id4:= idANY;
    devID.ex:= nil;
    drivermanagement.register_driver('ATA/PI AHCI Driver', @devID, @load);
    //TODO check IDE devices in ide for sata devices
end;

procedure stop_port(port : PHBA_Port);
var
    timeout : uint32;
begin
    // Clear ST (bit 0) first
    port^.cmd := port^.cmd and not $1;

    // Wait for CR (bit 15) to clear
    timeout := 0;
    while (port^.cmd and $8000) <> 0 do begin
        timeout := timeout + 1;
        if timeout > 100000 then break;
    end;

    // Clear FRE (bit 4)
    port^.cmd := port^.cmd and not $10;

    // Wait for FR (bit 14) to clear
    timeout := 0;
    while (port^.cmd and $4000) <> 0 do begin
        timeout := timeout + 1;
        if timeout > 100000 then break;
    end;
end;

procedure start_port(port : PHBA_Port);
begin
    // Wait for CR (bit 15) to clear before starting
    while (port^.cmd and $8000) <> 0 do begin
    end;

    // Enable FRE (bit 4) first so port can receive FIS
    port^.cmd := port^.cmd or $10;

    // Then enable ST (bit 0) to allow command processing
    port^.cmd := port^.cmd or $1;
end;

procedure reset_port(port : PHBA_Port);
var
  timeout : uint32;
begin
    // console.writestringln('AHCI: Performing a full port reset.');

    // Stop the port: clear ST (bit 0)
    port^.cmd := port^.cmd and not $1;

    // Wait until CR (bit 15) is cleared.
    timeout := 0;
    while (port^.cmd and $8000) <> 0 do begin
        timeout := timeout + 1;
        if timeout > 100000 then begin
            console.writestringln('AHCI: Port reset timeout (CR not clearing).');
            break;
        end;
    end;

    // Initiate COMRESET: set DET=1 in PxSCTL (bits 3:0)
    port^.sata_ctrl := (port^.sata_ctrl and $FFFFFFF0) or $1;

    // Wait for COMRESET to propagate (spec says >= 1ms)
    psleep(2);

    // Clear COMRESET: set DET=0
    port^.sata_ctrl := port^.sata_ctrl and $FFFFFFF0;

    // Wait for device detection (DET field in SStatus = 3)
    timeout := 0;
    while (port^.sata_status and $F) <> 3 do begin
        timeout := timeout + 1;
        if timeout > 100000 then begin
            console.writestringln('AHCI: Port reset timeout (waiting for device ready).');
            break;
        end;
    end;

    // Clear the SERR register by writing 1s to it.
    port^.sata_error := $FFFFFFFF;

    start_port(port);
end;

// procedure reset_port(port : PHBA_Port);
// var
//   ssts, serr, timeout : uint32;
// begin
//   console.writestringln('AHCI: Performing a full port reset.');

//     port^.cmd := port^.cmd and not $1;

//     // Wait until CR (bit 15) is cleared.
//     timeout := 0;
//     while (port^.cmd and $8000) <> 0 do begin
//         timeout := timeout + 1;
//         if timeout > 1000000 then begin
//             console.writestringln('AHCI: Port reset timeout.');
//             break;
//         end;
//     end;

//     port^.sata_ctrl := port^.sata_ctrl and $FFFF0000;
//     port^.sata_ctrl := port^.sata_ctrl or $1;
//     psleep(10);
//     port^.sata_ctrl := port^.sata_ctrl and $FFFF0000;

//     while (port^.sata_status and $F) <> $3 do begin
//         //wait for the port to be ready
//     end;

//     // Clear the SERR register by writing 1s to it.
//     port^.sata_error := $FFFFFFFF;

//     // start_port(port);
// end;


{
    Check the ports on the controller and setup the command list, FIS, and command table
}
procedure check_ports(controller : PAHCI_Controller);
var
    i : uint32;
    ii : uint32;
    port : PHBA_Port;
    device : PAHCI_Device;
    cmd_list_base : puint32;
    fis_base : puint32;
    cmd_table_base : puint32;
    command_header : PHBA_CMD_HEADER;
begin
    for i:=0 to 31 do begin
        if ((controller^.mio^.ports_implimented shr i) and 1) = 1 then begin
            port := @controller^.mio^.ports[i];

            device := PAHCI_Device(@controller^.devices[i]);
            device^.port := port;

            //check device type
            case port^.signature of
                SATA_SIG_ATA: begin
                    device^.device_type := SATA;
                end;
                SATA_SIG_ATAPI: begin
                    device^.device_type := ATAPI;
                end;
                SATA_SIG_SEMB: begin
                    device^.device_type := SEMB;
                end;
                SATA_SIG_PM: begin
                    device^.device_type := PM;
                end;
            end;

            //NEEED TO STOP the port before doing anything
            stop_port(port);
            reset_port(port);
            //allocate memory for the command list and ensure it is aligned to 1024 bytes
            // Need 32 command headers. Allocate extra (alignment-1) bytes for alignment.
            cmd_list_base := kalloc(sizeof(THBA_CMD_HEADER) * 32 + 1023);
            cmd_list_base := puint32((uint32(cmd_list_base) + 1023) and $FFFFFC00);
            memset(uint32(cmd_list_base), 0, sizeof(THBA_CMD_HEADER) * 32);

            //set the command list base address
            port^.cmdl_basel := vtop(uint32(cmd_list_base)); //todo set virtual address in device
            port^.cmdl_baseu := 0;

            device^.command_list := PHBA_CMD_HEADER(cmd_list_base);

            //allocate memory for the FIS and ensure it is aligned to 256 bytes
            fis_base := kalloc(sizeof(THBA_FIS) + 255);
            fis_base := puint32((uint32(fis_base) + 255) and $FFFFFF00);

            //set the FIS base address
            port^.fis_basel := vtop(uint32(fis_base));
            port^.fis_baseu := 0;

            memset(uint32(fis_base), 0, sizeof(THBA_FIS));

            device^.fis := PHBA_FIS(fis_base);
            //todo check how many simultaneous commands are supported

            //allocate memory for the command table and ensure it is aligned to 128 bytes
            // Need 32 command tables. Allocate extra (alignment-1) bytes for alignment.
            cmd_table_base := kalloc(sizeof(THBA_CMD_TABLE) * 32 + 127);
            cmd_table_base := puint32((uint32(cmd_table_base) + 127) and $FFFFFF80);
            memset(uint32(cmd_table_base), 0, sizeof(THBA_CMD_TABLE) * 32);

            device^.command_table := PHBA_CMD_TABLE(cmd_table_base);

            //set the command table base address and setup command table
            for ii:=0 to 31 do begin
                //set command header locations
                command_header := PHBA_CMD_HEADER(uint32(cmd_list_base) + (ii * sizeof(THBA_CMD_HEADER)));
                command_header^.prdtl := 32;
                command_header^.cmd_table_base := vtop(uint32(cmd_table_base)) + (ii * sizeof(THBA_CMD_TABLE));
                command_header^.cmd_table_baseu := 0;
            end;

            //reset the port
            reset_port(port);
            if (device^.device_type = SATA) then begin
                identify_device(controller, i, false);
            end else if (device^.device_type = ATAPI) then begin
                identify_device(controller, i, true);
            end else begin
                console.writestringln('AHCI: Unsupported device type');
            end;

            controller^.mio^.int_status := $FFFFFFFF;
        end;
    end;
end;

procedure identify_device(controller : PAHCI_Controller; portIndex : uint32; isATAPI : boolean);
var
    fis         : PHBA_FIS_REG_H2D;
    cmd_header  : PHBA_CMD_HEADER;
    cmd_table   : PHBA_CMD_TABLE;
    cmd         : uint32;
    i, timeout  : uint32;
    buffer      : puint32;
    device      : PAHCI_Device;
    tfd         : uint32;
    sec_count   : uint32;
    b8          : puint16;
    storageDev  : PStorage_Device;
    storageDev_sectorSize : uint32;
begin
    device := PAHCI_Device(@controller^.devices[portIndex]);

    //clear any pending interrupts
    device^.port^.int_status := $FFFFFFFF;
    device^.port^.int_enable := $0;   { disabled during IDENTIFY polling }
    
    // Allocate a 512-byte DMA buffer for the IDENTIFY d ata
    buffer := kalloc(512);
    memset(uint32(buffer), 0, 512);

    // Use command slot 0 for the IDENTIFY command.
    cmd_header := device^.command_list;  // Assuming slot 0 is at the beginning.
    cmd_header^.cmd_fis_length := sizeof(THBA_FIS_REG_H2D) div sizeof(uint32);
    cmd_header^.wrt := 0;
    cmd_header^.prdtl := 1;
    cmd_header^.clear_busy := 1;
    if isATAPI then begin
        cmd_header^.atapi := 1;
    end;


    // Setup the command table (using slot 0)
    cmd_table := device^.command_table;  
    cmd_table^.prdt[0].dba := vtop(uint32(buffer));
    cmd_table^.prdt[0].dbc := 511;   // 512 bytes (0-based count)
    cmd_table^.prdt[0].int := 1;     // Interrupt on completion

    // if isATAPI then begin
    // // ATAPI Identify Device command
    // buffer[0] := $A1;  // ATAPI Identify Device
    // end;

    // Construct the Command FIS in the command table's CFIS area
    fis := PHBA_FIS_REG_H2D(@device^.command_table^.cmd_fis);
    memset(uint32(fis), 0, sizeof(THBA_FIS_REG_H2D));
    fis^.fis_type := uint8(FIS_TYPE_REG_H2D);
    fis^.c   := $1;
    if isATAPI then begin
        fis^.command  := ATA_CMD_IDENTIFY_PACKET;
    end else begin
        fis^.command  := ATA_CMD_IDENTIFY;
    end;
    fis^.device   := $40; 

    //waut for the port to be ready, bit 7 in the TFD register and bit 3 tfd
    while (device^.port^.tfd and $88) <> 0 do begin
        // console.writestring('AHCI: tfd: ');
        // console.writehexln(device^.port^.tfd);
    end;

    // Issue the command by setting bit 0 in the port's Command Issue register.
    cmd := device^.port^.cmd_issue;
    cmd := cmd or $1;
    device^.port^.cmd_issue := cmd;

    // console.writestringln('AHCI: Sent identify command');


    // Wait for command completion with a timeout.
    timeout := 0;
    repeat
      tfd := device^.port^.tfd;

      if device^.port^.int_status <> 0 then begin
          device^.port^.int_status := device^.port^.int_status;
      end;

      timeout := timeout + 1;
      if timeout > 100 then begin
          console.writestringln('AHCI: IDENTIFY command timeout');
          break;
      end;
      if (tfd and $1) <> 0 then break;  // ERR bit set
      psleep(1);
    until ((device^.port^.cmd_issue and $1) = 0);  // Wait until slot 0 is cleared

    // console.writestringln('AHCI: Command complete');

    // Check if the command slot is still set (command didn't complete)
    if (device^.port^.cmd_issue and $1) <> 0 then begin
        console.writestringln('AHCI: Error sending identify command');

        // Check the error register for more information
        console.writestring('AHCI: Error sata register: ');
        console.writehexln(device^.port^.sata_error);

        //print out busy flag
        // console.writestring('AHCI: Status: ');
        // console.writehexln(device^.port^.sata_status);

        //print sata active flag
        // console.writestring('AHCI: Active flag: ');
        // console.writehexln(device^.port^.sata_active);

        //print tfd
        // console.writestring('AHCI: TFD: ');
        // console.writehexln(device^.port^.tfd);
    end;

    { Re-enable port interrupts now that IDENTIFY polling is done.
      $40000003 = bit 0 (D2H Register FIS) | bit 1 (PIO Setup FIS) | bit 30 (Task File Error)
      These three bits cover all normal completions and hardware error events. }
    device^.port^.int_enable := $40000003;

    b8 := puint16(buffer);
    sec_count := (b8[61] shl 16) or b8[60];

    { Free the 512-byte IDENTIFY buffer before allocating the write-test buffer }
    kfree(buffer);
    buffer := puint32(kalloc(2048));
    memset(uint32(buffer), 0, 2048);

    { For ATAPI devices, get capacity from SCSI READ CAPACITY instead of IDENTIFY }
    if isATAPI then begin
        if send_read_capacity(device, @sec_count, @storageDev_sectorSize) then begin
        end else begin
            console.writestringln('AHCI: ATAPI capacity query failed (no media?).');
            storageDev_sectorSize := 2048;
            sec_count := 0;
        end;
    end else begin
        storageDev_sectorSize := 512;
        memset(uint32(buffer), $77, 2048);
        send_write_dma_async(device, 22, 512, buffer, nil, nil);
        while device^.port^.cmd_issue <> 0 do ;  { init-time poll; runs once per device at boot }
        memset(uint32(buffer), 0, 2048);
        send_read_dma_async(device, 22, 512, buffer, nil, nil);
        while device^.port^.cmd_issue <> 0 do ;  { init-time poll }
    end;
    
    { Register this device with the storage manager.
      ATAPI devices (optical drives) are always registered even with 0 sectors (no media). }
    if (sec_count > 0) or isATAPI then begin
        storageDev := PStorage_Device(kalloc(sizeof(TStorage_Device)));
        memset(uint32(storageDev), 0, sizeof(TStorage_Device));

        storageDev^.id             := portIndex;
        storageDev^.controllerId0  := uint32(device);  { store PAHCI_Device for callback wrappers }
        storageDev^.sectorSize     := storageDev_sectorSize;
        storageDev^.maxSectorCount := sec_count;
        storageDev^.start          := 0;
        storageDev^.volumes        := DL_New(sizeof(Pointer));

        if isATAPI then begin
            storageDev^.controller := TControllerType.ControllerAHCI_ATAPI;
            storageDev^.writable   := false;
            storageDev^.readCallback       := PPHIOHook(nil);
            storageDev^.writeCallback      := PPHIOHook(nil);
            storageDev^.readCallbackAsync  := PPHIOHookAsync(@ahci_atapi_read_hook_async);
            storageDev^.writeCallbackAsync := PPHIOHookAsync(nil);
            storageDev^.pollCallback       := PPPollHook(@ahci_poll_hook);
        end else begin
            storageDev^.controller := TControllerType.ControllerAHCI;
            storageDev^.writable   := true;
            storageDev^.readCallback       := PPHIOHook(nil);
            storageDev^.writeCallback      := PPHIOHook(nil);
            storageDev^.readCallbackAsync  := PPHIOHookAsync(@ahci_read_hook_async);
            storageDev^.writeCallbackAsync := PPHIOHookAsync(@ahci_write_hook_async);
            storageDev^.pollCallback       := PPPollHook(@ahci_poll_hook);
        end;

        storagemanager.register_device(storageDev);

        { Only discover volumes if there is media present }
        if sec_count > 0 then
            volumemanager.discover_volumes(storageDev);

        console.writestring('AHCI: Registered device on port ');
        console.writeint(portIndex);
        if sec_count > 0 then begin
            console.writestring(' with storage manager (');
            console.writeint((sec_count * storageDev_sectorSize) div 1024 div 1024);
            console.writestringln(' MB)');
        end else begin
            console.writestringln(' with storage manager (no media)');
        end;
    end else begin
        console.writestring('AHCI: Port ');
        console.writeint(portIndex);
        console.writestringln(': sector count is 0, skipping registration.');
    end;

    { Free the write-test buffer allocated above }
    kfree(buffer);

end;


// procedure controller_reset(controller : PAHCI_Controller);
// begin
//     //check sam TODO
//     if (controller^.mio^.capabilites2 and $1) = 0 then begin
//         console.writestringln('AHCI: Controller does not support reset');
//         exit;
//     end;

//     //check ghc.ae is set to 1
//     if (controller^.mio^.global_ctrl and $1) = 0 then begin
//         console.writestringln('AHCI: Controller is not enabled');
//         controller^.mio^.global_ctrl := controller^.mio^.global_ctrl or $1;
//     end;

//     while (controller^.mio^.global_ctrl and $1) <> 0 do begin
//         //wait for the controller to be ready
//     end;

//     //set the reset bit
//     controller^.mio^.global_ctrl := controller^.mio^.global_ctrl or $2;



// end;

function load(ptr : void) : boolean;
var 
    device : PPCI_Device;
    controller : PAHCI_Controller;
    i : uint32;
    base : PHBA_Memory;
    cmd_list_base : puint32;
    fis_base : puint32;
    cmd_table_base : puint32;
    int_no : uInt8;
    timeout : uint32;
    bohc : uint32;
begin
    if ahciControllers = nil then begin
        ahciControllers := DL_New(SizeOf(TAHCI_Controller));
    end;

    device := PPCI_Device(ptr);

    pci.enableDevice(device^.bus, device^.slot, device^.func);
    psleep(5);
    int_no := device^.interrupt_line + 32;

    controller := PAHCI_Controller(DL_Add(ahciControllers));

    controller^.pci_device := PPCI_Device(device);
    
//     Perform BIOS/OS handoff (if the bit in the extended capabilities is set)
//     Reset controller

    //get the base address of the controller
    page_base := kpalloc(device^.address5); // TODO MEM memory manager need to be improved
    base := PHBA_Memory(device^.address5);
    controller^.mio := base;

    bohc := controller^.mio^.bohc;

    if (bohc and $1) <> 0 or (bohc and not (1 shl 1)) then begin

        // Set the OS Owned Semaphore (typically bit 1).
        bohc := bohc or (1 shl 1);
        controller^.mio^.bohc := bohc;

        // Wait until the BIOS Owned Semaphore (bit 0) is cleared.
        timeout := 0;
        while ((controller^.mio^.bohc and $1) <> 0) and (timeout < 10000) do begin
        timeout := timeout + 1;
        end;

        if timeout = 10000 then begin
        console.writestringln('AHCI: BIOS/OS handoff timed out.');
        end else begin
        // console.writestringln('AHCI: BIOS/OS handoff successful.');
        end;
    end else begin
        // console.writestringln('AHCI: BIOS not holding controller or handoff already complete.');
    end;
    
    //print ghc
    // console.writestring('AHCI: GHC: ');
    // console.writebin32ln(base^.global_ctrl);

    base^.global_ctrl := base^.global_ctrl or AHCI_CONTROLLER_MODE;

    base^.global_ctrl := base^.global_ctrl or 1;

    while (base^.global_ctrl and 1) <> 0 do begin
    end;
    

    registerISR(int_no, @ahci_isr);

    console.writestring('AHCI: IRQ ');
    console.writeint(device^.interrupt_line);
    console.writestring(' -> INT ');
    console.writeint(int_no);
    console.writestringln('');

    { Initialise IOAPIC/LAPIC support (safe no-op if no IOAPIC present).
      PCI interrupts may be routed through the IOAPIC instead of the
      legacy 8259 PIC — without programming the IOAPIC redirection
      entry the interrupt never reaches the CPU. }
    ioapic.init();
    ioapic.route_pci_irq(device^.interrupt_line, int_no);

    //enable AHCI mode
    base^.global_ctrl := base^.global_ctrl or AHCI_CONTROLLER_MODE;

    //enable interrupts (GHC.IE = bit 1)
    base^.global_ctrl := base^.global_ctrl or $2;

    //clear any pending interrupts
    base^.int_status := $FFFFFFFF;

    check_ports(controller);
end;

procedure ahci_isr();
var
    i          : uint32;
    j          : uint32;
    k          : uint32;
    ctrl_is    : uint32;
    port_is    : uint32;
    port       : PHBA_Port;
    controller : PAHCI_Controller;
    device     : PAHCI_Device;
    success    : boolean;
begin
    if ahciControllers = nil then exit;
    for i := 0 to DL_Size(ahciControllers) - 1 do begin
        controller := PAHCI_Controller(DL_Get(ahciControllers, i));
        ctrl_is := controller^.mio^.int_status;
        if ctrl_is = 0 then continue;

        for j := 0 to 31 do begin
            if (ctrl_is shr j) and 1 = 0 then continue;

            port    := @controller^.mio^.ports[j];
            port_is := port^.int_status;
            device  := PAHCI_Device(@controller^.devices[j]);

            { success: no ERR bit in TFD, and no Task File Error interrupt }
            success := ((port^.tfd and $1) = 0) and ((port_is and $40000000) = 0);

            { Scan all command slots for completed operations }
            for k := 0 to 31 do begin
                if device^.pending[k].inUse then begin
                    if (port^.cmd_issue shr k) and 1 = 0 then begin
                        device^.pending[k].inUse := false;
                        if device^.pending[k].completion <> nil then
                            device^.pending[k].completion(success, device^.pending[k].userdata);
                    end;
                end;
            end;

            { Acknowledge port interrupt by writing back the read value }
            port^.int_status := port_is;
        end;

        { Acknowledge controller interrupt }
        controller^.mio^.int_status := ctrl_is;
    end;
end;

function find_cmd_slot(device : PAHCI_Device) : uint32;
var
    i         : uint32;
    cmd_issue : uint32;
begin
    cmd_issue := device^.port^.cmd_issue;
    for i := 0 to 31 do begin
        if ((cmd_issue shr i) and 1 = 0) and (not device^.pending[i].inUse) then begin
            find_cmd_slot := i;
            exit;
        end;
    end;
    { All 32 slots busy }
    find_cmd_slot := $FFFFFFFF;
end;

{ Shared completion callback used by all sync wrappers.
  userdata points to a stack-local boolean; sets it true so the spin loop exits.
  Called from IRQ context \u2014 must stay short. }
procedure sync_completion(success : boolean; userdata : puint32);
begin
    userdata^ := 1;
end;

{ ---- Async send functions ---- }

function send_read_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;
var
    fis        : PHBA_FIS_REG_H2D;
    cmd_header : PHBA_CMD_HEADER;
    cmd_table  : PHBA_CMD_TABLE;
    i          : uint32;
    timeout    : uint32;
    sec_count  : uint32;
    prdt_count : uint32;
    slot       : uint32;
begin
    send_read_dma_async := false;

    prdt_count := (count div 4194304) + 1;
    if prdt_count > 32 then exit;

    slot := find_cmd_slot(device);
    if slot = $FFFFFFFF then exit;   { All 32 slots busy }

    cmd_header := PHBA_CMD_HEADER(uint32(device^.command_list) + (slot * sizeof(THBA_CMD_HEADER)));
    cmd_header^.cmd_fis_length := sizeof(THBA_FIS_REG_H2D) div sizeof(uint32);
    cmd_header^.wrt        := 0;
    cmd_header^.prdtl      := prdt_count;
    cmd_header^.clear_busy := 1;

    cmd_table := PHBA_CMD_TABLE(uint32(device^.command_table) + (slot * sizeof(THBA_CMD_TABLE)));

    for i := 0 to prdt_count - 1 do begin
        cmd_table^.prdt[i].dba := vtop(uint32(buffer) + (i * 4194304));
        if i = prdt_count - 1 then
            cmd_table^.prdt[i].dbc := count - (i * 4194304) - 1
        else
            cmd_table^.prdt[i].dbc := 4194304 - 1;
        cmd_table^.prdt[i].int := 1;
    end;

    fis := PHBA_FIS_REG_H2D(@cmd_table^.cmd_fis);
    memset(uint32(fis), 0, sizeof(THBA_FIS_REG_H2D));
    fis^.fis_type := uint8(FIS_TYPE_REG_H2D);
    fis^.c        := $1;
    fis^.command  := ATA_CMD_READ_DMA_EXT;
    fis^.device   := $40;

    fis^.lba0 := lba and $FF;
    fis^.lba1 := (lba shr 8)  and $FF;
    fis^.lba2 := (lba shr 16) and $FF;
    fis^.lba3 := (lba shr 24) and $FF;
    fis^.lba4 := (lba shr 32) and $FF;
    fis^.lba5 := (lba shr 40) and $FF;

    sec_count := count div 512;
    if sec_count = 0 then sec_count := 1;
    fis^.countl := sec_count and $FF;
    fis^.counth := (sec_count shr 8) and $FF;

    { Wait for TFD BSY+DRQ to clear }
    timeout := 0;
    while (device^.port^.tfd and $88) <> 0 do begin
        timeout := timeout + 1;
        if timeout > 100000 then begin
            console.writestringln('AHCI: Timeout waiting for port ready (async read)');
            exit;
        end;
    end;

    { Record the pending operation before issuing (ISR may fire immediately) }
    device^.pending[slot].inUse      := true;
    device^.pending[slot].completion := completion;
    device^.pending[slot].userdata   := userdata;

    { Issue command \u2014 returns immediately }
    device^.port^.cmd_issue := device^.port^.cmd_issue or (1 shl slot);

    send_read_dma_async := true;
end;


function send_write_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;
var
    fis        : PHBA_FIS_REG_H2D;
    cmd_header : PHBA_CMD_HEADER;
    cmd_table  : PHBA_CMD_TABLE;
    i          : uint32;
    timeout    : uint32;
    sec_count  : uint32;
    prdt_count : uint32;
    slot       : uint32;
begin
    send_write_dma_async := false;

    prdt_count := (count div 4194304) + 1;
    if prdt_count > 32 then exit;

    slot := find_cmd_slot(device);
    if slot = $FFFFFFFF then exit;   { All 32 slots busy }

    cmd_header := PHBA_CMD_HEADER(uint32(device^.command_list) + (slot * sizeof(THBA_CMD_HEADER)));
    cmd_header^.cmd_fis_length := sizeof(THBA_FIS_REG_H2D) div sizeof(uint32);
    cmd_header^.wrt        := 1;
    cmd_header^.prdtl      := prdt_count;
    cmd_header^.clear_busy := 1;

    cmd_table := PHBA_CMD_TABLE(uint32(device^.command_table) + (slot * sizeof(THBA_CMD_TABLE)));

    for i := 0 to prdt_count - 1 do begin
        cmd_table^.prdt[i].dba := vtop(uint32(buffer) + (i * 4194304));
        if i = prdt_count - 1 then
            cmd_table^.prdt[i].dbc := count - (i * 4194304) - 1
        else
            cmd_table^.prdt[i].dbc := 4194304 - 1;
        cmd_table^.prdt[i].int := 1;
    end;

    fis := PHBA_FIS_REG_H2D(@cmd_table^.cmd_fis);
    memset(uint32(fis), 0, sizeof(THBA_FIS_REG_H2D));
    fis^.fis_type := uint8(FIS_TYPE_REG_H2D);
    fis^.c        := $1;
    fis^.command  := ATA_CMD_WRITE_DMA_EXT;
    fis^.device   := $40;

    fis^.lba0 := lba and $FF;
    fis^.lba1 := (lba shr 8)  and $FF;
    fis^.lba2 := (lba shr 16) and $FF;
    fis^.lba3 := (lba shr 24) and $FF;
    fis^.lba4 := (lba shr 32) and $FF;
    fis^.lba5 := (lba shr 40) and $FF;

    sec_count := count div 512;
    if sec_count = 0 then sec_count := 1;
    fis^.countl := sec_count and $FF;
    fis^.counth := (sec_count shr 8) and $FF;

    { Wait for TFD BSY+DRQ to clear }
    timeout := 0;
    while (device^.port^.tfd and $88) <> 0 do begin
        timeout := timeout + 1;
        if timeout > 100000 then begin
            console.writestringln('AHCI: Timeout waiting for port ready (async write)');
            exit;
        end;
    end;

    { Record the pending operation before issuing }
    device^.pending[slot].inUse      := true;
    device^.pending[slot].completion := completion;
    device^.pending[slot].userdata   := userdata;

    { Issue command \u2014 returns immediately }
    device^.port^.cmd_issue := device^.port^.cmd_issue or (1 shl slot);

    send_write_dma_async := true;
end;

//read atapi 
function read_atapi_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : boolean;
var
    fis        : PHBA_FIS_REG_H2D;
    cmd_header : PHBA_CMD_HEADER;
    cmd_table  : PHBA_CMD_TABLE;
    timeout    : uint32;
    sec_count  : uint32;
    prdt_count : uint32;
    slot       : uint32;
begin
    read_atapi_async := false;

    prdt_count := (count div 4194304) + 1;
    if prdt_count > 32 then exit;

    slot := find_cmd_slot(device);
    if slot = $FFFFFFFF then exit;

    cmd_header := PHBA_CMD_HEADER(uint32(device^.command_list) + (slot * sizeof(THBA_CMD_HEADER)));
    cmd_header^.cmd_fis_length := sizeof(THBA_FIS_REG_H2D) div sizeof(uint32);
    cmd_header^.wrt        := 0;
    cmd_header^.prdtl      := 1;
    cmd_header^.atapi      := 1;
    cmd_header^.clear_busy := 1;

    cmd_table := PHBA_CMD_TABLE(uint32(device^.command_table) + (slot * sizeof(THBA_CMD_TABLE)));
    cmd_table^.prdt[0].dba := vtop(uint32(buffer));
    cmd_table^.prdt[0].dbc := count - 1;
    cmd_table^.prdt[0].int := 1;

    fis := PHBA_FIS_REG_H2D(@cmd_table^.cmd_fis);
    memset(uint32(fis), 0, sizeof(THBA_FIS_REG_H2D));
    fis^.fis_type := uint8(FIS_TYPE_REG_H2D);
    fis^.c        := $1;
    fis^.command  := ATA_CMD_PACKET;
    fis^.device   := $A0;
    fis^.featurel := fis^.featurel or 1;
    fis^.featurel := fis^.featurel or (1 shl 2);

    { SCSI READ(12) CDB }
    memset(uint32(@cmd_table^.acmd[0]), 0, 16);
    cmd_table^.acmd[0] := $A8;

    cmd_table^.acmd[2] := uInt8((lba shr 24) and $FF);
    cmd_table^.acmd[3] := uInt8((lba shr 16) and $FF);
    cmd_table^.acmd[4] := uInt8((lba shr 8)  and $FF);
    cmd_table^.acmd[5] := uInt8(lba and $FF);

    sec_count := count div 2048;
    if sec_count = 0 then sec_count := 1;
    cmd_table^.acmd[6] := uInt8((sec_count shr 24) and $FF);
    cmd_table^.acmd[7] := uInt8((sec_count shr 16) and $FF);
    cmd_table^.acmd[8] := uInt8((sec_count shr 8)  and $FF);
    cmd_table^.acmd[9] := uInt8(sec_count and $FF);

    { Wait for TFD BSY+DRQ to clear }
    timeout := 0;
    while (device^.port^.tfd and $88) <> 0 do begin
        timeout := timeout + 1;
        if timeout > 100000 then begin
            console.writestringln('AHCI: Timeout waiting for port ready (async ATAPI)');
            exit;
        end;
    end;

    { Record the pending operation before issuing }
    device^.pending[slot].inUse      := true;
    device^.pending[slot].completion := completion;
    device^.pending[slot].userdata   := userdata;

    { Issue command \u2014 returns immediately }
    device^.port^.cmd_issue := device^.port^.cmd_issue or (1 shl slot);

    read_atapi_async := true;
end;

{ Send a SCSI READ CAPACITY (10) command to an ATAPI device via AHCI.
  Returns the total sector count and block size (typically 2048 for CD-ROM). }
function send_read_capacity(device : PAHCI_Device; sectorCount : puint32; blockSize : puint32) : boolean;
var
    fis         : PHBA_FIS_REG_H2D;
    cmd_header  : PHBA_CMD_HEADER;
    cmd_table   : PHBA_CMD_TABLE;
    cmd         : uint32;
    timeout     : uint32;
    tfd         : uint32;
    buffer      : puint32;
    slot        : uint32;
    rawLBA      : uint32;
    rawBlkSz    : uint32;
begin
    send_read_capacity := false;
    sectorCount^ := 0;
    blockSize^ := 0;

    { Allocate an 8-byte buffer for the READ CAPACITY response }
    buffer := kalloc(512);
    memset(uint32(buffer), 0, 512);

    slot := find_cmd_slot(device);
    cmd_header := PHBA_CMD_HEADER(uint32(device^.command_list) + (slot * sizeof(THBA_CMD_HEADER)));
    cmd_header^.cmd_fis_length := sizeof(THBA_FIS_REG_H2D) div sizeof(uint32);
    cmd_header^.wrt := 0;
    cmd_header^.prdtl := 1;
    cmd_header^.atapi := 1;
    cmd_header^.clear_busy := 1;

    cmd_table := PHBA_CMD_TABLE(uint32(device^.command_table) + (slot * sizeof(THBA_CMD_TABLE)));
    cmd_table^.prdt[0].dba := vtop(uint32(buffer));
    cmd_table^.prdt[0].dbc := 8 - 1;  { 8 bytes response }
    cmd_table^.prdt[0].int := 1;

    { Build the ATA PACKET command FIS }
    fis := PHBA_FIS_REG_H2D(@cmd_table^.cmd_fis);
    memset(uint32(fis), 0, sizeof(THBA_FIS_REG_H2D));
    fis^.fis_type := uint8(FIS_TYPE_REG_H2D);
    fis^.c   := $1;
    fis^.command  := ATA_CMD_PACKET;
    fis^.device   := $A0;
    fis^.featurel := fis^.featurel or 1;
    fis^.featurel := fis^.featurel or (1 shl 2);

    { Build the 12-byte SCSI READ CAPACITY(10) CDB }
    memset(uint32(@cmd_table^.acmd[0]), 0, 16);
    cmd_table^.acmd[0] := $25;  { READ CAPACITY(10) opcode }

    { Wait for port ready }
    timeout := 0;
    while (device^.port^.tfd and $88) <> 0 do begin
        timeout := timeout + 1;
        if timeout > 100000 then begin
            console.writestringln('AHCI: Timeout waiting for port ready (READ CAPACITY)');
            kfree(buffer);
            exit;
        end;
    end;

    { Issue the command }
    device^.port^.cmd_issue := device^.port^.cmd_issue or (1 shl slot);

    { Wait for completion }
    timeout := 0;
    repeat
        tfd := device^.port^.tfd;
        timeout := timeout + 1;
        if timeout > 100 then begin
            console.writestringln('AHCI: READ CAPACITY command timeout');
            kfree(buffer);
            exit;
        end;
        if (tfd and $1) <> 0 then break;  { ERR bit set }
        psleep(1);
    until ((device^.port^.cmd_issue and (1 shl slot)) = 0);

    if (device^.port^.cmd_issue and (1 shl slot)) <> 0 then begin
        console.writestringln('AHCI: Error sending READ CAPACITY command');
        console.writestring('AHCI: Error register: ');
        console.writehexln(device^.port^.sata_error);
        kfree(buffer);
        exit;
    end;

    { Parse the 8-byte response: bytes 0-3 = last LBA (big-endian), bytes 4-7 = block size (big-endian) }
    rawLBA := puint32(buffer)[0];
    rawBlkSz := puint32(buffer)[1];

    { Byte-swap from big-endian to little-endian }
    sectorCount^ := ((rawLBA and $FF) shl 24) or
                    ((rawLBA and $FF00) shl 8) or
                    ((rawLBA and $FF0000) shr 8) or
                    ((rawLBA and $FF000000) shr 24);
    sectorCount^ := sectorCount^ + 1; { Last LBA + 1 = total sectors }

    blockSize^ := ((rawBlkSz and $FF) shl 24) or
                  ((rawBlkSz and $FF00) shl 8) or
                  ((rawBlkSz and $FF0000) shr 8) or
                  ((rawBlkSz and $FF000000) shr 24);

    kfree(buffer);
    send_read_capacity := true;
end;

{ ---------- StorageManager async callback wrappers ---------- }

{ Async SATA read hook }
procedure ahci_read_hook_async(drive : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32; completion : TStorageCompletion; userdata : puint32);
var
    ahciDev    : PAHCI_Device;
begin
    ahciDev := PAHCI_Device(drive^.controllerId0);
    { Forward to the AHCI async primitive.
      TStorageCompletion and TIOCompletion share the same binary signature,
      so the cast is safe. }
    send_read_dma_async(ahciDev, addr, sectors * drive^.sectorSize, buffer, TIOCompletion(completion), userdata);
end;

{ Async SATA write hook }
procedure ahci_write_hook_async(drive : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32; completion : TStorageCompletion; userdata : puint32);
var
    ahciDev : PAHCI_Device;
begin
    ahciDev := PAHCI_Device(drive^.controllerId0);
    send_write_dma_async(ahciDev, addr, sectors * drive^.sectorSize, buffer, TIOCompletion(completion), userdata);
end;

{ Async ATAPI read hook }
procedure ahci_atapi_read_hook_async(drive : PStorage_Device; addr : uint32; sectors : uint32; buffer : puint32; completion : TStorageCompletion; userdata : puint32);
var
    ahciDev : PAHCI_Device;
begin
    ahciDev := PAHCI_Device(drive^.controllerId0);
    read_atapi_async(ahciDev, addr, sectors * drive^.sectorSize, buffer, TIOCompletion(completion), userdata);
end;

{ Poll hook — called from storage_read/write sync bridge when the AHCI
  hardware interrupt is not delivered through the PIC.  Simply drives
  ahci_isr() inline so pending completions are processed. }
procedure ahci_poll_hook();
begin
    ahci_isr();
end;

end.
