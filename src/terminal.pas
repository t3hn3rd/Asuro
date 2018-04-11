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
    lmemorymanager,
    strings,
    tracer;

type
    PParamList = ^TParamList;
    TParamList = record
        Param : pchar;
        Next  : PParamList;  
    end;
    PHistory = ^THistory;
    THistory = record
        Command : pchar;
        Next : PHistory;
    end;
    TCommandBuffer = array[0..1023] of byte;
    TCommandMethod = procedure(params : PParamList);
    TCommand = record
        registered  : boolean;
        command     : pchar;
        method      : TCommandMethod;
        description : pchar;
    end;

var
    buffer   : TCommandBuffer;
    History  : PHistory;
    bIndex   : uint32 = 0;
    Commands : array[0..65534] of TCommand;

procedure run;
procedure init;
procedure registerCommand(command : pchar; method : TCommandMethod; description : pchar);
function getParams(buf : TCommandBuffer) : PParamList;
function paramCount(params : PParamList) : uint32;
function getParam(index : uint32; params : PParamList) : pchar;

implementation

function paramCount(params : PParamList) : uint32;
var
    current : PParamList;
    i : uint32;

begin
    current:= params;
    i:= 0;
    while current^.param <> nil do begin
        inc(i);
        current:= current^.next;
    end;
    paramCount:= i-1;
end;

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
    while buf[start] <> 0 do begin
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
        start:=finish+1;
        inc(finish);     
    end;
    getParams:= root;
end;

function getParam(index : uint32; params : PParamList) : pchar;
var
    result : pchar;
    search : PParamList;
    i      : uint32;

begin
    result:= nil;
    search:= params;
    for i:=0 to index do begin
        search:= search^.next;
    end;
    result:= search^.param;
end;

procedure freeParams(params : PParamList);
var
    p : PParamList;
    next : PParamList;

begin
    p:= params;
    next:= p^.next;
    while p^.next <> nil do begin
        if p^.param <> nil then kfree(void(p^.param));
        kfree(void(p));
        p:= next;
        next:= p^.next;
    end;
end;

procedure testParams(params : PParamList);
begin
    while params^.Param <> nil do begin
        writestringln(params^.Param);
        params:= params^.next;
    end;
end;

procedure echo(params : PParamList);
var
    current : PParamList;

begin
    current:= params^.next;
    while current^.param <> nil do begin
        console.writestring(current^.param);
        console.writestring(' ');
        current:= current^.next;
    end;
    console.writestringln('');
end;

procedure clear(params : PParamList);
begin
    console.clear();
end;

procedure version(params : PParamList);
begin
    console.writestringln('Asuro v1.0');
end;

procedure help(params : PParamList);
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

procedure test(params : PParamList);
begin
    if paramCount(params) > 0 then begin
        console.writeintln(stringToInt(getParam(0, params)));
    end else begin
        console.writestringln('Invalid number of params');
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

procedure process_command;
var
    fallthrough : boolean;
    params : PParamList;
    i : uint32;
    next : PParamList;
    uppera, upperb : pchar;

begin
    push_trace('terminal.process_command');

    { Start a new line. }
    console.writecharln(' ');

    { Enable fallthrough/Unrecognized command }
    fallthrough:= true;
    
    { Get all params and check params[0] (the command) to see if it's registered }
    params:= getParams(buffer);
    if params^.param <> nil then begin
        uppera:= stringToUpper(params^.param);
        for i:=0 to 65534 do begin
            if Commands[i].registered then begin
                upperb:= stringToUpper(Commands[i].command);
                if stringEquals(uppera, upperb) then begin
                    Commands[i].method(params);
                    fallthrough:= false;
                end;
                kfree(void(upperb));
            end;   
        end;
        kfree(void(uppera));
    end;

    { Free the params }
    freeParams(params);

    { Display message if command is unknown AKA fallthrough is active }
    if fallthrough then begin
        console.writestringln('Unknown Command.');
    end;

    { Reset the terminal ready for the next command }
    console.writestring('Asuro#> ');
    bIndex:= 0;
    memset(uint32(@buffer[0]), 0, 1024);

    pop_trace;
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
    console.writestringln('TERMINAL: INIT BEGIN.');
    memset(uint32(@Commands[0]), 0, 65535*sizeof(TCommand));
    memset(uint32(@buffer[0]), 0, 1024);
    registerCommand('VERSION', @version, 'Display the running version of Asuro.');
    registerCommand('CLEAR', @clear, 'Clear the Screen.');
    registerCommand('HELP', @help, 'Lists all registered commands and their description.');
    registerCommand('ECHO', @echo, 'Echo''s text to the terminal.');
    registerCommand('TESTPARAMS', @testParams, 'Tests param parsing.');
    registerCommand('TEST', @test, 'Command for testing.');
    console.writestringln('TERMINAL: INIT END.');
end;

procedure run;
begin
    keyboard.hook(@key_event);
    console.clear();
    console.writestring('Asuro#> ');
end;

end.