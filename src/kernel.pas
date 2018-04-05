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
     isr32,
     console,
     bios_data_area,
     keyboard,
     mouse,
     vmemorymanager,
     pmemorymanager,
     lmemorymanager,
     drivermanagement,
     tss,
     scheduler,
     PCI,
     Terminal,
     strings,
     AHCI,
     USB,
     testdriver;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure temphook(ignored : TKeyInfo);
begin
   Terminal.run;
end;

procedure terminal_command_meminfo(params : PParamList);
begin
    console.writestring('Lower Memory = ');
    console.writeint(multibootinfo^.mem_lower);
    console.writestringln('KB');
    console.writestring('Higher Memory = ');
    console.writeint(multibootinfo^.mem_upper);
    console.writestringln('KB');
    console.writestring('Total Memory = ');
    console.writeint(((multibootinfo^.mem_upper + 1000) div 1024) + 1);
    console.writestringln('MB');
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
   
begin
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

     terminal.init();
     terminal.registerCommand('MEMINFO', @terminal_command_meminfo, 'Print Simple Memory Information.');

     drivermanagement.init();

     console.init();

     console.writestringln('Booting Asuro...');

     if (multibootmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console.setdefaultattribute(console.combinecolors(Red, Black));
        console.writestringln('Multiboot Compliant Boot-Loader Needed!');
        console.writestringln('HALTING');
        util.halt_and_catch_fire;
     end;

     gdt.init();
     asm
        MOV dds, CS
     end;
     if dds = $08 then begin
        console.writestringlnex('GDT: LOAD SUCCESS.', console.combinecolors(Green, Black));
     end else begin
        console.writestringlnex('GDT: LOAD FAIL.', console.combinecolors(Red, Black));
        halt_and_catch_fire;
     end;

     idt.init();
     isr.init();
     irq.init();
     pmemorymanager.init();
     vmemorymanager.init();
     lmemorymanager.init();
     tss.init();
     scheduler.init();

     //asm INT 13 end;
     STI;
     isr32.hook(uint32(@bios_data_area.tick_update));

     //drivers
     console.writestringln('DRIVERS: INIT BEGIN.');
     //keyboard.init(keyboard_layout);
     //mouse.init();
     //AHCI.init();
     //testdriver.init();
     USB.init();
     pci.init();
     halt_and_catch_fire;
     console.writestringln('DRIVERS: INIT END.');

     console.writestringln('');
     console.setdefaultattribute(console.combinecolors(Green, Black));
     console.writestringln('Asuro Booted Correctly!');
     console.writestringln('');
     console.setdefaultattribute(console.combinecolors(White, Black));
     console.writestring('Lower Memory = ');
     console.writeint(multibootinfo^.mem_lower);
     console.writestringln('KB');
     console.writestring('Higher Memory = ');
     console.writeint(multibootinfo^.mem_upper);
     console.writestringln('KB');
     console.writestring('Total Memory = ');
     console.writeint(((multibootinfo^.mem_upper + 1000) div 1024) + 1);
     console.writestringln('MB');
     console.setdefaultattribute(console.combinecolors(White, Black));
     console.writestringln('');
     console.writestringln('Press any key to boot in to Asuro Terminal...');
     keyboard.hook(@temphook);
     util.halt_and_dont_catch_fire;
end;
 
end.
