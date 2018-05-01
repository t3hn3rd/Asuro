unit RTC;

interface

uses
    console, isrmanager, util, TMR_0_ISR;

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
        0:weekdayToString:= 'Saturday';
        1:weekdayToString:= 'Sunday';
        2:weekdayToString:= 'Monday';
        3:weekdayToString:= 'Tuesday';
        4:weekdayToString:= 'Wednesday';
        5:weekdayToString:= 'Thursday';
        6:weekdayToString:= 'Friday';
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
    //console.writestringln('RTC Update');
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
    //setup RTC
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
    
    //isrmanager.registerISR(32 + 8, @update);
    //TMR_0_ISR.hook(uint32(@update));
end;

end.