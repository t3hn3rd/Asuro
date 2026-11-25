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
unit driver.video.vesa;

interface

uses
    driver.video.types,
    debug.tracer,
    arch.x86.multiboot,
    memory.heap,
    arch.x86.v86,
    core.util,
    arch.x86.util,
    io.syslog,
    driver.video.gpu;

const
    { VBE buffer addresses in low physical memory }
    VBE_INFO_ADDR       = $1000;  { 512 bytes for VBE controller info }
    VBE_MODE_INFO_ADDR  = $1200;  { 256 bytes for VBE mode info }

//Init the driver, and register with the driver.video interface in a state ready for execution.
procedure init(Register : FRegisterDriver);

//Set a new VBE driver.video mode by resolution and bpp. Returns true on success.
function setMode(width, height : uint32; bpp : uint8) : boolean;

implementation

uses
    driver.video.vesa8,
    driver.video.vesa16,
    driver.video.vesa24,
    driver.video.vesa32;

type
    PVBEMode = ^TVBEMode;
    TVBEMode = record
        Next : PVBEMode;
        Number : uint16;
        Info : TGPUModeInfo;
    end;

var
    modes : PVBEMode;
    modesScanned : Boolean;

procedure EnumerateModes(visit : TGPUVisitMode); forward;

{ GPU framework: VBE setMode callback.
  Wraps the existing driver.video.vesa.setMode and fills TGPUModeInfo on success. }
function vbeSetModeGPU(width, height : uint32; bpp : uint8;
                       var info : TGPUModeInfo) : boolean;
begin
    push_trace('driver.video.vesa.vbeSetModeGPU');
    vbeSetModeGPU := false;
    if setMode(width, height, bpp) then begin
        info.Width       := width;
        info.Height      := height;
        info.BPP         := bpp;
        info.Framebuffer := arch.x86.multiboot.multibootinfo^.framebuffer_addr;
        info.Pitch       := arch.x86.multiboot.multibootinfo^.framebuffer_pitch;
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
    debug.tracer.push_trace('driver.video.vesa.allocateFrameBuffer.enter');
    FrameBufferSize := (Width * Height * BitsPerPixel) div 8;
    LowerAddress:= ((Address) SHR 22)-1;
    UpperAddress:= ((Address + FrameBufferSize) SHR 22)+1;
    For Block:=LowerAddress to UpperAddress do begin
        kpalloc(Block SHL 22);
    end;
    debug.tracer.push_trace('driver.video.vesa.allocateFrameBuffer.exit');
end;

procedure initVESAFrameBuffer(VideoBuffer : PVideoBuffer; Location : uint64; Width : uint32; Height : uint32; BitsPerPixel : uint8; Pitch : uint32);
begin
    debug.tracer.push_trace('driver.video.vesa.initVESAFrameBuffer.enter');
    if not(VideoBuffer^.Initialized) then begin
        VideoBuffer^.Location:= Location;
        VideoBuffer^.BitsPerPixel:= BitsPerPixel;
        VideoBuffer^.Width:= Width;
        VideoBuffer^.Height:= Height;
        allocateVESAFrameBuffer(VideoBuffer^.Location, VideoBuffer^.Width, VideoBuffer^.Height, BitsPerPixel);
        if VideoBuffer^.Location <> 0 then
            VideoBuffer^.Initialized:= True;
    end;
    debug.tracer.push_trace('driver.video.vesa.initVESAFrameBuffer.exit');
end;

function enable(VideoInterface : PVideoInterface) : boolean;
begin
    debug.tracer.push_trace('driver.video.vesa.enable.enter');
    initVESAFrameBuffer(@VideoInterface^.FrontBuffer, arch.x86.multiboot.multibootinfo^.framebuffer_addr, arch.x86.multiboot.multibootinfo^.framebuffer_width, arch.x86.multiboot.multibootinfo^.framebuffer_height, arch.x86.multiboot.multibootinfo^.framebuffer_bpp, arch.x86.multiboot.multibootinfo^.framebuffer_pitch);
    case (VideoInterface^.FrontBuffer.BitsPerPixel) of
        08:driver.video.vesa8.init(@VideoInterface^.DrawRoutines);
        16:driver.video.vesa16.init(@VideoInterface^.DrawRoutines);
        24:driver.video.vesa24.init(@VideoInterface^.DrawRoutines);
        32:driver.video.vesa32.init(@VideoInterface^.DrawRoutines);
    end;
    enable:= VideoInterface^.FrontBuffer.Initialized;  
    debug.tracer.push_trace('driver.video.vesa.enable.exit');
end;

procedure init(Register : FRegisterDriver);
begin
    debug.tracer.push_trace('driver.video.vesa.init.enter');
    if Register <> nil then
        Register('VESA', @enable);
    { Register VBE as a GPU driver (priority 50 = fallback behind BGA) }
    driver.video.gpu.registerDriver('VBE', 50, @vbeSetModeGPU, @EnumerateModes);
    { VBE is available if the bootloader already set up a framebuffer }
    if arch.x86.multiboot.multibootinfo^.framebuffer_addr <> 0 then
        driver.video.gpu.markAvailable('VBE');
    debug.tracer.push_trace('driver.video.vesa.init.exit');
end;

procedure ScanModes;
const
    MAX_MODE_ENTRIES = 1024;
