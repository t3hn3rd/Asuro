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
    {$ifdef ASURO_TEST_STORAGE}arch.x86_64.regression,{$endif}
    app.mgr, app.bsod, app.divzero,
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
    driver.bus.usb.uhci, driver.bus.usb.ehci,
    driver.bus.usb.ohci,
    driver.bus.usb.xhci,
    driver.storage.metatest,
    driver.storage.bench, driver.storage.perftest,
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
    driver.storage.fs.mgr,
    io.stdio,
    driver.storage.fdtable,
    arch.x86_64.proc.sched,
    proc.mgr,
    arch.x86_64.context,
    arch.x86_64.irq,
    memory.heap,
    debug.early,
    arch.x86_64.debug,
    arch.x86_64.isr,
    boot.multiboot, boot.mgr, boot.services,
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

procedure init_usb_hosts;
begin
    driver.bus.usb.uhci.load;
    driver.bus.usb.ehci.load;
    driver.bus.usb.ohci.load;
    driver.bus.usb.xhci.load;
end;

procedure registerNativeServices;
begin
    driver.hid.usb.keyboard.onAttach := @driver.hid.ps2.keyboard.disable;
    { Early CPU, memory, scheduler and framebuffer setup precedes this process.
      The remaining device services use the same phase graph as i386. }
    boot.services.registerDevices;
    boot.mgr.registerBoot('driver.storage.mgr', nil, 'Storage manager ready', nil);
    boot.mgr.registerBoot('io.syslog', nil, 'Early serial ready', nil);
    boot.mgr.registerBoot('driver.video.bga', @driver.video.bga.init, 'Display adapter', BOOT_MGR_BARRIER_EARLY);
    boot.mgr.registerBoot('driver.bus.usb.core', @driver.bus.usb.core.init, 'USB core', BOOT_MGR_BARRIER_EARLY);
    boot.mgr.registerBoot('driver.bus.usb.hub', @driver.bus.usb.hub.init, 'USB hubs', 'driver.bus.usb.core');
    boot.mgr.registerBoot('driver.bus.pci', @driver.bus.pci.init, 'PCI devices', BOOT_MGR_BARRIER_BUS_LATE);
    boot.mgr.registerBoot('driver.storage.vol.mount', @driver.storage.vfs.auto_mount_volumes, 'Mount volumes', 'driver.bus.pci');
    boot.mgr.registerBoot('driver.bus.usb.hosts', @init_usb_hosts, 'USB host controllers', 'driver.bus.pci');
    boot.mgr.registerBoot('driver.timer.rtc', @driver.timer.rtc.init, 'Real time clock', 'driver.bus.usb.hosts');
end;

procedure initDesktop;
begin
    driver.video.lvgl.onDebugToggle := @app.uidebug.toggle;
    driver.video.desktop.init;
end;

procedure finishDesktop;
begin
    {$ifdef UNIT_TESTS}
    app.wasm.runner.UnitTest;
    {$endif}
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
end;

procedure finish_boot(ctx: PProcessContext);
begin
    registerNativeServices;
    {$ifdef ASURO_TEST_STORAGE}
    boot.mgr.registerBoot('storage.verify', @arch.x86_64.regression.validateStorage, 'Storage checks', 'driver.bus.usb.hosts');
    {$endif}
    boot.mgr.registerBoot('driver.video.desktop', @initDesktop, 'Desktop', BOOT_MGR_BARRIER_LATE);
    boot.mgr.registerBoot('app.mgr', @app.mgr.init, 'Applications', 'driver.video.desktop');
    boot.mgr.registerBoot('svc.gfxd', @finishDesktop, 'Graphics service', 'app.mgr');
    if not boot.mgr.runChecked then begin
        puts('FAIL: unresolved native boot dependency'#13#10);
        bootstrap_halt;
    end;
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
    {$ifdef UNIT_TESTS}
    arch.x86_64.isr.UnitTest;
    {$endif}
    arch.x86_64.memory.physical.init(Pmultiboot_info_t(info));
    {$ifdef UNIT_TESTS}
    arch.x86_64.memory.physical.UnitTest(Pmultiboot_info_t(info));
    {$endif}
    arch.x86_64.memory.virtual.init;
    {$ifdef UNIT_TESTS}
    arch.x86_64.memory.virtual.UnitTest;
    {$endif}
    memory.heap.init;
    {$ifdef UNIT_TESTS}
    memory.heap.UnitTest;
    {$endif}
    driver.storage.fs.mgr.init;
    io.stdio.init;
    debug.tracer.init;
    app.bsod.init;
    app.divzero.init;
    arch.x86_64.irq.init;
    {$ifdef UNIT_TESTS}
    arch.x86_64.irq.UnitTest;
    arch.x86_64.context.UnitTest;
    driver.storage.fdtable.UnitTest;
    {$endif}
    proc.mgr.init;
    arch.x86_64.proc.sched.init;
    {$ifdef UNIT_TESTS}
    arch.x86_64.proc.sched.UnitTest;
    {$endif}
    driver.storage.mgr.init;
    driver.storage.vol.mgr.init;
    driver.storage.fs.iso9660.init;
    driver.storage.fs.ext2.init;
    driver.storage.fs.fat32.init;
    driver.storage.fs.ext2.StartWorker;
    driver.storage.vfs.init;
    driver.storage.vfs.auto_mount_volumes;
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
