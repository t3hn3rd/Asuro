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
    bios_data_area,
    console,
    keyboard,
    util,
    lmemorymanager,
    strings,
    tracer,
    asuro,
    serial;

const
    TERMINAL_HWND = 1;

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
    Working_Directory : PChar = '/';

procedure run;
procedure init;
procedure registerCommand(command : pchar; method : TCommandMethod; description : pchar);
function getParams(buf : TCommandBuffer) : PParamList;
function paramCount(params : PParamList) : uint32;
function getParam(index : uint32; params : PParamList) : pchar;
procedure setWorkingDirectory(str : pchar);
function getWorkingDirectory : pchar;
function getTerminalHWND : uint32;

implementation

uses
    RTC;

function getTerminalHWND : uint32;
begin
    getTerminalHWND:= TERMINAL_HWND;
end;

function getWorkingDirectory : pchar;
begin
    getWorkingDirectory:= Working_Directory;
end;

procedure setWorkingDirectory(str : pchar);
begin
    if str <> nil then begin
        Working_Directory:= stringCopy(str);
    end;
end;

function paramCount(params : PParamList) : uint32;
var
    current : PParamList;
    i : uint32;

begin
    push_trace('terminal.paramCount');
    current:= params;
    i:= 0;
    while current^.param <> nil do begin
        inc(i);
        current:= current^.next;
    end;
    paramCount:= i-1;
    pop_trace;
end;

function getParams(buf : TCommandBuffer) : PParamList;
var
    start, finish : uint32;
    size : uint32;
    ptr : uint32;
    root : PParamList;
    current : PParamList;

begin
    push_trace('terminal.getParams');
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
    pop_trace;
end;

function getParam(index : uint32; params : PParamList) : pchar;
var
    result : pchar;
    search : PParamList;
    i      : uint32;

begin
    push_trace('terminal.getParam');
    result:= nil;
    search:= params;
    for i:=0 to index do begin
        search:= search^.next;
    end;
    result:= search^.param;
    getParam:= result;
    pop_trace;
end;

procedure freeParams(params : PParamList);
var
    p : PParamList;
    next : PParamList;

begin
    push_trace('terminal.freeParams');
    p:= params;
    next:= p^.next;
    while p^.next <> nil do begin
        if p^.param <> nil then kfree(void(p^.param));
        kfree(void(p));
        p:= next;
        next:= p^.next;
    end;
    pop_trace;
end;

procedure testParams(params : PParamList);
begin
    while params^.Param <> nil do begin
        writestringlnWND(params^.Param, TERMINAL_HWND);
        params:= params^.next;
    end;
end;

procedure echo(params : PParamList);
var
    current : PParamList;

begin
    current:= params^.next;
    while current^.param <> nil do begin
        console.writestringWND(current^.param, TERMINAL_HWND);
        console.writestringWND(' ', TERMINAL_HWND);
        current:= current^.next;
    end;
    console.writestringlnWND('', TERMINAL_HWND);
end;

procedure clear(params : PParamList);
begin
    console.clearWND(TERMINAL_HWND);
end;

procedure version(params : PParamList);
begin
    console.writestringlnWND(asuro.VERSION, TERMINAL_HWND);
end;

procedure help(params : PParamList);
var

    i : uint32;
begin
    console.writestringlnWND('Registered Commands: ', TERMINAL_HWND);
    for i:=0 to 65534 do begin
        if Commands[i].Registered then begin
            console.writestringWND('  ', TERMINAL_HWND);
            console.writestringWND(Commands[i].command, TERMINAL_HWND);
            console.writestringWND(' - ', TERMINAL_HWND);
            console.writestringlnWND(Commands[i].description, TERMINAL_HWND);
        end;
    end;
end;

procedure cockwomble(params : PParamList);
var
    x, y : uint8;
    o : uint16;
    i : uint32;

begin
    i:= 1;
    while true do begin
        for y:=0 to 63 do begin
            for x:=0 to 159 do begin
                o:= uint16(y * i + x * i + i + (BDA^.Ticks SHR 3));
                outputChar(' ', x, y, $FFFF, o);
            end;
        end;
        i:= uint32(i) + 1;
    end;