var
    regs : TV86Regs;
    bufBase, listAddress, i : uint32;
    number, attributes : uint16;
    mode : PVBEMode;
    info : TGPUModeInfo;
begin
    if modesScanned then exit;
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

    if not arch.x86.v86.v86_int($10, regs) then begin
        io.syslog.logln('VESA', 'ScanModes: VBE 4F00h failed (arch.x86.v86 error).');
        exit;
    end;
    if (regs.EAX and $FFFF) <> $004F then begin
        io.syslog.logln('VESA', 'ScanModes: VBE 4F00h not supported.');
        exit;
    end;

    { Read mode list far pointer from VBE info block (offset 0x0E = offset, 0x10 = segment) }
    listAddress := uint32(PUInt16(bufBase + VBE_INFO_ADDR + $10)^) * 16
                   + PUInt16(bufBase + VBE_INFO_ADDR + $0E)^;
    if (listAddress = 0) or (listAddress >= $100000) then exit;

    for i := 0 to MAX_MODE_ENTRIES - 1 do begin
        if listAddress > $FFFFE then break;
        number := PUInt16(bufBase + listAddress)^;
        if number = $FFFF then break;
        Inc(listAddress, 2);

        memset(bufBase + VBE_MODE_INFO_ADDR, 0, 256);
        memset(uint32(@regs), 0, sizeof(TV86Regs));
        regs.EAX := $4F01;
        regs.ECX := number;
        regs.ES := 0;
        regs.EDI := VBE_MODE_INFO_ADDR;
        if not arch.x86.v86.v86_int($10, regs) then continue;
        if (regs.EAX and $FFFF) <> $004F then continue;

        attributes := PUInt16(bufBase + VBE_MODE_INFO_ADDR + $00)^;
        if (attributes and $91) <> $91 then continue;
        info.Width := PUInt16(bufBase + VBE_MODE_INFO_ADDR + $12)^;
        info.Height := PUInt16(bufBase + VBE_MODE_INFO_ADDR + $14)^;
        info.BPP := PuByte(bufBase + VBE_MODE_INFO_ADDR + $19)^;
        info.Framebuffer := PUInt32(bufBase + VBE_MODE_INFO_ADDR + $28)^;
        info.Pitch := PUInt16(bufBase + VBE_MODE_INFO_ADDR + $10)^;
        if (info.Width = 0) or (info.Height = 0) or (info.BPP = 0)
            or (info.Framebuffer = 0) or (info.Pitch = 0) then continue;

        mode := PVBEMode(kalloc(SizeOf(TVBEMode)));
        mode^.Number := number;
        mode^.Info := info;
        mode^.Next := modes;
        modes := mode;
    end;
    modesScanned := true;
end;

procedure EnumerateModes(visit : TGPUVisitMode);
var
    mode : PVBEMode;
begin
    ScanModes;
    mode := modes;
    while mode <> nil do begin
        visit(mode^.Info.Width, mode^.Info.Height, mode^.Info.BPP);
        mode := mode^.Next;
    end;
end;

function setMode(width, height : uint32; bpp : uint8) : boolean;
var
    regs : TV86Regs;
    mode : PVBEMode;
    found_mode : uint16;
    found_fb, found_pitch : uint32;
begin
    debug.tracer.push_trace('driver.video.vesa.setMode.enter');
    setMode := false;
    ScanModes;
    mode := modes;
    while mode <> nil do begin
        if (mode^.Info.Width = width) and (mode^.Info.Height = height)
            and (mode^.Info.BPP = bpp) then break;
        mode := mode^.Next;
    end;
    if mode = nil then begin
        io.syslog.logln('VESA', 'setMode: No matching VBE mode found.');
        debug.tracer.pop_trace;
        exit;
    end;
    found_mode := mode^.Number;
    found_fb := mode^.Info.Framebuffer;
    found_pitch := mode^.Info.Pitch;

    { Step 3: Set the mode with linear framebuffer flag }
    memset(uint32(@regs), 0, sizeof(TV86Regs));
    regs.EAX := $4F02;
    regs.EBX := found_mode or $4000; { Bit 14: use linear framebuffer }

    if not arch.x86.v86.v86_int($10, regs) then begin
        io.syslog.logln('VESA', 'setMode: VBE 4F02h failed (arch.x86.v86 error).');
        debug.tracer.pop_trace;
        exit;
    end;
    if (regs.EAX and $FFFF) <> $004F then begin
        io.syslog.logln('VESA', 'setMode: VBE 4F02h set mode failed.');
        debug.tracer.pop_trace;
        exit;
    end;

    { Step 4: Update arch.x86.multiboot info so driver.video.vesa.enable reads the new values }
    arch.x86.multiboot.multibootinfo^.framebuffer_addr   := found_fb;
    arch.x86.multiboot.multibootinfo^.framebuffer_width  := width;
    arch.x86.multiboot.multibootinfo^.framebuffer_height := height;
    arch.x86.multiboot.multibootinfo^.framebuffer_bpp    := bpp;
    arch.x86.multiboot.multibootinfo^.framebuffer_pitch  := found_pitch;

    { Step 5: Map pages for the new framebuffer address }
    allocateVESAFrameBuffer(found_fb, width, height, bpp);

    io.syslog.logln('VESA', 'setMode: Mode set successfully.');
    setMode := true;
    debug.tracer.pop_trace;
end;

end.