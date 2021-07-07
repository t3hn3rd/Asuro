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
	Driver->Video->Videotypes - Provides types relating to the video framework & driver interface.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit videotypes;

interface

uses
    color;

type
    //Arbitrary pointer to a video buffer in memory
    VideoBuffer = uint32;

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

    //(Abstract) Draw a pixel to screenspace
    FDrawPixel = procedure(Buffer : PVideoBuffer; X : uint32; Y : uint32; Pixel : TRGB32);
    //(Abstract) Flush backbuffer to MMIO Buffer
    FFlush     = procedure(FrontBuffer : PVideoBuffer; BackBuffer : PVideoBuffer);

    //Routines for drawing to the screen
    TDrawRoutines = record
        DrawPixel : FDrawPixel;
        Flush     : FFlush;
    end;
    //Pointer to drawing routines
    PDrawRoutines = ^TDrawRoutines;

    //Struct representing the whole video driver.
    TVideoInterface = record
        //Default buffer to be used when rendering, front buffer for no double buffering, back buffer otherwise.
        DefaultBuffer   : PVideoBuffer;
        //Memory Mapped IO Buffer for raw rasterization.
        FrontBuffer     : TVideoBuffer;
        //Back buffer used for double buffering, this is flushed to FrontBuffer with flush();
        BackBuffer      : TVideoBuffer;
        //Drawing Routines
        DrawRoutines    : TDrawRoutines;
    end;
    //Pointer to a video interface struct.
    PVideoInterface = ^TVideoInterface;

    //(Abstract) Enable method for a driver, called from video to enable driver.
    FEnableDriver = function(VideoInterface : PVideoInterface) : boolean;
    //(Abstract) Register driver, called from a driver to register with the video interface.
    FRegisterDriver = function(DriverIdentifier : pchar; EnableCallback : FEnableDriver) : boolean;
    //(Abstract) Init driver, called from _somewhere_ to start the driver and register it with the video interface.
    FInitDriver = procedure(Register : FRegisterDriver);

implementation

end.