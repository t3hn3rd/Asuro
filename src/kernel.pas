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
unit kernel;
 
interface
 
uses
     multiboot, bios_data_area,
     util,
     gdt, idt, isr, irq, tss,
     TMR_0_ISR,
     PS2_KEYBOARD_ISR,
     console,
     keyboard, mouse,
     vmemorymanager, pmemorymanager, lmemorymanager,
     tracer,
     drivermanagement,
     scheduler,
     progmanager,
     PCI,
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
     RTC,
     serial,
     cpu,
     md5,
     base64,
     rand,
     terminal,
     hashmap, vfs, 
     video, vesa, doublebuffer, color,
     imgui, imguitypes, desktop;
 
procedure kmain(mbinfo: Pmultiboot_info_t; mbmagic: uint32); stdcall;
 
implementation

procedure terminal_command_meminfo(params : PParamList);
begin
    push_trace('kernel.terminal_command_meminfo');

    console.writestringWND('Lower Memory = ', getTerminalHWND);
    console.writeintWND(multibootinfo^.mem_lower, getTerminalHWND);
    console.writestringlnWND('KB', getTerminalHWND);
    console.writestringWND('Higher Memory = ', getTerminalHWND);
    console.writeintWND(multibootinfo^.mem_upper, getTerminalHWND);
    console.writestringlnWND('KB', getTerminalHWND);
    console.writestringWND('Total Memory = ', getTerminalHWND);
    console.writeintWND(((multibootinfo^.mem_upper + 1000) div 1024) + 1, getTerminalHWND);
    console.writestringlnWND('MB', getTerminalHWND);

    pop_trace;
end;

procedure terminal_command_bsod(params : PParamList);
begin
    push_trace('kernel.terminal_command_bsod');

    if ParamCount(params) > 1 then begin
      bsod(getparam(0, params), getparam(1, params));
    end else begin
        console.writestringlnWND('Invalid number of params.', getTerminalHWND);
        console.writestringlnWND('Usage: bsod <error> <info>', getTerminalHWND);
    end;  

    pop_trace; 
end;

procedure myUserLandFunction;
var
    i : uint32;

begin
    i:=0;
    while true do begin 
        i:=i+1;
        asm
            MOV EAX, i
        end;
    end;
end;

var
    tick_count : uint32 = 0;

procedure tick_handler(data : void);
begin
    Inc(tick_count);
end;

procedure imgui_scancode_hook(scan_code : void);
begin
    imgui_handle_scancode(uint32(scan_code));
end;

procedure imgui_mouse_hook(x, y: sint32; lmb, rmb, mmb: boolean);
var
    fx, fy: Single;
begin
    { Buffer mouse events — will be drained before next frame }
    fx := x;
    fy := y;
    imgui_handle_mouse_pos(fx, fy);
    imgui_handle_mouse_button(0, sint32(lmb));
    imgui_handle_mouse_button(1, sint32(rmb));
    imgui_handle_mouse_button(2, sint32(mmb));
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
   l               : PLinkedListBase;
   ulf             : pointer;

   HM              : PHashMap;

   colour          : TRGB32;

   array1          : Array[0..255] of char;
   array2          : Array[0..255] of char;
   ticks           : uint32;
   dt_ticks        : uint32;
   last_tick_count : uint32;
   