end;

procedure test(params : PParamList);
begin
    if paramCount(params) > 0 then begin
        console.writeintlnWND(stringToInt(getParam(0, params)), TERMINAL_HWND);
    end else begin
        console.writestringlnWND('Invalid number of params', TERMINAL_HWND);
    end;
end;

procedure printTime(Params : PParamList);
var
    DateTime : TDateTime;

begin
     DateTime:= getDateTime;
     writeIntWND(DateTime.Day, TERMINAL_HWND);     
     writeStringWND('/', TERMINAL_HWND);
     writeIntWND(DateTime.Month, TERMINAL_HWND);
     writeStringWND('/', TERMINAL_HWND);  
     writeIntWND(DateTime.Century, TERMINAL_HWND);  
     writeIntWND(DateTime.Year, TERMINAL_HWND);    
     writeStringWND(' ', TERMINAL_HWND);  
     writeIntWND(DateTime.Hours, TERMINAL_HWND);
     writeStringWND(':', TERMINAL_HWND);
     writeIntWND(DateTime.Minutes, TERMINAL_HWND);
     writeStringWND(':', TERMINAL_HWND);
     writeIntlnWND(DateTime.Seconds, TERMINAL_HWND);
     //writeStringWND('Weekday: ', TERMINAL_HWND);
     //writeIntlnWND(DateTime.Weekday, TERMINAL_HWND); 
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
    console.writecharlnWND(' ', TERMINAL_HWND);

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
        console.writestringlnWND('Unknown Command.', TERMINAL_HWND);
    end;

    { Reset the terminal ready for the next command }
    console.writestringWND('Asuro#', TERMINAL_HWND);
    console.writestringWND(Working_Directory, TERMINAL_HWND);
    console.writestringWND('> ', TERMINAL_HWND);
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
            console.writecharWND(char(info.key_code), TERMINAL_HWND);
        end;
    end; 
    if info.key_code = 8 then begin //backspace
        if bIndex > 0 then begin
            console.backspaceWND(TERMINAL_HWND);
            dec(bIndex);
            buffer[bIndex]:= 0;
        end;
    end;
    if info.key_code = 13 then begin //return
        process_command;
    end;
end;

procedure change_dir(Params : PParamList);
begin
    if paramCount(Params) > 0 then begin
        setWorkingDirectory(getParam(0, Params));
    end;
end;

procedure ToggleWND1(Params : PParamList);
begin
    console.toggleWNDVisible(1);
end;

procedure SendSerial(Params : PParamList);
begin
    Serial.init(COM1);
    Serial.Send(uint8('H'), COM1, 1000);
    Serial.Send(uint8('E'), COM1, 1000);
    Serial.Send(uint8('L'), COM1, 1000);
    Serial.Send(uint8('L'), COM1, 1000);
    Serial.Send(uint8('O'), COM1, 1000);
    Serial.Send(uint8('W'), COM1, 1000);
    Serial.Send(uint8('O'), COM1, 1000);
    Serial.Send(uint8('R'), COM1, 1000);
    Serial.Send(uint8('L'), COM1, 1000);
    Serial.Send(uint8('D'), COM1, 1000);
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
    registerCommand('CD', @change_dir, 'Change Directory test.');
    registerCommand('PATTERN', @cockwomble, 'Print an animated pattern to the screen.');
    registerCommand('TOGGLEWND1', @ToggleWND1, 'Toggle WND 1 Visibility.');
    registerCommand('TIME', @printTime, 'Print the current time.');
    registerCommand('SERIAL', @SendSerial, 'Send ''helloworld'' through COM1.');
    console.writestringln('TERMINAL: INIT END.');
end;

procedure run;
begin
    keyboard.hook(@key_event);
    console.clearWND(TERMINAL_HWND);
    console.writestringWND('Asuro#', TERMINAL_HWND);
    console.writestringWND(Working_Directory, TERMINAL_HWND);
    console.writestringWND('> ', TERMINAL_HWND);
    console.setWNDVisible(TERMINAL_HWND, true);
end;

end.