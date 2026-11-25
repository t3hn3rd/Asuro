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
function unsignedRemainder(d, n: qword): qword; external name 'FPC_MOD_QWORD';
function signedProduct(a, b: int64): int64; external name 'FPC_MUL_INT64';

procedure testCompilerRuntime(var ctx: TTestContext);
var
    number: ^uint64;
    buf: jmp_buf;
    source: string[8];
    short: string[3];
    code: longint;
    bytes: SizeUInt;
    saved: PtrUInt;
    function moveResultMatches: boolean;
    begin
        moveResultMatches := (length(source) = 6) and
            (source[1] = 'b') and (source[2] = 'c') and (source[3] = 'd') and
            (source[4] = 'e') and (source[5] = 'e') and (source[6] = 'f');
    end;
begin
    saved := arch.platform.cpu.lock;
    bytes := lmm_total_free;
    system.new(number);
    number^ := $100000001;
    test.harness.Assert(@ctx, number^ = $100000001, 'New preserves 64-bit value');
    dispose(number);
    test.harness.Assert(@ctx, lmm_total_free = bytes, 'Dispose restores free bytes');
    arch.platform.cpu.unlock(saved);
    source := 'abcdef';
    short := source;
    test.harness.Assert(@ctx, (length(short) = 3) and (short[3] = 'c'), 'Short string truncation');
    system.move(source[1], source[2], 4);
    test.harness.Assert(@ctx, source[5] = 'd', 'Backward overlapping move');
    source := 'abcdef';
    system.move(source[2], source[1], 4);
    test.harness.Assert(@ctx, moveResultMatches, 'Move overlapping bytes toward lower addresses');
    system.move(source[1], source[2], 0);
    system.move(source[1], source[2], -1);
    system.move(source[1], source[1], length(source));
    test.harness.Assert(@ctx, moveResultMatches, 'Move preserves bytes for empty and identical ranges');
    source := '';
    short := source;
    test.harness.Assert(@ctx, length(short) = 0, 'Empty short string clears destination length');
    code := saveJump(buf);
    if code = 0 then restoreJump(buf, 42);
    test.harness.Assert(@ctx, code = 42, 'Longjmp preserves return value');
    code := saveJump(buf);
    if code = 0 then restoreJump(buf, 0);
    test.harness.Assert(@ctx, code = 1, 'Longjmp maps zero to one');
    test.harness.Assert(@ctx, signedProduct(-3, $100000001) = -12884901891, 'Signed multiply preserves upper bits');
    test.harness.Assert(@ctx, signedDivide(-3, 10) = -3, 'Signed division with negative divisor');
    test.harness.Assert(@ctx, signedRemainder(-3, 10) = 1, 'Signed remainder follows dividend sign');
    test.harness.Assert(@ctx, unsignedDivide(uint64($8000000000000000), High(qword)) = 1,
                 'Unsigned division with high-bit divisor');
    test.harness.Assert(@ctx, unsignedRemainder(uint64($8000000000000000), High(qword)) = $7FFFFFFFFFFFFFFF,
                 'Unsigned remainder with high-bit divisor');
    test.harness.Assert(@ctx, signedDivide(3, -10) = -3, 'Signed division truncates toward zero');
    test.harness.Assert(@ctx, signedRemainder(3, -10) = -1, 'Negative dividend remainder');
    test.harness.Assert(@ctx, unsignedDivide(2, $200000002) = $100000001, 'Wide quotient');
    test.harness.Assert(@ctx, wideProduct($FFFFFFFF, 2) = $1FFFFFFFE, 'Wide product');
    test.harness.Assert(@ctx, Round(2.75) = 3, 'Round positive fraction');
    test.harness.Assert(@ctx, Trunc(-2.75) = -2, 'Truncate negative fraction');
end;
