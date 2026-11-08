
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
	Drivers->Storage->driver.storage.ctl.ahci->driver.storage.ctl.ahci - driver.storage.ctl.ahci Driver.

	@author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.ctl.ahci;

interface

uses
    driver.storage.ctl.ahci.types,
    driver.mgr,
    driver.types,
    driver.storage.ctl.ide.types,
    arch.platform.interrupts,
    core.ds.lists,
    memory.heap,
    driver.bus.pci,
    driver.storage.mgr,
    driver.storage.types,
    io.syslog,
    core.util, arch.platform.cpu,
    arch.platform.memory;

var
    ahciControllers : PDList;
    page_base : puint32;

procedure UnitTest;
procedure init();
function load(ptr : void) : boolean;
procedure check_ports(controller : PAHCI_Controller);
function identify_device(controller : PAHCI_Controller; portIndex : uint32; isATAPI : boolean) : boolean;
procedure ahci_isr();
function find_cmd_slot(device : PAHCI_Device) : uint32;

{ Async primitives — return immediately after issuing the command.
  completion is called from IRQ context when the slot clears.
  completion may be nil if no callback is needed (e.g. init-time polling). }
function send_read_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : TError;
function send_write_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : TError;
function read_atapi_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : TError;

{ Storage-manager async callback wrappers }
{ Phase 3: TDriverDispatch procedures — bridge PIORequest to driver.storage.ctl.ahci DMA }
procedure ahci_dispatch_read(device : PStorage_Device; request : PIORequest);
procedure ahci_dispatch_write(device : PStorage_Device; request : PIORequest);
procedure ahci_dispatch_atapi_read(device : PStorage_Device; request : PIORequest);

function send_read_capacity(device : PAHCI_Device; sectorCount : puint32; blockSize : puint32) : boolean;


implementation

uses arch.platform.process, arch.platform.diagnostics, io.stdio, core.strings;

type
    PControllerSlot = ^PAHCI_Controller;

const
    AHCI_ENABLE_NCQ = true;
    AHCI_IO_TICKS = 80000; { about 10 seconds at the ~8 kHz PIT }
    AHCI_STOP_TICKS = 8000;
    AHCI_FATAL_MASK = $79000000; { TFES, HBFS, HBDS, IFS, OFS }
    AHCI_IRQ_MASK = $7900000B;

var watchdogDivider : uint32 = 0;

function build_prdt(table: PHBA_CMD_TABLE; address: PtrUInt; bytes: uint32; var entries: uint32; dma64: boolean): TError; forward;

procedure cmd_ahcitest(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf); forward;
procedure ahci_watchdog(data : void); forward;
procedure fail_controller(controller : PAHCI_Controller; error : TError); forward;

function min_u32(a : uint32; b : uint32) : uint32;
begin
    if a < b then
        min_u32 := a
    else
        min_u32 := b;
end;

procedure init();
var
    devID : TDeviceIdentifier;
begin
    io.syslog.writestringln('driver.storage.ctl.ahci: Registering driver');
    devID.bus:= biPCI;
    devID.id0:= idANY;
    devID.id1:= $00000001;
    devID.id2:= $00000006;
    devID.id3:= $00000001;
    devID.id4:= idANY;
    devID.ex:= nil;
    driver.mgr.register_driver('ATA/PI driver.storage.ctl.ahci Driver', @devID, @load);
    arch.platform.interrupts.registerTimer(@ahci_watchdog);
    io.stdio.registerCommand('AHCITEST',@cmd_ahcitest,'Run AHCI tests using simulated registers');
end;

{ Poll MMIO through a pointer on every iteration. The PIT runs at ~8 kHz;
  16 psleep ticks give a conservative ~2 ms poll interval, not a CPU-speed loop. }
function wait_register(reg : puint32; mask, expected, attempts : uint32) : boolean;
var n : uint32;
begin
    n := 0;
    repeat
        if (reg^ and mask) = expected then begin wait_register := true; exit; end;
        if n >= attempts then break;
        core.util.waitTicks(16); Inc(n);
    until false;
    wait_register := false;
end;

function stop_port(port : PHBA_Port) : boolean;
begin
    port^.cmd := port^.cmd and not $1;
    stop_port := wait_register(@port^.cmd,$8000,0,250);
    if not stop_port then exit;
    port^.cmd := port^.cmd and not $10;
    stop_port := wait_register(@port^.cmd,$4000,0,250);
end;

function start_port(port : PHBA_Port) : boolean;
begin
    start_port := wait_register(@port^.cmd,$8000,0,250);
    if not start_port then exit;
    port^.cmd := port^.cmd or $10;
    port^.cmd := port^.cmd or $1;
end;

{ DMA addresses must already be installed before enabling FIS reception. }
function reset_port(port : PHBA_Port) : boolean;
begin
    reset_port := false;
    port^.cmd := port^.cmd and not $1;
    if not wait_register(@port^.cmd,$8000,0,250) then exit;
    port^.int_enable := 0;
    port^.cmd := port^.cmd or $16; { FRE, power-on and spin-up }
    port^.sata_ctrl := (port^.sata_ctrl and $FFFFFFF0) or $1;
    core.util.waitTicks(16); { >= 1 ms COMRESET assertion at the ~8 kHz PIT rate }
    port^.sata_ctrl := port^.sata_ctrl and $FFFFFFF0;
    if not wait_register(@port^.sata_status,$F,3,500) then exit;
    if not wait_register(@port^.tfd,$88,0,2500) then exit;
    port^.sata_error := $FFFFFFFF;
    port^.int_status := $FFFFFFFF;
    reset_port := start_port(port);
end;

procedure log_port_failure(portIndex : uint32; port : PHBA_Port; reason : pchar);
begin
    io.syslog.log('AHCI','Port '); io.syslog.writeint(portIndex);
    io.syslog.writestring(': '); io.syslog.writestring(reason);
    io.syslog.writestring(' SSTS='); io.syslog.writehex(port^.sata_status);
    io.syslog.writestring(' SIG='); io.syslog.writehex(port^.signature);
    io.syslog.writestring(' TFD='); io.syslog.writehexln(port^.tfd);
end;

{
    Check the ports on the controller and setup the command list, FIS, and command table
}
procedure check_ports(controller : PAHCI_Controller);
var
    i : uint32;
    ii, attempt, signatureWait : uint32;
    registered : boolean;
    listAlloc, fisAlloc, tableAlloc : puint32;
    port : PHBA_Port;
    device : PAHCI_Device;
    cmd_list_base : puint32;
    fis_base : puint32;
    cmd_table_base : puint32;
    command_header : PHBA_CMD_HEADER;
