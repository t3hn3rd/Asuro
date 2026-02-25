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
    lmemorymanager, tracer, color, videotypes, hashmap, util, texture;

procedure init();
procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);
procedure DrawLine(x1,y1,x2,y2 : uint32; thickness : uint32; Color : TRGB32);
procedure DrawRect(x1,y1,x2,y2 : uint32; line_thickness : uint32; Color : TRGB32);
procedure FillRect(x1,y1,x2,y2 : uint32; line_thickness : uint32; Line_Color : TRGB32; Fill_Color : TRGB32);
procedure Flush();

function register(DriverIdentifier : pchar; EnableCallback : FEnableDriver) : boolean;
function enable(DriverIdentifier : pchar) : boolean;

function frontBufferWidth : uint32;
function frontBufferHeight : uint32;
function frontBufferBpp : uint8;
function backBufferWidth : uint32;
function backBufferHeight : uint32;
function backBufferBpp : uint8;
function backBufferLocation : uint32;

Procedure basicFDrawTexture(Buffer : PVideoBuffer; X : uint32; Y : uint32; Texture : PTexture);

implementation

Procedure dummyFDrawPixel(Buffer : PVideoBuffer; X : uint32; Y : uint32; Pixel : TRGB32);
begin
    tracer.push_trace('video.dummyFDrawPixel.enter');
    //Do nothing, this is the most basic function that must be implemented by a driver.
end;

Procedure basicFFlush(FrontBuffer : PVideoBuffer; BackBuffer : PVideoBuffer);
var
    idx : uint32;
    Back,Front : puint32;
    BufferSize : uint32;

const
    COPY_WIDTH = 32;

begin
    //tracer.push_trace('video.basicFFlush.enter');
    If not(FrontBuffer^.Initialized and BackBuffer^.Initialized) then exit;
    if (BackBuffer^.Width > FrontBuffer^.Width) or (BackBuffer^.Height > FrontBuffer^.Height) then exit;
    Back:= puint32(BackBuffer^.Location);
    Front:= puint32(FrontBuffer^.Location);
    BufferSize:= ( (BackBuffer^.Width * BackBuffer^.Height * BackBuffer^.BitsPerPixel ) div COPY_WIDTH ) - 1;
    for idx:=0 to BufferSize do begin
        Front[idx]:= Back[idx];
    end;
end;

Procedure basicFDrawTexture(Buffer : PVideoBuffer; X : uint32; Y : uint32; Texture : PTexture);
var
    i, j : uint32;

begin
    //Draw texture to Buffer at x and y
    for i:=0 to Texture^.Height - 1 do begin
        for j:=0 to Texture^.Width - 1 do begin
            DrawPixel(X + j, Y + i, Texture^.Pixels[(i * Texture^.Width) + j]);
        end;
    end;
end;

procedure basicFDrawLine(Buffer : PVideoBuffer; x1,y1,x2,y2 : uint32; thickness : uint32; Color : TRGB32);
var
    X, Y, DX, DY, DX1, DY1, PX, PY, XE, YE, I : sint32;

begin
    tracer.push_trace('video.basicFDrawLine.enter');

    if(x1 = x2) then begin
        for Y:=Y1 to Y2 do begin
            DrawPixel(X1,Y,Color);
        end;
    end else if (y1 = y2) then begin
        for X:=X1 to X2 do begin
            DrawPixel(X,Y1,Color);
        end;
    end else begin
        DX:= X2 - X1;
        DY:= Y2 - Y1;

        DX1:= util.abs(DX);
        DY1:= util.abs(DY);

        PX:= 2 * DY1 - DX1;
        PY:= 2 * DX1 - DY1;

        if (DY1 <= DX1) then begin
            if (dx >= 0) then begin
                X:= X1; Y:= Y1; XE:= X2;
            end else begin
                X:= X2; Y:= Y2; XE:= X1;
            end;

            DrawPixel(X, Y, Color);

            I:=0;
            while (x < xe) do begin
                X:= X + 1;
                if (PX < 0) then begin
                    PX:= PX + 2 + DY1; 
                end else begin
                    if(((dx < 0) and (dy < 0)) OR ((dx > 0) and (dy > 0))) then begin
                        Y:= Y + 1;  
                    end else begin
                        Y:= Y - 1;
                    end;
                    PX:= PX + 2 * (DY1 - DX1);
                end;
                DrawPixel(X,Y,Color);
                I:= I + 1;
            end;
        end else begin
            if (DY >= 0) then begin
                X:= X1; Y:= Y1; YE:= Y2; 
            end else begin
                X:= X2; Y:= Y2; YE:= Y1;
            end;

            DrawPixel(X, Y, Color);

            I:=0;
            while (Y < YE) do begin
                Y:= Y + 1;
                if (PY <= 0) then begin
                    PY:= PY + 2 * DX1;
                end else begin
                    if (((dx < 0) and (dy < 0)) OR ((dx > 0) and (dy > 0))) then begin
                        X:= X + 1; 
                    end else begin
                        X:= X - 1;
                    end;
                    PY:= PY + 2 * (dx1 - dy1);
                end;
                DrawPixel(X,Y,Color);
                I:= I + 1;
            end;
        end;
    end;
