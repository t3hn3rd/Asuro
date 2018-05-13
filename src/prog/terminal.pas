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
    serial,
    netutils, nettypes;

type
    THaltCallback = procedure();
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
        hidden      : boolean;
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
    Halted   : Boolean = false;
    HaltID   : uint32 = 0;
    HaltCB   : THaltCallback = nil;

procedure run;
procedure init;
procedure registerCommand(command : pchar; method : TCommandMethod; description : pchar);
procedure registerCommandEx(command : pchar; method : TCommandMethod; description : pchar; hide : boolean);
function getParams(buf : TCommandBuffer) : PParamList;
function paramCount(params : PParamList) : uint32;
function getParam(index : uint32; params : PParamList) : pchar;
procedure setWorkingDirectory(str : pchar);
function getWorkingDirectory : pchar;
function getTerminalHWND : uint32;
function halt(id : uint32; cb : THaltCallback) : boolean;
function done(id : uint32) : boolean;

implementation

uses
    RTC;

var
    TERMINAL_HWND : HWND = 0;

function halt(id : uint32; cb : THaltCallback) : boolean;
begin
    halt:= false;
    if not Halted then begin
        Halted:= true;
        halt:= true;
        HaltID:= id;
        HaltCB:= cb;
    end;
end;

function done(id : uint32) : boolean;
begin
    done:= false;
    if Halted then begin
        if id = HaltID then begin
            if HaltCB <> nil then HaltCB();
            HaltCB:= nil;
            Halted:= false;
            HaltID:= 0;
            done:= true;
            console.writestringWND('Asuro#', TERMINAL_HWND);
            console.writestringWND(Working_Directory, TERMINAL_HWND);
            console.writestringWND('> ', TERMINAL_HWND);
            bIndex:= 0;
            memset(uint32(@buffer[0]), 0, 1024);
        end;
    end;
end;

procedure force_done;
begin
    HaltID:= 0;
    done(0);
end;

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
    //push_trace('terminal.paramCount');
    current:= params;
    i:= 0;
    while current^.param <> nil do begin
        inc(i);
        current:= current^.next;
    end;
    paramCount:= i-1;
    //pop_trace;
end;

function getParams(buf : TCommandBuffer) : PParamList;
var
    start, finish : uint32;
    size : uint32;
    ptr : uint32;
    root : PParamList;
    current : PParamList;

begin
    //push_trace('terminal.getParams');
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
    //pop_trace;
end;

function getParam(index : uint32; params : PParamList) : pchar;
var
    result : pchar;
    search : PParamList;
    i      : uint32;

begin
    //push_trace('terminal.getParam');
    result:= nil;
    search:= params;
    for i:=0 to index do begin
        search:= search^.next;
    end;
    result:= search^.param;
    getParam:= result;
    //pop_trace;
end;

procedure freeParams(params : PParamList);
var
    p : PParamList;
    next : PParamList;

begin
    //push_trace('terminal.freeParams');
    p:= params;
    next:= p^.next;
    while p^.next <> nil do begin
        if p^.param <> nil then kfree(void(p^.param));
        kfree(void(p));
        p:= next;
        next:= p^.next;
    end;
    //pop_trace;
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
    console.writestringWND('  Asuro Version: ', TERMINAL_HWND);
    console.writestringlnWND(asuro.VERSION, TERMINAL_HWND);
    console.writestringWND('  Compiled on: ', TERMINAL_HWND);
    console.writestringWND(asuro.COMPILE_DATE, TERMINAL_HWND);
    console.writestringWND(' ', TERMINAL_HWND);
    console.writestringlnWND(asuro.COMPILE_TIME, TERMINAL_HWND);
    console.writestringlnWND('  Compiled With: ', TERMINAL_HWND);
    console.writestringWND('    NASM - Version: ', TERMINAL_HWND);
    console.writestringlnWND(asuro.NASM_VERSION, TERMINAL_HWND);
    console.writestringWND('    FPC  - Version: ', TERMINAL_HWND);
    console.writestringlnWND(asuro.FPC_VERSION, TERMINAL_HWND);
    console.writestringWND('    MAKE - Version: ', TERMINAL_HWND);
    console.writestringlnWND(asuro.MAKE_VERSION, TERMINAL_HWND);
    console.writestringWND('  ', TERMINAL_HWND);
    console.writeintWND(asuro.LINE_COUNT, TERMINAL_HWND);
    console.writestringWND(' lines, across ', TERMINAL_HWND);
    console.writeintWND(asuro.FILE_COUNT, TERMINAL_HWND);
    console.writestringlnWND(' files.', TERMINAL_HWND);
    console.writestringWND('  Baked Drivers: ', TERMINAL_HWND);
    console.writeintlnWND(asuro.DRIVER_COUNT, TERMINAL_HWND);
