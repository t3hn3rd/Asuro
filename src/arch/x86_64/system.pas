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

{ Minimal bootstrap runtime. Unsupported runtime operations deliberately have
  no implementation, so accidental dependencies fail at compile/link time. }
unit system;

interface

const TRACER_ENABLE = true;

type SizeInt = int64;
     SizeUInt = qword;

{$i ../common/system.types.inc}

type
    { SysV AMD64 nonvolatile register layout. No exception-unwinding helpers
      are provided at this bootstrap stage. FPC still requires these types. }
    jmp_buf = packed record
        rbx, rbp, r12, r13, r14, r15, rsp, rip: uint64;
    end;
    PJmp_buf = ^jmp_buf;
    PExceptAddr = ^TExceptAddr;
    TExceptAddr = record
        buf: PJmp_buf;
        next: PExceptAddr;
        frametype: longint;
    end;

procedure init;
procedure fpc_initializeunits; compilerproc;

procedure bootstrap_halt; external name 'bootstrap_halt';
function Trunc(d: Double): int64;

implementation

var
    InitFinalTable: TInitFinalTable; external name 'INITFINAL';

{$i ../common/system.init.inc}

procedure init;
begin
    initializeUnits;
end;

procedure fpc_initializeunits; [public, alias: 'FPC_INITIALIZEUNITS']; compilerproc;
begin
    initializeUnits;
end;

{ SysV AMD64 passes Double in XMM0. CVTTSD2SI rounds toward zero without
  changing the caller's x87 control word or MXCSR rounding mode. }
function Trunc(d: Double): int64; assembler; nostackframe;
asm
    cvttsd2si rax, xmm0
end;

end.