begin
     { Init the base system unit }
     System.init();

     { Serial Init }
     serial.init();

     { Store Multiboot info }
     multibootinfo:= mbinfo;
     multibootmagic:= mbmagic;

    //video.init();

     { Ensure tracer is frozen }
     tracer.freeze();

     { Terminal Init }
     terminal.init();
     terminal.registerCommand('MEMINFO', @terminal_command_meminfo, 'Print Simple Memory Information.');
     terminal.registerCommand('BSOD', @terminal_command_bsod, 'Force a Panic Screen.');

     console.writestringln('Booting Asuro...');
     
     console.writestringln('Checking for Multiboot Compliance');
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

     console.output('MULTIBOOT', 'Assigned Framebuffer: ');
     console.writehexln(multibootinfo^.framebuffer_addr);
     console.output('MULTIBOOT', 'Assigned Framebuffer Metrics: ');
     console.writeint(multibootinfo^.framebuffer_width);
     console.writestring('x');
     console.writeint(multibootinfo^.framebuffer_height);
     console.writestring('x');
     console.writeintln(multibootinfo^.framebuffer_bpp);

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

     { CPUID }
     console.outputln('CPU', 'Init begin');
     cpu.init();
     console.outputln('CPU', 'Init end');

     { Call Tracer }
     tracer.init();

     { Virtual File System }
     vfs.init();

     video.init();
     vesa.init(@video.register);
     doublebuffer.init(@video.register);
     video.enable('VESA');
     video.enable('BASIC_DOUBLE_BUFFER');
     colour:= color.white;

    //  serial.sendHex(uint32(@array1[8]));
    //  serial.sendHex(uint32(@array2[8]));
    //  for i:=8 to 23 do begin
    //     array2[i]:= '?';
    //  end;
    //  array2[24]:= #0;

    //  array1[8]:= 'H';
    //  array1[9]:= 'e';
    //  array1[10]:= 'l';
    //  array1[11]:= 'l';
    //  array1[12]:= 'o';
    //  array1[13]:= 'w';
    //  array1[14]:= 'o';
    //  array1[15]:= 'r';
    //  array1[16]:= 'l';
    //  array1[17]:= 'd';
    //  array1[18]:= '1';
    //  array1[19]:= '2';
    //  array1[20]:= '3';
    //  array1[21]:= '4';
    //  array1[22]:= '5';
    //  array1[23]:= '!';
    //  __SSE_128_memcpy(uint32(@array1[8]), uint32(@array2[8]));
    //  serial.sendString(pchar(@array2[8]));

     { Clear screen to dark grey }
     colour.R := 40; colour.G := 40; colour.B := 40; colour.A := 0;
     for i:=0 to video.frontBufferWidth-1 do begin
        for z:=0 to video.frontBufferHeight-1 do begin
            video.DrawPixel(i, z, colour);
        end;
     end;
     video.Flush();

     { Initialize ImGui }
     console.outputln('KERNEL', 'ImGui: INIT BEGIN.');
     imgui_init(video.frontBufferWidth, video.frontBufferHeight);
     console.outputln('KERNEL', 'ImGui: INIT END.');

     { Initialize desktop }
     console.outputln('KERNEL', 'Desktop: INIT BEGIN.');
     desktop_init;
     console.outputln('KERNEL', 'Desktop: INIT END.');

     { Initialize input drivers }
     console.outputln('KERNEL', 'Input: INIT BEGIN.');
     keyboard.init(keyboard_layout);
     mouse.init();
     console.outputln('KERNEL', 'Input: INIT END.');

     { Enable interrupts }
     STI;

     { Hook timer for delta time }
     TMR_0_ISR.hook(uint32(@tick_handler));

     { Hook PS2 keyboard ISR for raw scancodes -> ImGui keys }
     PS2_KEYBOARD_ISR.hook(uint32(@imgui_scancode_hook));

     { Hook mouse -> ImGui }
     mouse.setHook(@imgui_mouse_hook);

     { Warm-up frames: ImGui needs 2+ frames for window layout }
     imgui_new_frame;
     desktop_frame;
     imgui_render;
     imgui_new_frame;
     desktop_frame;
     imgui_render;

     { Main interactive render loop }
     console.outputln('KERNEL', 'ImGui: Entering render loop.');
     last_tick_count := tick_count;
     while true do begin
         { Compute delta time from ~1024 Hz timer ticks }
         ticks := tick_count;
         dt_ticks := ticks - last_tick_count;
         last_tick_count := ticks;
         if dt_ticks > 0 then
             imgui_feed_delta_time(Single(dt_ticks) * Single(0.0009765625))  { 1/1024 }
         else
             imgui_feed_delta_time(Single(0.001));

         imgui_process_input;
         imgui_new_frame;
         desktop_frame;
         imgui_render;
     end;

end;

end.