begin
    for i:=0 to 31 do begin
        if controller^.offline then break;
        if ((controller^.mio^.ports_implimented shr i) and 1) = 1 then begin
            port := @controller^.mio^.ports[i];

            device := PAHCI_Device(@controller^.devices[i]);
            device^.port := port;
            device^.owner := controller;
            device^.supports64BitDMA := (controller^.mio^.capabilites and $80000000) <> 0;

            port^.int_enable := 0;
            if not stop_port(port) then begin log_port_failure(i,port,'cannot stop engine'); continue; end;
            { Bring up power before checking for an attached device. }
            port^.cmd := port^.cmd or $6;
            if not wait_register(@port^.sata_status,$F,3,100) then begin
                if (port^.sata_status and $F) = 0 then continue;
                { Present but not yet communicating: COMRESET below may recover it. }
            end;
            //allocate memory for the command list and ensure it is aligned to 1024 bytes
            // Need 32 command headers. Allocate extra (alignment-1) bytes for alignment.
            listAlloc := kalloc(sizeof(THBA_CMD_HEADER) * 32 + 1023);
            if listAlloc = nil then continue;
            cmd_list_base := listAlloc;
            cmd_list_base := puint32((PtrUInt(cmd_list_base) + 1023) and not PtrUInt(1023));

            //set the command list base address
            port^.cmdl_basel := arch.platform.memory.physicalAddress(PtrUInt(cmd_list_base)); //todo set virtual address in device
            port^.cmdl_baseu := arch.platform.memory.physicalAddress(PtrUInt(cmd_list_base)) shr 32;

            device^.command_list := PHBA_CMD_HEADER(cmd_list_base);

            //allocate memory for the FIS and ensure it is aligned to 256 bytes
            fisAlloc := kalloc(sizeof(THBA_FIS) + 255);
            if fisAlloc = nil then begin
                port^.cmdl_basel := 0;
                port^.cmdl_baseu := 0;
                kfree(listAlloc);
                continue;
            end;
            fis_base := fisAlloc;
            fis_base := puint32((PtrUInt(fis_base) + 255) and not PtrUInt(255));

            //set the FIS base address
            port^.fis_basel := arch.platform.memory.physicalAddress(PtrUInt(fis_base));
            port^.fis_baseu := arch.platform.memory.physicalAddress(PtrUInt(fis_base)) shr 32;


            device^.fis := PHBA_FIS(fis_base);
            //todo check how many simultaneous commands are supported

            // Each command table must fit inside one physical page.
            tableAlloc := kalloc(4096 * 32 + 4095);
            if tableAlloc = nil then begin
                port^.cmdl_basel := 0;
                port^.cmdl_baseu := 0;
                port^.fis_basel := 0;
                port^.fis_baseu := 0;
                kfree(listAlloc);
                kfree(fisAlloc);
                continue;
            end;
            cmd_table_base := tableAlloc;
            cmd_table_base := puint32((PtrUInt(cmd_table_base) + 4095) and not PtrUInt(4095));

            device^.command_table := PHBA_CMD_TABLE(cmd_table_base);

            //set the command table base address and setup command table
            for ii:=0 to 31 do begin
                //set command header locations
                command_header := PHBA_CMD_HEADER(PtrUInt(cmd_list_base) + (ii * sizeof(THBA_CMD_HEADER)));
                command_header^.prdtl := 32;
                command_header^.cmd_table_base := arch.platform.memory.physicalAddress(PtrUInt(cmd_table_base) + (ii * 4096));
                command_header^.cmd_table_baseu := arch.platform.memory.physicalAddress(PtrUInt(cmd_table_base) + ii * 4096) shr 32;
            end;

            if not device^.supports64BitDMA then begin
                registered := (port^.cmdl_baseu <> 0) or (port^.fis_baseu <> 0);
                for ii := 0 to 31 do begin
                    command_header := PHBA_CMD_HEADER(PtrUInt(cmd_list_base) + ii * sizeof(THBA_CMD_HEADER));
                    if command_header^.cmd_table_baseu <> 0 then registered := true;
                end;
                if registered then begin
                    port^.cmdl_basel := 0;
                    port^.cmdl_baseu := 0;
                    port^.fis_basel := 0;
                    port^.fis_baseu := 0;
                    device^.command_list := nil;
                    device^.fis := nil;
                    device^.command_table := nil;
                    kfree(listAlloc);
                    kfree(fisAlloc);
                    kfree(tableAlloc);
                    io.syslog.logln('AHCI', 'Controller cannot address allocated DMA structures.');
                    continue;
                end;
            end;

            registered := false;
            for attempt := 1 to 2 do begin
                if controller^.offline or device^.offline then break;
                if not reset_port(port) then begin log_port_failure(i,port,'reset/readiness timeout'); continue; end;
                signatureWait := 0;
                while (puint32(@port^.signature)^ = 0) or (puint32(@port^.signature)^ = $FFFFFFFF) do begin
                    if signatureWait >= 500 then break;
                    core.util.waitTicks(16); Inc(signatureWait);
                end;
                case puint32(@port^.signature)^ of
                    SATA_SIG_ATA: begin device^.device_type := SATA; registered := identify_device(controller,i,false); end;
                    SATA_SIG_ATAPI: begin device^.device_type := ATAPI; registered := identify_device(controller,i,true); end;
                else log_port_failure(i,port,'unsupported or missing signature');
                end;
                if registered then break;
                log_port_failure(i,port,'IDENTIFY failed; retrying detection');
            end;
            if not registered then begin
                port^.int_enable := 0;
                if not controller^.offline then
                    if not stop_port(port) then fail_controller(controller,eIOTimeout);
                begin
                    port^.cmdl_basel := 0; port^.fis_basel := 0;
                    kfree(listAlloc); kfree(fisAlloc); kfree(tableAlloc);
                    device^.command_list := nil; device^.fis := nil; device^.command_table := nil;
                end;
                log_port_failure(i,port,'device unavailable after bounded retries');
            end;

            controller^.mio^.int_status := $FFFFFFFF;
        end;
    end;
end;

function identify_device(controller : PAHCI_Controller; portIndex : uint32; isATAPI : boolean) : boolean;
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
    ncqDepth    : uint32;
    slotCount, entries : uint32;
    ncqSupported : boolean;
