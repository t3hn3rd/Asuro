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
	Driver->Video->Video - Provides abstract rasterization/drawing functions.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit video;

interface

uses
    lmemorymanager, tracer, color, rand;

procedure init();
procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);
procedure Flush();

type
    //Arbitrary pointer to a video buffer in memory
    VideoBuffer = uint64;

    //Struct representing a Memory Mapped Video Buffer
    TVideoBuffer = record
        //Has this buffer been initialized? Has it been paged/created in memory?
        Initialized     : Boolean;
        //Location of the video buffer in memory as a QWORD.
        Location        : VideoBuffer;
        //How many bits per pixel?
        BitsPerPixel    : uint8;
        //Width of the buffer.
        Width           : uint32;
        //Height of the buffer.
        Height          : uint32;
    end;
    //Pointer to a video buffer
    PVideoBuffer = ^TVideoBuffer;

    //Routines for drawing to the screen
    TDrawRoutines = record
        DrawPixel : FDrawPixel;
        Flush     : FFlush;
    end;
    //Pointer to drawing routines
    PDrawRoutines = ^TDrawRoutines;

    //Struct representing the whole video driver.
    TVideoDriver = record
        //Default buffer to be used when rendering, front buffer for no double buffering, back buffer otherwise.
        DefaultBuffer   : PVideoBuffer;
        //Memory Mapped IO Buffer for raw rasterization.
        MMIOBuffer      : TVideoBuffer;
        //Back buffer used for double buffering, this is flushed to MMIOBuffer with flush();
        BackBuffer      : TVideoBuffer;
        //Drawing Routines
        DrawRoutines    : TDrawRoutines;
    end;
    //Pointer to a video driver struct.
    PVideoDriver = ^TVideoDriver;

    //Draw a pixel to screenspace
    FDrawPixel = procedure(Buffer : PVideoBuffer; X : uint32; Y : uint32; Pixel : TRGB32);
    //Flush backbuffer to MMIO Buffer
    FFlush     = procedure(FrontBuffer : PVideoBuffer; BackBuffer : PVideoBuffer);

implementation

var
    VideoDriver : TVideoDriver;

function allocateBackBuffer(Width : uint32; Height : uint32; BitsPerPixel : uint8) : uint64;
begin
    Outputln('VIDEO','Start Kalloc Backbuffer');
    //This doesn't currently work... Needs a rework of lmemorymanager
    allocateBackBuffer:= uint64(klalloc((Width * Height) * BitsPerPixel));
    Outputln('VIDEO','End Kalloc Backbuffer');
end;

procedure initBackBuffer(DriverInfo : PVideoDriver; Width : uint32; Height : uint32; BitsPerPixel : uint8);
begin
    if not(DriverInfo^.BackBuffer.Initialized) then begin
        DriverInfo^.BackBuffer.Width:= Width;
        DriverInfo^.BackBuffer.Height:= Height;
        DriverInfo^.BackBuffer.BitsPerPixel:= BitsPerPixel;
        DriverInfo^.BackBuffer.Location:= allocateBackBuffer(DriverInfo^.BackBuffer.Width, DriverInfo^.BackBuffer.Height, DriverInfo^.BackBuffer.BitsPerPixel);
        DriverInfo^.DefaultBuffer:= DriverInfo^.BackBuffer.Location;
        DriverInfo^.BackBuffer.Initialized:= True;
    end;
end;

procedure init();
var
    RGB : TRGB32;
    x,y : uint32;

begin
    tracer.push_trace('video.init.enter');
    
    console.Outputln('VIDEO', 'Init VideoDriver MMIOBuffer');
       
    console.Outputln('VIDEO', 'Init VideoDriver Backbuffer');
    //initBackBuffer(@VideoDriver, multiboot.multibootinfo^.framebuffer_width, multiboot.multibootinfo^.framebuffer_height, multiboot.multibootinfo^.framebuffer_bpp);

    tracer.push_trace('video.init.exit');
end;

procedure DrawPixel(X : uint32; Y : uint32; Pixel : TRGB32);
begin

end;

procedure Flush();
begin

end;

end.