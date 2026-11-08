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

{ Compose shared services with the i386 boot manager and platform commands. }
unit arch.x86.startup;

interface

implementation
uses
    app.mgr, app.vbeinfo, app.divzero, app.bsod, app.iotest, arch.x86.cpu,
    driver.net,
    driver.video.desktop, driver.timer.rtc, svc.gfxd,
    app.uidebug,
    driver.video.bga, driver.video, driver.video.gpu, driver.video.vesa,
    driver.video.doublebuffer, driver.video.lvgl,
    driver.hid.usb.keyboard,
    driver.hid.usb.mouse,
    driver.hid.ps2.keyboard, driver.hid.ps2.mouse,
    driver.storage.ctl.usb,
    driver.storage.metatest,
    driver.mgr,
    driver.bus.pci,
    driver.storage.ctl.ahci,
    driver.storage.mgr,
    driver.storage.vfs,
    driver.storage.vol.mgr,
    driver.storage.fs.flatfs,
    driver.storage.fs.iso9660,
    driver.storage.fs.ext2,
    driver.storage.fs.fat32,
    driver.io.serial,
    io.syslog,
    debug.tracer,
    driver.storage.fs.mgr,
    boot.mgr,
    memory.heap,
    proc.mgr,
    io.stdio,
    arch.x86.console;

procedure initApps;
begin
    app.mgr.init;
    io.stdio.registerCommand('CPU', @arch.x86.cpu.Terminal_Command_CPU, 'CPU Info.');
    app.vbeinfo.init;
    app.divzero.init;
    app.bsod.init;
    app.iotest.init;
end;

procedure consoleInit;
begin
    io.stdio.init;
    arch.x86.console.init;
end;
procedure lateInit();
begin
    driver.video.vesa.init(@driver.video.register);
    driver.video.doublebuffer.init(@driver.video.register);

    io.syslog.logln('VIDEO', 'VESA Enable.');
    driver.video.enable('VESA');

    io.syslog.logln('VIDEO', 'Double Buffer Enable.');
    driver.video.enable('BASIC_DOUBLE_BUFFER');

    { Initialize LVGL early so the boot.splash screen can use it }
    io.syslog.logln('VIDEO', 'LVGL: INIT BEGIN.');
    lvgl_init(driver.video.frontBufferWidth, driver.video.frontBufferHeight);
    io.syslog.logln('VIDEO', 'LVGL: INIT END.');
end;

