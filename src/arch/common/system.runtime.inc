// Copyright 2021 Kieron Morris & Aaron Hance
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

{ Move memory block — minimal implementation needed by shortstr_assign }
procedure move(const source; var dest; count: SizeInt);
    [public, alias: 'FPC_MOVE'];
var
    i: SizeInt;
    s, d: PuInt8;
begin
    if count <= 0 then exit;
    s := @source;
    d := @dest;
    if SizeUInt(d) > SizeUInt(s) then begin
        { Copy backward to handle overlap }
        for i := count - 1 downto 0 do
            d[i] := s[i];
    end else begin
        for i := 0 to count - 1 do
            d[i] := s[i];
    end;
end;

procedure fpc_handleerror(errno: longint); [public, alias: 'FPC_HANDLEERROR']; compilerproc;
begin
    HandleErrorInternal(errno);
end;

procedure fpc_rangeerror; [public, alias: 'FPC_RANGEERROR']; compilerproc;
begin
    HandleErrorInternal(201);
end;

procedure fpc_overflow; [public, alias: 'FPC_OVERFLOW']; compilerproc;
begin
    HandleErrorInternal(215);
end;

procedure fpc_divbyzero; [public, alias: 'FPC_DIVBYZERO']; compilerproc;
begin
    HandleErrorInternal(200);
end;

procedure fpc_objecterror; [public, alias: 'FPC_OBJECTERROR']; compilerproc;
begin
    HandleErrorInternal(210);
end;

procedure fpc_abstracterror; [public, alias: 'FPC_ABSTRACTERROR']; compilerproc;
begin
    HandleErrorInternal(211);
end;

procedure fpc_stackcheck(stack_size: SizeUInt); [public, alias: 'FPC_STACKCHECK']; compilerproc;
begin
    { No stack checking on bare metal }
end;

procedure fpc_iocheck; [public, alias: 'FPC_IOCHECK']; compilerproc;
begin
    { No IO error checking on bare metal }
end;

function fpc_pushexceptaddr(ft: longint; _buf: PJmp_buf; var newaddr: TExceptAddr): PJmp_buf;
    [public, alias: 'FPC_PUSHEXCEPTADDR']; compilerproc;
begin
    newaddr.buf := _buf;
    newaddr.next := ExceptAddrStack;
    newaddr.frametype := ft;
    ExceptAddrStack := @newaddr;
    fpc_pushexceptaddr := _buf;
end;

procedure fpc_popaddrstack; [public, alias: 'FPC_POPADDRSTACK']; compilerproc;
begin
    if ExceptAddrStack <> nil then
        ExceptAddrStack := ExceptAddrStack^.next;
end;

procedure copyShortString(capacity: longint; source, dest: PuInt8);
var
    count: byte;
begin
    count := source^;
    if capacity < 0 then count := 0
    else if count > capacity then count := capacity;
    move(source^, dest^, SizeInt(count) + 1);
    dest^ := count;
end;

procedure fpc_shortstr_to_shortstr(var dest: OpenString; const source: ShortString);
    [public, alias: 'FPC_SHORTSTR_TO_SHORTSTR']; compilerproc;
begin
    copyShortString(high(dest), @source[0], @dest[0]);
end;

procedure fpc_shortstr_assign(len: longint; sstr, dstr: Pointer);
    [public, alias: 'FPC_SHORTSTR_ASSIGN']; compilerproc;
begin
    copyShortString(len, sstr, dstr);
end;

{ ---------- Memory allocation compilerprocs ---------- }
function kernel_kalloc(size: PtrUInt): Pointer; external name 'kernel_kalloc';

procedure kernel_kfree(p: Pointer); external name 'kernel_kfree';

function fpc_getmem(size: PtrUInt): Pointer;
    [public, alias: 'FPC_GETMEM']; compilerproc;
begin
    fpc_getmem := kernel_kalloc(size);
end;

procedure fpc_freemem(p: Pointer);
    [public, alias: 'FPC_FREEMEM']; compilerproc;
begin
    kernel_kfree(p);
end;

{ ---------- Exception handling compilerprocs ---------- }
procedure fpc_reraise; [public, alias: 'FPC_RERAISE']; compilerproc;
begin
    { In a bare-metal core.version re-raise is a fatal condition }
    HandleErrorInternal(217);
end;

procedure fpc_raiseexception(obj: Pointer; anaddr, aframe: Pointer);
    [public, alias: 'FPC_RAISEEXCEPTION']; compilerproc;
begin
    HandleErrorInternal(217);
end;

function fpc_catches(obj: Pointer; t: Pointer): Pointer;
    [public, alias: 'FPC_CATCHES']; compilerproc;
begin
    fpc_catches := nil;
end;

procedure fpc_doneexception; [public, alias: 'FPC_DONEEXCEPTION']; compilerproc;
begin
    { nothing to do in bare-metal context }
end;
