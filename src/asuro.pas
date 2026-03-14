//  Copyright 2021 Kieron Morris & Aaron Hance
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{ 
	Kernel Main - Main Kernel Entry Point.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit asuro;
 
interface
 
uses
    boot.mgr,
    io.syslog,
    core.panic,
    arch.x86.multiboot,
    arch.x86.proc.sched;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure init();
begin
    { Syslog Init — right after driver.io.serial so log hooks work }
    io.syslog.logln('ASURO', 'Booting Asuro...');

    { Check for Multiboot }
    io.syslog.logln('ASURO', 'Checking for Multiboot Compliance');
    if (multibootmagic <> MULTIBOOT_BOOTLOADER_MAGIC) then begin
        io.syslog.logln('ASURO', 'Multiboot Compliant Boot-Loader Needed!');
        io.syslog.logln('ASURO', 'HALTING.');
        core.panic.panic('Multiboot Error', 'Multiboot Compliant Boot-Loader Needed!', nil);
    end;

    io.syslog.log('ASURO', 'Assigned Multiboot Framebuffer: ');
    io.syslog.writehexln(multibootinfo^.framebuffer_addr);
    io.syslog.log('ASURO', 'Assigned Multiboot Framebuffer Metrics: ');
    io.syslog.writeint(multibootinfo^.framebuffer_width);
    io.syslog.writestring('x');
    io.syslog.writeint(multibootinfo^.framebuffer_height);
    io.syslog.writestring('x');
    io.syslog.writeintln(multibootinfo^.framebuffer_bpp);
end;

procedure yield();
begin
    io.syslog.logln('KERNEL', 'Boot complete - halting into IDLE');
    arch.x86.proc.sched.init;
    asm
         sti
     @idle:
         hlt
         jmp @idle
     end;
end;

procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall; [public, alias: 'kmain'];   
begin
    { Store Multiboot info }
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

     { Init the base system unit }
     System.init();

     { Run the boot manager }
     boot.mgr.run;

     { All work is now driven by interrupts & scheduling — idle the CPU }
     { Enable preemptive context switching (replaces ISR_32) }
     yield();
end;

initialization
    boot.mgr.registerBoot('asuro', @asuro.init, 'Kernel Initialization', 'io.syslog');
    
end.
