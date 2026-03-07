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
unit kernel;
 
interface
 
uses
    AHCI,
    base64,
    bga,
    bios_data_area,
    cfifo,
    cfifols,
    circ,
    color,
    contextswitcher,
    cpu,
    desktop,
    diskcmd,
    diskutil,
    doublebuffer,
    drivermanagement,
    E1000,
    EHCI,
    fat32,
    faults,
    fifo,
    filesystemmanager,
    flatfs,
    fonts,
    gdt,
    gpu,
    graphicsrefresh,
    hashmap,
    idt,
    ioapic,
    irq,
    iso9660,
    isr,
    isrmanager,
    keyboard,
    lifo,
    lists,
    lmemorymanager,
    lvgl,
    maxh,
    md5,
    minh,
    mouse,
    multiboot,
    net,
    notepad,
    OHCI,
    partcmd,
    PCI,
    pmemorymanager,
    prio,
    processmanager,
    progmanager,
    ps2_keyboard,
    ps2_mouse,
    rand,
    RTC,
    serial,
    splash,
    stdio,
    storagemanager,
    storagetest,
    strings,
    syslog,
    testdriver,
    testprocs,
    TMR_0_ISR,
    tracer,
    UHCI,
    uidebug,
    USB,
    usb_keyboard,
    usb_mouse,
    usb_storage,
    usbcore,
    usbhotplug,
    usbhub,
    usbtypes,
    util,
    v86,
    vesa,
    vfs,
    video,
    vmemorymanager,
    volcmd,
    volumemanager,
    vterminal,
    Windows,
    XHCI;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure terminal_command_bsod(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    push_trace('kernel.terminal_command_bsod');

    if paramCount(params) > 1 then begin
      bsod(getparam(0, params), getparam(1, params));
    end else begin
        stdio.bufWriteStrLn(stderr_buf, 'Invalid number of params.');
        stdio.bufWriteStrLn(stderr_buf, 'Usage: bsod <error> <info>');
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
     serial.init();

     { Syslog Init — right after serial so log hooks work }
     syslog.init();
     syslog.writestringln('Booting Asuro...');

     { Store Multiboot info }
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

     { Ensure tracer is frozen }
     tracer.freeze();

     { Check for Multiboot }
     syslog.writestringln('Checking for Multiboot Compliance');
     if (multibootmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        syslog.logln('KERNEL', 'Multiboot Compliant Boot-Loader Needed!');
        syslog.logln('KERNEL', 'HALTING.');
        BSOD('Multiboot Error', 'Multiboot Compliant Boot-Loader Needed!');
        util.halt_and_catch_fire;
     end;

     { GDT Init }
     gdt.init();
     asm
        MOV dds, CS
     end;
     if dds = $08 then begin
        syslog.logln('KERNEL', 'GDT: LOAD SUCCESS.');
     end else begin
        syslog.logln('KERNEL', 'GDT: LOAD FAIL.');
        syslog.logln('KERNEL', 'HALTING.');
        BSOD('GDT', 'Failed to load the GDT correctly.');
     end;

     syslog.log('MULTIBOOT', 'Assigned Framebuffer: ');
     syslog.writehexln(multibootinfo^.framebuffer_addr);
     syslog.log('MULTIBOOT', 'Assigned Framebuffer Metrics: ');
     syslog.writeint(multibootinfo^.framebuffer_width);
     syslog.writestring('x');
     syslog.writeint(multibootinfo^.framebuffer_height);
     syslog.writestring('x');
     syslog.writeintln(multibootinfo^.framebuffer_bpp);

     { Memory/CPU Init }
     idt.init();
     irq.init();
     isrmanager.init();
     faults.init();
     RTC.init();
          
     pmemorymanager.init();
     vmemorymanager.init();
     lmemorymanager.init();

     { V86 Monitor Init }
     v86.init();

     { Stdio Init }
     stdio.init();
     stdio.registerCommand('BSOD', @terminal_command_bsod, 'Force a Panic Screen.');

     { CPUID }
     syslog.logln('CPU', 'Init begin');
     cpu.init();
     syslog.logln('CPU', 'Init end');

     { Call Tracer }
     tracer.init();

     tracer.push_trace('kmain.DRVMGMT');
     drivermanagement.init();

     { Video Init }
     gpu.init();
     video.init();
     vesa.init(@video.register);
     doublebuffer.init(@video.register);
     bga.init();
     video.enable('VESA');
     video.enable('BASIC_DOUBLE_BUFFER');

     { Initialize LVGL early so the splash screen can use it }
     syslog.logln('KERNEL', 'LVGL: INIT BEGIN.');
     lvgl_init(video.frontBufferWidth, video.frontBufferHeight);
     syslog.logln('KERNEL', 'LVGL: INIT COMPLETE.');

     { Safe to init splash screen now that Video & LVGL are ready }
     splash.init;

     { VFS Init }
     splash.update(5, 'Initializing VFS...');
     vfs.init();
     storagetest.init;

     { Management Interfaces }
     tracer.push_trace('kmain.STRMGMT');
     splash.update(10, 'Initializing storage management...');
     storagemanager.init();
     storagemanager.set_boot_drive_byte((multibootinfo^.boot_device shr 24) and $FF);
     volumemanager.init();
     filesystemmanager.init();

     { Enable interrupts and hook timer }
     tracer.push_trace('kmain.TMR');
     splash.update(15, 'Enabling interrupts...');
     STI;
     TMR_0_ISR.hook(uint32(@bios_data_area.tick_update));

     { Filesystems }
     fat32.init();
     flatfs.init();
     iso9660.init();

     { Init process manager (must be before device drivers — submit_io needs CurrentProcess) }
     processmanager.init;

     { Device Drivers }
     tracer.push_trace('kmain.DEVDRV');
     splash.update(20, 'Loading device drivers...');
     syslog.logln('KERNEL', 'DEVICE DRIVERS: INIT BEGIN.');
     ps2_keyboard.init(keyboard_layout);
     ps2_mouse.init();
     testdriver.init();
     E1000.init();
     AHCI.init();
     diskcmd.init();
     partcmd.init();
     volcmd.init();
     syslog.logln('KERNEL', 'DEVICE DRIVERS: INIT END.');

     { Bus Drivers }
     tracer.push_trace('kmain.BUSDRV');
     splash.update(25, 'Loading bus drivers...');
     syslog.logln('KERNEL', 'BUS DRIVERS: INIT BEGIN.');
     splash.update(30, 'Loading bus drivers (USB)...');
     USB.init();
     splash.update(35, 'Loading bus drivers (PCI)...');
     pci.init();
     syslog.logln('KERNEL', 'BUS DRIVERS: INIT END.');

     { Auto-mount discovered volumes into VFS }
     vfs.auto_mount_volumes();

     { Network Stack }
     splash.update(40, 'Initializing network...');
     tracer.push_trace('kmain.NETDRV');
     net.init;

     { Init Progs }
     splash.update(45, 'Initializing progmon...');
     progmanager.init();

     { Init process manager }
     splash.update(50, 'Initializing process manager...');
     processmanager.init;

     { Seed RNG }
     splash.update(55, 'Seeding RNG...');
     rand.srand((getDateTime.Seconds SHL 24) OR (getDateTime.Minutes SHL 16) OR (getDateTime.Hours SHL 8) OR (getDateTime.Day));

     { Run unit tests }
     splash.update(65, 'Running test suite...');
     strings.UnitTest;
     usbtypes.UnitTest;
     usbcore.UnitTest;
     splash.update(70, 'Running test suite...');
     UHCI.UnitTest;
     OHCI.UnitTest;
     EHCI.UnitTest;
     splash.update(75, 'Running test suite...');
     XHCI.UnitTest;
     usbhub.UnitTest;
     usb_keyboard.UnitTest;
     splash.update(80, 'Running test suite...');
     usb_mouse.UnitTest;
     fifo.UnitTest;
     cfifo.UnitTest;
     splash.update(85, 'Running test suite...');
     cfifols.UnitTest;
     lifo.UnitTest;
     circ.UnitTest;
     splash.update(90, 'Running test suite...');
     minh.UnitTest;
     maxh.UnitTest;
     prio.UnitTest;
     vfs.UnitTest;
     storagetest.UnitTest;

     { Initialize desktop environment }
     splash.update(100, 'Booting desktop...');
     splash.teardown;
     syslog.logln('KERNEL', 'DESKTOP: INIT BEGIN.');
     desktop.init;
     syslog.logln('KERNEL', 'DESKTOP: INIT COMPLETE.');

     { Initialize visual terminal (registers with desktop search) }
     vterminal.init;

     { Register timer-driven tasks }
     graphicsrefresh.init;
     usbhotplug.init;

     { Initialize disk utility (registers with desktop search) }
     diskutil.init;

     { Initialize notepad (registers with desktop search) }
     notepad.init;

     { Enable preemptive context switching (replaces ISR_32) }
     contextswitcher.init;
     
     { All work is now driven by timer interrupts — idle the CPU }
     syslog.logln('KERNEL', 'All tasks registered. Halting into idle.');
     kernel.yield();
end;
 
end.
