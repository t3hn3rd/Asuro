unit kernel;
 
interface
 
uses
     multiboot,
     util,
     gdt,
     idt,
     isr,
     console,
     bios_data_area,
     keyboard;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation
 
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
     gdt.init();
     idt.init();
     isr.init();
     console.init();
     console.writestringln('Booting Asuro...');
     if (mbm <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console.setdefaultattribute(console.combinecolors(Red, Black));
        console.writestringln('Multiboot Compliant Boot-Loader Needed!');
        console.writestringln('HALTING');
        util.halt_and_catch_fire;
     end;
     console.clear();
     console.writestring('If this reads "0x8" then we have a GDT: ');
     asm
        MOV dds, CS
     end;
     console.setdefaultattribute(console.combinecolors(Red, Black));
     if dds = $08 then console.setdefaultattribute(console.combinecolors(Green, Black));
     console.writehexln(dds);
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
     util.halt_and_dont_catch_fire;
     {while true do begin
          c:= keyboard.get_scancode;
          console.writehexln(c);  
     end;
     util.halt_and_catch_fire;}
end;
 
end.
