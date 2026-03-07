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
     multiboot, bios_data_area,
     util,
     gdt, idt, isr, irq,
     TMR_0_ISR,
     syslog, stdio,
     keyboard, mouse,
     ps2_keyboard, ps2_mouse,
     vmemorymanager, pmemorymanager, lmemorymanager,
     tracer,
     drivermanagement,
     progmanager,
     processmanager, contextswitcher,
     testprocs,
     PCI,
     strings,
     USB,
     usbtypes,
     usbcore,
     usbhub,
     usb_keyboard,
     usb_mouse,
     usb_storage,
     UHCI,
     OHCI,
     EHCI,
     XHCI,
     testdriver,
     E1000,
     IDE,
     storagemanagement,
     lists,
     net,
     fat32,
     isrmanager,
     faults,
     fonts,
     RTC,
     serial,
     cpu,
     md5,
     base64,
     rand,
     hashmap, 
     vfs,
     video, 
     vesa, 
     doublebuffer, 
     color,
     lvgl, 
     desktop, 
     uidebug,
     gpu, 
     bga,
     vterminal,
     graphicsrefresh, 
     usbhotplug,
     fifo, 
     cfifo, 
     cfifols, 
     lifo, 
     circ, 
     minh, 
     maxh, 
     prio,
     v86;
 
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
   dds             : uint32;
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

     { VFS Init }
     vfs.init();
     storagetest.init;

     { Management Interfaces }
     tracer.push_trace('kmain.STRMGMT');
     storagemanager.init();
     storagemanager.set_boot_drive_byte((multibootinfo^.boot_device shr 24) and $FF);
     volumemanager.init();
     filesystemmanager.init();

     { Enable interrupts and hook timer }
     tracer.push_trace('kmain.TMR');
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
     syslog.logln('KERNEL', 'BUS DRIVERS: INIT BEGIN.');
     USB.init();
     pci.init();
     syslog.logln('KERNEL', 'BUS DRIVERS: INIT END.');

     { Auto-mount discovered volumes into VFS }
     vfs.auto_mount_volumes();

     { Network Stack }
     tracer.push_trace('kmain.NETDRV');
     net.init;

     { Init Progs }
     progmanager.init();

     { Seed RNG }
     rand.srand((getDateTime.Seconds SHL 24) OR (getDateTime.Minutes SHL 16) OR (getDateTime.Hours SHL 8) OR (getDateTime.Day));

     { Initialize LVGL }
     syslog.logln('KERNEL', 'LVGL: INIT BEGIN.');
     lvgl_init(video.frontBufferWidth, video.frontBufferHeight);
     syslog.logln('KERNEL', 'LVGL: INIT COMPLETE.');

     { Initialize desktop environment }
     syslog.logln('KERNEL', 'DESKTOP: INIT BEGIN.');
     desktop.init;
     syslog.logln('KERNEL', 'DESKTOP: INIT COMPLETE.');

     { Initialize visual terminal (registers with desktop search) }
     vterminal.init;

     { Initialize disk utility (registers with desktop search) }
     diskutil.init;

     { Initialize notepad (registers with desktop search) }
     notepad.init;

     { Run unit tests }
     strings.UnitTest;
     usbtypes.UnitTest;
     usbcore.UnitTest;
     UHCI.UnitTest;
     OHCI.UnitTest;
     EHCI.UnitTest;
     XHCI.UnitTest;
     usbhub.UnitTest;
     usb_keyboard.UnitTest;
     usb_mouse.UnitTest;
     fifo.UnitTest;
     cfifo.UnitTest;
     cfifols.UnitTest;
     lifo.UnitTest;
     circ.UnitTest;
     minh.UnitTest;
     maxh.UnitTest;
     prio.UnitTest;
     vfs.UnitTest;
     storagetest.UnitTest;

     { Register timer-driven tasks }
     graphicsrefresh.init;
     usbhotplug.init;

     { Spawn test processes (before preemption is enabled) }
     //testprocs.init;

     { Enable preemptive context switching (replaces ISR_32) }
     contextswitcher.init;
     
     { All work is now driven by timer interrupts — idle the CPU }
     syslog.logln('KERNEL', 'All tasks registered. Halting into idle.');
     kernel.yield();
end;
 
end.
