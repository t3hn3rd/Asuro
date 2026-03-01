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
     gdt, idt, isr, irq, tss,
     TMR_0_ISR,
     syslog, stdio,
     keyboard, mouse,
     ps2_keyboard, ps2_mouse,
     vmemorymanager, pmemorymanager, lmemorymanager,
     tracer,
     drivermanagement,
     scheduler,
     progmanager,
     PCI,
     strings,
     USB,
     usbtypes,
     usbcore,
     usbhub,
     usb_keyboard,
     usb_mouse,
     UHCI,
     OHCI,
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
     hashmap, vfs,
     video, vesa, doublebuffer, color, lvgl, desktop, uidebug,
     vterminal;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure terminal_command_meminfo(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    push_trace('kernel.terminal_command_meminfo');

    stdio.bufWriteStr(stdout_buf, 'Lower Memory = ');
    stdio.bufWriteInt(stdout_buf, multibootinfo^.mem_lower);
    stdio.bufWriteStrLn(stdout_buf, 'KB');
    stdio.bufWriteStr(stdout_buf, 'Higher Memory = ');
    stdio.bufWriteInt(stdout_buf, multibootinfo^.mem_upper);
    stdio.bufWriteStrLn(stdout_buf, 'KB');
    stdio.bufWriteStr(stdout_buf, 'Total Memory = ');
    stdio.bufWriteInt(stdout_buf, ((multibootinfo^.mem_upper + 1000) div 1024) + 1);
    stdio.bufWriteStrLn(stdout_buf, 'MB');

    pop_trace;
end;

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

procedure myUserLandFunction;
var
    i : uint32;

begin
    i:=0;
    while true do begin 
        i:=i+1;
        asm
            MOV EAX, i
        end;
    end;
end;

procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall; [public, alias: 'kmain'];   
var
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

     { Store Multiboot info }
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

     { Ensure tracer is frozen }
     tracer.freeze();

     syslog.writestringln('Booting Asuro...');

     syslog.writestringln('Checking for Multiboot Compliance');
     { Check for Multiboot }
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

     { Stdio Init }
     stdio.init();
     stdio.registerCommand('MEMINFO', @terminal_command_meminfo, 'Print Simple Memory Information.');
     stdio.registerCommand('BSOD', @terminal_command_bsod, 'Force a Panic Screen.');

     tss.init();
     scheduler.init();

     { CPUID }
     syslog.logln('CPU', 'Init begin');
     cpu.init();
     syslog.logln('CPU', 'Init end');

     { Call Tracer }
     tracer.init();

     { Video Init }
     video.init();
     vesa.init(@video.register);
     doublebuffer.init(@video.register);
     video.enable('VESA');
     video.enable('BASIC_DOUBLE_BUFFER');

     { VFS Init }
     vfs.init();

     { Management Interfaces }
     tracer.push_trace('kmain.DRVMGMT');
     drivermanagement.init();
     tracer.push_trace('kmain.STRMGMT');
     storagemanagement.init();

     { Enable interrupts and hook timer }
     tracer.push_trace('kmain.TMR');
     STI;
     TMR_0_ISR.hook(uint32(@bios_data_area.tick_update));

     { Filesystems }
     fat32.init();

     { Device Drivers }
     tracer.push_trace('kmain.DEVDRV');
     syslog.logln('KERNEL', 'DEVICE DRIVERS: INIT BEGIN.');
     ps2_keyboard.init(keyboard_layout);
     ps2_mouse.init();
     testdriver.init();
     E1000.init();
     IDE.init();
     syslog.logln('KERNEL', 'DEVICE DRIVERS: INIT END.');

     { Bus Drivers }
     tracer.push_trace('kmain.BUSDRV');
     syslog.logln('KERNEL', 'BUS DRIVERS: INIT BEGIN.');
     USB.init();
     pci.init();
     syslog.logln('KERNEL', 'BUS DRIVERS: INIT END.');

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

     { Run unit tests }
     strings.UnitTest;
     usbtypes.UnitTest;
     usbcore.UnitTest;
     UHCI.UnitTest;
     OHCI.UnitTest;
     usbhub.UnitTest;
     usb_keyboard.UnitTest;
     usb_mouse.UnitTest;

     { Main render loop }
     syslog.logln('KERNEL', 'Entering main render loop.');
     while true do begin
        usbcore.poll_all;
        usb_keyboard.poll_keyboards;
        usb_mouse.poll_mice;
        desktop.update;
        uidebug.update;
        lvgl_handler;
        video.Flush();
     end;

end;
 
end.
