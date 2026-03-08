# arch.x86.isr.types

ISR shared data structures, type definitions, and interrupt register frame adjustment.

## Overview

This unit defines the shared types used across the ISR and fault subsystems. It provides the packed record types that describe the layout of the saved register frame on the stack when a Free Pascal `interrupt`-attributed procedure is entered, as well as global pointers into that frame. The `correctInterruptRegisters` procedure adjusts these pointers based on whether the triggering exception pushes an error code, allowing fault handlers to correctly locate EIP, CS, EFLAGS, and any error code.

## Constants

### MAX_HOOKS

`16` — Maximum number of callback hooks that can be registered per interrupt vector.

## Types

### TInterruptRegisters / PInterruptRegisters

```pascal
TInterruptRegisters = packed record
    EBP : uint32;
    EAX : uint32;
    EBX : uint32;
    ECX : uint32;
    EDX : uint32;
    ESI : uint32;
    EDI : uint32;
    DS  : uint16;
    ES  : uint16;
    FS  : uint16;
    GS  : uint16;
end;
```

The general-purpose register save area at the base of the interrupt stack frame. EBP is saved first (lowest address), followed by the PUSHAD register set, then the segment registers. The `interrupt` procedure directive causes Free Pascal to generate this layout automatically.

### TError / PError

```pascal
TError = packed record
    Error : uint32;
end;
```

A single 32-bit error code field. On exceptions that push an error code (e.g., GPF, page fault, double fault), this record sits immediately above `TInterruptRegisters` on the stack.

### TInterruptSpecialRegisters / PInterruptSpecialRegisters

```pascal
TInterruptSpecialRegisters = packed record
    EIP    : uint32;
    CS     : uint32;
    EFLAGS : uint32;
end;
```

The CPU-pushed return state: instruction pointer, code segment, and EFLAGS. This structure sits above the error code (if present) or immediately above `TInterruptRegisters` (if no error code).

### TRegisters / PRegisters

```pascal
TRegisters = record
    edi, esi, ebp, esp, ebx, edx, ecx, eax : uint32;
    ErrorCode : uint32;
    eip, cs, eflags, UserESP, ss : uint32;
end;
```

An alternative full register snapshot used in some contexts. Includes user-mode ESP and SS for ring-transition frames.

### pp_hook_method / pp_void

```pascal
pp_hook_method = procedure(data : void);
```

Type of a hookable ISR callback that receives a single `void` pointer argument. `pp_void` is an alias for the same type.

## Variables

### IntReg

```pascal
var IntReg : PInterruptRegisters = nil;
```

Points to the saved general-purpose register frame on the interrupt stack. Set by the ISR assembly stub (via `MOV IntReg, EBP`) before the Pascal ISR body executes.

### IntSpec

```pascal
var IntSpec : PInterruptSpecialRegisters = nil;
```

Points to the CPU-pushed EIP/CS/EFLAGS frame. Calculated by `correctInterruptRegisters`.

### IntErr

```pascal
var IntErr : PError = nil;
```

Points to the error code pushed by the CPU. Set to a zero-filled sentinel for exceptions that do not push an error code.

### ZeroError

```pascal
var ZeroError : uint32 = 0;
```

Sentinel value used as the error code for exceptions that do not push one. `IntErr` points here when `correctInterruptRegisters(false)` is called.

## Functions and Procedures

### correctInterruptRegisters

```pascal
procedure correctInterruptRegisters(Errorcode : boolean);
```

Adjusts the `IntSpec` and `IntErr` pointers based on the current `IntReg` value and whether the exception pushes an error code.

- If `Errorcode` is `true`: `IntErr` points to the dword immediately above `TInterruptRegisters`; `IntSpec` points 4 bytes further up (past the error code).
- If `Errorcode` is `false`: `IntSpec` points immediately above `TInterruptRegisters`; `IntErr` points to `ZeroError`.

Must be called by fault handlers after the ISR stub has set `IntReg`, and before `arch.x86.panic.x86_panic` is invoked to read the register state.
