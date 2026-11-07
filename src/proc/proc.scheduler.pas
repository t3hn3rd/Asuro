// Copyright 2026 Aaron Hance
// Copyright 2026 Kieron Morris
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

{ Shared round-robin/quantum policy extracted from proc.mgr (Kieron Morris).
  Caller excludes interrupts and owns process lifetime/reaping. }
unit proc.scheduler;
interface
uses proc.types;
type TGetProcess = function(index: uint32): PProcessContext;
function pickNext(current, idle: PProcessContext; count: uint32;
                  var cursor: uint32; getProcess: TGetProcess): PProcessContext;
implementation
function pickNext(current, idle: PProcessContext; count: uint32;
                  var cursor: uint32; getProcess: TGetProcess): PProcessContext;
var
    i       : uint32;
    idx     : uint32;
    ctx     : PProcessContext;
begin
    { Check if current process still has quantum left }
    if (current <> nil) and (current^.State = psRunning) then begin
        current^.TicksUsed := current^.TicksUsed + 1;
        if current^.TicksUsed < current^.Quantum then begin
            pickNext := current;
            exit;
        end;
        { Quantum expired, move to ready }
        current^.State := psReady;
        current^.TicksUsed := 0;
    end;

    { Round-robin: scan from cursor, skipping idle }
    if cursor >= count then
        cursor := 0;

    if count > 0 then for i := 0 to count - 1 do begin
        idx := (cursor + i) mod count;
        ctx := getProcess(idx);
        if ctx = nil then continue;
        if ctx^.ProcessID = 0 then continue;  { Skip idle in round-robin }
        if (ctx^.State = psReady) or (ctx^.State = psCreated) then begin
            ctx^.State := psRunning;
            ctx^.TicksUsed := 0;
            cursor := (idx + 1) mod count;
            pickNext := ctx;
            exit;
        end;
    end;

    { No runnable process found — fall back to idle }
    if idle = nil then begin pickNext := nil; exit; end;
    idle^.State := psRunning;
    idle^.TicksUsed := 0;
    pickNext := idle;
end;

end.
