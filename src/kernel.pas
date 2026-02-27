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
     console,
     keyboard, mouse,
     vmemorymanager, pmemorymanager, lmemorymanager,
     tracer,
     drivermanagement,
     scheduler,
     progmanager,
     PCI,
     strings,
     USB,
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
     terminal,
     hashmap, vfs, 
     video, vesa, doublebuffer, color, lvgl, desktop, uidebug;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure terminal_command_meminfo(params : PParamList);
begin
    push_trace('kernel.terminal_command_meminfo');

    console.writestringWND('Lower Memory = ', getTerminalHWND);
    console.writeintWND(multibootinfo^.mem_lower, getTerminalHWND);
    console.writestringlnWND('KB', getTerminalHWND);
    console.writestringWND('Higher Memory = ', getTerminalHWND);
    console.writeintWND(multibootinfo^.mem_upper, getTerminalHWND);
    console.writestringlnWND('KB', getTerminalHWND);
    console.writestringWND('Total Memory = ', getTerminalHWND);
    console.writeintWND(((multibootinfo^.mem_upper + 1000) div 1024) + 1, getTerminalHWND);
    console.writestringlnWND('MB', getTerminalHWND);

    pop_trace;
end;

procedure terminal_command_bsod(params : PParamList);
begin
    push_trace('kernel.terminal_command_bsod');

    if ParamCount(params) > 1 then begin
      bsod(getparam(0, params), getparam(1, params));
    end else begin
        console.writestringlnWND('Invalid number of params.', getTerminalHWND);
        console.writestringlnWND('Usage: bsod <error> <info>', getTerminalHWND);
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
   
begin
     { Init the base system unit }
     System.init();

     { Serial Init }
     serial.init();

     { Store Multiboot info }
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

    //video.init();

     { Ensure tracer is frozen }
     tracer.freeze();

     { Terminal Init }
     terminal.init();
     terminal.registerCommand('MEMINFO', @terminal_command_meminfo, 'Print Simple Memory Information.');
     terminal.registerCommand('BSOD', @terminal_command_bsod, 'Force a Panic Screen.');

     console.writestringln('Booting Asuro...');
     
     console.writestringln('Checking for Multiboot Compliance');
     { Check for Multiboot }
     if (multibootmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console.setdefaultattribute(console.combinecolors($F800, $0000));
        console.outputln('KERNEL', 'Multiboot Compliant Boot-Loader Needed!');
        console.outputln('KERNEL', 'HALTING.');
        BSOD('Multiboot Error', 'Multiboot Compliant Boot-Loader Needed!');
        util.halt_and_catch_fire;
     end;

     { GDT Init }
     gdt.init();
     asm
        MOV dds, CS
     end;
     if dds = $08 then begin
        console.outputln('KERNEL', 'GDT: LOAD SUCCESS.');
     end else begin
        console.outputln('KERNEL', 'GDT: LOAD FAIL.');
        console.outputln('KERNEL', 'HALTING.');
        BSOD('GDT', 'Failed to load the GDT correctly.');
     end;

     console.output('MULTIBOOT', 'Assigned Framebuffer: ');
     console.writehexln(multibootinfo^.framebuffer_addr);
     console.output('MULTIBOOT', 'Assigned Framebuffer Metrics: ');
     console.writeint(multibootinfo^.framebuffer_width);
     console.writestring('x');
     console.writeint(multibootinfo^.framebuffer_height);
     console.writestring('x');
     console.writeintln(multibootinfo^.framebuffer_bpp);

     { Memory/CPU Init }
     idt.init();
     irq.init();
     isrmanager.init();
     faults.init();
     RTC.init();
          
     pmemorymanager.init();
     vmemorymanager.init();
     lmemorymanager.init();
     tss.init();
     scheduler.init();

     { Console Init }
     console.init();

     { CPUID }
     console.outputln('CPU', 'Init begin');
     cpu.init();
     console.outputln('CPU', 'Init end');

     { Call Tracer }
     tracer.init();

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

     { Enable interrupts and hook timer BEFORE LVGL }
     tracer.push_trace('kmain.TMR');
     STI;
     TMR_0_ISR.hook(uint32(@bios_data_area.tick_update));

     { Filesystems }
     fat32.init();

     { Device Drivers — must init before LVGL so mouse/keyboard are available }
     tracer.push_trace('kmain.DEVDRV');
     console.outputln('KERNEL', 'DEVICE DRIVERS: INIT BEGIN.');
     keyboard.init(keyboard_layout);
     mouse.init();
     testdriver.init();
     E1000.init();
     IDE.init();
     console.outputln('KERNEL', 'DEVICE DRIVERS: INIT END.');

     { Bus Drivers }
     tracer.push_trace('kmain.BUSDRV');
     console.outputln('KERNEL', 'BUS DRIVERS: INIT BEGIN.');
     USB.init();
     pci.init();
     console.outputln('KERNEL', 'BUS DRIVERS: INIT END.');

     { Network Stack }
     tracer.push_trace('kmain.NETDRV');
     net.init;

     { Init Progs }
     progmanager.init();

     { Seed RNG }
     rand.srand((getDateTime.Seconds SHL 24) OR (getDateTime.Minutes SHL 16) OR (getDateTime.Hours SHL 8) OR (getDateTime.Day));

     { Initialize LVGL }
     console.outputln('KERNEL', 'LVGL: INIT BEGIN.');
     lvgl_init(video.frontBufferWidth, video.frontBufferHeight);
     console.outputln('KERNEL', 'LVGL: INIT COMPLETE.');

     { Initialize desktop environment }
     console.outputln('KERNEL', 'DESKTOP: INIT BEGIN.');
     desktop.init;
     console.outputln('KERNEL', 'DESKTOP: INIT COMPLETE.');

     { Main render loop }
     console.outputln('KERNEL', 'Entering main render loop.');
     tracer.push_trace('kmain.MAINLOOP');
     while true do begin
        desktop.update;
        uidebug.update;
        lvgl_handler;
        video.Flush();
     end;

end;
 
end.