end;

procedure help(params : PParamList);
var
    i, j : uint32;
    longestCommand : uint32;
    len : uint32;

begin
    longestCommand:= 0;
    for i:=0 to 65534 do begin
        if (Commands[i].Registered) and not(Commands[i].hidden) then begin
            if stringSize(Commands[i].command) > longestCommand then longestCommand:= stringSize(Commands[i].command);
        end;
    end;
    console.writestringlnWND('Registered Commands: ', TERMINAL_HWND);
    for i:=0 to 65534 do begin
        if (Commands[i].Registered) and not(Commands[i].hidden) then begin
            console.writestringWND('  ', TERMINAL_HWND);
            console.writestringWND(Commands[i].command, TERMINAL_HWND);
            len:= longestCommand - StringSize(Commands[i].command);
            for j:=0 to len do begin
                writeStringWND(' ', TERMINAL_HWND);
            end;
            console.writestringWND('- ', TERMINAL_HWND);
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
     if DateTime.Day < 10 then writeStringWND('0', TERMINAL_HWND);
     writeIntWND(DateTime.Day, TERMINAL_HWND);     
     writeStringWND('/', TERMINAL_HWND);
     if DateTime.Month < 10 then writeStringWND('0', TERMINAL_HWND);
     writeIntWND(DateTime.Month, TERMINAL_HWND);
     writeStringWND('/', TERMINAL_HWND);  
     writeIntWND(DateTime.Century, TERMINAL_HWND);  
     writeIntWND(DateTime.Year, TERMINAL_HWND);    
     writeStringWND(' ', TERMINAL_HWND);  
     if DateTime.Hours < 10 then writeStringWND('0', TERMINAL_HWND);
     writeIntWND(DateTime.Hours, TERMINAL_HWND);
     writeStringWND(':', TERMINAL_HWND);
     if DateTime.Minutes < 10 then writeStringWND('0', TERMINAL_HWND);
     writeIntWND(DateTime.Minutes, TERMINAL_HWND);
     writeStringWND(':', TERMINAL_HWND);
     if DateTime.Seconds < 10 then writeStringWND('0', TERMINAL_HWND);
     writeIntlnWND(DateTime.Seconds, TERMINAL_HWND);
     writeStringWND('Weekday: ', TERMINAL_HWND);
     writeStringlnWND(WeekdayToString(DateTime.Weekday), TERMINAL_HWND); 
end;

procedure registerCommand(command : pchar; method : TCommandMethod; description : pchar);
var
    index : uint32;

begin
    index:= 0;
    while Commands[index].registered = true do inc(index);
    Commands[index].registered:= true;
    Commands[index].Command:= command;
    Commands[index].hidden:= false;
    Commands[index].method:= method;
    Commands[index].description:= description;
end;

procedure registerCommandEx(command : pchar; method : TCommandMethod; description : pchar; hide : boolean);
var
    index : uint32;

