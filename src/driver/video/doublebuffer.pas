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
	Driver->Video->Doublebuffer - Implements a very basic double buffer, tested with VESA drivers.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit doublebuffer;

interface

uses
    lmemorymanager, tracer, videotypes, serial, util;

//Init the driver, and register with the video interface in a state ready for execution.
procedure init(Register : FRegisterDriver);

implementation

function allocateBackBuffer(Width : uint32; Height : uint32; BitsPerPixel : uint8) : uint64;
begin
    tracer.push_trace('doublebuffer.allocateBackBuffer.enter');
    //This doesn't currently work... Needs a rework of lmemorymanager
    allocateBackBuffer:= uint64(klalloc((Width * Height) * BitsPerPixel));
    tracer.push_trace('doublebuffer.allocateBackBuffer.exit');
end;

procedure initBackBuffer(VInterface : PVideoInterface; Width : uint32; Height : uint32; BitsPerPixel : uint8);
begin
    tracer.push_trace('doublebuffer.initBackBuffer.enter');
    if not(VInterface^.BackBuffer.Initialized) then begin
        VInterface^.BackBuffer.Location:= allocateBackBuffer(Width, Height, BitsPerPixel);
        if (VInterface^.BackBuffer.Location <> 0) then begin
            VInterface^.BackBuffer.Width:= Width;
            VInterface^.BackBuffer.Height:= Height;
            VInterface^.BackBuffer.BitsPerPixel:= BitsPerPixel;
            VInterface^.BackBuffer.Initialized:= True;
        end;
    end;
    tracer.push_trace('doublebuffer.initBackBuffer.exit');
end;

procedure Flush(FrontBuffer : PVideoBuffer; BackBuffer : PVideoBuffer);
var
    Back,Front : uint32;
    Count64 : uint32;

begin
    //tracer.push_trace('doublebuffer.Flush.enter');
    if not(BackBuffer^.Initialized) then exit;
    if ((FrontBuffer^.Width > BackBuffer^.Width) or (FrontBuffer^.Height > BackBuffer^.Height)) then exit;
    Back:= BackBuffer^.Location;
    Front:= FrontBuffer^.Location;
    { Number of 64-byte blocks: total_bytes / 64 = (W * H * BPP/8) / 64 }
    Count64:= ( BackBuffer^.Width * BackBuffer^.Height * BackBuffer^.BitsPerPixel) div 512;
    if Count64 = 0 then exit;
    { Bulk SSE copy: 4 x MOVAPS (64 bytes) per iteration.
      4x fewer loop iterations than the old per-16-byte function-call loop. }
    asm
        PUSH ESI
        PUSH EDI
        MOV ESI, Back
        MOV EDI, Front
        MOV ECX, Count64
    @sseloop:
        MOVAPS XMM0, [ESI]
        MOVAPS XMM1, [ESI + 16]
        MOVAPS XMM2, [ESI + 32]
        MOVAPS XMM3, [ESI + 48]
        MOVAPS [EDI], XMM0
        MOVAPS [EDI + 16], XMM1
        MOVAPS [EDI + 32], XMM2
        MOVAPS [EDI + 48], XMM3
        ADD ESI, 64
        ADD EDI, 64
        DEC ECX
        JNZ @sseloop
        POP EDI
        POP ESI
    end;
    //tracer.push_trace('doublebuffer.Flush.exit');
end;

function enable(VideoInterface : PVideoInterface) : boolean;
begin
    tracer.push_trace('doublebuffer.enable.enter');
    enable:= false;
    initBackBuffer(VideoInterface, VideoInterface^.FrontBuffer.Width, VideoInterface^.FrontBuffer.Height, VideoInterface^.FrontBuffer.BitsPerPixel);
    if VideoInterface^.BackBuffer.Initialized then begin
        VideoInterface^.DefaultBuffer:= @VideoInterface^.BackBuffer;
        VideoInterface^.DrawRoutines.Flush:= @Flush;
        enable:= true;
    end;
    tracer.push_trace('doublebuffer.enable.exit');
end;

procedure init(Register : FRegisterDriver);
begin
    tracer.push_trace('doublebuffer.init.enter');
    Register('BASIC_DOUBLE_BUFFER', @enable);
    tracer.push_trace('doublebuffer.init.exit');
end;

end.