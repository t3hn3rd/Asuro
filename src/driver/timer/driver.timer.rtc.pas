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
    boot.mgr,
    arch.x86.isr.mgr, core.util, arch.x86.util, arch.x86.isr.tmr0;

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
    io_wait();
    bin:= inb($71);
    is_update_in_progress:= (bin AND ($1 SHL 7)) <> 0;
end;

procedure update();
begin
    //outb($70, $0C);	// select register C
    //io_wait();
    //inb($71);
    //console.writestringln('driver.timer.rtc Update');
    //while not is_update_in_progress do begin 
    //end;
    //while is_update_in_progress do begin 
    //end;
    outb($70, $00);
    io_wait();
    DateTime.Seconds:= BCDToUint8(inb($71));
    io_wait();
    outb($70, $02);
    io_wait();
    DateTime.Minutes:= BCDToUint8(inb($71));
    io_wait();
    outb($70, $04);
    io_wait();
    DateTime.Hours:= BCDToUint8(inb($71));
    io_wait();
    outb($70, $06);
    io_wait();
    DateTime.Weekday:= BCDToUint8(inb($71));
    io_wait();
    outb($70, $07);
    io_wait();
    DateTime.Day:= BCDToUint8(inb($71));
    io_wait();
    outb($70, $08);
    io_wait();
    DateTime.Month:= BCDToUint8(inb($71));
    io_wait();
    outb($70, $09);
    io_wait();
    DateTime.Year:= BCDToUint8(inb($71));
    io_wait();
    outb($70, $32);
    io_wait();
    DateTime.Century:= BCDToUint8(inb($71));
    io_wait();
end;

function getDateTime : TDateTime;
begin
    update();
    getDateTime:= DateTime;
end;

procedure init;
var
    prev : uint8;

begin
    CLI;
    //setup driver.timer.rtc
    outb($70, $8A);
    io_wait();
    outb($71, $20);
    io_wait();

    //enable ints
    outb($70, $8B);
    io_wait();
    prev:= inb($71);
    io_wait();
    outb($70, $8B);
    io_wait();
    outb($71, prev OR $40);
    STI;
    outb($70, $00);
    inb($71);
    
    //arch.x86.isr.mgr.registerISR(32 + 8, @update);
    //arch.x86.isr.tmr0.hook(uint32(@update));
end;

initialization
    boot.mgr.registerBoot('driver.timer.rtc', @init, 'Real Time Clock Driver', 'arch.x86.fault');

end.