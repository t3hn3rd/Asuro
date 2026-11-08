// Copyright 2026 Aaron Hance
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
    io.types, memory.heap, core.strings, core.util;

type
    POutBuf = io.types.POutBuf;
    TOutBuf = io.types.TOutBuf;
    PParamList = io.types.PParamList;
    TParamList = io.types.TParamList;
    TCommandBuffer = io.types.TCommandBuffer;
    TCommandMethod = io.types.TCommandMethod;
    PCommand = io.types.PCommand;
    TCommand = io.types.TCommand;
    THaltCallback = io.types.THaltCallback;

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


{ Halt mechanism for async commands }
function  halt(id: uint32; cb: THaltCallback): boolean;
function  done(id: uint32): boolean;

var
    Halted   : boolean;
    HaltID   : uint32;
    HaltCB   : THaltCallback;

{ Initialization }
procedure init;
procedure UnitTest;

implementation

uses
    arch.platform.diagnostics, arch.platform.cpu;

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
    createOutBuf := nil;
    if ob = nil then exit;
    ob^.buf := pchar(kalloc(cap));
    if ob^.buf = nil then begin
        kfree(void(ob));
        exit;
    end;
    ob^.len := 0;
    ob^.cap := cap;
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

function bufGrow(buf: POutBuf; needed: uint32): boolean;
var
    newCap, required: uint32;
    newBuf: pchar;
begin
    bufGrow := false;
    if needed >= high(uint32) - buf^.len then exit;
    required := buf^.len + needed + 1;
    if required <= buf^.cap then begin
        bufGrow := true;
        exit;
    end;
    newCap := buf^.cap;
    if newCap = 0 then newCap := 64;
    while newCap < required do begin
        if newCap > high(uint32) div 2 then begin
            newCap := required;
            break;
        end;
        newCap := newCap * 2;
    end;
    newBuf := pchar(kalloc(newCap));
    if newBuf = nil then exit;
    memcpy(PtrUInt(buf^.buf), PtrUInt(newBuf), buf^.len);
    newBuf[buf^.len] := #0;
    kfree(void(buf^.buf));
    buf^.buf := newBuf;
    buf^.cap := newCap;
    bufGrow := true;
end;

procedure bufWriteChar(buf: POutBuf; c: char);
begin
    if buf = nil then exit;
    if not bufGrow(buf, 1) then exit;
    buf^.buf[buf^.len] := c;
    Inc(buf^.len);
    buf^.buf[buf^.len] := #0;
end;

procedure bufWriteStr(buf: POutBuf; s: pchar);
var
    len, offset: uint32;
    aliases: boolean;
begin
    if (buf = nil) or (s = nil) then exit;
    len := stringSize(s);
    { A source inside the buffer must follow it if growth relocates storage. }
    aliases := (PtrUInt(s) >= PtrUInt(buf^.buf)) and
               (PtrUInt(s) - PtrUInt(buf^.buf) < buf^.cap);
    offset := 0;
    if aliases then offset := PtrUInt(s) - PtrUInt(buf^.buf);
    if not bufGrow(buf, len) then exit;
    if aliases then s := buf^.buf + offset;
    memcpy(PtrUInt(s), PtrUInt(buf^.buf + buf^.len), len);
    inc(buf^.len, len);
    buf^.buf[buf^.len] := #0;
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
function growCommands: boolean;
var
    newCap: uint32;
    newArr: PCommand;
begin
    growCommands := false;
    if CmdCap > high(uint32) div sizeof(TCommand) div 2 then exit;
    if CmdCap = 0 then newCap := INITIAL_CMD_CAP else newCap := CmdCap * 2;
    newArr := PCommand(kalloc(newCap * sizeof(TCommand)));
    if newArr = nil then exit;
    memcpy(PtrUInt(Commands), PtrUInt(newArr), CmdCount * sizeof(TCommand));
    kfree(void(Commands));
    Commands := newArr;
    CmdCap := newCap;
    growCommands := true;
end;

function getCmdPtr(index: uint32): PCommand; inline;
begin
    getCmdPtr := PCommand(PtrUInt(Commands) + index * SizeOf(TCommand));
end;

procedure registerCommand(command: pchar; method: TCommandMethod; description: pchar);
begin
    registerCommandEx(command, method, description, false);