begin
    identify_device := false;
    device := PAHCI_Device(@controller^.devices[portIndex]);
    slotCount := ((controller^.mio^.capabilites shr 8) and $1F) + 1;
    device^.slotCount := slotCount;
    device^.supportsNCQ := false;
    device^.queueDepth := 1;

    //clear any pending interrupts
    device^.port^.int_status := $FFFFFFFF;
    device^.port^.int_enable := $0;   { disabled during IDENTIFY polling }

    // Allocate a 512-byte DMA buffer for the IDENTIFY d driver.storage.ctl.ide.ata
    buffer := kalloc(512);
    if buffer = nil then exit;
    memset(PtrUInt(buffer), 0, 512);

    // Use command slot 0 for the IDENTIFY command.
    cmd_header := device^.command_list;  // Assuming slot 0 is at the beginning.
    cmd_header^.cmd_fis_length := sizeof(THBA_FIS_REG_H2D) div sizeof(uint32);
    cmd_header^.wrt := 0;
    cmd_header^.prdtl := 1;
    cmd_header^.clear_busy := 1;
    cmd_header^.atapi := 0; { IDENTIFY PACKET is ATA $A1, not an ATAPI PACKET $A0 command }


    // Setup the command table (using slot 0)
    cmd_table := device^.command_table;
    if build_prdt(cmd_table, PtrUInt(buffer), 512, entries, device^.supports64BitDMA) <> eNone then begin
        kfree(buffer);
        exit;
    end;
    cmd_header^.prdtl := entries;

    // if isATAPI then begin
    // // ATAPI Identify Device command
    // buffer[0] := $A1;  // ATAPI Identify Device
    // end;

    // Construct the Command FIS in the command table's CFIS area
    fis := PHBA_FIS_REG_H2D(@device^.command_table^.cmd_fis);
    memset(PtrUInt(fis), 0, sizeof(THBA_FIS_REG_H2D));
    fis^.fis_type := uint8(FIS_TYPE_REG_H2D);
    fis^.c   := $1;
    if isATAPI then begin
        fis^.command  := ATA_CMD_IDENTIFY_PACKET;
    end else begin
        fis^.command  := ATA_CMD_IDENTIFY;
    end;
    fis^.device   := $40;

    if not wait_register(@device^.port^.tfd,$88,0,2500) then begin
        log_port_failure(portIndex,device^.port,'busy before IDENTIFY'); kfree(buffer); exit;
    end;
    device^.port^.cmd_issue := 1;
    if (not wait_register(@device^.port^.cmd_issue,1,0,2500)) or
       ((device^.port^.tfd and $1) <> 0) or ((device^.port^.int_status and $40000000) <> 0) then begin
        log_port_failure(portIndex,device^.port,'IDENTIFY timeout or task-file error');
        if not stop_port(device^.port) then fail_controller(controller,eIOTimeout);
        kfree(buffer);
        exit;
    end;
    device^.port^.int_status := $FFFFFFFF;

    { Re-enable port interrupts now that IDENTIFY polling is done.
      $4000000B = bit 0 (D2H Register FIS) | bit 1 (PIO Setup FIS) | bit 3 (Set Device Bits / NCQ) | bit 30 (Task File Error)
      Bit 3 is required for NCQ completion notifications via SDB FIS. }
    device^.port^.int_enable := AHCI_IRQ_MASK;

    b8 := puint16(buffer);
    memcpy(PtrUInt(buffer), PtrUInt(@device^.ata_info[0]), 512);
    sec_count := (b8[61] shl 16) or b8[60];
    ncqDepth := (b8[75] and $1F) + 1;
    ncqSupported := ((b8[76] and (1 shl 8)) <> 0) and (not isATAPI) and AHCI_ENABLE_NCQ and ((controller^.mio^.capabilites and (1 shl 30)) <> 0);
    if ncqSupported then begin
        device^.supportsNCQ := true;
        device^.queueDepth := min_u32(slotCount, ncqDepth);
    end else begin
        device^.supportsNCQ := false;
        device^.queueDepth := 1;
    end;

    kfree(buffer);

    { For ATAPI devices, get capacity from SCSI READ CAPACITY instead of IDENTIFY }
    if isATAPI then begin
        if send_read_capacity(device, @sec_count, @storageDev_sectorSize) then begin
        end else begin
            io.syslog.writestringln('driver.storage.ctl.ahci: ATAPI capacity query failed (no media?).');
            storageDev_sectorSize := 2048;
            sec_count := 0;
        end;
    end else begin
        storageDev_sectorSize := 512;
    end;

    { Register this device with the storage manager.
      ATAPI devices (optical drives) are always registered even with 0 sectors (no media). }
    if (sec_count > 0) or isATAPI then begin
        storageDev := PStorage_Device(kalloc(sizeof(TStorage_Device)));
        memset(PtrUInt(storageDev), 0, sizeof(TStorage_Device));

        storageDev^.controllerId0  := PtrUInt(device);  { store PAHCI_Device for callback wrappers }
        storageDev^.sectorSize     := storageDev_sectorSize;
        storageDev^.maxSectorCount := sec_count;
        if not isATAPI then storageDev^.mergeMaxSectors := 65536;
        storageDev^.start          := 0;
        storageDev^.volumes        := DL_New(sizeof(Pointer));

        if isATAPI then begin
            storageDev^.controller := TControllerType.ControllerAHCI_ATAPI;
            storageDev^.writable   := false;
            storageDev^.dispatchRead       := TDriverDispatch(@ahci_dispatch_atapi_read);
            storageDev^.dispatchWrite      := TDriverDispatch(nil);
            storageDev^.maxActive          := 1;
        end else begin
            storageDev^.controller := TControllerType.ControllerAHCI;
            storageDev^.writable   := true;
            storageDev^.dispatchRead       := TDriverDispatch(@ahci_dispatch_read);
            storageDev^.dispatchWrite      := TDriverDispatch(@ahci_dispatch_write);
            storageDev^.maxActive          := device^.queueDepth;
        end;

        driver.storage.mgr.register_device(storageDev);
        kfree(void(storageDev)); { manager owns a copy }
        identify_device := true;

        io.syslog.writestring('driver.storage.ctl.ahci: Registered device on port ');
        io.syslog.writeint(portIndex);
        if sec_count > 0 then begin
            io.syslog.writestring(' with storage manager (');
            io.syslog.writeint((uint64(sec_count) * storageDev_sectorSize) div 1024 div 1024);
            io.syslog.writestringln(' MB)');
        end else begin
            io.syslog.writestringln(' with storage manager (no media)');
        end;
    end else begin
        io.syslog.writestring('driver.storage.ctl.ahci: Port ');
        io.syslog.writeint(portIndex);
        io.syslog.writestringln(': sector count is 0, skipping registration.');
    end;



end;


