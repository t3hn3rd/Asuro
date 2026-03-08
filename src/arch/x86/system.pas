//  Copyright 2021 Kieron Morris & Aaron Hance
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

{ 
	Include->System - Base Types & Structures.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit system;

interface

const
     KERNEL_VIRTUAL_BASE = $C0000000;
     KERNEL_PAGE_NUMBER = KERNEL_VIRTUAL_BASE SHR 22;
     BSOD_ENABLE = true;
     TRACER_ENABLE = true;

type
    //internal core.types
    cardinal = 0..$FFFFFFFF;
    hresult = type longint;
    dword = cardinal;
    integer = longint;
    pchar = ^char;

    //Standard Types
    uInt8  = BYTE;
    uInt16 = WORD;
    uInt32 = DWORD;
    uInt64 = QWORD;
    uint128 = packed record
      case Integer of
        0: (
            Hi : uint64;
            Lo : uint64;
        );
        1: (
            DWords : array [0..3] of uint32;
        );
        2: (
            Words : array [0..7] of uint16;
        );
        3: (
            Bytes : array [0..15] of uint8;
        );
    end;

    sInt8 = shortint;
    sInt16 = smallint;
    sInt32 = integer;
    sInt64 = int64;

    Float = Single;
 
    //Pointer Types
    PuByte = ^Byte;
    PuInt8 = PuByte;
    PuInt16 = ^uInt16;
    PuInt32 = ^uInt32;
    PuInt64 = ^uInt64;
    PuInt128 = ^uint128;

    PsInt8 = ^sInt8;
    PsInt16 = ^sInt16;
    PsInt32 = ^sInt32;
    PsInt64 = ^sInt64;

    PFloat = ^Float;
    PDouble = ^Double;

    Void = ^uInt32;

    yord = uInt8;
    xord = uInt8;
    zord = uInt16;

    //Alternate Types
    UBit1 =  0..(1 shl 01) - 1;
    UBit2 =  0..(1 shl 02) - 1;
    UBit3 =  0..(1 shl 03) - 1;
    UBit4 =  0..(1 shl 04) - 1;
    UBit5 =  0..(1 shl 05) - 1;
    UBit6 =  0..(1 shl 06) - 1;
    UBit7 =  0..(1 shl 07) - 1;
    UBit9 =  0..(1 shl 09) - 1;
    UBit10 = 0..(1 shl 10) - 1;
    UBit11 = 0..(1 shl 11) - 1;
    UBit12 = 0..(1 shl 12) - 1;
    UBit13 = 0..(1 shl 13) - 1;
    UBit14 = 0..(1 shl 14) - 1;
    UBit15 = 0..(1 shl 15) - 1;
    UBit16 = 0..(1 shl 16) - 1;
    UBit17 = 0..(1 shl 17) - 1;
    UBit18 = 0..(1 shl 18) - 1;
    UBit19 = 0..(1 shl 19) - 1;
    UBit20 = 0..(1 shl 20) - 1;
    UBit21 = 0..(1 shl 21) - 1;
    UBit22 = 0..(1 shl 22) - 1;
    UBit23 = 0..(1 shl 23) - 1;
    UBit24 = 0..(1 shl 24) - 1;
    UBit25 = 0..(1 shl 25) - 1;
    UBit26 = 0..(1 shl 26) - 1;
    UBit27 = 0..(1 shl 27) - 1;
    UBit28 = 0..(1 shl 28) - 1;
    UBit30 = 0..(1 shl 30) - 1;
    UBit31 = 0..(1 shl 31) - 1;

    TBitMask = bitpacked record
      b0,b1,b2,b3,b4,b5,b6,b7 : Boolean;
    end;
    PBitMask = ^TBitMask;

    TMask = bitpacked array[0..7] of Boolean;
    PMask = ^TMask;

    PText = ^Text;

    { ---- Types required by FPC 3.2.2 compiler internals ---- }

    { Size/pointer integer core.types for 32-bit target }
    SizeInt = longint;
    SizeUInt = cardinal;
    PtrInt = longint;
    PtrUInt = cardinal;
    ValSInt = longint;
    ValUInt = cardinal;
    NativeInt = longint;
    NativeUInt = cardinal;
    CodePointer = Pointer;
    PCodePointer = ^CodePointer;
    PSizeInt = ^SizeInt;

    { RTTI type kind enumeration — must match compiler's internal list }
    TTypeKind = (
        tkUnknown, tkInteger, tkChar, tkEnumeration, tkFloat,
        tkSet, tkMethod, tkSString, tkLString, tkAString,
        tkWString, tkVariant, tkArray, tkRecord, tkInterface,
        tkClass, tkObject, tkWChar, tkBool, tkInt64,
        tkQWord, tkDynArray, tkInterfaceRaw, tkProcVar, tkUString,
        tkUChar, tkHelper, tkFile, tkClassRef, tkPointer
    );

    { jmp_buf for i386 — used by exception handling internals }
    jmp_buf = packed record
        ebx, esi, edi: LongInt;
        bp, sp, pc: Pointer;
    end;
    PJmp_buf = ^jmp_buf;

    { Exception address stack entry }
    PExceptAddr = ^TExceptAddr;
    TExceptAddr = record
        buf: PJmp_buf;
        next: PExceptAddr;
        frametype: LongInt;
    end;

    { GUID record — required by compiler for interface support }
    PGuid = ^TGuid;
    TGuid = packed record
        case Integer of
            1: (Data1: DWord; Data2: Word; Data3: Word; Data4: array[0..7] of Byte);
            2: (D1: DWord; D2: Word; D3: Word; D4: array[0..7] of Byte);
            3: (time_low: DWord; time_mid: Word; time_hi_and_version: Word;
                clock_seq_hi_and_reserved: Byte; clock_seq_low: Byte;
                node: array[0..5] of Byte);
    end;

    { File record core.types — required by compiler for file I/O internals }
    FileRec = packed record
        Handle    : longint;
        Mode      : longint;
        RecSize   : SizeInt;
        _private  : array[0..31] of byte;
        UserData  : array[0..31] of byte;
        name      : array[0..255] of char;
    end;
    PFileRec = ^FileRec;

    TextBuf = array[0..255] of char;
    TextRec = packed record
        Handle    : longint;
        Mode      : longint;
        BufSize   : SizeInt;
        _private  : SizeInt;
        BufPos    : SizeInt;
        BufEnd    : SizeInt;
        BufPtr    : ^TextBuf;
        OpenFunc  : CodePointer;
        InOutFunc : CodePointer;
        FlushFunc : CodePointer;
        CloseFunc : CodePointer;
        UserData  : array[0..31] of byte;
        name      : array[0..255] of char;
        LineEnd   : array[0..3] of char;
        Buffer    : TextBuf;
    end;
    PTextRec = ^TextRec;

var
  AK_START : uint32; external name 'kernel_start';
  AK_END   : uint32; external name 'kernel_end';
  ASURO_KERNEL_START : uint32;
  ASURO_KERNEL_END   : uint32;
  ASURO_KERNEL_SIZE  : uint32;

  { FPC 3.2.2 required globals }
  ExceptAddrStack : PExceptAddr;
  ExitCode : longint; public name 'operatingsystem_result';
  ErrorAddr : Pointer;
  ErrorCode : Word;
  ExitProc : CodePointer;
  StackBottom : Pointer;
  StackLength : SizeUInt;
  RandSeed : Cardinal;

procedure init();

{ ---- FPC 3.2.2 compilerproc stubs ---- }
{ These are required by the compiler for program init/exit and error handling. }
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
procedure fpc_shortstr_assign(len: longint; sstr, dstr: Pointer); compilerproc;

{ 64-bit multiply compilerproc required by FPC on i386 when
  any int64/uint64 arithmetic occurs (e.g. sint32 * uint32 promotion).
  Must live in the system unit so the compiler can resolve it. }
function fpc_mul_int64(f1, f2: int64): int64; compilerproc;
function fpc_div_int64(d, n: int64): int64; compilerproc;
function fpc_mod_int64(d, n: int64): int64; compilerproc;
function fpc_mod_qword(d, n: qword): qword; compilerproc;
function fpc_div_qword(d, n: qword): qword; compilerproc;

{ Memory allocation compilerprocs – delegate to core.version heap (memory.heap) }
function fpc_getmem(size: PtrUInt): Pointer; compilerproc;
procedure fpc_freemem(p: Pointer); compilerproc;

{ Exception handling compilerprocs }
procedure fpc_reraise; compilerproc;
procedure fpc_raiseexception(obj: Pointer; anaddr, aframe: Pointer); compilerproc;
function fpc_catches(obj: Pointer; t: Pointer): Pointer; compilerproc;
procedure fpc_doneexception; compilerproc;

procedure move(const source; var dest; count: SizeInt);

{ Float-to-integer intrinsics }
function Trunc(d: Double): int64;
function Round(d: Double): int64;

implementation

{ ---- Raw driver.intf.serial debug helpers (COM1 $3F8, no dependencies) ---- }

procedure serial_putch(ch: char); assembler;
asm
    push edx
    push ecx
    mov cl, al               { ch passed in AL (register convention) }
    mov dx, $3FD
@wait:
    in al, dx
    and al, $20
    jz @wait
    mov dx, $3F8
    mov al, cl
    out dx, al
    pop ecx
    pop edx
end;

procedure serial_puthex8(val: uint32);
const
    hex: array[0..15] of char = '0123456789ABCDEF';
begin
    serial_putch(hex[(val shr 4) and $F]);
    serial_putch(hex[val and $F]);
end;

procedure serial_puthex32(val: uint32);
begin
    serial_puthex8((val shr 24) and $FF);
    serial_puthex8((val shr 16) and $FF);
    serial_puthex8((val shr 8) and $FF);
    serial_puthex8(val and $FF);
end;

procedure serial_putstr(s: pchar);
var i: uint32;
begin
    i := 0;
    while s[i] <> #0 do begin
        serial_putch(s[i]);
        Inc(i);
    end;
end;

{ ---- compilerproc implementations ---- }

{ Internal error handler — called by the individual error stubs.
  Declared as a normal procedure so it's visible to other procs. }
procedure HandleErrorInternal(errno: longint);
begin
    ErrorCode := Word(errno);
    ErrorAddr := nil;
    asm
        cli
        hlt
    end;
end;

{ Move memory block — minimal implementation needed by shortstr_assign }
procedure move(const source; var dest; count: SizeInt);
    [public, alias: 'FPC_MOVE'];
var
    i: SizeInt;
    s, d: PuInt8;
begin
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

procedure fpc_initializeunits; [public, alias: 'FPC_INITIALIZEUNITS']; compilerproc;
begin
    { Unit initialization is handled by the core.version boot sequence }
end;

procedure fpc_do_exit; [public, alias: 'FPC_DO_EXIT']; compilerproc;
begin
    { Bare metal: halt the CPU }
    asm
        cli
        hlt
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

function fpc_setjmp(var s: jmp_buf): longint; [public, alias: 'FPC_SETJMP']; compilerproc; assembler;
asm
    mov ecx, eax   { eax = @s (register calling convention) }
    mov [ecx],    ebx
    mov [ecx+4],  esi
    mov [ecx+8],  edi
    mov [ecx+12], ebp
    mov [ecx+16], esp
    mov eax, [esp]       { return address }
    mov [ecx+20], eax
    xor eax, eax         { return 0 }
end;

procedure fpc_longjmp(var s: jmp_buf; value: longint); [public, alias: 'FPC_LONGJMP']; compilerproc; assembler;
asm
    mov ecx, eax    { eax = @s }
    mov eax, edx    { edx = value }
    test eax, eax
    jnz @notZero
    inc eax          { value must be non-zero }
@notZero:
    mov ebx, [ecx]
    mov esi, [ecx+4]
    mov edi, [ecx+8]
    mov ebp, [ecx+12]
    mov esp, [ecx+16]
    jmp dword [ecx+20]
end;

procedure fpc_shortstr_assign(len: longint; sstr, dstr: Pointer);
    [public, alias: 'FPC_SHORTSTR_ASSIGN']; compilerproc;
var
    slen: uint8;
    src, dst: PuInt8;
begin
    src := PuInt8(sstr);
    dst := PuInt8(dstr);
    slen := src^;
    if slen > uint8(len) then
        slen := uint8(len);
    dst^ := slen;
    if slen > 0 then
        move(PuInt8(PtrUInt(sstr) + 1)^, PuInt8(PtrUInt(dstr) + 1)^, SizeInt(slen));
end;

function fpc_mul_int64(f1, f2: int64): int64; [public, alias: 'FPC_MUL_INT64']; compilerproc;
{ 64x64->64 multiply using three 32-bit MUL instructions.
  We only keep the low 64 bits of the 128-bit product. }
var
  res: int64;
begin
    asm
        MOV  EAX, DWORD [f1]        { f1_lo }
        MUL  DWORD [f2]             { EDX:EAX = f1_lo * f2_lo }
        MOV  DWORD [res], EAX       { result_lo }
        MOV  ECX, EDX               { carry = high(f1_lo * f2_lo) }

        MOV  EAX, DWORD [f1]        { f1_lo }
        MUL  DWORD [f2+4]           { EDX:EAX = f1_lo * f2_hi }
        ADD  ECX, EAX               { carry += low(f1_lo * f2_hi) }

        MOV  EAX, DWORD [f1+4]      { f1_hi }
        MUL  DWORD [f2]             { EDX:EAX = f1_hi * f2_lo }
        ADD  ECX, EAX               { carry += low(f1_hi * f2_lo) }

        MOV  DWORD [res+4], ECX     { result_hi }
    end;
    fpc_mul_int64 := res;
end;

{ ---------- 64-bit division / modulo ---------- }

{ Helper: unsigned 64÷64→64 using shift-subtract (binary long division).
  Called by both signed div and mod after sign handling. }
procedure udiv64(dividendLo, dividendHi, divisorLo, divisorHi: uint32;
                 var quotLo, quotHi, remLo, remHi: uint32);
var
    bit: longint;
begin
    quotLo := 0; quotHi := 0;
    remLo  := 0; remHi  := 0;

    for bit := 63 downto 0 do begin
        { rem := rem shl 1 }
        remHi := (remHi shl 1) or (remLo shr 31);
        remLo := remLo shl 1;

        { bring down next bit of dividend }
        if bit >= 32 then begin
            remLo := remLo or ((dividendHi shr (bit - 32)) and 1);
        end else begin
            remLo := remLo or ((dividendLo shr bit) and 1);
        end;

        { if rem >= divisor then rem -= divisor; set quotient bit }
        if (remHi > divisorHi) or
           ((remHi = divisorHi) and (remLo >= divisorLo)) then begin
            { rem -= divisor (64-bit subtract) }
            if remLo < divisorLo then begin
                remHi := remHi - divisorHi - 1;
                remLo := remLo - divisorLo;
            end else begin
                remHi := remHi - divisorHi;
                remLo := remLo - divisorLo;
            end;
            { set quotient bit }
            if bit >= 32 then
                quotHi := quotHi or (uint32(1) shl (bit - 32))
            else
                quotLo := quotLo or (uint32(1) shl bit);
        end;
    end;
end;

function fpc_div_int64(d, n: int64): int64; [public, alias: 'FPC_DIV_INT64']; compilerproc;
var
    negate: boolean;
    nLo, nHi, dLo, dHi: uint32;
    qLo, qHi, rLo, rHi: uint32;
begin
    if d = 0 then begin
        HandleErrorInternal(200);
        fpc_div_int64 := 0;
        exit;
    end;

    negate := false;
    if n < 0 then begin
        n := -n;
        negate := not negate;
    end;
    if d < 0 then begin
        d := -d;
        negate := not negate;
    end;

    nLo := PuInt32(@n)[0];
    nHi := PuInt32(@n)[1];
    dLo := PuInt32(@d)[0];
    dHi := PuInt32(@d)[1];

    if dHi = 0 then begin
        { Fast path: divisor fits in 32 bits }
        asm
            xor edx, edx
            mov eax, dword [nHi]
            div dword [dLo]
            mov dword [qHi], eax
            mov eax, dword [nLo]
            div dword [dLo]
            mov dword [qLo], eax
        end;
    end else begin
        udiv64(nLo, nHi, dLo, dHi, qLo, qHi, rLo, rHi);
    end;

    PuInt32(@fpc_div_int64)[0] := qLo;
    PuInt32(@fpc_div_int64)[1] := qHi;
    if negate then
        fpc_div_int64 := -fpc_div_int64;
end;

function fpc_mod_int64(d, n: int64): int64; [public, alias: 'FPC_MOD_INT64']; compilerproc;
var
    nNeg: boolean;
    nLo, nHi, dLo, dHi: uint32;
    qLo, qHi, rLo, rHi: uint32;
begin
    if d = 0 then begin
        HandleErrorInternal(200);
        fpc_mod_int64 := 0;
        exit;
    end;

    nNeg := n < 0;
    if n < 0 then n := -n;
    if d < 0 then d := -d;

    nLo := PuInt32(@n)[0];
    nHi := PuInt32(@n)[1];
    dLo := PuInt32(@d)[0];
    dHi := PuInt32(@d)[1];

    if dHi = 0 then begin
        { Fast path: divisor fits in 32 bits }
        asm
            xor edx, edx
            mov eax, dword [nHi]
            div dword [dLo]
            mov eax, dword [nLo]
            div dword [dLo]
            mov dword [rLo], edx
        end;
        rHi := 0;
    end else begin
        udiv64(nLo, nHi, dLo, dHi, qLo, qHi, rLo, rHi);
    end;

    PuInt32(@fpc_mod_int64)[0] := rLo;
    PuInt32(@fpc_mod_int64)[1] := rHi;
    if nNeg then
        fpc_mod_int64 := -fpc_mod_int64;
end;

function fpc_mod_qword(d, n: qword): qword; [public, alias: 'FPC_MOD_QWORD']; compilerproc;
var
    nLo, nHi, dLo, dHi: uint32;
    qLo, qHi, rLo, rHi: uint32;
begin
    { Extract halves via pointer — avoids any 64-bit operations }
    nLo := PuInt32(@n)[0];
    nHi := PuInt32(@n)[1];
    dLo := PuInt32(@d)[0];
    dHi := PuInt32(@d)[1];

    if (dLo = 0) and (dHi = 0) then begin
        HandleErrorInternal(200);
        fpc_mod_qword := 0;
        exit;
    end;

    if dHi = 0 then begin
        { Fast path: divisor fits in 32 bits — use hardware DIV }
        asm
            xor edx, edx
            mov eax, dword [nHi]
            div dword [dLo]
            { EDX now has remainder from high division }
            mov eax, dword [nLo]
            div dword [dLo]
            mov dword [rLo], edx         { remainder is in EDX }
        end;
        rHi := 0;
    end else begin
        { Slow path: full 64-bit software division }
        udiv64(nLo, nHi, dLo, dHi, qLo, qHi, rLo, rHi);
    end;
    PuInt32(@fpc_mod_qword)[0] := rLo;
    PuInt32(@fpc_mod_qword)[1] := rHi;
end;

function fpc_div_qword(d, n: qword): qword; [public, alias: 'FPC_DIV_QWORD']; compilerproc;
var
    nLo, nHi, dLo, dHi: uint32;
    qLo, qHi, rLo, rHi: uint32;
begin
    { Extract halves via pointer — avoids any 64-bit operations }
    nLo := PuInt32(@n)[0];
    nHi := PuInt32(@n)[1];
    dLo := PuInt32(@d)[0];
    dHi := PuInt32(@d)[1];

    if (dLo = 0) and (dHi = 0) then begin
        HandleErrorInternal(200);
        fpc_div_qword := 0;
        exit;
    end;

    if dHi = 0 then begin
        { Fast path: divisor fits in 32 bits — use hardware DIV }
        asm
            xor edx, edx
            mov eax, dword [nHi]
            div dword [dLo]
            mov dword [qHi], eax       { quotient high dword }
            mov eax, dword [nLo]
            div dword [dLo]
            mov dword [qLo], eax       { quotient low dword }
        end;
    end else begin
        { Slow path: full 64-bit software division }
        udiv64(nLo, nHi, dLo, dHi, qLo, qHi, rLo, rHi);
    end;
    PuInt32(@fpc_div_qword)[0] := qLo;
    PuInt32(@fpc_div_qword)[1] := qHi;
end;

{ ---------- Float-to-integer intrinsics ---------- }

function Trunc(d: Double): int64; [public, alias: 'FPC_TRUNC'];
var
    oldcw, newcw: word;
    res: int64;
begin
    asm
        fnstcw oldcw
        mov    ax, oldcw
        or     ax, $0C00      { set rounding mode to "truncate" (round toward zero) }
        mov    newcw, ax
        fldcw  newcw
        fld    qword [d]
        fistp  qword [res]
        fldcw  oldcw           { restore original rounding mode }
    end;
    Trunc := res;
end;

function Round(d: Double): int64; [public, alias: 'FPC_ROUND'];
var
    res: int64;
begin
    { FPU default rounding mode is "round to nearest" which is what Round needs }
    asm
        fld   qword [d]
        fistp qword [res]
    end;
    Round := res;
end;

{ ---------- Memory allocation compilerprocs ---------- }

function kernel_kalloc(size: uint32): Pointer; external name 'kernel_kalloc';
procedure kernel_kfree(p: Pointer); external name 'kernel_kfree';

function fpc_getmem(size: PtrUInt): Pointer;
    [public, alias: 'FPC_GETMEM']; compilerproc;
begin
    fpc_getmem := kernel_kalloc(uint32(size));
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

procedure init();
begin
    ASURO_KERNEL_START := uint32(@AK_START);
    ASURO_KERNEL_END := uint32(@AK_END);
    ASURO_KERNEL_SIZE:= ASURO_KERNEL_END - ASURO_KERNEL_START;
    ExceptAddrStack := nil;
    ErrorAddr := nil;
    ErrorCode := 0;
    ExitCode := 0;
    ExitProc := nil;
end;

end.