initialization
    boot.mgr.registerBoot('app.mgr', @initApps, 'Program Manager', BOOT_MGR_BARRIER_LATE);
    boot.mgr.registerBoot('driver.video.bga', @driver.video.bga.init, 'BGA Display Driver Initialization', 'driver.video');
    boot.mgr.registerBoot('driver.net', @driver.net.init, 'Net Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.hid.ps2.keyboard', @driver.hid.ps2.keyboard.init, 'PS/2 Keyboard Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.hid.ps2.mouse', @driver.hid.ps2.mouse.init, 'PS/2 Mouse Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('proc.desktop', @driver.video.desktop.init, 'Initialize Desktop', 'boot.splash.teardown');
    boot.mgr.registerBoot('svc.gfxd', @svc.gfxd.init, 'GFX Daemon', BOOT_MGR_BARRIER_LATE);
    boot.mgr.registerBoot('driver.timer.rtc', @driver.timer.rtc.init, 'Real Time Clock Driver', 'arch.x86.fault');
    boot.mgr.registerBoot('driver.video', @driver.video.init, 'Video Driver Initialization', 'driver.video.gpu');
    boot.mgr.registerBoot('driver.video.gpu', @driver.video.gpu.init, 'GPU Framework', BOOT_MGR_BARRIER_EARLY);
    boot.mgr.registerBoot('driver.video_late', @lateInit, 'Video Driver Late Initialization', 'driver.video.*');
    driver.video.lvgl.onDebugToggle := @app.uidebug.toggle;
    driver.hid.usb.keyboard.onAttach := @driver.hid.ps2.keyboard.disable;
    boot.mgr.registerBoot('driver.hid.usb.keyboard', @driver.hid.usb.keyboard.init, 'USB Keyboard Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.hid.usb.mouse', @driver.hid.usb.mouse.init, 'USB Mouse Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.storage.ctl.usb', @driver.storage.ctl.usb.init, 'USB Mass Storage Driver', BOOT_MGR_BARRIER_DEVICE);
    boot.mgr.registerBoot('driver.storage.metatest', @driver.storage.metatest.init, 'Storage Metadata Tests', BOOT_MGR_BARRIER_MID);
    boot.mgr.registerBoot('driver.mgr', @driver.mgr.init, 'Driver Manager Initialization', BOOT_MGR_BARRIER_MID);
    boot.mgr.registerBoot('driver.bus.pci', @driver.bus.pci.Init, 'PCI Bus Driver', BOOT_MGR_BARRIER_BUS_LATE);
    boot.mgr.registerBoot('driver.storage.ctl.ahci', @driver.storage.ctl.ahci.init, 'AHCI Controller', 'driver.storage.fs.*');
    boot.mgr.registerBoot('driver.storage.mgr', @driver.storage.mgr.init, 'Storage Manager', 'driver.storage.vfs');
    boot.mgr.registerBoot('driver.storage.vfs', @driver.storage.vfs.init, 'Virtual File System', BOOT_MGR_BARRIER_STORAGE);
    boot.mgr.registerBoot('driver.storage.vol.mount', @driver.storage.vfs.auto_mount_volumes, 'Mount Storage Volumes', BOOT_MGR_BARRIER_LATE);
    boot.mgr.registerBoot('driver.storage.vol.mgr', @driver.storage.vol.mgr.init, 'Volume Manager', 'driver.storage.mgr*');
    boot.mgr.registerBoot('driver.storage.fs.flatfs', @driver.storage.fs.flatfs.init, 'FlatFS Filesystem', 'driver.storage.fs.mgr');
    boot.mgr.registerBoot('driver.storage.fs.iso9660', @driver.storage.fs.iso9660.Init, 'IS9660 File System', 'driver.storage.fs.mgr');
    boot.mgr.registerBoot('driver.storage.fs.ext2',@driver.storage.fs.ext2.init,'Ext2 Filesystem','driver.storage.fs.mgr');
    boot.mgr.registerBoot('driver.storage.ext2.worker',@driver.storage.fs.ext2.StartWorker,'Ext2 I/O Worker','proc.mgr');
    boot.mgr.registerBoot('driver.storage.fs.fat32', @driver.storage.fs.fat32.init, 'FAT32 Filesystem', 'driver.storage.fs.mgr');
    boot.mgr.registerBoot('driver.io.serial', @driver.io.serial.init, 'Serial Interface', 'immediate');
    boot.mgr.registerBoot('io.syslog', @io.syslog.init, 'Syslog Interface', 'driver.io.serial');
    boot.mgr.registerBoot('debug.tracer.freeze', @debug.tracer.freeze, 'Debug Tracer Freeze', 'io.syslog' );
    boot.mgr.registerBoot('debug.tracer', @debug.tracer.init, 'Debug Tracer Initialization', 'io.stdio' );
    boot.mgr.registerBoot('driver.storage.fs.mgr', @driver.storage.fs.mgr.init, 'Filesystem Manager', 'driver.storage.vol.mgr');
    boot.mgr.registerBoot('memory.heap', @memory.heap.init, 'Heap Memory Manager', 'arch.*.memory.*');
    boot.mgr.registerBoot('io.stdio', @consoleInit, 'Standard I/O Abstraction', BOOT_MGR_BARRIER_EARLY);
    boot.mgr.registerBoot('proc.mgr', @proc.mgr.init, 'Process Manager', 'driver.storage.fs*');
end.
