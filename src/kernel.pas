{
/////////////////////////////////////////////////////////
//                                                     //
//               Freepascal barebone OS                //
//                      kernel.pas                     //
//                                                     //
/////////////////////////////////////////////////////////
//
//      By:             De Deyn Kim <kimdedeyn@skynet.be>
//      License:        Public domain
//
}
 
unit kernel;
 
interface
 
uses
        multiboot,
        console;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: DWORD); stdcall;
 
implementation
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: DWORD); stdcall; [public, alias: 'kmain'];
begin
     console_init();
     console_writestringln('Asuro Booting...', #7);
     if (mbmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        console_writestringln('Multiboot Compliant Boot-Loader Needed!', #7);
        console_writestringln('HALTING', #7);
        asm
           cli
           hlt
        end;
     end;
     console_writestringln('Asuro Booted Correctly!', #7);
     console_writestring('Lower Memory = ', #7);
     console_writeint(mbinfo^.mem_lower, #7);
     console_writestringln('KB', #7);
     console_writestring('Higher Memory = ', #7);
     console_writeint(mbinfo^.mem_upper, #7);
     console_writestringln('KB', #7);
     console_writestring('Total Memory = ', #7);
     console_writeint(((mbinfo^.mem_upper + 1000) div 1024) +1, #7);
     console_writestringln('MB', #7);
     asm
        @loop:
        jmp @loop
     end;
end;
 
end.
