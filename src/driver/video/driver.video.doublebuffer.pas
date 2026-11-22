//  Copyright 2021 Kieron Morris
//  Copyright 2026 Aaron Hance
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
	Driver->Video->Doublebuffer - Implements a very basic double buffer, tested with VESA drivers.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.video.doublebuffer;

interface

uses
    memory.heap, debug.tracer, driver.video.types, driver.io.serial, core.util, arch.platform.cpu;

//Init the driver, and register with the driver.video interface in a state ready for execution.
procedure init(Register : FRegisterDriver);
procedure FlushRect(FrontBuffer, BackBuffer: PVideoBuffer; x, y, width, height: uint32);

implementation

function allocateBackBuffer(Width : uint32; Height : uint32; BitsPerPixel : uint8) : PtrUInt;
var
    bytes: uint64;
begin
    allocateBackBuffer := 0;
    if (Width = 0) or (Height = 0) or (BitsPerPixel = 0) or
       (BitsPerPixel mod 8 <> 0) then exit;
    bytes := uint64(Width) * (BitsPerPixel div 8);
    if bytes > High(uint32) then exit;
    bytes := bytes * Height;
    if bytes > High(SizeUInt) then exit;
    debug.tracer.push_trace('driver.video.doublebuffer.allocateBackBuffer.enter');
    allocateBackBuffer := PtrUInt(klalloc(SizeUInt(bytes)));
    debug.tracer.push_trace('driver.video.doublebuffer.allocateBackBuffer.exit');
end;

procedure initBackBuffer(VInterface : PVideoInterface; Width : uint32; Height : uint32; BitsPerPixel : uint8);
begin
    debug.tracer.push_trace('driver.video.doublebuffer.initBackBuffer.enter');
    if not(VInterface^.BackBuffer.Initialized) then begin
        VInterface^.BackBuffer.Location:= allocateBackBuffer(Width, Height, BitsPerPixel);
        if (VInterface^.BackBuffer.Location <> 0) then begin
            VInterface^.BackBuffer.Width:= Width;
            VInterface^.BackBuffer.Height:= Height;
            VInterface^.BackBuffer.Pitch := Width * (BitsPerPixel div 8);
            VInterface^.BackBuffer.BitsPerPixel:= BitsPerPixel;
            VInterface^.BackBuffer.Initialized:= True;
        end;
    end;
    debug.tracer.push_trace('driver.video.doublebuffer.initBackBuffer.exit');
end;

procedure FlushRect(FrontBuffer, BackBuffer: PVideoBuffer; x, y, width, height: uint32);
var
    row, bytes, pixelBytes: uint32;
    source, dest: PtrUInt;
begin
    if not (FrontBuffer^.Initialized and BackBuffer^.Initialized) then exit;
    if (BackBuffer^.Width > FrontBuffer^.Width) or
       (BackBuffer^.Height > FrontBuffer^.Height) or
       (BackBuffer^.BitsPerPixel <> FrontBuffer^.BitsPerPixel) then exit;
    if (width = 0) or (height = 0) or
       (x >= BackBuffer^.Width) or (y >= BackBuffer^.Height) then exit;
    if width > BackBuffer^.Width - x then width := BackBuffer^.Width - x;
    if height > BackBuffer^.Height - y then height := BackBuffer^.Height - y;
    pixelBytes := BackBuffer^.BitsPerPixel div 8;
    if (pixelBytes = 0) or (BackBuffer^.BitsPerPixel mod 8 <> 0) then exit;
    if (uint64(x + width) * pixelBytes > BackBuffer^.Pitch) or
       (uint64(x + width) * pixelBytes > FrontBuffer^.Pitch) then exit;
    bytes := width * pixelBytes;
    source := BackBuffer^.Location + SizeUInt(y) * BackBuffer^.Pitch + SizeUInt(x) * pixelBytes;
    dest := FrontBuffer^.Location + SizeUInt(y) * FrontBuffer^.Pitch + SizeUInt(x) * pixelBytes;
    for row := 0 to height - 1 do begin
        memcpy(source, dest, bytes);
        inc(source, BackBuffer^.Pitch);
        inc(dest, FrontBuffer^.Pitch);
    end;
end;

procedure Flush(FrontBuffer : PVideoBuffer; BackBuffer : PVideoBuffer);
begin
    FlushRect(FrontBuffer, BackBuffer, 0, 0, BackBuffer^.Width, BackBuffer^.Height);
end;

function enable(VideoInterface : PVideoInterface) : boolean;
begin
    debug.tracer.push_trace('driver.video.doublebuffer.enable.enter');
    enable:= false;
    initBackBuffer(VideoInterface, VideoInterface^.FrontBuffer.Width, VideoInterface^.FrontBuffer.Height, VideoInterface^.FrontBuffer.BitsPerPixel);
    if VideoInterface^.BackBuffer.Initialized then begin
        VideoInterface^.DefaultBuffer:= @VideoInterface^.BackBuffer;
        VideoInterface^.DrawRoutines.Flush:= @Flush;
        enable:= true;
    end;
    debug.tracer.push_trace('driver.video.doublebuffer.enable.exit');
end;

procedure init(Register : FRegisterDriver);
begin
    debug.tracer.push_trace('driver.video.doublebuffer.init.enter');
    Register('BASIC_DOUBLE_BUFFER', @enable);
    debug.tracer.push_trace('driver.video.doublebuffer.init.exit');
end;

end.
