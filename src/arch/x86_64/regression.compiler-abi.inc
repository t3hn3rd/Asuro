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

function saveJump(var state: jmp_buf): longint; external name 'FPC_SETJMP';
procedure restoreJump(var state: jmp_buf; value: longint); external name 'FPC_LONGJMP';
function signedDivide(d, n: int64): int64; external name 'FPC_DIV_INT64';
function signedRemainder(d, n: int64): int64; external name 'FPC_MOD_INT64';
function unsignedDivide(d, n: qword): qword; external name 'FPC_DIV_QWORD';
function wideProduct(a, b: uint32): qword; external name 'FPC_MUL_DWORD_TO_QWORD';

procedure testCompilerRuntime;
var
    number: ^uint64;
    buf: jmp_buf;
    source: string[8];
    short: string[3];
    code: longint;
    bytes: SizeUInt;
begin
    bytes := lmm_total_free;
    system.new(number);
    number^ := $100000001;
    if number^ <> $100000001 then bootstrap_halt;
    dispose(number);
    if lmm_total_free <> bytes then bootstrap_halt;
    source := 'abcdef';
    short := source;
    if (length(short) <> 3) or (short[3] <> 'c') then bootstrap_halt;
    system.move(source[1], source[2], 4);
    if source[5] <> 'd' then bootstrap_halt;
    code := saveJump(buf);
    if code = 0 then restoreJump(buf, 42);
    if code <> 42 then bootstrap_halt;
    if (signedDivide(3, -10) <> -3) or (signedRemainder(3, -10) <> -1) or
       (unsignedDivide(2, $200000002) <> $100000001) or
       (wideProduct($FFFFFFFF, 2) <> $1FFFFFFFE) or
       (Round(2.75) <> 3) or (Trunc(-2.75) <> -2) then bootstrap_halt;
    puts('PASS: native FPC compiler runtime'#13#10);
end;
