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
     PCI,
     Terminal,
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
     shell,
     memview,
     splash,
     themer,
     netlog,
     vmlog,
     vm,
     vmstate,
     edit,
     udpcat,
     cpu,
     rand;
 
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

procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall; [public, alias: 'kmain'];   
var
   c               : uint8;
   z               : uint32;
   dds             : uint32;
   pint            : puint32;
   pint2           : puint32;
   keyboard_layout : array [0..1] of TKeyInfo;
   i               : uint32;
   cEIP            : uint32;
   temp            : uint32;
   atmp            : puint32;
   test            : puint8;
   fb              : puint16;
   l               : PLinkedListBase;
   
begin
     { Serial Init }
     serial.init();

     { Store Multiboot info }
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

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
     rand.srand((getDateTime.Seconds SHR 24) OR (getDateTime.Minutes SHR 16) OR (getDateTime.Hours SHR 8) OR (getDateTime.Day));     
     pmemorymanager.init();
     vmemorymanager.init();
     lmemorymanager.init();
     tss.init();
     scheduler.init();

     { Console Init }
     console.init();

     { CPUID }
     cpu.init();

     { Call Tracer }
     tracer.init();

     { Management Interfaces }
     tracer.push_trace('kmain.DRVMGMT');
     drivermanagement.init();
     tracer.push_trace('kmain.STRMGMT');
     storagemanagement.init();

     { Hook Timer for Ticks }
     tracer.push_trace('kmain.TMR');
     STI;
     TMR_0_ISR.hook(uint32(@bios_data_area.tick_update));

     { Filsystems }
     fat32.init();

     { Device Drivers }
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
     //USB.init();
     pci.init();
     console.outputln('KERNEL', 'BUS DRIVERS: INIT END.');

     { Network Stack }
     tracer.push_trace('kmain.NETDRV');
     net.init;

     tracer.push_trace('kmain.VMINIT');
     vm.init();

     { Init Progs }
     tracer.push_trace('kmain.SHELLINIT');
     shell.init();
     tracer.push_trace('kmain.MEMVIEWINIT');
     memview.init();
     tracer.push_trace('kmain.THEMERINIT');
     themer.init();
     tracer.push_trace('kmain.NETLOGINIT');
     netlog.init();
     tracer.push_trace('kmain.VMLOGINIT');
     vmlog.init();
     tracer.push_trace('kmain.VMSTATEINIT');
     vmstate.init();
     tracer.push_trace('kmain.EDIT');
     edit.init();
     udpcat.init();
     terminal.run();

     { Init Splash }
     //tracer.push_trace('kmain.SPLASHINIT');
     //splash.init();

     { End of Boot }
     tracer.push_trace('kmain.EOB');

     console.writestringln('');
     console.setdefaultattribute(console.combinecolors($17E0, $0000));
     console.writestringln('Asuro Booted Correctly!');
     console.setdefaultattribute(console.combinecolors($FFFF, $0000));

     tracer.push_trace('kmain.END');

     writehexln(rand.rand32);
     writehexln(rand.rand32);
     writehexln(rand.rand32);

     tracer.push_trace('kmain.TICK');
     while true do begin
        tracer.push_trace('kmain.RedrawWindows');
        console.redrawWindows;
        tracer.push_trace('kmain.VMTick');
        vm.tick();
     end;
end;
 
end.
