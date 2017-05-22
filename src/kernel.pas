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
     vmemorymanager,
     pmemorymanager,
     lmemorymanager,
     tss,
     scheduler,
     PCI;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall; [public, alias: 'kmain'];   
var
   c    : uint8;
   z    : uint32;
   dds  : uint32;
   pint : puint32;
   pint2 : puint32;
   keyboard_layout : array [0..1] of TKeyInfo;
   i : uint32;
   cEIP : uint32;
   
begin
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

     console.init();

     console.writestringln('Booting Asuro...');

     if (multibootmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console.setdefaultattribute(console.combinecolors(Red, Black));
        console.writestringln('Multiboot Compliant Boot-Loader Needed!');
        console.writestringln('HALTING');
        util.halt_and_catch_fire;
     end;

     gdt.init();
     idt.init();
     isr.init();
     irq.init();
     pmemorymanager.init();
     vmemorymanager.init();
     lmemorymanager.init();
     scheduler.init();
     tss.init();
    
     STI;
     isr32.hook(uint32(@bios_data_area.tick_update));

     //drivers
     console.writestringln('Initializing Drivers');
     pci.init();
     keyboard.init(keyboard_layout);
     console.writestringln('Drivers Initialized');


     asm
        MOV dds, CS
     end;
     if dds = $08 then begin
        console.setdefaultattribute(console.combinecolors(Green, Black));
        console.writestringln('GDT: LOAD SUCCESS.');
     end else begin
        console.setdefaultattribute(console.combinecolors(Red, Black));
        console.writestringln('GDT: LOAD FAIL.');
     end;

     console.writestringln('');
     console.setdefaultattribute(console.combinecolors(Green, Black));
     console.writestringln('Asuro Booted Correctly!');
     console.writestringln('');
     console.setdefaultattribute(console.combinecolors(White, Black));
     console.writestring('Lower Memory = ');
     console.writeint(mbinfo^.mem_lower);
     console.writestringln('KB');
     console.writestring('Higher Memory = ');
     console.writeint(mbinfo^.mem_upper);
     console.writestringln('KB');
     console.writestring('Total Memory = ');
     console.writeint(((mbinfo^.mem_upper + 1000) div 1024) + 1);
     console.writestringln('MB');
     console.setdefaultattribute(console.combinecolors(lYellow, Black));
     util.halt_and_dont_catch_fire;
end;
 
end.
