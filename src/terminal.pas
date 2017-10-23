{ ************************************************
  * Asuro
  * Unit: Terminal
  * Description: Interactive shell for the user
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit terminal;

interface

uses
    console,
    keyboard,
    util,
    lmemorymanager;

type
    PParamList = ^TParamList;
    TParamList = record
        Param : pchar;
        Next  : PParamList;  
    end;
    TCommandBuffer = array[0..1023] of byte;
    TCommandMethod = procedure(buf : TCommandBuffer);
    TCommand = record
        registered  : boolean;
        command     : pchar;
        method      : TCommandMethod;
        description : pchar;
    end;

var
    buffer   : TCommandBuffer;
    bIndex   : uint32 = 0;
    Commands : array[0..65534] of TCommand;

procedure run;
procedure init;
procedure registerCommand(command : pchar; method : TCommandMethod; description : pchar);
function getParams(buf : TCommandBuffer) : PParamList;

implementation

function getParams(buf : TCommandBuffer) : PParamList;
var
    start, finish : uint32;
    size : uint32;
    ptr : uint32;
    root : PParamList;
    current : PParamList;

begin
    root:= PParamList(kalloc(sizeof(TParamList)));
    current:= root;
    current^.next:= nil;
    current^.Param:= nil;
    start:= 0;
    finish:= 0;
    while (char(buf[finish]) <> ' ') and (buf[finish] <> 0) do begin
        inc(finish);
    end;
    while buf[start] <> 0 do begin
        start:=finish+1;
        inc(finish);
        while (char(buf[finish]) <> ' ') and (buf[finish] <> 0) do begin
            inc(finish);
        end;  
        size:= finish - start;
        if size > 0 then begin
            ptr:= uint32(@buf[start]);
            current^.Param:= pchar(kalloc(size+2));
            memset(uint32(current^.Param), 0, size+2);
            memcpy(uint32(ptr), uint32(current^.Param), size);
            current^.next:= PParamList(kalloc(sizeof(TParamList)));
            current:= current^.next;
            current^.next:= nil;
            current^.Param:= nil;
        end;      
    end;
    getParams:= root;
end;

procedure testParams(buffer : TCommandBuffer);
var
    params : PParamList;

begin
    params:= getParams(buffer);
    while params^.Param <> nil do begin
        writestringln(params^.Param);
        params:= params^.next;
    end;
end;

procedure echo(buffer : TCommandBuffer);
var
    idx : uint32;

begin
    idx:= 5;
    while buffer[idx] <> 0 do begin
        console.writechar(char(buffer[idx]));
        inc(idx);
    end;
    console.writestringln('');
end;

procedure clear(buffer : TCommandBuffer);
begin
    console.clear();
end;

procedure version(buffer : TCommandBuffer);
begin
    console.writestringln('Asuro v1.0');
end;

procedure help(buffer : TCommandBuffer);
var
    i : uint32;
begin
    console.writestringln('Registered Commands: ');
    for i:=0 to 65534 do begin
        if Commands[i].Registered then begin
            console.writestring('  ');
            console.writestring(Commands[i].command);
            console.writestring(' - ');
            console.writestringln(Commands[i].description);
        end;
    end;
end;

procedure registerCommand(command : pchar; method : TCommandMethod; description : pchar);
var
    index : uint32;

begin
    index:= 0;
    while Commands[index].registered = true do inc(index);
    Commands[index].registered:= true;
    Commands[index].Command:= command;
    Commands[index].method:= method;
    Commands[index].description:= description;
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
        if char(buffer[i]) = ' ' then begin
            if i = 0 then isCommand:= false;
            exit;
        end;
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

procedure init;
begin
    memset(uint32(@Commands[0]), 0, 65535*sizeof(TCommand));
    memset(uint32(@buffer[0]), 0, 1024);
    registerCommand('VERSION', @version, 'Display the running version of Asuro.');
    registerCommand('CLEAR', @clear, 'Clear the Screen.');
    registerCommand('HELP', @help, 'Lists all registered commands and their description.');
    registerCommand('ECHO', @echo, 'Echo''s text to the terminal.');
    registerCommand('TESTPARAMS', @testParams, 'Tests param parsing.');
end;

procedure run;
begin
    keyboard.hook(@key_event);
    console.clear();
    console.writestring('Asuro#> ');
end;

end.