// procedure controller_reset(controller : PAHCI_Controller);
// begin
//     //check sam TODO
//     if (controller^.mio^.capabilites2 and $1) = 0 then begin
//         io.syslog.writestringln('driver.storage.ctl.ahci: Controller does not support reset');
//         exit;
//     end;

//     //check ghc.ae is set to 1
//     if (controller^.mio^.global_ctrl and $1) = 0 then begin
//         io.syslog.writestringln('driver.storage.ctl.ahci: Controller is not enabled');
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
    irqFlags: PtrUInt;

    device : PPCI_Device;
    controller : PAHCI_Controller;
    i : uint32;
    base : PHBA_Memory;
    cmd_list_base : puint32;
    fis_base : puint32;
    cmd_table_base : puint32;
    int_no : uInt8;
    timeout : uint32;
    flags : uint32;
begin
    if ahciControllers = nil then begin
        ahciControllers := DL_New(SizeOf(Pointer));
    end;

    device := PPCI_Device(ptr);

    driver.bus.pci.enableDevice(device^.bus, device^.slot, device^.func);
    core.util.waitTicks(5);
    int_no := device^.interrupt_line + 32;

    load := false;
    controller := PAHCI_Controller(kalloc(sizeof(TAHCI_Controller)));
    if controller = nil then exit;

    controller^.pci_device := PPCI_Device(device);

//     Perform BIOS/OS handoff (if the bit in the extended capabilities is set)
//     Reset controller

    //get the base address of the controller
    page_base := arch.platform.memory.mapDevice(device^.address5 and $FFFFFFF0, sizeof(THBA_Memory)); // TODO MEM memory manager need to be improved
    base := PHBA_Memory(page_base);
    if base = nil then begin
        kfree(void(controller));
        exit;
    end;
    controller^.mio := base;

    if (base^.capabilites2 and 1) <> 0 then begin
        base^.bohc := base^.bohc or 2;
        if not wait_register(@base^.bohc,$11,0,1000) then begin
            io.syslog.logln('AHCI','BIOS handoff timed out; controller not started.');
            kfree(void(controller)); exit;
        end;
    end;
    base^.global_ctrl := base^.global_ctrl or AHCI_CONTROLLER_MODE or 1;
    if not wait_register(@base^.global_ctrl,1,0,500) then begin
        io.syslog.logln('AHCI','Controller reset timed out; controller not started.');
        driver.bus.pci.setBusMaster(device^.bus,device^.slot,device^.func,false);
        kfree(void(controller)); exit;
    end;
    { Publish a stable heap pointer, never an interior pointer into a growing DList. }
    irqFlags := arch.platform.cpu.lock;
    DL_Add(ahciControllers); DL_Set(ahciControllers,DL_Size(ahciControllers)-1,puint32(@controller));
    arch.platform.cpu.unlock(irqFlags);

    arch.platform.interrupts.registerIRQ(int_no, @ahci_isr);

    io.syslog.writestring('driver.storage.ctl.ahci: IRQ ');
    io.syslog.writeint(device^.interrupt_line);
    io.syslog.writestring(' -> INT ');
    io.syslog.writeint(int_no);
    io.syslog.writestringln('');

    { Initialise IOAPIC/LAPIC support (safe no-op if no IOAPIC present).
      driver.bus.pci interrupts may be routed through the IOAPIC instead of the
      legacy 8259 PIC — without programming the IOAPIC redirection
      entry the interrupt never reaches the CPU. }
    arch.platform.interrupts.routePCI(device^.interrupt_line, int_no);

    //enable driver.storage.ctl.ahci mode
    base^.global_ctrl := base^.global_ctrl or AHCI_CONTROLLER_MODE;

    //enable interrupts (GHC.IE = bit 1)
    base^.global_ctrl := base^.global_ctrl or $2;

    //clear any pending interrupts
    base^.int_status := $FFFFFFFF;

    check_ports(controller);
    load := not controller^.offline;
end;

function now_tick : uint32;
begin now_tick := arch.platform.process.timerTicks; end;

{ Only complete commands whose DMA ownership has ended. Callback re-entry may
  submit more work, so consume a fixed mask rather than rescanning new slots. }
procedure finish_slots(device : PAHCI_Device; mask : uint32; error : TError);
var slot : uint32; cb : TIOCompletion; data : puint32;
begin
    for slot := 0 to 31 do if (mask and (uint32(1) shl slot)) <> 0 then begin
        if device^.pending[slot].inUse and device^.pending[slot].issued then begin
            cb := device^.pending[slot].completion; data := device^.pending[slot].userdata;
            device^.pending[slot].inUse := false; device^.pending[slot].issued := false;
            device^.pending[slot].completion := nil; device^.pending[slot].userdata := nil;
            if cb <> nil then cb(error,data);
        end;
    end;
end;

procedure fail_controller(controller : PAHCI_Controller; error : TError);
var j, command : uint32; pci : PPCI_Device; device : PAHCI_Device;
begin
    if controller = nil then exit;
    controller^.offline := true;
    pci := controller^.pci_device;
    { Last resort: fence DMA for the whole controller before returning buffers.
      Write only PCI command bits, not the adjacent write-one-to-clear status. }
    driver.bus.pci.requestConfig(pci^.bus,pci^.slot,pci^.func,1);
    command := inl($CFC) and $FFFF;
    driver.bus.pci.writeConfig(pci^.bus,pci^.slot,pci^.func,1,command and not uint32(4));
    driver.bus.pci.requestConfig(pci^.bus,pci^.slot,pci^.func,1);
    command := inl($CFC);
    if (command <> $FFFFFFFF) and ((command and 4) <> 0) then
        arch.platform.diagnostics.fatal('AHCI DMA cannot be stopped','PCI bus mastering could not be disabled');
    controller^.mio^.global_ctrl := controller^.mio^.global_ctrl and not uint32(2);
    { Reject all new work before any callback drains a queued request. }
    for j := 0 to 31 do controller^.devices[j].offline := true;
    for j := 0 to 31 do begin
        device := @controller^.devices[j];
        device^.recovering := false;
        if device^.port <> nil then begin
            device^.port^.int_enable := 0;
            device^.port^.cmd := device^.port^.cmd and not uint32($11);
        end;
        finish_slots(device,$FFFFFFFF,error);
    end;
    io.syslog.logln('AHCI','Controller taken offline after DMA stop timeout.');
end;

procedure begin_recovery(device : PAHCI_Device; error : TError);
begin
    if device^.recovering or device^.offline then exit;
    device^.offline := true; device^.recovering := true;
    device^.recoveryTick := now_tick; device^.recoveryError := error;
    device^.port^.int_enable := 0;
    device^.port^.cmd := device^.port^.cmd and not uint32(1);
    io.syslog.logln('AHCI','I/O failed or timed out; stopping port before releasing DMA buffers.');
