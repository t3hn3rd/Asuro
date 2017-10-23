unit terminal;

interface

uses
    console,
    keyboard,
    util;

var
    buffer : array[0..1023] of byte;
    bIndex : uint32 = 0;

procedure run;

implementation

function isCommand(command : pchar) : boolean;
var
    i : uint32;

begin
    isCommand:= true;
    for i:=0 to bIndex do begin
        if char(buffer[i]) = ' ' then exit;
        if char(buffer[i]) <> char(command[i]) then begin
            isCommand:= false;
            exit;
        end;
    end;
end;

procedure process_command;
var
    fallthrough : boolean;

begin
    console.writecharln(' ');
    //Process Here
    fallthrough:= true;
    if isCommand('version') then begin
        console.writestringln('Asuro v1.0');
        fallthrough:= false;
    end;
    if isCommand('clear') then begin
        console.clear();
        fallthrough:= false;
    end;
    if fallthrough then begin
        console.writestringln('Unknown Command.');
    end;
    console.writestring('Asuro#> ');
    bIndex:= 0;
    memset(uint32(@buffer[0]), 0, 1024);
end;

procedure key_event(info : TKeyInfo);
begin
    if (info.key_code >= 32) and (info.key_code <= 126) then begin
        if bIndex < 1024 then begin
            buffer[bIndex]:= info.key_code;
            inc(bIndex);
            console.writechar(char(info.key_code));
        end;
    end; 
    if info.key_code = 8 then begin //backspace
        if bIndex > 0 then begin
            console.backspace;
            dec(bIndex);
            buffer[bIndex]:= 0;
        end;
    end;
    if info.key_code = 13 then begin //return
        process_command;
    end;
end;

procedure run;
begin
    memset(uint32(@buffer[0]), 0, 1024);
    keyboard.hook(@key_event);
    console.clear();
    console.writestring('Asuro#> ');
end;

end.