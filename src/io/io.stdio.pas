{
    Stdio - Standard I/O abstraction for command-line programs.

    Provides:
    - Buffer-based output (POutBuf) with ANSI escape support
    - Dynamic command registry (replaces terminal.pas static array)
    - Parameter parsing (moved from terminal.pas)
    - Working directory delegation
    - Halt/resume mechanism for async commands (e.g. PING)

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit io.stdio;

interface

uses
    memory.heap, core.strings, core.util, arch.x86.util, debug.tracer;

type
    { Output buffer — kalloc'd, growable }
    POutBuf = ^TOutBuf;
    TOutBuf = record
        buf : pchar;
        len : uint32;
        cap : uint32;
    end;

    { Parameter linked list }
    PParamList = ^TParamList;
    TParamList = record
        Param : pchar;
        Next  : PParamList;
    end;

    { Command buffer type }
    TCommandBuffer = array[0..1023] of byte;

    { Command method — receives params plus stdin (read), stdout (write), stderr (write) }
    TCommandMethod = procedure(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);

    { Command record }
    PCommand = ^TCommand;
    TCommand = record
        registered  : boolean;
        hidden      : boolean;
        command     : pchar;
        method      : TCommandMethod;
        description : pchar;
    end;

    { Halt callback }
    THaltCallback = procedure();

{ Output buffer management }
function  createOutBuf(initial_cap: uint32): POutBuf;
procedure freeOutBuf(buf: POutBuf);
procedure bufClear(buf: POutBuf);

{ Buffer write helpers }
procedure bufWriteChar(buf: POutBuf; c: char);
procedure bufWriteStr(buf: POutBuf; s: pchar);
procedure bufWriteStrLn(buf: POutBuf; s: pchar);
procedure bufWriteInt(buf: POutBuf; i: integer);
procedure bufWriteIntLn(buf: POutBuf; i: integer);
procedure bufWriteHexPair(buf: POutBuf; b: uint8);
procedure bufWriteHex(buf: POutBuf; i: uint32);
procedure bufWriteHexLn(buf: POutBuf; i: uint32);
procedure bufWriteBin8(buf: POutBuf; b: uint8);
procedure bufWriteBin8Ln(buf: POutBuf; b: uint8);
procedure bufWriteBin16(buf: POutBuf; b: uint16);
procedure bufWriteBin16Ln(buf: POutBuf; b: uint16);
procedure bufWriteBin32(buf: POutBuf; b: uint32);
procedure bufWriteBin32Ln(buf: POutBuf; b: uint32);
procedure bufWriteNewLine(buf: POutBuf);

{ ANSI core.gfx.color helpers }
procedure bufSetColor(buf: POutBuf; fg: uint8);
procedure bufResetColor(buf: POutBuf);

{ Command registry }
procedure registerCommand(command: pchar; method: TCommandMethod; description: pchar);
procedure registerCommandEx(command: pchar; method: TCommandMethod; description: pchar; hide: boolean);
function  getCommandCount: uint32;
function  getCommand(index: uint32): PCommand;
function  findCommand(name: pchar): PCommand;

{ Parameter parsing }
function  getParams(var buf: TCommandBuffer): PParamList;
procedure freeParams(params: PParamList);
function  paramCount(params: PParamList): uint32;
function  getParam(index: uint32; params: PParamList): pchar;

{ Working directory }
function  getWorkingDirectory: pchar;
procedure setWorkingDirectory(str: pchar);

{ Halt mechanism for async commands }
function  halt(id: uint32; cb: THaltCallback): boolean;
function  done(id: uint32): boolean;

var
    Halted   : boolean;
    HaltID   : uint32;
    HaltCB   : THaltCallback;

{ Initialization }
procedure init;

implementation

uses
    core.version, driver.timer.rtc, driver.io.serial, driver.storage.vfs, io.syslog;

const
    INITIAL_CMD_CAP = 64;

var
    Commands   : PCommand;
    CmdCount   : uint32 = 0;
    CmdCap     : uint32 = 0;

{ ---- Output buffer ---- }

function createOutBuf(initial_cap: uint32): POutBuf;
var
    ob: POutBuf;
    cap: uint32;
begin
    if initial_cap = 0 then cap := 1 else cap := initial_cap;
    ob := POutBuf(kalloc(SizeOf(TOutBuf)));
    ob^.buf := pchar(kalloc(cap));
    ob^.len := 0;
    ob^.cap := cap;
    memset(uint32(ob^.buf), 0, cap);
    createOutBuf := ob;
end;

procedure freeOutBuf(buf: POutBuf);
begin
    if buf = nil then exit;
    if buf^.buf <> nil then kfree(void(buf^.buf));
    kfree(void(buf));
end;

procedure bufClear(buf: POutBuf);
begin
    if buf = nil then exit;
    buf^.len := 0;
    if buf^.buf <> nil then
        buf^.buf[0] := #0;
end;

procedure bufGrow(buf: POutBuf; needed: uint32);
var
    newCap: uint32;
    newBuf: pchar;
begin
    if buf^.len + needed < buf^.cap then exit;
    newCap := buf^.cap;
    if newCap = 0 then newCap := 64;
    while newCap <= buf^.len + needed do
        newCap := newCap * 2;
    newBuf := pchar(kalloc(newCap));
    memset(uint32(newBuf), 0, newCap);
    if buf^.len > 0 then
        memcpy(uint32(buf^.buf), uint32(newBuf), buf^.len);
    kfree(void(buf^.buf));
    buf^.buf := newBuf;
    buf^.cap := newCap;
end;

procedure bufWriteChar(buf: POutBuf; c: char);
begin
    if buf = nil then exit;
    bufGrow(buf, 2);
    buf^.buf[buf^.len] := c;
    Inc(buf^.len);
    buf^.buf[buf^.len] := #0;
end;

procedure bufWriteStr(buf: POutBuf; s: pchar);
var
    i: uint32;
begin
    if (buf = nil) or (s = nil) then exit;
    i := 0;
    while s[i] <> #0 do begin
        bufWriteChar(buf, s[i]);
        Inc(i);
    end;
end;

procedure bufWriteStrLn(buf: POutBuf; s: pchar);
begin
    bufWriteStr(buf, s);
    bufWriteChar(buf, #10);
end;

procedure bufWriteNewLine(buf: POutBuf);
begin
    bufWriteChar(buf, #10);
end;

procedure bufWriteInt(buf: POutBuf; i: integer);
var
    buffer: array[0..11] of char;
    p: uint32;
    digit: uint32;
    minus: boolean;
begin
    if buf = nil then exit;
    p := 11;
    buffer[11] := #0;
    if i < 0 then begin
        digit := uint32(-i);
        minus := true;
    end else begin
        digit := uint32(i);
        minus := false;
    end;
    repeat
        Dec(p);
        buffer[p] := char((digit mod 10) + uint32(byte('0')));
        digit := digit div 10;
    until digit = 0;
    if minus then begin
        Dec(p);
        buffer[p] := '-';
    end;
    bufWriteStr(buf, @buffer[p]);
end;

procedure bufWriteIntLn(buf: POutBuf; i: integer);
begin
    bufWriteInt(buf, i);
    bufWriteChar(buf, #10);
end;

procedure bufWriteHexPair(buf: POutBuf; b: uint8);
const
    HexDigits: array[0..15] of char = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
begin
    if buf = nil then exit;
    bufWriteChar(buf, HexDigits[b SHR 4]);
    bufWriteChar(buf, HexDigits[b AND $0F]);
end;

procedure bufWriteHex(buf: POutBuf; i: uint32);
begin
    if buf = nil then exit;
    bufWriteStr(buf, '0x');
    bufWriteHexPair(buf, uint8(i SHR 24));
    bufWriteHexPair(buf, uint8((i SHR 16) AND $FF));
    bufWriteHexPair(buf, uint8((i SHR 8) AND $FF));
    bufWriteHexPair(buf, uint8(i AND $FF));
end;

procedure bufWriteHexLn(buf: POutBuf; i: uint32);
begin
    bufWriteHex(buf, i);
    bufWriteChar(buf, #10);
end;

procedure bufWriteBin8(buf: POutBuf; b: uint8);
var
    i: uint8;
begin
    if buf = nil then exit;
    for i := 7 downto 0 do begin
        if (b AND (1 SHL i)) <> 0 then
            bufWriteChar(buf, '1')
        else
            bufWriteChar(buf, '0');
    end;
end;

procedure bufWriteBin8Ln(buf: POutBuf; b: uint8);
begin
    bufWriteBin8(buf, b);
    bufWriteChar(buf, #10);
end;

procedure bufWriteBin16(buf: POutBuf; b: uint16);
begin
    bufWriteBin8(buf, uint8(b SHR 8));
    bufWriteBin8(buf, uint8(b AND $FF));
end;

procedure bufWriteBin16Ln(buf: POutBuf; b: uint16);
begin
    bufWriteBin16(buf, b);
    bufWriteChar(buf, #10);
end;

procedure bufWriteBin32(buf: POutBuf; b: uint32);
begin
    bufWriteBin16(buf, uint16(b SHR 16));
    bufWriteBin16(buf, uint16(b AND $FFFF));
end;

procedure bufWriteBin32Ln(buf: POutBuf; b: uint32);
begin
    bufWriteBin32(buf, b);
    bufWriteChar(buf, #10);
end;

{ ---- ANSI core.gfx.color helpers ---- }

procedure bufSetColor(buf: POutBuf; fg: uint8);
begin
    { ESC[38;5;<n>m }
    bufWriteChar(buf, #27);
    bufWriteChar(buf, '[');
    bufWriteChar(buf, '3');
    bufWriteChar(buf, '8');
    bufWriteChar(buf, ';');
    bufWriteChar(buf, '5');
    bufWriteChar(buf, ';');
    bufWriteInt(buf, fg);
    bufWriteChar(buf, 'm');
end;

procedure bufResetColor(buf: POutBuf);
begin
    { ESC[0m }
    bufWriteChar(buf, #27);
    bufWriteChar(buf, '[');
    bufWriteChar(buf, '0');
    bufWriteChar(buf, 'm');
end;

{ ---- Dynamic command registry ---- }

procedure growCommands;
var
    newCap: uint32;
    newArr: PCommand;
    i: uint32;
begin
    newCap := CmdCap * 2;
    newArr := PCommand(kalloc(newCap * SizeOf(TCommand)));
    memset(uint32(newArr), 0, newCap * SizeOf(TCommand));
    { Copy existing }
    for i := 0 to CmdCap - 1 do begin
        PCommand(uint32(newArr) + i * SizeOf(TCommand))^ :=
            PCommand(uint32(Commands) + i * SizeOf(TCommand))^;
    end;
    kfree(void(Commands));
    Commands := newArr;
    CmdCap := newCap;
end;

function getCmdPtr(index: uint32): PCommand; inline;
begin
    getCmdPtr := PCommand(uint32(Commands) + index * SizeOf(TCommand));
end;

procedure registerCommand(command: pchar; method: TCommandMethod; description: pchar);
begin
    registerCommandEx(command, method, description, false);
end;

procedure registerCommandEx(command: pchar; method: TCommandMethod; description: pchar; hide: boolean);
var
    cmd: PCommand;
begin
    if CmdCount >= CmdCap then growCommands;
    cmd := getCmdPtr(CmdCount);
    cmd^.registered := true;
    cmd^.hidden := hide;
    cmd^.command := command;
    cmd^.method := method;
    cmd^.description := description;
    Inc(CmdCount);
end;

function getCommandCount: uint32;
begin
    getCommandCount := CmdCount;
end;

function getCommand(index: uint32): PCommand;
begin
    if index < CmdCount then
        getCommand := getCmdPtr(index)
    else
        getCommand := nil;
end;

function findCommand(name: pchar): PCommand;
var
    i: uint32;
    cmd: PCommand;
    ua, ub: pchar;
begin
    findCommand := nil;
    ua := stringToUpper(name);
    for i := 0 to CmdCount - 1 do begin
        cmd := getCmdPtr(i);
        if cmd^.registered then begin
            ub := stringToUpper(cmd^.command);
            if stringEquals(ua, ub) then begin
                kfree(void(ub));
                kfree(void(ua));
                findCommand := cmd;
                exit;
            end;
            kfree(void(ub));
        end;
    end;
    kfree(void(ua));
end;

{ ---- Parameter parsing ---- }

function getParams(var buf: TCommandBuffer): PParamList;
var
    start, finish: uint32;
    size: uint32;
    ptr: uint32;
    root: PParamList;
    current: PParamList;
begin
    root := PParamList(kalloc(SizeOf(TParamList)));
    current := root;
    current^.next := nil;
    current^.Param := nil;
    start := 0;
    finish := 0;
    while buf[start] <> 0 do begin
        while (char(buf[finish]) <> ' ') and (buf[finish] <> 0) do
            Inc(finish);
        size := finish - start;
        if size > 0 then begin
            ptr := uint32(@buf[start]);
            current^.Param := pchar(kalloc(size + 2));
            memset(uint32(current^.Param), 0, size + 2);
            memcpy(uint32(ptr), uint32(current^.Param), size);
            current^.next := PParamList(kalloc(SizeOf(TParamList)));
            current := current^.next;
            current^.next := nil;
            current^.Param := nil;
        end;
        start := finish + 1;
        Inc(finish);
    end;
    getParams := root;
end;

procedure freeParams(params: PParamList);
var
    p, next: PParamList;
begin
    p := params;
    while p <> nil do begin
        next := p^.next;
        if p^.param <> nil then kfree(void(p^.param));
        kfree(void(p));
        p := next;
    end;
end;

function paramCount(params: PParamList): uint32;
var
    current: PParamList;
    i: uint32;
begin
    current := params;
    i := 0;
    while (current <> nil) and (current^.param <> nil) do begin
        Inc(i);
        current := current^.next;
    end;
    if i > 0 then
        paramCount := i - 1
    else
        paramCount := 0;
end;

function getParam(index: uint32; params: PParamList): pchar;
var
    search: PParamList;
    i: uint32;
begin
    search := params;
    for i := 0 to index do begin
        if search^.next = nil then begin
            getParam := nil;
            exit;
        end;
        search := search^.next;
    end;
    getParam := search^.param;
end;

{ ---- Working directory ---- }

function getWorkingDirectory: pchar;
begin
    getWorkingDirectory := driver.storage.vfs.getWorkingDirectory;
end;

procedure setWorkingDirectory(str: pchar);
begin
    if str <> nil then
        driver.storage.vfs.changeDirectory(str);
end;

{ ---- Halt mechanism ---- }

function halt(id: uint32; cb: THaltCallback): boolean;
begin
    halt := false;
    if not Halted then begin
        Halted := true;
        halt := true;
        HaltID := id;
        HaltCB := cb;
    end;
end;

function done(id: uint32): boolean;
begin
    done := false;
    if Halted then begin
        if id = HaltID then begin
            if HaltCB <> nil then HaltCB();
            HaltCB := nil;
            Halted := false;
            HaltID := 0;
            done := true;
        end;
    end;
end;

{ ---- Built-in commands ---- }

procedure cmd_version(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
begin
    bufWriteStr(stdout_buf, '  Asuro Version: ');
    bufWriteStrLn(stdout_buf, core.version.VERSION);
    bufWriteStr(stdout_buf, '  Compiled on: ');
    bufWriteStr(stdout_buf, core.version.COMPILE_DATE);
    bufWriteStr(stdout_buf, ' ');
    bufWriteStrLn(stdout_buf, core.version.COMPILE_TIME);
    bufWriteStrLn(stdout_buf, '  Compiled With: ');
    bufWriteStr(stdout_buf, '    NASM - Version: ');
    bufWriteStrLn(stdout_buf, core.version.NASM_VERSION);
    bufWriteStr(stdout_buf, '    FPC  - Version: ');
    bufWriteStrLn(stdout_buf, core.version.FPC_VERSION);
    bufWriteStr(stdout_buf, '    MAKE - Version: ');
    bufWriteStrLn(stdout_buf, core.version.MAKE_VERSION);
    bufWriteStr(stdout_buf, '  ');
    bufWriteInt(stdout_buf, core.version.LINE_COUNT);
    bufWriteStr(stdout_buf, ' lines, across ');
    bufWriteInt(stdout_buf, core.version.FILE_COUNT);
    bufWriteStrLn(stdout_buf, ' files.');
    bufWriteStr(stdout_buf, '  Baked Drivers: ');
    bufWriteIntLn(stdout_buf, core.version.DRIVER_COUNT);
    bufWriteStr(stdout_buf, '  Checksum: ');
    bufWriteStrLn(stdout_buf, core.version.CHECKSUM);
end;

procedure cmd_echo(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    current: PParamList;
begin
    current := params^.next;
    while (current <> nil) and (current^.param <> nil) do begin
        bufWriteStr(stdout_buf, current^.param);
        bufWriteChar(stdout_buf, ' ');
        current := current^.next;
    end;
    bufWriteNewLine(stdout_buf);
end;

procedure cmd_clear(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
begin
    { ANSI clear screen: ESC[2J ESC[H }
    bufWriteChar(stdout_buf, #27);
    bufWriteStr(stdout_buf, '[2J');
    bufWriteChar(stdout_buf, #27);
    bufWriteStr(stdout_buf, '[H');
end;

procedure cmd_help(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    i, j: uint32;
    longestCommand: uint32;
    len: uint32;
    cmd: PCommand;
begin
    longestCommand := 0;
    for i := 0 to CmdCount - 1 do begin
        cmd := getCmdPtr(i);
        if cmd^.registered and not cmd^.hidden then begin
            len := stringSize(cmd^.command);
            if len > longestCommand then longestCommand := len;
        end;
    end;
    bufWriteStrLn(stdout_buf, 'Registered Commands: ');
    for i := 0 to CmdCount - 1 do begin
        cmd := getCmdPtr(i);
        if cmd^.registered and not cmd^.hidden then begin
            bufWriteStr(stdout_buf, '  ');
            bufWriteStr(stdout_buf, cmd^.command);
            len := longestCommand - stringSize(cmd^.command);
            for j := 0 to len do
                bufWriteChar(stdout_buf, ' ');
            bufWriteStr(stdout_buf, '- ');
            bufWriteStrLn(stdout_buf, cmd^.description);
        end;
    end;
end;

procedure cmd_time(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    dt: TDateTime;
begin
    dt := getDateTime;
    if dt.Day < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteInt(stdout_buf, dt.Day);
    bufWriteChar(stdout_buf, '/');
    if dt.Month < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteInt(stdout_buf, dt.Month);
    bufWriteChar(stdout_buf, '/');
    bufWriteInt(stdout_buf, dt.Century);
    bufWriteInt(stdout_buf, dt.Year);
    bufWriteChar(stdout_buf, ' ');
    if dt.Hours < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteInt(stdout_buf, dt.Hours);
    bufWriteChar(stdout_buf, ':');
    if dt.Minutes < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteInt(stdout_buf, dt.Minutes);
    bufWriteChar(stdout_buf, ':');
    if dt.Seconds < 10 then bufWriteChar(stdout_buf, '0');
    bufWriteIntLn(stdout_buf, dt.Seconds);
    bufWriteStr(stdout_buf, 'Weekday: ');
    bufWriteStrLn(stdout_buf, WeekdayToString(dt.Weekday));
end;

procedure cmd_reboot(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
begin
    resetSystem;
end;

{ ---- Initialization ---- }

procedure init;
begin
    { Allocate initial command array }
    CmdCap := INITIAL_CMD_CAP;
    CmdCount := 0;
    Commands := PCommand(kalloc(CmdCap * SizeOf(TCommand)));
    memset(uint32(Commands), 0, CmdCap * SizeOf(TCommand));

    Halted := false;
    HaltID := 0;
    HaltCB := nil;

    { Register built-in commands }
    registerCommand('VERSION', @cmd_version, 'Display the running version of Asuro.');
    registerCommand('CLEAR', @cmd_clear, 'Clear the Screen.');
    registerCommand('HELP', @cmd_help, 'Lists all registered commands and their description.');
    registerCommand('ECHO', @cmd_echo, 'Echo''s text to the terminal.');
    registerCommand('TIME', @cmd_time, 'Print the current time.');
    registerCommand('REBOOT', @cmd_reboot, 'Reboot the system.');

    io.syslog.logln('STDIO', 'Initialized.');
end;

end.