end;

{ Nonblocking; called by IRQ and the timer watchdog with interrupts disabled. }
procedure service_port(device : PAHCI_Device; now, status : uint32);
var active, doneMask, pendingMask, slot : uint32; expired : boolean;
begin
    if device^.port = nil then exit;
    if device^.recovering then begin
        if (puint32(@device^.port^.cmd)^ and $8000) = 0 then begin
            device^.port^.cmd := device^.port^.cmd and not uint32($10);
            if (puint32(@device^.port^.cmd)^ and $4000) = 0 then begin
                device^.recovering := false;
                device^.port^.int_status := $FFFFFFFF;
                finish_slots(device,$FFFFFFFF,device^.recoveryError);
                exit;
            end;
        end;
        if uint32(now-device^.recoveryTick) >= AHCI_STOP_TICKS then
            fail_controller(PAHCI_Controller(device^.owner),device^.recoveryError);
        exit;
    end;
    if device^.offline then exit;
    active := puint32(@device^.port^.cmd_issue)^ or puint32(@device^.port^.sata_active)^;
    doneMask := 0; pendingMask := 0; expired := false;
    for slot := 0 to 31 do if device^.pending[slot].inUse and device^.pending[slot].issued then begin
        pendingMask := pendingMask or (uint32(1) shl slot);
        if (active and (uint32(1) shl slot)) = 0 then doneMask := doneMask or (uint32(1) shl slot)
        else if uint32(now-device^.pending[slot].started) >= AHCI_IO_TICKS then expired := true;
    end;
    if pendingMask = 0 then exit; { polling IDENTIFY owns its own recovery }
    if (status and AHCI_FATAL_MASK) <> 0 then begin
        begin_recovery(device,eIOError); exit;
    end;
    if (doneMask <> 0) and ((device^.port^.tfd and $1) <> 0) then begin
        begin_recovery(device,eIOError); exit;
    end;
    if expired then begin begin_recovery(device,eIOTimeout); exit; end;
    finish_slots(device,doneMask,eNone);
end;

procedure ahci_isr();
var i,j,ctrlIS,portIS : uint32; controller : PAHCI_Controller; device : PAHCI_Device;
begin
    if (ahciControllers = nil) or (DL_Size(ahciControllers) = 0) then exit;
    for i := 0 to DL_Size(ahciControllers)-1 do begin
        controller := PControllerSlot(DL_Get(ahciControllers,i))^;
        if controller^.offline then continue;
        ctrlIS := controller^.mio^.int_status;
        if ctrlIS = 0 then continue;
        { Acknowledge before callbacks can submit a new command/interrupt. }
        for j := 0 to 31 do if (ctrlIS and (uint32(1) shl j)) <> 0 then begin
            device := @controller^.devices[j];
            if device^.port = nil then continue;
            portIS := device^.port^.int_status;
            device^.port^.int_status := portIS;
            controller^.mio^.int_status := uint32(1) shl j;
            service_port(device,now_tick,portIS);
        end;
    end;
end;

procedure ahci_watchdog(data : void);
var i,j,now : uint32; controller : PAHCI_Controller;
begin
    Inc(watchdogDivider); if watchdogDivider < 80 then exit; watchdogDivider := 0;
    if (ahciControllers = nil) or (DL_Size(ahciControllers) = 0) then exit;
    now := now_tick;
    for i := 0 to DL_Size(ahciControllers)-1 do begin
        controller := PControllerSlot(DL_Get(ahciControllers,i))^;
        if controller^.offline then continue;
        for j := 0 to 31 do
            if controller^.devices[j].slotCount <> 0 then service_port(@controller^.devices[j],now,controller^.devices[j].port^.int_status);
    end;
end;

{ Atomic reserve: software ownership precedes descriptor construction. }
function find_cmd_slot(device : PAHCI_Device) : uint32;
var
    irqFlags: PtrUInt;
    flags, slot, active, count : uint32;
begin
    find_cmd_slot := $FFFFFFFF;
    if (device = nil) or (device^.port = nil) then exit;
    irqFlags := arch.platform.cpu.lock;
    if not device^.offline then begin
        active := device^.port^.cmd_issue or device^.port^.sata_active;
        count := device^.slotCount; if count > 32 then count := 32;
        if not device^.supportsNCQ then if count > 1 then count := 1;
        if count > 0 then for slot := 0 to count-1 do begin
            if ((active and (uint32(1) shl slot)) = 0) and (not device^.pending[slot].inUse) then begin
                device^.pending[slot].inUse := true; device^.pending[slot].issued := false;
                find_cmd_slot := slot; break;
            end;
        end;
    end;
    arch.platform.cpu.unlock(irqFlags);
end;

{ Split at the kernel's 4 MiB virtual mapping boundaries. Every segment gets
  its own physical translation, including buffers with an unaligned start. }
function build_prdt(table: PHBA_CMD_TABLE; address: PtrUInt; bytes: uint32; var entries: uint32; dma64: boolean): TError;
var
    remaining, chunk, previousBytes: uint32;
    physical, previous: uint64;
begin
    build_prdt := eInvalidArgument;
    entries := 0;
    if (bytes = 0) or ((address and 1) <> 0) or ((bytes and 1) <> 0) or
       (bytes > High(PtrUInt) - address) then exit;
    remaining := bytes;
    while remaining > 0 do begin
        physical := arch.platform.memory.physicalAddress(address);
        if physical = 0 then exit;
        if not dma64 and (physical > $FFFFFFFF) then exit;
        chunk := 4096 - (address and 4095);
        if chunk > remaining then chunk := remaining;
        previousBytes := 0;
        if (entries > 0) and ((address and $3FFFFF) <> 0) then begin
            previous := uint64(table^.prdt[entries - 1].dba) or
                (uint64(table^.prdt[entries - 1].dbau) shl 32);
            previousBytes := table^.prdt[entries - 1].dbc + 1;
            if (previous + previousBytes <> physical) or
               (previousBytes + chunk > $400000) then previousBytes := 0;
        end;
        if previousBytes <> 0 then
            table^.prdt[entries - 1].dbc := previousBytes + chunk - 1
        else begin
            if entries = 32 then exit;
            table^.prdt[entries].dba := uint32(physical);
            table^.prdt[entries].dbau := uint32(physical shr 32);
            table^.prdt[entries].rsv0 := 0;
            table^.prdt[entries].reserved := 0;
            table^.prdt[entries].dbc := chunk - 1;
            table^.prdt[entries].int := 0;
            inc(entries);
        end;
        inc(address, chunk);
        dec(remaining, chunk);
    end;
    table^.prdt[entries - 1].int := 1;
    build_prdt := eNone;
