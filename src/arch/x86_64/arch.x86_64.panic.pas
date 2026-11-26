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

unit arch.x86_64.panic;

interface
uses arch.x86_64.context;
procedure panic(reason, detail: pchar; frame: PFrame);

implementation
uses debug.early, debug.tracer, driver.video, driver.video.types, core.gfx.fonts;

var active: boolean;

{ IRQs are masked. Use only the live front buffer, including for gfxd faults. }
procedure panic(reason, detail: pchar; frame: PFrame);
const digits: array[0..15] of char = '0123456789ABCDEF';
var fb: PVideoBuffer;
    x, y, row, col, i: uint32;
    pixels: PUInt32;
    trace: pchar;

    procedure writeText(s: pchar);
    var r, c: uint32;
        bits: uint8;
        line: PUInt32;
    begin
        if (s = nil) or (y + 16 > fb^.Height) then exit;
        while (s^ <> #0) and (x + 8 <= fb^.Width) do begin
            for r := 0 to 15 do begin
                bits := Std_Font[ord(s^) * 16 + r];
                line := PUInt32(fb^.Location + SizeUInt(y + r) * fb^.Pitch) + x;
                for c := 0 to 7 do
                    if (bits and ($80 shr c)) <> 0 then line[c] := $FFFFFF;
            end;
            inc(x, 8);
            inc(s);
        end;
    end;

    procedure newline;
    begin
        x := 8;
        inc(y, 18);
    end;

    procedure reg(name: pchar; value: uint64);
    var buf: array[0..16] of char;
        n: sint32;
    begin
        for n := 15 downto 0 do begin
            buf[n] := digits[value and 15];
            value := value shr 4;
        end;
        buf[16] := #0;
        writeText(name);
        writeText(@buf[0]);
        newline;
    end;

begin
    asm cli end;
    if active then bootstrap_halt;
    active := true;
    debug.tracer.freeze;
    puts('PANIC: '); puts(reason); puts(' '); puts(detail); puts(#13#10);
    fb := frontBufferInfo;
    if fb^.Initialized and (fb^.Location <> 0) and (fb^.BitsPerPixel = 32) and
       (fb^.Width > 0) and (fb^.Height > 0) and (uint64(fb^.Width) * 4 <= fb^.Pitch) then begin
        for row := 0 to fb^.Height - 1 do begin
            pixels := PUInt32(fb^.Location + SizeUInt(row) * fb^.Pitch);
            for col := 0 to fb^.Width - 1 do pixels[col] := $702828;
        end;
        x := 8; y := 8;
        writeText('Asuro kernel panic'); newline;
        writeText(reason); newline;
        writeText(detail); newline;
        if frame <> nil then begin
            reg('VECTOR  ', frame^.vector);
            reg('ERROR   ', frame^.error);
            reg('RIP     ', frame^.rip);
            reg('RSP     ', frame^.rsp);
            reg('CR2     ', frame^.cr2);
        end;
        newline;
        writeText('Recent trace entries'); newline;
    end else fb := nil;
    i := 0;
    while i < debug.tracer.get_trace_count do begin
        trace := debug.tracer.get_trace_N(i);
        if trace = nil then break;
        puts('TRACE: '); puts(trace); puts(#13#10);
        if fb <> nil then begin writeText(trace); newline end;
        inc(i);
    end;
    bootstrap_halt;
end;
end.
