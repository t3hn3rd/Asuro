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
	Driver->Timers->driver.timer.rtc - Real Time Clock Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.timer.rtc;

interface

uses
    core.util, arch.platform.cpu;

type
    TDateTime = record
        Seconds : uint8;
        Minutes : uint8;
        Hours   : uint8;
        Weekday : uint8;
        Day     : uint8;
        Month   : uint8;
        Year    : uint8;
        Century : uint8;
    end;

procedure init;
function getDateTime : TDateTime;
function weekdayToString(Weekday : uint8) : pchar;

implementation

var
    DateTime : TDateTime;

function weekdayToString(Weekday : uint8) : pchar;
begin
    case Weekday of
        1:weekdayToString:= 'Sunday';
        2:weekdayToString:= 'Monday';
        3:weekdayToString:= 'Tuesday';
        4:weekdayToString:= 'Wednesday';
        5:weekdayToString:= 'Thursday';
        6:weekdayToString:= 'Friday';
        7:weekdayToString:= 'Saturday';
        else weekdayToString:= 'Unknown';
    end;
end;

function is_update_in_progress : boolean;
var
    bin : uint8;

begin
    outb($70, $0A);
    arch.platform.cpu.outb($80, 0);
    bin:= inb($71);
    is_update_in_progress:= (bin AND ($1 SHL 7)) <> 0;
end;

procedure update();
begin
    //outb($70, $0C);	// select register C
    //arch.platform.cpu.outb($80, 0);
    //inb($71);
    //console.writestringln('driver.timer.rtc Update');
    //while not is_update_in_progress do begin 
    //end;
    //while is_update_in_progress do begin 
    //end;
    outb($70, $00);
    arch.platform.cpu.outb($80, 0);
    DateTime.Seconds:= BCDToUint8(inb($71));
    arch.platform.cpu.outb($80, 0);
    outb($70, $02);
    arch.platform.cpu.outb($80, 0);
    DateTime.Minutes:= BCDToUint8(inb($71));
    arch.platform.cpu.outb($80, 0);
    outb($70, $04);
    arch.platform.cpu.outb($80, 0);
    DateTime.Hours:= BCDToUint8(inb($71));
    arch.platform.cpu.outb($80, 0);
    outb($70, $06);
    arch.platform.cpu.outb($80, 0);
    DateTime.Weekday:= BCDToUint8(inb($71));
    arch.platform.cpu.outb($80, 0);
    outb($70, $07);
    arch.platform.cpu.outb($80, 0);
    DateTime.Day:= BCDToUint8(inb($71));
    arch.platform.cpu.outb($80, 0);
    outb($70, $08);
    arch.platform.cpu.outb($80, 0);
    DateTime.Month:= BCDToUint8(inb($71));
    arch.platform.cpu.outb($80, 0);
    outb($70, $09);
    arch.platform.cpu.outb($80, 0);
    DateTime.Year:= BCDToUint8(inb($71));
    arch.platform.cpu.outb($80, 0);
    outb($70, $32);
    arch.platform.cpu.outb($80, 0);
    DateTime.Century:= BCDToUint8(inb($71));
    arch.platform.cpu.outb($80, 0);
end;

function getDateTime : TDateTime;
begin
    update();
    getDateTime:= DateTime;
end;

procedure init;
begin
    update;
end;

end.
