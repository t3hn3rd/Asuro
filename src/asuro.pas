//  Copyright 2021 Kieron Morris & Aaron Hance
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
	Kernel Main - Main Kernel Entry Point.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit asuro;
 
interface
 
uses
    driver.storage.ctl.ahci,
    core.enc.base64,
    core.panic,
    driver.video.bga,
    arch.x86.bda,
    arch.x86.panic,
    core.ds.cfifo,
    core.ds.cfifols,
    core.ds.circ,
    core.gfx.color,
    arch.x86.proc.sched,
    arch.x86.cpu,
    driver.video.desktop,
    driver.video.doublebuffer,
    driver.mgr,
    driver.net.dev.e1000,
    driver.bus.usb.ehci,
    driver.storage.fs.fat32,
    arch.x86.fault,
    core.ds.fifo,
    driver.storage.fs.mgr,
    driver.storage.fs.flatfs,
    core.gfx.fonts,
    arch.x86.gdt,
    driver.video.gpu,
    svc.gfxd,
    core.ds.hashmap,
    arch.x86.idt,
    arch.x86.isr.ioapic,
    arch.x86.irq,
    driver.storage.fs.iso9660,
    arch.x86.isr,
    arch.x86.isr.mgr,
    driver.hid.keyboard,
    core.ds.lifo,
    core.ds.lists,
    memory.heap,
    driver.video.lvgl,
    core.ds.maxh,
    core.enc.md5,
    core.ds.minh,
    driver.hid.mouse,
    arch.x86.multiboot,
    driver.net,
    driver.bus.usb.ohci,
    app.partcmd,
    driver.bus.pci,
    arch.x86.memory.physical,
    core.ds.prio,
    proc.mgr,
    app.mgr,
    driver.hid.ps2.keyboard,
    driver.hid.ps2.mouse,
    core.rand,
    driver.timer.rtc,
    driver.io.serial,
    boot.splash,
    io.stdio,
    driver.storage.mgr,
    driver.storage.test,
    core.strings,
    core.stringhelpers,
    io.syslog,
    driver.exp.testdriver,
    proc.testprocs,
    arch.x86.isr.tmr0,
    debug.tracer,
    driver.bus.usb.uhci,
    app.uidebug,
    driver.bus.usb,
    driver.hid.usb.keyboard,
    driver.hid.usb.mouse,
    driver.storage.ctl.usb,
    driver.bus.usb.core,
    svc.usbd,
    driver.bus.usb.hub,
    driver.bus.usb.types,
    core.util, 
    arch.x86.util,
    arch.x86.v86,
    driver.video.vesa,
    driver.storage.vfs,
    driver.video,
    arch.x86.memory.virtual,
    core.enc.fnv1a,
    core.enc.djb2,
    core.ds.bloom,
    app.volcmd,
    driver.storage.vol.mgr,
    app.vterminal,
    wasm, 
    wasm.vm.io, 
    wasm.test, 
    wasm.test.framework,
    driver.video.windows,
    driver.bus.usb.xhci,
    core.fmt.json;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure terminal_command_bsod(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    push_trace('kernel.terminal_command_bsod');

    if paramCount(params) > 1 then begin
      core.panic.panic(getparam(0, params), getparam(1, params), nil);
    end else begin
        io.stdio.bufWriteStrLn(stderr_buf, 'Invalid number of params.');
        io.stdio.bufWriteStrLn(stderr_buf, 'Usage: bsod <error> <info>');
    end;

    pop_trace;
end;

procedure yield();
begin
    asm
         sti
     @idle:
         hlt
         jmp @idle
     end;
end;

procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall; [public, alias: 'kmain'];   
var
   dds             : uint16;
   keyboard_layout : array [0..1] of TKeyInfo;
   i : uint32;
   
begin
     { Init the base system unit }
     System.init();

     { Serial Init }
     driver.io.serial.init();

     { Syslog Init — right after driver.io.serial so log hooks work }
     io.syslog.init();
     io.syslog.writestringln('Booting Asuro...');

     { Store Multiboot info }
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

     { Ensure debug.tracer is frozen }
     debug.tracer.freeze();

     { Check for Multiboot }
     io.syslog.writestringln('Checking for Multiboot Compliance');
     if (multibootmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        io.syslog.logln('KERNEL', 'Multiboot Compliant Boot-Loader Needed!');
        io.syslog.logln('KERNEL', 'HALTING.');
        core.panic.panic('Multiboot Error', 'Multiboot Compliant Boot-Loader Needed!', nil);
     end;

     { GDT Init }
     arch.x86.gdt.init();
     asm
        MOV dds, CS
     end;
     if dds = $08 then begin
        io.syslog.logln('KERNEL', 'GDT: LOAD SUCCESS.');
     end else begin
        io.syslog.logln('KERNEL', 'GDT: LOAD FAIL.');
        io.syslog.logln('KERNEL', 'HALTING.');
        core.panic.panic('GDT', 'Failed to load the GDT correctly.', nil);
     end;

     io.syslog.log('MULTIBOOT', 'Assigned Framebuffer: ');
     io.syslog.writehexln(multibootinfo^.framebuffer_addr);
     io.syslog.log('MULTIBOOT', 'Assigned Framebuffer Metrics: ');
     io.syslog.writeint(multibootinfo^.framebuffer_width);
     io.syslog.writestring('x');
     io.syslog.writeint(multibootinfo^.framebuffer_height);
     io.syslog.writestring('x');
     io.syslog.writeintln(multibootinfo^.framebuffer_bpp);

     { Memory/CPU Init }
     arch.x86.idt.init();
     arch.x86.irq.init();
     arch.x86.isr.mgr.init();
     arch.x86.fault.init();
     driver.timer.rtc.init();
          
     arch.x86.memory.physical.init();
     arch.x86.memory.virtual.init();
     memory.heap.init();

     { V86 Monitor Init }
     arch.x86.v86.init();

     { Stdio Init }
     io.stdio.init();
     io.stdio.registerCommand('BSOD', @terminal_command_bsod, 'Force a Panic Screen.');

     { CPUID }
     io.syslog.logln('CPU', 'Init begin');
     arch.x86.cpu.init();
     io.syslog.logln('CPU', 'Init end');

     { Call Tracer }
     debug.tracer.init();

     debug.tracer.push_trace('kmain.DRVMGMT');
     driver.mgr.init();

     { Video Init }
     driver.video.gpu.init();
     driver.video.init();
     driver.video.vesa.init(@driver.video.register);
     driver.video.doublebuffer.init(@driver.video.register);
     driver.video.bga.init();
     driver.video.enable('VESA');
     driver.video.enable('BASIC_DOUBLE_BUFFER');

     { Initialize LVGL early so the boot.splash screen can use it }
     io.syslog.logln('KERNEL', 'LVGL: INIT BEGIN.');
     lvgl_init(driver.video.frontBufferWidth, driver.video.frontBufferHeight);
     io.syslog.logln('KERNEL', 'LVGL: INIT COMPLETE.');

     { Initialize the BSOD panic screen (must be after LVGL, before anything that could fault) }
     arch.x86.panic.init;
     io.syslog.logln('KERNEL', 'PANIC SCREEN: INIT COMPLETE.');

     { Safe to init boot.splash screen now that Video & LVGL are ready }
     boot.splash.init;

     { VFS Init }
     boot.splash.update(5, 'Initializing VFS...');
     driver.storage.vfs.init();
     driver.storage.test.init;

     { Let's test Wasuro! }
     wasm.vm.io.io_set_writechar(@io.syslog.logchar);
     wasm.wasm_init;

     { Management Interfaces }
     debug.tracer.push_trace('kmain.STRMGMT');
     boot.splash.update(10, 'Initializing storage management...');
     driver.storage.mgr.init();
     driver.storage.mgr.set_boot_drive_byte((multibootinfo^.boot_device shr 24) and $FF);
     driver.storage.vol.mgr.init();
     driver.storage.fs.mgr.init();

     { Enable interrupts and hook timer }
     debug.tracer.push_trace('kmain.TMR');
     boot.splash.update(15, 'Enabling interrupts...');
     STI;
     arch.x86.isr.tmr0.hook(uint32(@arch.x86.bda.tick_update));

     { Filesystems }
     driver.storage.fs.fat32.init();
     driver.storage.fs.flatfs.init();
     driver.storage.fs.iso9660.init();

     { Init process manager (must be before device drivers — submit_io needs CurrentProcess) }
     proc.mgr.init;

     { Device Drivers }
     debug.tracer.push_trace('kmain.DEVDRV');
     boot.splash.update(20, 'Loading device drivers...');
     io.syslog.logln('KERNEL', 'DEVICE DRIVERS: INIT BEGIN.');
     driver.hid.ps2.keyboard.init(keyboard_layout);
     driver.hid.ps2.mouse.init();
     driver.exp.testdriver.init();
     driver.net.dev.e1000.init();
     driver.storage.ctl.ahci.init();
     io.syslog.logln('KERNEL', 'DEVICE DRIVERS: INIT END.');

     { Bus Drivers }
     debug.tracer.push_trace('kmain.BUSDRV');
     boot.splash.update(25, 'Loading bus drivers...');
     io.syslog.logln('KERNEL', 'BUS DRIVERS: INIT BEGIN.');
     boot.splash.update(30, 'Loading bus drivers (driver.bus.usb)...');
     driver.bus.usb.init();
     boot.splash.update(35, 'Loading bus drivers (driver.bus.pci)...');
     driver.bus.pci.init();
     io.syslog.logln('KERNEL', 'BUS DRIVERS: INIT END.');

     { Auto-mount discovered volumes into VFS }
     boot.splash.update(38, 'Auto-mounting volumes...');
     driver.storage.vfs.auto_mount_volumes();

     { Network Stack }
     boot.splash.update(40, 'Initializing network...');
     debug.tracer.push_trace('kmain.NETDRV');
     driver.net.init;

     { Init Progs }
     boot.splash.update(45, 'Initializing progmon...');
     app.mgr.init();

     { Init process manager }
     boot.splash.update(50, 'Initializing process manager...');
     proc.mgr.init;

     { Seed RNG }
     boot.splash.update(55, 'Seeding RNG...');
     core.rand.srand((getDateTime.Seconds SHL 24) OR (getDateTime.Minutes SHL 16) OR (getDateTime.Hours SHL 8) OR (getDateTime.Day));

     { Run unit tests }
     boot.splash.update(65, 'Running test suite...');
     core.strings.UnitTest;
     core.stringhelpers.UnitTest;
     driver.bus.usb.types.UnitTest;
     driver.bus.usb.core.UnitTest;
     boot.splash.update(70, 'Running test suite...');
     driver.bus.usb.uhci.UnitTest;
     driver.bus.usb.ohci.UnitTest;
     driver.bus.usb.ehci.UnitTest;
     boot.splash.update(75, 'Running test suite...');
     driver.bus.usb.xhci.UnitTest;
     driver.bus.usb.hub.UnitTest;
     driver.hid.usb.keyboard.UnitTest;
     boot.splash.update(80, 'Running test suite...');
     driver.hid.usb.mouse.UnitTest;
     core.ds.fifo.UnitTest;
     core.ds.cfifo.UnitTest;
     boot.splash.update(85, 'Running test suite...');
     core.ds.cfifols.UnitTest;
     core.ds.lifo.UnitTest;
     core.ds.circ.UnitTest;
     wasm.test.run_all_tests;
     boot.splash.update(90, 'Running test suite...');
     core.ds.minh.UnitTest;
     core.ds.maxh.UnitTest;
     core.ds.prio.UnitTest;
     driver.storage.vfs.UnitTest;
     driver.storage.test.UnitTest;
     boot.splash.update(95, 'Running test suite...');
     core.enc.fnv1a.UnitTest;
     core.enc.djb2.UnitTest;
     core.ds.bloom.UnitTest;
     core.fmt.json.UnitTest;

     { Initialize driver.video.desktop environment }
     boot.splash.update(100, 'Booting desktop...');
     boot.splash.teardown;
     io.syslog.logln('KERNEL', 'DESKTOP: INIT BEGIN.');
     driver.video.desktop.init;
     io.syslog.logln('KERNEL', 'DESKTOP: INIT COMPLETE.');

     { Initialize visual terminal (registers with driver.video.desktop search) }
     app.vterminal.init;

     { Register timer-driven tasks }
     svc.gfxd.init;
     svc.usbd.init;

     { Enable preemptive context switching (replaces ISR_32) }
     arch.x86.proc.sched.init;
     
     { All work is now driven by timer interrupts — idle the CPU }
     io.syslog.logln('KERNEL', 'All tasks registered. Halting into idle.');
     yield();
end;
 
end.
