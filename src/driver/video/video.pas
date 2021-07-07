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
	Driver->Video->Video - Provides an abstract rasterization/drawing interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit video;

interface

uses
    lmemorymanager, tracer, color, videotypes, hashmap;

procedure init();
procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);
procedure Flush();
function register(DriverIdentifier : pchar; EnableCallback : FEnableDriver) : boolean;
function enable(DriverIdentifier : pchar) : boolean;
function frontBufferWidth : uint32;
function frontBufferHeight : uint32;
function frontBufferBpp : uint8;
function backBufferWidth : uint32;
function backBufferHeight : uint32;
function backBufferBpp : uint8;

implementation

Procedure dummyFDrawPixel(Buffer : PVideoBuffer; X : uint32; Y : uint32; Pixel : TRGB32);
begin
    tracer.push_trace('video.dummyFDrawPixel.enter');
    //Do nothing
end;

Procedure dummyFFlush(FrontBuffer : PVideoBuffer; BackBuffer : PVideoBuffer);
begin
    tracer.push_trace('video.dummyFFlush.enter');
    //Do nothing
end;

var
    VideoInterface : TVideoInterface;
    DriverMap      : PHashMap;

procedure init();
var
    RGB : TRGB32;
    x,y : uint32;

begin
    tracer.push_trace('video.init.enter');
    VideoInterface.FrontBuffer.Initialized:= false;
    VideoInterface.BackBuffer.Initialized:= false;
    VideoInterface.DefaultBuffer:= @VideoInterface.FrontBuffer;
    VideoInterface.DrawRoutines.DrawPixel:= @dummyFDrawPixel;
    VideoInterface.DrawRoutines.Flush:= @dummyFFlush;
    DriverMap:= hashmap.new;
    tracer.push_trace('video.init.exit');
end;

function register(DriverIdentifier : pchar; EnableCallback : FEnableDriver) : boolean;
var
    Value : Void;

begin
    tracer.push_trace('video.register.enter');
    register:= false;
    Value:= Hashmap.get(DriverMap, DriverIdentifier);
    if (Value = nil) then begin
        Hashmap.add(DriverMap, DriverIdentifier, void(EnableCallback));
        register:= true;
    end;
    tracer.push_trace('video.register.exit');
end;

function enable(DriverIdentifier : pchar) : boolean;
var
    Value : Void;

begin
    tracer.push_trace('video.enable.enter');
    enable:= false;
    Value:= Hashmap.get(DriverMap, DriverIdentifier);
    if (Value <> nil) then begin
        enable:= FEnableDriver(Value)(@VideoInterface);
    end;
    tracer.push_trace('video.enable.exit');
end;

procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);
begin
    tracer.push_trace('video.DrawPixel.enter');
    VideoInterface.DrawRoutines.DrawPixel(VideoInterface.DefaultBuffer, X, Y, Pixel);
    tracer.push_trace('video.DrawPixel.exit');
end;

procedure Flush();
begin
    tracer.push_trace('video.Flush.enter');
    VideoInterface.DrawRoutines.Flush(@VideoInterface.FrontBuffer, @VideoInterface.BackBuffer);
    tracer.push_trace('video.Flush.exit');
end;

function frontBufferWidth : uint32;
begin
    frontBufferWidth:= VideoInterface.FrontBuffer.Width;
end;

function frontBufferHeight : uint32;
begin
    frontBufferHeight:= VideoInterface.FrontBuffer.Height;
end;

function frontBufferBpp : uint8;
begin
    frontBufferBpp:= VideoInterface.FrontBuffer.BitsPerPixel;
end;

function backBufferWidth : uint32;
begin
    backBufferWidth:= VideoInterface.BackBuffer.Width;
end;

function backBufferHeight : uint32;
begin
    backBufferHeight:= VideoInterface.BackBuffer.Height;
end;

function backBufferBpp : uint8;
begin
    backBufferBpp:= VideoInterface.BackBuffer.BitsPerPixel;
end;

end.