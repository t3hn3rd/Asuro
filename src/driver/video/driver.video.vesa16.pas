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
	Driver->Video->VESA16 - Implementation of VESA 16bpp draw routines for the VESA Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.video.vesa16;

interface

uses
    driver.video.types, driver.video.vesa, debug.tracer, core.gfx.color;

//Init the draw routines by providing what we support through the DrawRoutines struct.
procedure init(DrawRoutines : PDrawRoutines);

implementation

procedure DrawPixel(Buffer : PVideoBuffer; X : uint32; Y : uint32; Pixel : TRGB32);
begin

end;

procedure init(DrawRoutines : PDrawRoutines);
begin
    debug.tracer.push_trace('vesa16.init.enter');   
    debug.tracer.push_trace('vesa16.init.exit');
end;

end.