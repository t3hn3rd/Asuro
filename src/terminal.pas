unit terminal;

interface

uses
    console,
    keyboard,
    util;

type
    TCommandBuffer = array[0..1023] of byte;
    TCommandMethod = procedure(buf : TCommandBuffer);
    TCommand = record
        registered : boolean;
        command    : pchar;
        method     : TCommandMethod;
    end;

var
    buffer   : TCommandBuffer;
    bIndex   : uint32 = 0;
    Commands : array[0..65534] of TCommand;

procedure run;
procedure registerCommand(command : pchar; method : TCommandMethod);

implementation

procedure version(buffer : TCommandBuffer);
begin
    writestringln('Asuro v1.0');
end;

procedure registerCommand(command : pchar; method : TCommandMethod);
var
    index : uint32;

begin
    index:= 0;
    while Commands[index].registered = true do inc(index);
    Commands[index].registered:= true;
    Commands[index].Command:= command;
    Commands[index].method:= method;
end;

procedure upper;
var
    i : uint32;

begin
    for i:=0 to bIndex do begin
        if char(buffer[i]) = ' ' then exit;
        if (buffer[i] >= 97) and (buffer[i] <= 122) then begin
            buffer[i]:= buffer[i] - 32;
        end;
    end;
end;

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
    i : uint32;

begin
    console.writecharln(' ');
    fallthrough:= true;
    upper;
    for i:=0 to 65534 do begin
        if Commands[i].registered then begin
            if isCommand(Commands[i].command) then begin
                Commands[i].method(buffer);
                fallthrough:= false;
            end;
        end;   
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
    memset(uint32(@Commands[0]), 0, 65535*sizeof(TCommand));
    memset(uint32(@buffer[0]), 0, 1024);
    registerCommand('VERSION', @version);
    keyboard.hook(@key_event);
    console.clear();
    console.writestring('Asuro#> ');
end;

end.