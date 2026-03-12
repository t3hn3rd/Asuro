{
    Syslog - Kernel logging with multi-hook fan-out.

    All core.version/driver logging goes through this unit. Output is dispatched
    to all registered hooks (driver.io.serial, file, debug panel, etc.) simultaneously.
    Replaces the logging portion of the old console.pas.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit io.syslog;

interface

uses
    boot.mgr;

type
    TLogHook = procedure(msg: pchar);

{ Hook management }
function  registerHook(hook: TLogHook): boolean;
procedure removeHook(hook: TLogHook);

{ Core logging }
procedure logChar(c: char);
procedure logFlush;

{ Convenience — mirror the old console logging API }
procedure log(identifier: pchar; str: pchar);
procedure logln(identifier: pchar; str: pchar);
procedure writestring(str: pchar);
procedure writestringln(str: pchar);
procedure writeint(i: integer);
procedure writeintln(i: integer);
procedure writehexpair(b: uint8);
procedure writehex(i: uint32);
procedure writehexln(i: uint32);
procedure writebin8(b: uint8);
procedure writebin8ln(b: uint8);
procedure writebin16(b: uint16);
procedure writebin16ln(b: uint16);
procedure writebin32(b: uint32);
procedure writebin32ln(b: uint32);

{ Initialization — registers driver.io.serial as default hook }
procedure init;

implementation

uses
    driver.io.serial, core.strings;

const
    MAX_HOOKS = 8;
    LINE_BUF_SIZE = 256;

var
    Hooks       : array[0..MAX_HOOKS-1] of TLogHook;
    HookCount   : uint32 = 0;
    LineBuf     : array[0..LINE_BUF_SIZE-1] of char;
    LinePos     : uint32 = 0;
    Initialized : boolean = false;

{ ---- Hook management ---- }

function registerHook(hook: TLogHook): boolean;
begin
    registerHook := false;
    if HookCount < MAX_HOOKS then begin
        Hooks[HookCount] := hook;
        Inc(HookCount);
        registerHook := true;
    end;
end;

procedure removeHook(hook: TLogHook);
var
    i, j: uint32;
begin
    if HookCount = 0 then exit;
    for i := 0 to HookCount - 1 do begin
        if Hooks[i] = hook then begin
            for j := i to HookCount - 2 do
                Hooks[j] := Hooks[j + 1];
            Dec(HookCount);
            Hooks[HookCount] := nil;
            exit;
        end;
    end;
end;

procedure dispatchLine;
var
    i: uint32;
begin
    if LinePos = 0 then exit;
    { Null-terminate }
    if LinePos < LINE_BUF_SIZE then
        LineBuf[LinePos] := #0
    else
        LineBuf[LINE_BUF_SIZE - 1] := #0;
    { Send to all hooks }
    if HookCount > 0 then begin
        for i := 0 to HookCount - 1 do begin
            if Hooks[i] <> nil then
                Hooks[i](@LineBuf[0]);
        end;
    end;
    LinePos := 0;
end;

{ ---- Core logging ---- }

procedure logChar(c: char);
begin
    { Also send each char to driver.io.serial directly for immediate byte-level output }
    if not Initialized then exit;  { Avoid calling driver.io.serial before it's ready }
    driver.io.serial.send(COM1, uint8(c), 10000);
    if c = #10 then begin
        dispatchLine;
    end else if c <> #13 then begin
        if LinePos < LINE_BUF_SIZE - 1 then begin
            LineBuf[LinePos] := c;
            Inc(LinePos);
        end;
    end;
end;

procedure logFlush;
begin
    dispatchLine;
end;

{ ---- Convenience functions ---- }

procedure writestring(str: pchar);
var
    i: uint32;
begin
    if str = nil then exit;
    i := 0;
    while str[i] <> #0 do begin
        logChar(str[i]);
        Inc(i);
    end;
end;

procedure writestringln(str: pchar);
begin
    writestring(str);
    logChar(#13);
    logChar(#10);
end;

procedure log(identifier: pchar; str: pchar);
begin
    writestring('[');
    writestring(identifier);
    writestring('] ');
    writestring(str);
end;

procedure logln(identifier: pchar; str: pchar);
begin
    log(identifier, str);
    logChar(#13);
    logChar(#10);
end;

procedure writeint(i: integer);
var
    buffer: array[0..11] of char;
    p: uint32;
    digit: uint32;
    minus: boolean;
begin
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
    writestring(@buffer[p]);
end;

procedure writeintln(i: integer);
begin
    writeint(i);
    logChar(#13);
    logChar(#10);
end;

procedure writehexpair(b: uint8);
const
    HexDigits: array[0..15] of char = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
begin
    logChar(HexDigits[b SHR 4]);
    logChar(HexDigits[b AND $0F]);
end;

procedure writehex(i: uint32);
begin
    writestring('0x');
    writehexpair(uint8(i SHR 24));
    writehexpair(uint8((i SHR 16) AND $FF));
    writehexpair(uint8((i SHR 8) AND $FF));
    writehexpair(uint8(i AND $FF));
end;

procedure writehexln(i: uint32);
begin
    writehex(i);
    logChar(#13);
    logChar(#10);
end;

procedure writebin8(b: uint8);
var
    i: uint8;
begin
    for i := 7 downto 0 do begin
        if (b AND (1 SHL i)) <> 0 then
            logChar('1')
        else
            logChar('0');
    end;
end;

procedure writebin8ln(b: uint8);
begin
    writebin8(b);
    logChar(#13);
    logChar(#10);
end;

procedure writebin16(b: uint16);
begin
    writebin8(uint8(b SHR 8));
    writebin8(uint8(b AND $FF));
end;

procedure writebin16ln(b: uint16);
begin
    writebin16(b);
    logChar(#13);
    logChar(#10);
end;

procedure writebin32(b: uint32);
begin
    writebin16(uint16(b SHR 16));
    writebin16(uint16(b AND $FFFF));
end;

procedure writebin32ln(b: uint32);
begin
    writebin32(b);
    logChar(#13);
    logChar(#10);
end;

{ ---- Serial hook adapter ---- }

procedure serialHook(msg: pchar);
begin
    { driver.io.serial.sendString already sends CR+LF, but our dispatchLine sends
      the raw line without CR+LF, so sendString is appropriate here. }
    driver.io.serial.sendString(msg);
end;

{ ---- Initialization ---- }

procedure init;
var
    i: uint32;
begin
    for i := 0 to MAX_HOOKS - 1 do
        Hooks[i] := nil;
    HookCount := 0;
    LinePos := 0;
    Initialized:= true;
    { Note: We don't register serialHook here because logChar already sends
      each character to driver.io.serial directly. The hook system is for line-level
      consumers (file logging, debug panels, etc.) that want complete lines.
      If we registered serialHook, driver.io.serial would get double output. }
end;

initialization
    boot.mgr.registerBoot('io.syslog', @init, 'Syslog Interface', 'driver.io.serial');

end.