end;

procedure registerCommandEx(command: pchar; method: TCommandMethod; description: pchar; hide: boolean);
var
    cmd: PCommand;
begin
    if (command = nil) or (method = nil) then exit;
    if CmdCount >= CmdCap then if not growCommands then exit;
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
begin
    findCommand := nil;
    if (name = nil) or (CmdCount = 0) then exit;
    for i := 0 to CmdCount - 1 do begin
        cmd := getCmdPtr(i);
        if cmd^.registered and stringEqualsCI(name, cmd^.command) then begin
            findCommand := cmd;
            exit;
        end;
    end;
end;

{ ---- Parameter parsing ---- }
function getParams(var buf: TCommandBuffer): PParamList;
var
    start, finish, size: uint32;
    root, current: PParamList;
begin
    getParams := nil;
    root := PParamList(kalloc(SizeOf(TParamList)));
    if root = nil then exit;
    current := root;
    current^.next := nil;
    current^.Param := nil;
    finish := 0;
    while finish < sizeof(buf) do begin
        while (finish < sizeof(buf)) and (buf[finish] = ord(' ')) do inc(finish);
        if finish = sizeof(buf) then break;
        if buf[finish] = 0 then break;
        start := finish;
        while (finish < sizeof(buf)) and (buf[finish] <> ord(' ')) and
              (buf[finish] <> 0) do inc(finish);
        size := finish - start;
        current^.Param := stringNew(size);
        if current^.Param = nil then begin
            freeParams(root);
            exit;
        end;
        memcpy(PtrUInt(@buf[start]), PtrUInt(current^.Param), size);
        current^.next := PParamList(kalloc(SizeOf(TParamList)));
        if current^.next = nil then begin
            freeParams(root);
            exit;
        end;
        current := current^.next;
        current^.next := nil;
        current^.Param := nil;
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
        if search = nil then begin
            getParam := nil;
            exit;
        end;
        if search^.next = nil then begin
            getParam := nil;
            exit;
        end;
        search := search^.next;
    end;
    getParam := search^.param;
end;


{ ---- Halt mechanism ---- }
function halt(id: uint32; cb: THaltCallback): boolean;
var
    flags: PtrUInt;
begin
    flags := arch.platform.cpu.lock;
    halt := not Halted;
    if not Halted then begin
        HaltID := id;
        HaltCB := cb;
        Halted := true;
    end;
    arch.platform.cpu.unlock(flags);
end;

function done(id: uint32): boolean;
var
    flags: PtrUInt;
    callback: THaltCallback;
begin
    flags := arch.platform.cpu.lock;
    done := Halted and (id = HaltID);
    callback := nil;
    if done then begin
        callback := HaltCB;
        HaltCB := nil;
        Halted := false;
        HaltID := 0;
    end;
    arch.platform.cpu.unlock(flags);
    if callback <> nil then callback();
end;

{ ---- Built-in commands ---- }


