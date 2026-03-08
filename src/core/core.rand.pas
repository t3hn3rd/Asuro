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
	Include->Rand - Utilities for creating pseudo-random numbers.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit core.rand;

interface

function rand32 : uint32;
function rand16 : uint16;
function rand8  : uint8;
procedure srand(seed : uint32);

implementation

var
    next : uint32 = 1;

function rand : uint32;
begin
    next:= next * 1103515245 + 12345;
    rand:= (next div 65536) mod 32768;    
end;

function rand32 : uint32;
begin
    rand32:= (rand SHL 16) OR rand;
end;

function rand16 : uint16;
begin
    rand16:= rand32 AND $FFFF;
end;

function rand8 : uint8;
begin
    rand8:= rand32 AND $FF;
end;

procedure srand(seed : uint32);
begin
    next:= next + seed;
end;

end.