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
    lmemorymanager, tracer, videotypes;

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
    X,Y : uint32;
    Back,Front : PuInt64;

begin
    tracer.push_trace('doublebuffer.Flush.enter');
    if not(BackBuffer^.Initialized) then exit;
    if ((FrontBuffer^.Width > BackBuffer^.Width) or (FrontBuffer^.Height > BackBuffer^.Height)) then exit;
    Back:= PUint64(BackBuffer^.Location);
    Front:= PuInt64(FrontBuffer^.Location);
    for X:=0 to (BackBuffer^.Width-1) div 2 do begin
        for Y:=0 to (BackBuffer^.Height-1) div 2 do begin
            Front[(Y * BackBuffer^.Width) + X]:= Back[(Y * BackBuffer^.Width) + X];
        end;
    end;
    tracer.push_trace('doublebuffer.Flush.exit');
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