end;

procedure basicFDrawRect(Buffer : PVideoBuffer; x1,y1,x2,y2 : uint32; line_thickness : uint32; Color : TRGB32);
begin
    tracer.push_trace('video.basicFDrawRect.enter');
    DrawLine(x1,y1,x2,y1,line_thickness,Color);
    DrawLine(x1,y2,x2,y2,line_thickness,Color);
    DrawLine(x1,y1,x1,y2,line_thickness,Color);
    DrawLine(x2,y1,x2,y2,line_thickness,Color);
end;

procedure basicFFillRect(Buffer : PVideoBuffer; x1,y1,x2,y2 : uint32; line_thickness : uint32; Line_Color : TRGB32; Fill_Color : TRGB32);
var
    Y : uint32;

begin
    tracer.push_trace('video.basicFFillRect.enter');   
    for Y:=y1 to y2 do begin
        DrawLine(x1,y,x2,y,line_thickness,Fill_Color);
    end;
    DrawRect(x1,y1,x2,y2,line_thickness,Line_Color);
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
    //Ensure the frontbuffer is empty & nil, ready for initialization by a driver.
    VideoInterface.FrontBuffer.Initialized:= false;
    VideoInterface.FrontBuffer.Width:= 0;
    VideoInterface.FrontBuffer.Height:= 0;
    VideoInterface.FrontBuffer.BitsPerPixel:= 0;
    VideoInterface.FrontBuffer.Location:= 0;

    //Ensure the backbuffer is empty & nil, ready for initialization by a driver.
    VideoInterface.BackBuffer.Initialized:= false;
    VideoInterface.BackBuffer.Width:= 0;
    VideoInterface.BackBuffer.Height:= 0;
    VideoInterface.BackBuffer.BitsPerPixel:= 0;
    VideoInterface.BackBuffer.Location:= 0;

    //Set the default buffer to be the FrontBuffer, assume no double buffering to begin with.
    VideoInterface.DefaultBuffer:= @VideoInterface.FrontBuffer;

    { Set the draw routines to point to dummy/empty routines.
      Calls will still succeed but do nothing until a driver has registered. }
    VideoInterface.DrawRoutines.DrawPixel:= @dummyFDrawPixel;
    VideoInterface.DrawRoutines.Flush:= @basicFFlush;
    VideoInterface.DrawRoutines.DrawLine:= @basicFDrawLine;
    VideoInterface.DrawRoutines.DrawRect:= @basicFDrawRect;
    VideoInterface.DrawRoutines.FillRect:= @basicFFillRect;

    //Initialize our 'DriverMap', a hashmap of loadable display drivers.
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
    //tracer.push_trace('video.DrawPixel.enter');
    VideoInterface.DrawRoutines.DrawPixel(VideoInterface.DefaultBuffer, X, Y, Pixel);
    //tracer.push_trace('video.DrawPixel.exit');
end;

procedure Flush();
begin
    //tracer.push_trace('video.Flush.enter');
    VideoInterface.DrawRoutines.Flush(@VideoInterface.FrontBuffer, @VideoInterface.BackBuffer);
    //tracer.push_trace('video.Flush.exit');
end;

procedure DrawLine(x1,y1,x2,y2 : uint32; thickness : uint32; Color : TRGB32);
begin
    VideoInterface.DrawRoutines.DrawLine(VideoInterface.DefaultBuffer,x1,y1,x2,y2,thickness,Color);
end;

procedure DrawRect(x1,y1,x2,y2 : uint32; line_thickness : uint32; Color : TRGB32);
begin
    VideoInterface.DrawRoutines.DrawRect(VideoInterface.DefaultBuffer,x1,y1,x2,y2,line_thickness,color);
end;

procedure FillRect(x1,y1,x2,y2 : uint32; line_thickness : uint32; Line_Color : TRGB32; Fill_Color : TRGB32);
begin
    VideoInterface.DrawRoutines.FillRect(VideoInterface.DefaultBuffer,x1,y1,x2,y2,line_thickness,Line_Color,Fill_Color);
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

function backBufferLocation : uint32;
begin
    backBufferLocation:= VideoInterface.BackBuffer.Location;
end;

end.