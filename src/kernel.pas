unit kernel;
 
interface
 
uses
        multiboot,
        console,
        util;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: DWORD); stdcall;
 
implementation
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: DWORD); stdcall; [public, alias: 'kmain'];
begin
     console_init();
     console_writestringln('Asuro Booting...');
     if (mbmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console_setdefaultattribute(console_combinecolors(Red, Black));
        console_writestringln('Multiboot Compliant Boot-Loader Needed!');
        console_writestringln('HALTING');
        asm
           cli
           hlt
        end;
     end;
     console_setdefaultattribute(console_combinecolors(Green, Black));
     console_writestringln('Asuro Booted Correctly!');
     console_writestring('Lower Memory = ');
     console_writeint(mbinfo^.mem_lower);
     console_writestringln('KB');
     console_writestring('Higher Memory = ');
     console_writeint(mbinfo^.mem_upper);
     console_writestringln('KB');
     console_writestring('Total Memory = ');
     console_writeint(((mbinfo^.mem_upper + 1000) div 1024) +1);
     console_writestringln('MB');
     asm
        cli
        hlt
     end;
end;
 
end.
