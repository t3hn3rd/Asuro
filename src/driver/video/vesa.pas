//  Copyright 2021 Kieron Morris
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
	Driver->Video->VESA - VESA Display Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit vesa;

interface

uses
    videotypes, tracer, multiboot, lmemorymanager, v86, util, syslog, gpu;

const
    { VBE buffer addresses in low physical memory }
    VBE_INFO_ADDR       = $1000;  { 512 bytes for VBE controller info }
    VBE_MODE_INFO_ADDR  = $1200;  { 256 bytes for VBE mode info }

//Init the driver, and register with the video interface in a state ready for execution.
procedure init(Register : FRegisterDriver);

//Set a new VBE video mode by resolution and bpp. Returns true on success.
function setMode(width, height : uint32; bpp : uint8) : boolean;

implementation

uses
    VESA8, VESA16, VESA24, VESA32;

{ GPU framework: VBE setMode callback.
  Wraps the existing vesa.setMode and fills TGPUModeInfo on success. }
function vbeSetModeGPU(width, height : uint32; bpp : uint8;
                       var info : TGPUModeInfo) : boolean;
begin
    push_trace('vesa.vbeSetModeGPU');
    vbeSetModeGPU := false;
    if setMode(width, height, bpp) then begin
        info.Width       := width;
        info.Height      := height;
        info.BPP         := bpp;
        info.Framebuffer := multiboot.multibootinfo^.framebuffer_addr;
        info.Pitch       := multiboot.multibootinfo^.framebuffer_pitch;
        vbeSetModeGPU := true;
    end;
    pop_trace;
end;

procedure allocateVESAFrameBuffer(Address : uint32; Width : uint32; Height : uint32; BitsPerPixel : uint8);
var
    LowerAddress, UpperAddress : uint32;
    Block : uint32;
    FrameBufferSize : uint32;

begin
    tracer.push_trace('VESA.allocateFrameBuffer.enter');
    FrameBufferSize := (Width * Height * BitsPerPixel) div 8;
    LowerAddress:= ((Address) SHR 22)-1;
    UpperAddress:= ((Address + FrameBufferSize) SHR 22)+1;
    For Block:=LowerAddress to UpperAddress do begin
        kpalloc(Block SHL 22);
    end;
    tracer.push_trace('VESA.allocateFrameBuffer.exit');
end;

procedure initVESAFrameBuffer(VideoBuffer : PVideoBuffer; Location : uint64; Width : uint32; Height : uint32; BitsPerPixel : uint8; Pitch : uint32);
begin
    tracer.push_trace('VESA.initVESAFrameBuffer.enter');
    if not(VideoBuffer^.Initialized) then begin
        VideoBuffer^.Location:= Location;
        VideoBuffer^.BitsPerPixel:= BitsPerPixel;
        VideoBuffer^.Width:= Width;
        VideoBuffer^.Height:= Height;
        allocateVESAFrameBuffer(VideoBuffer^.Location, VideoBuffer^.Width, VideoBuffer^.Height, BitsPerPixel);
        if VideoBuffer^.Location <> 0 then
            VideoBuffer^.Initialized:= True;
    end;
    tracer.push_trace('VESA.initVESAFrameBuffer.exit');
end;

function enable(VideoInterface : PVideoInterface) : boolean;
begin
    tracer.push_trace('VESA.enable.enter');
    initVESAFrameBuffer(@VideoInterface^.FrontBuffer, multiboot.multibootinfo^.framebuffer_addr, multiboot.multibootinfo^.framebuffer_width, multiboot.multibootinfo^.framebuffer_height, multiboot.multibootinfo^.framebuffer_bpp, multiboot.multibootinfo^.framebuffer_pitch);
    case (VideoInterface^.FrontBuffer.BitsPerPixel) of
        08:VESA8.init(@VideoInterface^.DrawRoutines);
        16:VESA16.init(@VideoInterface^.DrawRoutines);
        24:VESA24.init(@VideoInterface^.DrawRoutines);
        32:VESA32.init(@VideoInterface^.DrawRoutines);
    end;
    enable:= VideoInterface^.FrontBuffer.Initialized;  
    tracer.push_trace('VESA.enable.exit');
end;

procedure init(Register : FRegisterDriver);
begin
    tracer.push_trace('VESA.init.enter');
    if Register <> nil then
        Register('VESA', @enable);
    { Register VBE as a GPU driver (priority 50 = fallback behind BGA) }
    gpu.registerDriver('VBE', 50, @vbeSetModeGPU);
    { VBE is available if the bootloader already set up a framebuffer }
    if multiboot.multibootinfo^.framebuffer_addr <> 0 then
        gpu.markAvailable('VBE');
    tracer.push_trace('VESA.init.exit');
end;

function setMode(width, height : uint32; bpp : uint8) : boolean;
var
    regs : TV86Regs;
    mode_list_off, mode_list_seg : uint16;
    mode_list_linear : uint32;
    mode : uint16;
    mode_width, mode_height : uint16;
    mode_bpp : uint8;
    mode_attr : uint16;
    mode_fb : uint32;
    mode_pitch : uint16;
    found_mode : uint16;
    found_fb : uint32;
    found_pitch : uint16;
    bufBase : uint32;

