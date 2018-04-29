{ ************************************************
  * Asuro
  * Unit: Kernel
  * Description: Main Entry Point for Asuro
  ************************************************
  * Author: K Morris
  * Contributors: A Hance
  ************************************************ }

unit kernel;
 
interface
 
uses
     multiboot,
     util,
     gdt,
     idt,
     isr,
     irq,
     TMR_0_ISR,
     console,
     bios_data_area,
     keyboard,
     mouse,
     vmemorymanager,
     pmemorymanager,
     lmemorymanager,
     tracer,
     drivermanagement,
     tss,
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
     RTC;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure temphook(ignored : TKeyInfo);
begin
   Terminal.run;
end;

procedure terminal_command_meminfo(params : PParamList);
begin
    push_trace('kernel.terminal_command_meminfo');

    console.writestring('Lower Memory = ');
    console.writeint(multibootinfo^.mem_lower);
    console.writestringln('KB');
    console.writestring('Higher Memory = ');
    console.writeint(multibootinfo^.mem_upper);
    console.writestringln('KB');
    console.writestring('Total Memory = ');
    console.writeint(((multibootinfo^.mem_upper + 1000) div 1024) + 1);
    console.writestringln('MB');

    pop_trace;
end;

procedure terminal_command_bsod(params : PParamList);
begin
    push_trace('kernel.terminal_command_bsod');

    if ParamCount(params) > 1 then begin
      bsod(getparam(0, params), getparam(1, params));
    end else begin
        console.writestringln('Invalid number of params.');
        console.writestringln('Usage: bsod <error> <info>');
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
   
begin
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

     { Call Tracer }
     tracer.init();

     { Management Interfaces }
     tracer.push_trace('kmain.DRVMGMT');
     drivermanagement.init();
     tracer.pop_trace;
     tracer.push_trace('kmain.STRMGMT');
     storagemanagement.init();
     tracer.pop_trace;

     { Hook Timer for Ticks }
     tracer.push_trace('kmain.TMR');
     STI;
     TMR_0_ISR.hook(uint32(@bios_data_area.tick_update));
     tracer.pop_trace;

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
     tracer.pop_trace;

     { Bus Drivers }
     tracer.push_trace('kmain.BUSDRV');
     console.outputln('KERNEL', 'BUS DRIVERS: INIT BEGIN.');
     USB.init();
     pci.init();
     console.outputln('KERNEL', 'BUS DRIVERS: INIT END.');
     tracer.pop_trace;

     { Network Stack }
     tracer.push_trace('kmain.NETDRV');
     net.init;
     tracer.pop_trace;

     { End of Boot }
     tracer.push_trace('kmain.EOB');
     console.writestringln('');
     console.setdefaultattribute(console.combinecolors($17E0, $0000));
     console.writestringln('Asuro Booted Correctly!');
     console.setdefaultattribute(console.combinecolors($FFFF, $0000));
     console.writestringln('');
     console.writestringln('Press any key to boot in to Asuro Terminal...');
     tracer.pop_trace;

     tracer.push_trace('kmain.KEYHOOK');
     keyboard.hook(@temphook);
     tracer.pop_trace;

     tracer.push_trace('kmain.END');

     while true do begin
        console.redrawWindows;
     end;
end;
 
end.