procedure cmd_echo(params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
var
    current: PParamList;
begin
    if params = nil then exit;
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
    if CmdCount = 0 then exit;
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


var
    testCallbackCount: uint32;
    testCallbackReentered: boolean;

procedure testHaltCallback;
begin
    inc(testCallbackCount);
    testCallbackReentered := (not done(41)) and halt(42, nil);
end;

{ Tests use an isolated command registry; production registrations are restored. }
procedure UnitTest;
type PCommandBuffer = ^TCommandBuffer;
var
    input: PCommandBuffer;
    params: PParamList;
    output: POutBuf;
    oldCommands: PCommand;
    oldHalted: boolean;
    oldHaltID: uint32;
    oldHaltCB: THaltCallback;
    oldCount, oldCap, i, passed, failed: uint32;
    beforeFree: SizeUInt;

    procedure Assert(condition: boolean; name: pchar);
    begin
        if condition then inc(passed) else begin
            inc(failed);
            arch.platform.diagnostics.log('STDIO FAIL', name);
        end;
    end;
begin
    passed := 0;
    failed := 0;
    beforeFree := lmm_total_free;
    oldHalted := Halted;
    oldHaltID := HaltID;
    oldHaltCB := HaltCB;
    Halted := false;
    HaltID := 0;
    HaltCB := nil;
    testCallbackCount := 0;
    testCallbackReentered := false;
    Assert(halt(41, @testHaltCallback) and not halt(42, nil), 'halt reserves one owner');
    Assert(not done(42) and Halted, 'wrong completion preserves halt owner');
    Assert(done(41) and (testCallbackCount = 1) and testCallbackReentered and
           Halted and (HaltID = 42), 'completion detaches before callback reentry');
    Assert(done(42) and not done(42), 'completion releases exactly once');
    Halted := oldHalted;
    HaltID := oldHaltID;
    HaltCB := oldHaltCB;
    oldCommands := Commands;
    oldCount := CmdCount;
    oldCap := CmdCap;
    Commands := nil;
    CmdCount := 0;
    CmdCap := 0;
    Assert(findCommand('missing') = nil, 'empty registry lookup');
    for i := 0 to 69 do registerCommand('ECHO', @cmd_echo, 'test');
    Assert((getCommandCount = 70) and (getCommand(69) <> nil) and
           (getCommand(70) = nil), 'registry growth and bounds');
    Assert(findCommand('echo') = getCommand(0), 'case-insensitive command lookup');
    output := createOutBuf(1);
    input := PCommandBuffer(kalloc(sizeof(TCommandBuffer)));
    if (output <> nil) and (input <> nil) then begin
        bufWriteStr(output, 'grow');
        bufWriteStr(output, output^.buf);
        Assert(stringEquals(output^.buf, 'growgrow'), 'self append across buffer relocation');
        bufClear(output);
        bufWriteInt(output, low(integer));
        Assert(stringEquals(output^.buf, '-2147483648'), 'signed integer formatting');
        bufClear(output);
        bufWriteHex(output, $89ABCDEF);
        Assert(stringEquals(output^.buf, '0x89ABCDEF'), 'hexadecimal formatting');
        bufClear(output);
        memset(PtrUInt(input), 0, sizeof(TCommandBuffer));
        memcpy(PtrUInt(pchar('echo  one two')), PtrUInt(input), 13);
        params := getParams(input^);
        Assert((paramCount(params) = 2) and stringEquals(getParam(1, params), 'two') and
               (getParam(2, params) = nil), 'parser terminates at final token');
        findCommand('EcHo')^.method(params, nil, output, nil);
        Assert(stringEquals(output^.buf, 'one two '#10), 'registered ECHO dispatch');
        freeParams(params);
        memset(PtrUInt(input), ord('x'), sizeof(TCommandBuffer));
        params := getParams(input^);
        Assert((params <> nil) and (stringSize(params^.param) = sizeof(TCommandBuffer)),
               'parser bounded without terminator');
        freeParams(params);
        memset(PtrUInt(input), ord(' '), sizeof(TCommandBuffer));
        input^[1023] := ord('z');
        params := getParams(input^);
        Assert((params <> nil) and stringEquals(params^.param, 'z'), 'parser final byte');
        freeParams(params);
        input^[0] := 0;
        params := getParams(input^);
        Assert((paramCount(params) = 0) and (getParam(0, params) = nil), 'empty parameters');
        freeParams(params);
        Assert(getParam(0, nil) = nil, 'nil parameter lookup');
    end else Assert(false, 'stdio test allocation');
    freeOutBuf(output);
    kfree(void(input));
    kfree(void(Commands));
    Commands := oldCommands;
    CmdCount := oldCount;
    CmdCap := oldCap;
    Assert(lmm_total_free = beforeFree, 'stdio allocation ownership restored');
    arch.platform.diagnostics.testSummary('STDIO', 'STDIO_TESTS_PASSED', 'STDIO_TESTS_FAILED', passed, failed);
end;

{ ---- Initialization ---- }
procedure init;
begin
    if Commands <> nil then exit;
    if not growCommands then exit;
    UnitTest;

    Halted := false;
    HaltID := 0;
    HaltCB := nil;

    { Register built-in commands }
        registerCommand('CLEAR', @cmd_clear, 'Clear the Screen.');
    registerCommand('HELP', @cmd_help, 'Lists all registered commands and their description.');
    registerCommand('ECHO', @cmd_echo, 'Echo''s text to the terminal.');
    end;


end.