begin
    tracer.push_trace('VESA.setMode.enter');
    setMode := false;
    found_mode := $FFFF;
    bufBase := KERNEL_VIRTUAL_BASE;

    { Step 1: Get VBE controller info }
    { Write "VBE2" signature at buffer start for VBE2.0+ extended info }
    PuByte(bufBase + VBE_INFO_ADDR + 0)^ := ord('V');
    PuByte(bufBase + VBE_INFO_ADDR + 1)^ := ord('B');
    PuByte(bufBase + VBE_INFO_ADDR + 2)^ := ord('E');
    PuByte(bufBase + VBE_INFO_ADDR + 3)^ := ord('2');
    memset(bufBase + VBE_INFO_ADDR + 4, 0, 512 - 4);

    { INT 10h, AX=4F00h: Get VBE Controller Information }
    memset(uint32(@regs), 0, sizeof(TV86Regs));
    regs.EAX := $4F00;
    regs.ES  := 0;
    regs.EDI := VBE_INFO_ADDR;

    if not v86.v86_int($10, regs) then begin
        syslog.logln('VESA', 'setMode: VBE 4F00h failed (v86 error).');
        tracer.pop_trace;
        exit;
    end;
    if (regs.EAX and $FFFF) <> $004F then begin
        syslog.logln('VESA', 'setMode: VBE 4F00h not supported.');
        tracer.pop_trace;
        exit;
    end;

    { Read mode list far pointer from VBE info block (offset 0x0E = offset, 0x10 = segment) }
    mode_list_off := PUInt16(bufBase + VBE_INFO_ADDR + $0E)^;
    mode_list_seg := PUInt16(bufBase + VBE_INFO_ADDR + $10)^;
    mode_list_linear := uint32(mode_list_seg) * 16 + mode_list_off;

    { Step 2: Enumerate modes to find a match }
    mode := PUInt16(bufBase + mode_list_linear)^;
    while mode <> $FFFF do begin
        { INT 10h, AX=4F01h: Get VBE Mode Information }
        memset(bufBase + VBE_MODE_INFO_ADDR, 0, 256);
        memset(uint32(@regs), 0, sizeof(TV86Regs));
        regs.EAX := $4F01;
        regs.ECX := mode;
        regs.ES  := 0;
        regs.EDI := VBE_MODE_INFO_ADDR;

        if v86.v86_int($10, regs) then begin
            if (regs.EAX and $FFFF) = $004F then begin
                mode_attr   := PUInt16(bufBase + VBE_MODE_INFO_ADDR + $00)^;
                mode_width  := PUInt16(bufBase + VBE_MODE_INFO_ADDR + $12)^;
                mode_height := PUInt16(bufBase + VBE_MODE_INFO_ADDR + $14)^;
                mode_bpp    := PuByte(bufBase + VBE_MODE_INFO_ADDR + $19)^;
                mode_fb     := PUInt32(bufBase + VBE_MODE_INFO_ADDR + $28)^;
                mode_pitch  := PUInt16(bufBase + VBE_MODE_INFO_ADDR + $10)^;

                { Check: mode supported (bit 0) and has linear framebuffer (bit 7) }
                if ((mode_attr and $01) <> 0) and ((mode_attr and $80) <> 0) then begin
                    if (mode_width = width) and (mode_height = height) and (mode_bpp = bpp) then begin
                        found_mode  := mode;
                        found_fb    := mode_fb;
                        found_pitch := mode_pitch;
                    end;
                end;
            end;
        end;

        mode_list_linear := mode_list_linear + 2;
        mode := PUInt16(bufBase + mode_list_linear)^;
    end;

    if found_mode = $FFFF then begin
        syslog.logln('VESA', 'setMode: No matching VBE mode found.');
        tracer.pop_trace;
        exit;
    end;

    syslog.log('VESA', 'setMode: Found VBE mode $');
    syslog.writehex(found_mode);
    syslog.writestring(' fb=$');
    syslog.writehexln(found_fb);

    { Step 3: Set the mode with linear framebuffer flag }
    memset(uint32(@regs), 0, sizeof(TV86Regs));
    regs.EAX := $4F02;
    regs.EBX := found_mode or $4000; { Bit 14: use linear framebuffer }

    if not v86.v86_int($10, regs) then begin
        syslog.logln('VESA', 'setMode: VBE 4F02h failed (v86 error).');
        tracer.pop_trace;
        exit;
    end;
    if (regs.EAX and $FFFF) <> $004F then begin
        syslog.logln('VESA', 'setMode: VBE 4F02h set mode failed.');
        tracer.pop_trace;
        exit;
    end;

    { Step 4: Update multiboot info so vesa.enable reads the new values }
    multiboot.multibootinfo^.framebuffer_addr   := found_fb;
    multiboot.multibootinfo^.framebuffer_width  := width;
    multiboot.multibootinfo^.framebuffer_height := height;
    multiboot.multibootinfo^.framebuffer_bpp    := bpp;
    multiboot.multibootinfo^.framebuffer_pitch  := found_pitch;

    { Step 5: Map pages for the new framebuffer address }
    allocateVESAFrameBuffer(found_fb, width, height, bpp);

    syslog.logln('VESA', 'setMode: Mode set successfully.');
    setMode := true;
    tracer.pop_trace;
end;

end.