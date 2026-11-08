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

unit arch.x86_64.boot;

interface

procedure kmain(info: pointer; magic: uint32); cdecl;

implementation

uses
    app.mgr,
    driver.net, app.wasm.runner,
    driver.hid.ps2.keyboard, driver.hid.ps2.mouse,
    driver.video.desktop, driver.timer.rtc, svc.gfxd, app.uidebug,
    driver.video.lvgl,
    driver.video.bga, driver.video, driver.video.gpu, driver.video.doublebuffer,
    core.gfx.color, arch.platform.memory,
    proc.types,
    driver.hid.usb.keyboard,
    driver.hid.usb.mouse,
    driver.storage.ctl.usb,
    driver.bus.usb.types,
    driver.bus.usb.core,
    driver.bus.usb.hub,
    driver.bus.usb.ohci,
    driver.storage.metatest,
    driver.storage.types,
    arch.common.legacyirq,
    driver.mgr,
    driver.bus.pci,
    driver.storage.ctl.ahci,
    driver.storage.fs.fat32,
    driver.storage.fs.ext2,
    driver.storage.vfs,
    driver.storage.mgr,
    driver.storage.vol.mgr,
    driver.storage.fs.iso9660,
    io.syslog,
    driver.io.serial,
    debug.tracer,
    core.ds.cfifo,
    driver.storage.iorequest,
    driver.storage.path,
    driver.storage.fs.mgr,
    core.ds.lists,
    core.ds.hashmap,
    core.enc.fnv1a,
    io.stdio,
    core.strings,
    driver.storage.fdtable,
    arch.x86_64.proc.sched,
    proc.mgr,
    arch.x86_64.context,
    arch.x86_64.irq,
    memory.heap,
    debug.early,
    arch.x86_64.debug,
    arch.x86_64.isr,
    boot.multiboot,
    arch.x86_64.memory.physical,
    arch.x86_64.memory.virtual;

var
    initializationCount: uint32;

function long_mode_active: boolean; assembler; nostackframe;
asm
    mov ecx, $C0000080
    rdmsr
    shr eax, 10
    and eax, 1
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
    buffer: puint32;
    attempt, i, count: uint32;