end;

{ mode: 0 SATA read, 1 SATA write, 2 ATAPI READ(12), 3 READ CAPACITY. }
function submit_command(device : PAHCI_Device; lba : uint64; bytes : uint32; buffer : puint32;
                        mode : uint32; completion : TIOCompletion; userdata : puint32) : TError;
var
    irqFlags: PtrUInt;
    slot, entries, sectors, flags : uint32; header : PHBA_CMD_HEADER; table : PHBA_CMD_TABLE;
    fis : PHBA_FIS_REG_H2D; err : TError;
begin
    submit_command := eInvalidArgument;
    if (device = nil) or (buffer = nil) or (bytes = 0) then exit;
    if (device^.port = nil) or (device^.command_list = nil) or (device^.command_table = nil) then exit;
    if device^.offline then begin submit_command := eDeviceNotReady; exit; end;
    if mode < 2 then begin
        if ((bytes mod 512) <> 0) or (bytes > 33554432) or (lba > $FFFFFFFFFFFF) then exit;
        sectors := bytes div 512;
        if uint64(sectors-1) > $FFFFFFFFFFFF-lba then exit;
    end else if mode = 2 then begin
        if ((bytes mod 2048) <> 0) or (lba > $FFFFFFFF) then exit;
        sectors := bytes div 2048;
        if uint64(sectors-1) > $FFFFFFFF-lba then exit;
    end else begin
        if (mode <> 3) or (bytes <> 8) then exit;
        sectors := 0;
    end;
    slot := find_cmd_slot(device);
    if slot = $FFFFFFFF then begin submit_command := eNoFreeSlot; exit; end;
    header := @device^.command_list[slot]; table := PHBA_CMD_TABLE(PtrUInt(device^.command_table) + slot * 4096);
    { Preserve the command-table pointer but reset every per-command header flag. }
    puint32(header)^ := 0; header^.prdbc := 0;
    header^.cmd_fis_length := sizeof(THBA_FIS_REG_H2D) div 4;
    if mode = 1 then header^.wrt := 1;
    if mode >= 2 then header^.atapi := 1;
    memset(PtrUInt(table),0,128);
    err := build_prdt(table,PtrUInt(buffer),bytes,entries,device^.supports64BitDMA);
    if err = eNone then begin
        header^.prdtl := entries; fis := PHBA_FIS_REG_H2D(@table^.cmd_fis);
        fis^.fis_type := uint8(FIS_TYPE_REG_H2D); fis^.c := 1;
        if mode < 2 then begin
            fis^.device := $40;
            fis^.lba0 := lba and $FF; fis^.lba1 := (lba shr 8) and $FF;
            fis^.lba2 := (lba shr 16) and $FF; fis^.lba3 := (lba shr 24) and $FF;
            fis^.lba4 := (lba shr 32) and $FF; fis^.lba5 := (lba shr 40) and $FF;
            if device^.supportsNCQ then begin
                if mode = 0 then fis^.command := ATA_CMD_READ_FPDMA_QUEUED else fis^.command := ATA_CMD_WRITE_FPDMA_QUEUED;
                fis^.featurel := sectors and $FF; fis^.featureh := (sectors shr 8) and $FF;
                fis^.countl := slot shl 3;
            end else begin
                if mode = 0 then fis^.command := ATA_CMD_READ_DMA_EXT else fis^.command := ATA_CMD_WRITE_DMA_EXT;
                fis^.countl := sectors and $FF; fis^.counth := (sectors shr 8) and $FF;
            end;
        end else begin
            fis^.command := ATA_CMD_PACKET; fis^.device := $A0; fis^.featurel := 1;
            if mode = 3 then table^.acmd[0] := $25
            else begin
                table^.acmd[0] := $A8;
                table^.acmd[2] := (lba shr 24) and $FF; table^.acmd[3] := (lba shr 16) and $FF;
                table^.acmd[4] := (lba shr 8) and $FF; table^.acmd[5] := lba and $FF;
                table^.acmd[6] := (sectors shr 24) and $FF; table^.acmd[7] := (sectors shr 16) and $FF;
                table^.acmd[8] := (sectors shr 8) and $FF; table^.acmd[9] := sectors and $FF;
            end;
        end;
    end;
    irqFlags := arch.platform.cpu.lock;
    if err = eNone then begin
        if device^.offline then err := eDeviceNotReady
        else if (device^.port^.tfd and $88) <> 0 then err := eDeviceNotReady;
    end;
    if err = eNone then begin
        device^.pending[slot].completion := completion; device^.pending[slot].userdata := userdata;
        device^.pending[slot].started := now_tick; device^.pending[slot].issued := true;
        { RW1 registers: never write a stale snapshot of other command bits. }
        if (mode < 2) and device^.supportsNCQ then device^.port^.sata_active := uint32(1) shl slot;
        device^.port^.cmd_issue := uint32(1) shl slot;
    end else device^.pending[slot].inUse := false;
    arch.platform.cpu.unlock(irqFlags);
    submit_command := err;
end;

function send_read_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : TError;
begin send_read_dma_async := submit_command(device,lba,count,buffer,0,completion,userdata); end;
function send_write_dma_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : TError;
begin send_write_dma_async := submit_command(device,lba,count,buffer,1,completion,userdata); end;
function read_atapi_async(device : PAHCI_Device; lba : uint64; count : uint32; buffer : puint32; completion : TIOCompletion; userdata : puint32) : TError;
begin read_atapi_async := submit_command(device,lba,count,buffer,2,completion,userdata); end;

type TCapacityWait = record Done : uint32; Error : TError; end;
     PCapacityWait = ^TCapacityWait;
procedure capacity_done(error : TError; userdata : puint32);
var state : PCapacityWait;
begin state := PCapacityWait(userdata); state^.Error := error; puint32(@state^.Done)^ := 1; end;

