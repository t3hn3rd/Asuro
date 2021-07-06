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
	Driver->Video->VESA - Provides an interface the VESA drivers.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit VESA;

interface

uses
    Video, multiboot;

procedure init();


implementation

uses
    VESA8, VESA16, VESA24, VESA32;

procedure allocateVESAFrameBuffer(Address : uint32; Width : uint32; Height : uint32);
var
    LowerAddress, UpperAddress : uint32;
    Block : uint32;

begin
    tracer.push_trace('vesa.allocateFrameBuffer.enter');
    LowerAddress:= ((Address) SHR 22)-1;
    UpperAddress:= ((Address + (Width * Height)) SHR 22)+1;
    For Block:=LowerAddress to UpperAddress do begin
        kpalloc(Block SHL 22);
    end;
    tracer.push_trace('vesa.allocateFrameBuffer.enter');
end;

procedure initVESAFrameBuffer(VideoBuffer : PVideoBuffer; Location : uint64; Width : uint32; Height : uint32; BitsPerPixel : uint8);
begin
    if not(VideoBuffer^.MMIOBuffer.Initialized) then begin
        VideoBuffer^.MMIOBuffer.Location:= Location;
        VideoBuffer^.MMIOBuffer.BitsPerPixel:= BitsPerPixel;
        VideoBuffer^.MMIOBuffer.Width:= Width;
        VideoBuffer^.MMIOBuffer.Height:= Height;
        allocateVESAFrameBuffer(VideoBuffer^.MMIOBuffer.Location, VideoBuffer^.MMIOBuffer.Width, VideoBuffer^.MMIOBuffer.Height);
        VideoBuffer^.DefaultBuffer:= VideoBuffer^.MMIOBuffer.Location;
        VideoBuffer^.MMIOBuffer.Initialized:= True;
    end;
end;

procedure Flush(FrontBuffer : PVideoBuffer; BackBuffer : PVideoBuffer);
var
    x,y : uint32;
    Back,Front : PuInt64;

begin
    if not(BackBuffer^.Initialized) then exit;
    Back:= PUint64(BackBuffer^.Location);
    Front:= PuInt64(FrontBuffer^.Location);
    for x:=0 to (VideoDriver.MMIOBuffer.Width-1) div 2 do begin
        for y:=0 to (VideoDriver.MMIOBuffer.Height-1) div 2 do begin
            Front[(Y * VideoDriver.MMIOBuffer.Width)+X]:= Back[(Y * VideoDriver.MMIOBuffer.Width)+X];
        end;
    end;
end;

procedure init();
begin
    initVESAFrameBuffer(@VideoDriver, multiboot.multibootinfo^.framebuffer_addr, multiboot.multibootinfo^.framebuffer_width, multiboot.multibootinfo^.framebuffer_height, multiboot.multibootinfo^.framebuffer_bpp); 
    VESA8.init();
    VESA16.init();
    VESA24.init();
    VESA32.init();
end;

end.