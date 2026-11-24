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

procedure fpc_initializeunits; compilerproc;
procedure fpc_do_exit; compilerproc;
procedure fpc_handleerror(errno: longint); compilerproc;
procedure fpc_rangeerror; compilerproc;
procedure fpc_overflow; compilerproc;
procedure fpc_divbyzero; compilerproc;
procedure fpc_objecterror; compilerproc;
procedure fpc_abstracterror; compilerproc;
procedure fpc_stackcheck(stack_size: SizeUInt); compilerproc;
procedure fpc_iocheck; compilerproc;
function fpc_pushexceptaddr(ft: longint; _buf: PJmp_buf; var newaddr: TExceptAddr): PJmp_buf; compilerproc;
procedure fpc_popaddrstack; compilerproc;
function fpc_setjmp(var s: jmp_buf): longint; compilerproc;
procedure fpc_longjmp(var s: jmp_buf; value: longint); compilerproc;
procedure fpc_shortstr_to_shortstr(var dest: OpenString; const source: ShortString); compilerproc;
procedure fpc_shortstr_assign(len: longint; sstr, dstr: Pointer); compilerproc;

function fpc_mul_int64(f1, f2: int64): int64; compilerproc;
function fpc_mul_dword_to_qword(f1, f2: uint32): qword; compilerproc;
function fpc_div_int64(d, n: int64): int64; compilerproc;
function fpc_mod_int64(d, n: int64): int64; compilerproc;
function fpc_mod_qword(d, n: qword): qword; compilerproc;
function fpc_div_qword(d, n: qword): qword; compilerproc;

function fpc_getmem(size: PtrUInt): Pointer; compilerproc;
procedure fpc_freemem(p: Pointer); compilerproc;

procedure fpc_reraise; compilerproc;
procedure fpc_raiseexception(obj: Pointer; anaddr, aframe: Pointer); compilerproc;
function fpc_catches(obj: Pointer; t: Pointer): Pointer; compilerproc;
procedure fpc_doneexception; compilerproc;

procedure move(const source; var dest; count: SizeInt);

function Trunc(d: Double): int64;
function Round(d: Double): int64;
