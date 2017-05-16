unit kernel;
 
interface
 
uses
     multiboot,
     util,
     gdt,
     console,
     bios_data_area,
     keyboard;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: DWORD); stdcall;
 
implementation
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: DWORD); stdcall; [public, alias: 'kmain'];   
var
   c : byte;
   mbi : Pmultiboot_info_t;
   mbm : DWORD;
   dds  : DWORD;
   
begin
     mbi:= mbinfo;
     mbm:= mbmagic;
     //gdt.init();
     console.init();
     console.writestringln('Booting Asuro...');
     if (mbm <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console.setdefaultattribute(console.combinecolors(Red, Black));
        console.writestringln('Multiboot Compliant Boot-Loader Needed!');
        console.writestringln('HALTING');
        util.halt_and_catch_fire;
     end;
     console.clear();
     asm
        MOV dds, DS
     end;
     console.writehexln(dds);
     util.halt_and_catch_fire;
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
     while true do begin
          c:= keyboard.get_scancode;
          console.writehexln(c);  
     end;
     util.halt_and_catch_fire;
end;
 
end.