function send_read_capacity(device : PAHCI_Device; sectorCount : puint32; blockSize : puint32) : boolean;
var flags: PtrUInt; buffer : puint32; state : TCapacityWait; rawLBA, rawBlkSz : uint32; err : TError;
begin
    send_read_capacity := false; sectorCount^ := 0; blockSize^ := 0;
    flags := arch.platform.cpu.lock;
    arch.platform.cpu.unlock(flags);
    if (flags and $200) = 0 then exit; { init/task context only }
    buffer := kalloc(512); if buffer = nil then exit;
    memset(PtrUInt(buffer),0,512); state.Done := 0; state.Error := eNone;
    err := submit_command(device,0,8,buffer,3,@capacity_done,puint32(@state));
    if err = eNone then begin
        { The watchdog ends ownership only after stopping DMA on error/timeout. }
        while puint32(@state.Done)^ = 0 do arch.platform.cpu.idle;
        err := state.Error;
    end;
    if err = eNone then begin
        rawLBA := buffer[0]; rawBlkSz := buffer[1];
        rawLBA := ((rawLBA and $FF) shl 24) or ((rawLBA and $FF00) shl 8) or
                  ((rawLBA and $FF0000) shr 8) or ((rawLBA and $FF000000) shr 24);
        rawBlkSz := ((rawBlkSz and $FF) shl 24) or ((rawBlkSz and $FF00) shl 8) or
                    ((rawBlkSz and $FF0000) shr 8) or ((rawBlkSz and $FF000000) shr 24);
        if (rawLBA <> $FFFFFFFF) and (rawBlkSz = 2048) then begin
            sectorCount^ := rawLBA+1; blockSize^ := rawBlkSz; send_read_capacity := true;
        end;
    end;
    kfree(buffer);
end;

{ ---------- StorageManager async callback wrappers ---------- }

{ ========================================================================== }
{              Phase 3: TDriverDispatch bridge to driver.storage.ctl.ahci DMA                   }
{ ========================================================================== }

{ ISR-safe completion — bridges from per-slot TIOCompletion callback to
  driver.storage.mgr.complete_io.  userdata is the PIORequest pointer. }
procedure ahci_io_completion(error : TError; userdata : puint32);
var request : PIORequest;
begin
    request := PIORequest(userdata);
    if error = eNone then request^.ByteCount := request^.SectorCount*request^.Device^.sectorSize;
    driver.storage.mgr.complete_io(request,error = eNone,error);
end;

{ TDriverDispatch — SATA read via DMA }
procedure ahci_dispatch_read(device : PStorage_Device; request : PIORequest);
var
    ahciDev : PAHCI_Device;
    err     : TError;
begin
    if (device^.sectorSize = 0) or (request^.SectorCount = 0) or
       (request^.SectorCount > $FFFFFFFF div device^.sectorSize) or
       (request^.LBA >= device^.maxSectorCount) or
       (request^.SectorCount > device^.maxSectorCount-request^.LBA) then begin
        driver.storage.mgr.complete_io(request,false,eInvalidArgument); exit;
    end;
    ahciDev := PAHCI_Device(device^.controllerId0);
    err := send_read_dma_async(ahciDev, request^.LBA,
            request^.SectorCount * device^.sectorSize,
            puint32(request^.Buffer),
            @ahci_io_completion, puint32(request));
    if err <> eNone then
        driver.storage.mgr.complete_io(request, false, err);
end;

{ TDriverDispatch — SATA write via DMA }
procedure ahci_dispatch_write(device : PStorage_Device; request : PIORequest);
var
    ahciDev : PAHCI_Device;
    err     : TError;
begin
    if (device^.sectorSize = 0) or (request^.SectorCount = 0) or
       (request^.SectorCount > $FFFFFFFF div device^.sectorSize) or
       (request^.LBA >= device^.maxSectorCount) or
       (request^.SectorCount > device^.maxSectorCount-request^.LBA) then begin
        driver.storage.mgr.complete_io(request,false,eInvalidArgument); exit;
    end;
    ahciDev := PAHCI_Device(device^.controllerId0);
    err := send_write_dma_async(ahciDev, request^.LBA,
            request^.SectorCount * device^.sectorSize,
            puint32(request^.Buffer),
            @ahci_io_completion, puint32(request));
    if err <> eNone then
        driver.storage.mgr.complete_io(request, false, err);
end;

{ TDriverDispatch — ATAPI read via SCSI READ(12) }
procedure ahci_dispatch_atapi_read(device : PStorage_Device; request : PIORequest);
var
    ahciDev : PAHCI_Device;
    err     : TError;
begin
    if (device^.sectorSize = 0) or (request^.SectorCount = 0) or
       (request^.SectorCount > $FFFFFFFF div device^.sectorSize) or
       (request^.LBA >= device^.maxSectorCount) or
       (request^.SectorCount > device^.maxSectorCount-request^.LBA) then begin
        driver.storage.mgr.complete_io(request,false,eInvalidArgument); exit;
    end;
    ahciDev := PAHCI_Device(device^.controllerId0);
    err := read_atapi_async(ahciDev, request^.LBA,
            request^.SectorCount * device^.sectorSize,
            puint32(request^.Buffer),
            @ahci_io_completion, puint32(request));
    if err <> eNone then
        driver.storage.mgr.complete_io(request, false, err);
end;


{ Synthetic MMIO only: these tests never issue I/O to a real disk. }
type TTestCompletion = record Count : uint32; Error : TError; end;
     PTestCompletion = ^TTestCompletion;
procedure test_done(error : TError; data : puint32);
begin
    Inc(PTestCompletion(data)^.Count); PTestCompletion(data)^.Error := error;
end;

procedure run_ahci_tests(stdout_buf : POutBuf);
var device : PAHCI_Device; port : PHBA_Port; table : PHBA_CMD_TABLE;
    buffer : pointer; aligned: PtrUInt; entries, first, second, passed, failed, i, total : uint32;
    result : TError; completed : TTestCompletion; msg, number : pchar;
    procedure Assert(ok : boolean; name : pchar);
    begin
        if ok then Inc(passed) else begin
            Inc(failed); io.syslog.log('AHCITEST','FAIL: '); io.syslog.writestringln(name);
            if stdout_buf <> nil then begin
                io.stdio.bufWriteStr(stdout_buf,'FAIL: '); io.stdio.bufWriteStrLn(stdout_buf,name);
            end;
        end;
    end;
    procedure reset_fake;
    begin
        memset(PtrUInt(port),0,sizeof(THBA_Port));
        memset(PtrUInt(@device^.pending),0,sizeof(device^.pending));
        device^.offline := false; device^.recovering := false;
        device^.supportsNCQ := true; completed.Count := 0; completed.Error := eNone;
    end;