begin
    index:= 0;
    while Commands[index].registered = true do inc(index);
    Commands[index].registered:= true;
    Commands[index].Command:= command;
    Commands[index].hidden:= hide;
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

    if not Halted then begin
        { Reset the terminal ready for the next command }
        console.writestringWND('Asuro#', TERMINAL_HWND);
        console.writestringWND(Working_Directory, TERMINAL_HWND);
        console.writestringWND('> ', TERMINAL_HWND);
        bIndex:= 0;
        memset(uint32(@buffer[0]), 0, 1024);
    end;
    pop_trace;
end;

procedure key_event(info : TKeyInfo);
begin
    if TERMINAL_HWND <> 0 then begin
        //writeintlnWND(info.key_code, TERMINAL_HWND);
        if info.CTRL_DOWN then begin
            if info.key_code = uint8('c') then force_done;
        end else begin
            if not halted then begin
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
        end;
    end;
end;

procedure change_dir(Params : PParamList);
begin
    if paramCount(Params) > 0 then begin
        setWorkingDirectory(getParam(0, Params));
    end;
end;

procedure SendSerial(Params : PParamList);
var
    success : boolean;

begin
    success:= true;
    success:= success AND Serial.Send(COM1, uint8('H'), 1000);
    success:= success AND Serial.Send(COM1, uint8('E'), 1000);
    success:= success AND Serial.Send(COM1, uint8('L'), 1000);
    success:= success AND Serial.Send(COM1, uint8('L'), 1000);
    success:= success AND Serial.Send(COM1, uint8('O'), 1000);
    success:= success AND Serial.Send(COM1, uint8('W'), 1000);
    success:= success AND Serial.Send(COM1, uint8('O'), 1000);
    success:= success AND Serial.Send(COM1, uint8('R'), 1000);
    success:= success AND Serial.Send(COM1, uint8('L'), 1000);
    success:= success AND Serial.Send(COM1, uint8('D'), 1000);
    success:= success AND Serial.Send(COM1, 10, 1000);
    success:= success AND Serial.Send(COM1, 13, 1000);
    if success then begin
        console.writestringlnWND('Send Success!', TERMINAL_HWND);
    end else begin
        console.writestringlnWND('Send Failed!', TERMINAL_HWND);
    end;
end;

procedure Reboot(Params : PParamList);
begin
    resetSystem;
end;

procedure teapot_halt;
begin
    console.writeStringlnWND('Stopped. [CTRL+C]', getTerminalHWND);
end;

procedure teapot(Params : PParamList);
var
    packet : array[0..39] of uint8 = ( $00, $00, $00, $00, $00, $01, $00, $f3, $61, $62, $63, $64, $65, $66, $67, $68, 
                                       $69, $6a, $6b, $6c, $6d, $6e, $6f, $70, $71, $72, $73, $74, $75, $76, $77, $61, 
                                       $62, $63, $64, $65, $66, $67, $68, $69);
    CHK : uint16;

begin
    CHK:= calculateChecksum(puint16(@packet[0]), 40);
    writehexlnWND(CHK, getTerminalHWND);
    terminal.halt(555, @teapot_halt);
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
    registerCommand('TIME', @printTime, 'Print the current time.');
    registerCommandEx('SERIAL', @SendSerial, 'Send ''helloworld'' through COM1.', true);
    registerCommand('REBOOT', @Reboot, 'Reboot the system.');
    registerCommandEx('LOLWUT', @teapot, '?', true);
    console.writestringln('TERMINAL: INIT END.');
end;

procedure OnClose();
begin
    TERMINAL_HWND:= 0;
end;

procedure run;
begin
    if TERMINAL_HWND = 0 then begin
        TERMINAL_HWND:= newWindow(20, 10, 90, 30, 'ASURO TERMINAL');
        console.registerEventHandler(TERMINAL_HWND, EVENT_KEY_PRESSED, void(@key_event));
        console.registerEventHandler(TERMINAL_HWND, EVENT_CLOSE, void(@OnClose));
        console.clearWND(TERMINAL_HWND);
        console.writestringWND('Asuro#', TERMINAL_HWND);
        console.writestringWND(Working_Directory, TERMINAL_HWND);
        console.writestringWND('> ', TERMINAL_HWND);
    end;
end;

end.