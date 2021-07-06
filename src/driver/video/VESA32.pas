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
	Driver->Video->VESA32 - Implementation of VESA 32bpp draw routines.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit VESA32;

interface

uses
    Video, VESA;

procedure init();

implementation

procedure DrawPixel(Buffer : PVideoBuffer; X : uint32; Y : uint32; Pixel : TRGB32);
var
    Location : PuInt32;
    LocationIndex : Uint32;

begin
    Location:= Puint32(Buffer^.Location);
    LocationIndex:= (Y * Buffer^.Width) + X;
    Location[LocationIndex]:= uint32(Pixel);
end;

procedure init();
begin
    
end;

end.