begin
    passed := 0; failed := 0;
    device := PAHCI_Device(kalloc(sizeof(TAHCI_Device)));
    port := PHBA_Port(kalloc(sizeof(THBA_Port))); device^.port := port;
    device^.command_list := PHBA_CMD_HEADER(kalloc(32*sizeof(THBA_CMD_HEADER)));
    device^.command_table := PHBA_CMD_TABLE(kalloc(32*4096));
    device^.slotCount := 32; table := device^.command_table;
    buffer := kalloc($800000); aligned := (PtrUInt(buffer)+$3FFFFF) and not PtrUInt($3FFFFF);
    device^.supports64BitDMA := true;
    reset_fake;
    Assert(build_prdt(table,aligned,$400000,entries,true)=eNone,'exact 4 MiB accepted');
    total := 0;
    if entries > 0 then
        for i := 0 to entries - 1 do inc(total, table^.prdt[i].dbc + 1);
    Assert((entries > 0) and (total = $400000), 'PRDs cover the complete transfer');
    Assert(build_prdt(table,aligned-512,1024,entries,true)=eNone,'cross-page transfer accepted');
    Assert((entries=2) and (table^.prdt[0].dbc=511) and (table^.prdt[1].dbc=511),'cross-page segments bounded');
    Assert(((uint64(table^.prdt[0].dba) or (uint64(table^.prdt[0].dbau) shl 32))=arch.platform.memory.physicalAddress(aligned-512)) and ((uint64(table^.prdt[1].dba) or (uint64(table^.prdt[1].dbau) shl 32))=arch.platform.memory.physicalAddress(aligned)),'each page translated independently');
    Assert((table^.prdt[0].int=0) and (table^.prdt[1].int=1),'only final PRD interrupts');
    Assert(build_prdt(table,aligned,0,entries,true)=eInvalidArgument,'zero length rejected');
    Assert(build_prdt(table,aligned+1,512,entries,true)=eInvalidArgument,'odd address rejected');
    Assert(build_prdt(table,aligned,513,entries,true)=eInvalidArgument,'odd length rejected');
    Assert(build_prdt(table,High(PtrUInt)-$FF,512,entries,true)=eInvalidArgument,'address wrap rejected');
    first := find_cmd_slot(device); second := find_cmd_slot(device);
    Assert((first=0) and (second=1),'reservation excludes concurrent builder');
    service_port(device,now_tick,AHCI_FATAL_MASK);
    Assert(device^.pending[0].inUse and not device^.offline,'unissued reservation not completed or recovered');
    reset_fake; device^.supportsNCQ := false;
    first := find_cmd_slot(device); second := find_cmd_slot(device);
    Assert((first=0) and (second=$FFFFFFFF),'non-NCQ serializes commands');
    reset_fake; port^.cmd_issue := $20; port^.sata_active := $20;
    result := send_read_dma_async(device,0,512,puint32(buffer),@test_done,puint32(@completed));
    Assert(result=eNone,'valid read accepted');
    Assert((port^.cmd_issue=1) and (port^.sata_active=1),'issue writes only newly set bit');
    Assert(device^.pending[0].issued,'ownership published before issuing');
    port^.cmd_issue := 0; port^.sata_active := 0;
    service_port(device,now_tick,0); service_port(device,now_tick,0);
    Assert((completed.Count=1) and (completed.Error=eNone),'successful completion exactly once');
    reset_fake;
    Assert(send_read_dma_async(device,0,513,puint32(buffer),nil,nil)=eInvalidArgument,'partial sector rejected');
    Assert(send_read_dma_async(device,0,33554944,puint32(buffer),nil,nil)=eInvalidArgument,'ATA count overflow rejected');
    Assert(send_read_dma_async(device,$FFFFFFFFFFFF,1024,puint32(buffer),nil,nil)=eInvalidArgument,'ATA LBA wrap rejected');
    Assert(read_atapi_async(device,$FFFFFFFF,4096,puint32(buffer),nil,nil)=eInvalidArgument,'ATAPI LBA wrap rejected');
    Assert((port^.cmd_issue=0) and not device^.pending[0].inUse,'invalid requests do not acquire DMA ownership');
    port^.tfd := $80;
    Assert(send_read_dma_async(device,0,512,puint32(buffer),nil,nil)=eDeviceNotReady,'busy device fails without spinning');
    Assert(not device^.pending[0].inUse,'rejected command releases reservation');
    reset_fake;
    result := send_read_dma_async(device,0,512,puint32(buffer),@test_done,puint32(@completed));
    port^.cmd := $C011;
    service_port(device,now_tick,$40000000);
    Assert(device^.recovering and (completed.Count=0),'task-file error begins recovery without releasing buffer');
    service_port(device,device^.recoveryTick,0);
    Assert((completed.Count=0) and device^.pending[0].inUse,'CR retains DMA ownership');
    port^.cmd := $4010; service_port(device,device^.recoveryTick,0);
    Assert((completed.Count=0) and ((port^.cmd and $10)=0),'FR retains DMA ownership after FRE cleared');
    port^.cmd := 0; service_port(device,device^.recoveryTick,0); service_port(device,now_tick,0);
    Assert((completed.Count=1) and (completed.Error=eIOError),'stopped error completes exactly once');
    Assert(send_read_dma_async(device,0,512,puint32(buffer),nil,nil)=eDeviceNotReady,'failed port rejects new commands');
    reset_fake;
    result := submit_command(device,0,8,puint32(buffer),3,@test_done,puint32(@completed));
    Assert((result=eNone) and (table^.acmd[0]=$25),'READ CAPACITY uses tracked ownership');
    device^.pending[0].started := 0; port^.cmd := $C011;
    service_port(device,AHCI_IO_TICKS,0);
    Assert(device^.recovering and (completed.Count=0),'watchdog retains timed-out capacity buffer');
    port^.cmd := 0; service_port(device,device^.recoveryTick,0);
    Assert((completed.Count=1) and (completed.Error=eIOTimeout),'timeout completes after DMA stop');
    port^.cmd := 1;
    Assert(not wait_register(@port^.cmd,1,0,0),'stuck reset exits at bounded deadline');
    port^.cmd := 0;
    Assert(wait_register(@port^.cmd,1,0,0),'cleared reset succeeds');
    kfree(buffer); kfree(void(device^.command_table)); kfree(void(device^.command_list)); kfree(void(port)); kfree(void(device));
    number := intToString(passed); msg := stringConcat(number,' passed, '); kfree(void(number));
    number := intToString(failed); buffer := msg; msg := stringConcat(msg,number); kfree(buffer); kfree(void(number));
    buffer := msg; msg := stringConcat(msg,' failed'); kfree(buffer);
    arch.platform.diagnostics.testSummary('AHCI', 'AHCI_TESTS_PASSED', 'AHCI_TESTS_FAILED', passed, failed);
    if stdout_buf <> nil then io.stdio.bufWriteStrLn(stdout_buf,msg);
    kfree(void(msg));
end;

procedure UnitTest;
begin run_ahci_tests(nil); end;
procedure cmd_ahcitest(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin run_ahci_tests(stdout_buf); end;

end.
