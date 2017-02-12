unit kernel;
 
interface
 
uses
     multiboot,
     util,
     console,
     BIOS_DATA_AREA;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: DWORD); stdcall;
 
implementation
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: DWORD); stdcall; [public, alias: 'kmain'];   
begin
     console.init();
     console.writestringln('Booting Asuro...');
     if (mbmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console.setdefaultattribute(console.combinecolors(Red, Black));
        console.writestringln('Multiboot Compliant Boot-Loader Needed!');
        console.writestringln('HALTING');
        util.halt_and_catch_fire;
     end;
     console.clear();
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
     util.halt_and_catch_fire;
end;
 
end.