begin
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
    buffer := puint32(kalloc(device^.sectorSize));
    if buffer = nil then begin
        puts('FAIL: USB read buffer allocation'#13#10);
        exit;
    end;
    if storage_read(device, 0, 1, buffer) = eNone then
        puts('PASS: USB mass storage reads sector zero through OHCI'#13#10)
    else
        puts('FAIL: USB mass storage sector read'#13#10);
    kfree(void(buffer));
end;

procedure init_video(info: Pmultiboot_info_t);
var
    framebuffer: pointer;
    bytes: SizeUInt;
begin
    if (info^.flags and (1 shl 12) = 0) or
       (info^.framebuffer_bpp <> 32) or
       (info^.framebuffer_width = 0) or (info^.framebuffer_height = 0) or
       (info^.framebuffer_pitch < uint64(info^.framebuffer_width) * 4) then begin
        puts('FAIL: boot framebuffer geometry'#13#10);
        exit;
    end;
    bytes := SizeUInt(info^.framebuffer_pitch) * info^.framebuffer_height;
    framebuffer := arch.platform.memory.mapDevice(info^.framebuffer_addr, bytes);
    if framebuffer = nil then begin
        puts('FAIL: boot framebuffer mapping'#13#10);
        exit;
    end;
    driver.video.gpu.init;
    driver.video.init;
    driver.video.doublebuffer.init(@driver.video.register);
    driver.video.reinit(PtrUInt(framebuffer), info^.framebuffer_width,
        info^.framebuffer_height, info^.framebuffer_pitch, info^.framebuffer_bpp);
    driver.video.DrawString(32, 32, 'Asuro x86-64', core.gfx.color.white);
    driver.video.Flush;
    driver.video.lvgl.lvgl_init(info^.framebuffer_width, info^.framebuffer_height);
    driver.video.lvgl.lvgl_handler;
    driver.video.Flush;
    puts('PASS: native framebuffer and double buffer initialized'#13#10);
end;

procedure finish_boot(ctx: PProcessContext);
begin
    driver.storage.metatest.RunTests(true);
    driver.video.bga.init;
    driver.net.init;
    driver.bus.pci.init;
    driver.storage.vfs.auto_mount_volumes;
    test_storage_read;
    driver.hid.ps2.mouse.init;
    driver.hid.ps2.keyboard.init;
    driver.hid.usb.keyboard.onAttach := @driver.hid.ps2.keyboard.disable;
    driver.bus.usb.core.init;
    driver.bus.usb.hub.init;
    driver.storage.ctl.usb.init;
    driver.hid.usb.keyboard.init;
    driver.hid.usb.mouse.init;
    driver.bus.usb.ohci.load;
    test_usb_read;
    test_storage_read;
    test_high_dma;
    driver.timer.rtc.init;
    driver.video.lvgl.onDebugToggle := @app.uidebug.toggle;
    driver.video.desktop.init;
    app.mgr.init;
    app.wasm.runner.UnitTest;
    driver.video.lvgl.lvgl_handler;
    driver.video.Flush;
    {$ifdef ASURO_TEST_UD}
    arch.x86_64.isr.testFatal(6);
    {$endif}
    {$ifdef ASURO_TEST_PF}
    arch.x86_64.isr.testFatal(14);
    {$endif}
    {$ifdef ASURO_TEST_DF}
    arch.x86_64.isr.testFatal(8);
    {$endif}
    svc.gfxd.init;
    puts('ASURO x86_64: desktop ready'#13#10);
end;

procedure kmain(info: pointer; magic: uint32); cdecl; [public, alias: 'kmain'];
var
    wide: PtrUInt;
begin
    boot.multiboot.multibootinfo := Pmultiboot_info_t(info);
    arch.x86_64.debug.init;
    arch.x86_64.isr.init;
    io.syslog.init;
    system.init;
    system.init;
    if initializationCount <> 1 then begin
        puts('FAIL: unit initialization dispatch'#13#10);
        bootstrap_halt;
    end;
    puts('PASS: native unit initialization runs once'#13#10);
    puts('ASURO x86_64: entered Pascal'#13#10);
    if (magic <> $2BADB002) or (info = nil) then begin
        puts('FAIL: Multiboot handoff'#13#10);
        bootstrap_halt;
    end;
    if (sizeof(pointer) <> 8) or (sizeof(PtrUInt) <> 8) or
       (sizeof(SizeUInt) <> 8) or (sizeof(uint32) <> 4) then begin
        puts('FAIL: native type widths'#13#10);
        bootstrap_halt;
    end;
    wide := PtrUInt($100000000) + PtrUInt(magic);
    if (wide shr 32 <> 1) or not long_mode_active then begin
        puts('FAIL: long mode or 64-bit arithmetic'#13#10);
        bootstrap_halt;
    end;
    puts('PASS: long mode, Multiboot handoff, 64-bit Pascal types'#13#10);
    arch.x86_64.isr.UnitTest;
    arch.x86_64.memory.physical.init(Pmultiboot_info_t(info));
    arch.x86_64.memory.physical.UnitTest;
    arch.x86_64.memory.virtual.init;
    arch.x86_64.memory.virtual.UnitTest;
    memory.heap.init;
    memory.heap.UnitTest;
    driver.bus.usb.types.UnitTest;
    driver.bus.usb.core.UnitTest;
    driver.bus.usb.hub.UnitTest;
    driver.hid.usb.keyboard.UnitTest;
    driver.hid.usb.mouse.UnitTest;
    driver.bus.usb.ohci.UnitTest;
    core.strings.UnitTest;
    core.enc.fnv1a.UnitTest;
    core.ds.hashmap.UnitTest;
    core.ds.lists.TestAllLists;
    core.ds.cfifo.UnitTest;
    driver.storage.iorequest.UnitTest;
    driver.storage.path.UnitTest;
    driver.storage.fs.mgr.UnitTest;
    driver.storage.fs.mgr.init;
    io.stdio.init;
    arch.x86_64.irq.init;
    arch.x86_64.irq.UnitTest;
    arch.x86_64.context.UnitTest;
    driver.storage.fdtable.UnitTest;
    proc.mgr.init;
    arch.x86_64.proc.sched.init;
    arch.x86_64.proc.sched.UnitTest;
    driver.storage.mgr.init;
    driver.storage.vol.mgr.init;
    driver.storage.fs.iso9660.init;
    driver.storage.fs.ext2.init;
    driver.storage.fs.fat32.init;
    driver.storage.fs.ext2.StartWorker;
    driver.storage.vfs.init;
    driver.storage.vfs.auto_mount_volumes;
    driver.storage.vfs.UnitTest;
    driver.storage.ctl.ahci.UnitTest;
    driver.storage.ctl.usb.UnitTest;
    init_video(Pmultiboot_info_t(info));
    driver.mgr.init;
    driver.storage.ctl.ahci.init;
    if proc.mgr.create('bootstrap', @finish_boot, nil, 1) = nil then begin
        puts('FAIL: bootstrap process allocation'#13#10);
        bootstrap_halt;
    end;
    arch.common.legacyirq.masks($FE, $FF);
    asm
        sti
    end;
    while true do begin
        asm
            hlt
        end;
    end;
end;

initialization
    inc(initializationCount);

end.
