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
    videotypes, tracer, multiboot, lmemorymanager;

//Init the driver, and register with the video interface in a state ready for execution.
procedure init(Register : FRegisterDriver);

implementation

uses
    VESA8, VESA16, VESA24, VESA32;

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
    tracer.push_trace('VESA.init.exit');
end;

end.