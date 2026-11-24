// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

unit arch.x86_64.regression;

interface

procedure testSharedUnits;
procedure validateStorage;

implementation

uses
    driver.bus.pci, driver.bus.usb.core,
    driver.storage.types, driver.storage.fs.mgr, driver.storage.mgr, driver.storage.vfs,
    driver.storage.perftest, memory.heap, proc.mgr, debug.early,
    arch.x86_64.memory.physical, arch.x86_64.memory.virtual;

{$i regression.compiler-abi.inc}

procedure testSharedUnits;
begin
    testCompilerRuntime;
    memory.heap.UnitTest;
    if (driver.bus.pci.memoryBAR($2004, 1) <> uint64($100002000)) or
       (driver.bus.pci.memoryBAR($2000, 1) <> $2000) or
       (driver.bus.pci.memoryBAR($2001, 1) <> 0) then begin
        puts('FAIL: PCI memory BAR decoding'#13#10);
        bootstrap_halt;
    end;

end;

procedure test_high_dma;
var
    address: PtrUInt;
    frame, oldFrame: uint64;
    device: PStorage_Device;
    reference: puint8;
    i, j, count: uint32;
    ok: boolean;
begin
    frame := arch.x86_64.memory.physical.alloc_high;
    if frame = 0 then begin
        puts('SKIP: no high physical frame for DMA test'#13#10);
        exit;
    end;
    address := arch.x86_64.memory.virtual.allocate_region(1);
    if address = 0 then begin
        arch.x86_64.memory.physical.free_page(frame);
        puts('FAIL: DMA test mapping allocation'#13#10);
        exit;
    end;
    if not unmap_page(address, oldFrame) then bootstrap_halt;
    arch.x86_64.memory.physical.free_page(oldFrame);
    if not map_page(address, frame, true) then bootstrap_halt;
    reference := puint8(kalloc(4096));
    ok := reference <> nil;
    count := driver.storage.mgr.get_device_count;
    if count = 0 then ok := false;
    if ok then
        for i := 0 to count - 1 do begin
            device := driver.storage.mgr.get_device(i);
            if not (device^.controller in [ControllerAHCI, ControllerAHCI_ATAPI]) then continue;
            if (device^.sectorSize = 0) or (device^.sectorSize > 4096) then begin
                ok := false;
                break;
            end;
            if (storage_read(device, 0, 1, puint32(reference)) <> eNone) or
               (storage_read(device, 0, 1, puint32(address)) <> eNone) then begin
                ok := false;
                break;
            end;
            for j := 0 to device^.sectorSize - 1 do
                if reference[j] <> puint8(address)[j] then ok := false;
        end;
    if reference <> nil then kfree(void(reference));
    if not release_region(address, 1) then ok := false;
    if ok then
        puts('PASS: AHCI DMA above 4 GiB matches every disk sector'#13#10)
    else
        puts('FAIL: AHCI DMA above 4 GiB'#13#10);
end;

procedure test_storage_read;
var
    handle: TFileHandle;
    error: TError;
    buffer: puint8;
    bytes: uint32;
begin
    buffer := puint8(kalloc(4096));
    if buffer = nil then begin
        puts('FAIL: storage read buffer allocation'#13#10);
        exit;
    end;
    handle := driver.storage.vfs.OpenFile('/disk/ISOIMAGE/boot/asuro.bin', omRead, @error);
    if error = eNone then begin
        bytes := driver.storage.vfs.ReadFile(handle, 0, buffer, 4096);
        if (bytes = 4096) and (buffer[0] = $7F) and
           (buffer[1] = ord('E')) and (buffer[2] = ord('L')) and
           (buffer[3] = ord('F')) and (buffer[4] = 2) then
            puts('PASS: VFS reads ELF64 kernel through AHCI'#13#10)
        else
            puts('FAIL: VFS kernel file contents'#13#10);
        driver.storage.vfs.CloseFile(handle);
    end else
        puts('FAIL: VFS opens kernel file'#13#10);
    kfree(void(buffer));
end;

procedure test_usb_read;
var
    device: PStorage_Device;
    buffer, reference: puint8;
    sectors, chunk, offset, bytes: uint32;
    matches: boolean;
    attempt, i, count: uint32;
begin
    if driver.bus.usb.core.get_hc_count = 0 then begin
        puts('SKIP: no supported USB host controller registered'#13#10);
        exit;
    end;
    device := nil;
    for attempt := 0 to 499 do begin
        count := driver.storage.mgr.get_device_count;
        if count > 0 then
            for i := 0 to count - 1 do
                if driver.storage.mgr.get_device(i)^.controller = ControllerUSB then
                    device := driver.storage.mgr.get_device(i);
        if device <> nil then break;
        proc.mgr.proc_sleep_ms(10);
    end;
    if device = nil then begin
        puts('SKIP: no USB storage device registered'#13#10);
        exit;
    end;
    if (device^.sectorSize = 0) or (device^.sectorSize > 4096) then begin
        puts('FAIL: USB disk sector size'#13#10);
        exit;
    end;
    sectors := 131072 div device^.sectorSize;
    if sectors > device^.maxSectorCount then sectors := device^.maxSectorCount;
    if sectors = 0 then begin
        puts('FAIL: USB disk capacity'#13#10);
        exit;
    end;
    buffer := puint8(kalloc(sectors * device^.sectorSize));
    reference := puint8(kalloc(4096));
    if (buffer <> nil) and (reference <> nil) then begin
        matches := storage_read(device, 0, sectors, puint32(buffer)) = eNone;
        offset := 0;
        while matches and (offset < sectors) do begin
            chunk := 4096 div device^.sectorSize;
            if chunk > sectors - offset then chunk := sectors - offset;
            bytes := chunk * device^.sectorSize;
            matches := storage_read(device, offset, chunk, puint32(reference)) = eNone;
            if matches then
                for i := 0 to bytes - 1 do
                    if buffer[offset * device^.sectorSize + i] <> reference[i] then begin
                        matches := false;
                        break;
                    end;
            inc(offset, chunk);
        end;
        if matches then
            puts('PASS: USB bulk read from sector zero matches reference reads'#13#10)
        else
            puts('FAIL: USB bulk read comparison'#13#10);
    end else
        puts('FAIL: USB read buffer allocation'#13#10);
    if reference <> nil then kfree(void(reference));
    if buffer <> nil then kfree(void(buffer));
end;

procedure validateStorage;
begin
    test_storage_read;
    {$ifdef ASURO_TEST_STORAGE}
    test_usb_read;
    test_high_dma;
    {$endif}
end;

end.
