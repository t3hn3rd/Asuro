unit kernel;
 
interface
 
uses
     multiboot,
     util,
     gdt,
     idt,
     isr,
     irq,
     isr0,
     console,
     bios_data_area,
     keyboard;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation
 
procedure test(data : void);
begin
    console.writestringln('It works.');
end;

procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall; [public, alias: 'kmain'];   
var
   c : uint8;
   mbi : Pmultiboot_info_t;
   mbm : uint32;
   z    : uint32;
   dds  : uint32;
   
begin
     mbi:= mbinfo;
     mbm:= mbmagic;
     console.init();

     console.writestringln('Booting Asuro...');

     if (mbm <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console.setdefaultattribute(console.combinecolors(Red, Black));
        console.writestringln('Multiboot Compliant Boot-Loader Needed!');
        console.writestringln('HALTING');
        util.halt_and_catch_fire;
     end;

     gdt.init();
     idt.init();
     isr.init();
     irq.init();

     STI;

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
     console.writeint(((mbinfo^.mem_upper + 1000) div 1024) +1);
     console.writestringln('MB');
     console.setdefaultattribute(console.combinecolors(lYellow, Black));

     isr0.hook(uint32(@test));
     asm INT 0 end;

     util.halt_and_dont_catch_fire;
end;
 
end.
