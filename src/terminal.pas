unit terminal;

interface

uses
    console,
    keyboard;

var
    buffer : array[0..1024] of byte;
    bIndex : uint32 = 0;

procedure run;

implementation

procedure process_command;
begin
    console.writecharln(' ');
    console.writestring('Asuro#> ');
    bIndex:= 0;
end;

procedure key_event(info : TKeyInfo);
begin
    if (info.key_code >= 32) and (info.key_code <= 126) then begin
        if bIndex <= 1024 then begin
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
    keyboard.hook(@key_event);
    console.clear();
    console.writestring('Asuro#> ');
end;

end.