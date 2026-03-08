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
	Include->BIOS_Data_Area - Data Structures Controlled by the BIOS.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit arch.x86.bda;

interface

type
     TBDA = bitpacked record
          COM1            : uint16;
          COM2            : uint16;
          COM3            : uint16;
          COM4            : uint16;
          LPT1            : uint16;
          LPT2            : uint16;
          LPT3            : uint16;
          EBDA            : uint16;
          Hardware_Flags  : uint16;
          Keyboard_Flags  : uint16;
          Keyboard_Buffer : ARRAY[0..31] OF uint8;
          Display_Mode    : uint8;
          BaseIO          : uint16;
          Ticks           : uint16;
          HDD_Count       : uint8;
          Keyboard_Start  : uint16;
          Keyboard_End    : uint16;
          Keyboard_State  : uint8;
     end;
     PBDA = ^TBDA;

     TMCFG = bitpacked record
        Signature        : Array[0..3] of Char;
        Table_Length     : uint32;
        Revision         : Byte;
        Checksum         : Byte;
        OEM_ID           : Array[0..5] of Byte;
        OEM_Table_ID     : uint64;
        OEM_Revision     : uint32;
        Creator_ID       : uint32;
        Creator_Revision : uint32;
        Reserved         : uint64;
     end;
     PMCFG = ^TMCFG;

     TCounters = record
        c16 : uint16;
        c32 : uint32;
        c64 : uint64;
     end;

const
     BDA : PBDA = PBDA($C0000400);

var
    Counters : TCounters;

procedure tick_update(data : void);

implementation

uses
    arch.x86.memory.virtual;

procedure tick_update(data : void);
begin
    //BDA^.Ticks:= BDA^.Ticks + 1;
    inc(BDA^.Ticks);
    inc(Counters.c16);
    inc(Counters.c32);
    inc(Counters.c64);
end;

end.
