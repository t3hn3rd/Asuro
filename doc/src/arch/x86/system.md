# system

Kernel base type definitions, FPC compiler runtime stubs, and system initialisation.

## Overview

This is the Free Pascal system unit for the Asuro kernel. It provides three categories of functionality:

1. **Base types** — Fundamental integer, pointer, and composite types used throughout the kernel, including fixed-width integer aliases (`uint8` through `uint64`), signed counterparts, bit-width-constrained subrange types (`UBit1`–`UBit31`), and types required by the FPC 3.2.2 compiler internals (RTTI, exception frames, GUIDs, file records).

2. **FPC compiler runtime stubs** — Implementations of the `compilerproc` procedures that FPC generates calls to when compiling Pascal code: program initialisation and exit, error handling, range and overflow checks, I/O checks, exception handling (setjmp/longjmp), short string assignment, 64-bit integer arithmetic (multiply, divide, modulo for both signed and unsigned), and memory allocation. All stubs are implemented for a bare-metal environment with no operating system beneath them.

3. **System initialisation** — Captures the kernel start and end addresses from linker-defined symbols, and initialises FPC runtime globals.

## Constants

### KERNEL_VIRTUAL_BASE

`$C0000000` — The virtual address at which the kernel is linked (higher-half at 3 GiB). Physical addresses are converted to kernel virtual addresses by adding this offset.

### KERNEL_PAGE_NUMBER

`KERNEL_VIRTUAL_BASE shr 22` = `768` — The page directory index corresponding to the start of the kernel virtual address space.

### BSOD_ENABLE

`true` — Compile-time flag enabling the BSOD (Blue Screen of Death) panic display.

### TRACER_ENABLE

`true` — Compile-time flag enabling the call tracer (`debug.tracer`).

## Types

### Integer and Cardinal Types

| Type     | Underlying Type | Description |
|----------|-----------------|-------------|
| cardinal | 0..$FFFFFFFF    | Unsigned 32-bit integer |
| hresult  | longint         | COM-style result code |
| dword    | cardinal        | Alias for cardinal |
| integer  | longint         | Signed 32-bit integer |
| uint8    | BYTE            | Unsigned 8-bit integer |
| uint16   | WORD            | Unsigned 16-bit integer |
| uint32   | DWORD           | Unsigned 32-bit integer |
| uint64   | QWORD           | Unsigned 64-bit integer |
| sInt8    | shortint        | Signed 8-bit integer |
| sInt16   | smallint        | Signed 16-bit integer |
| sInt32   | integer         | Signed 32-bit integer |
| sInt64   | int64           | Signed 64-bit integer |
| Float    | Single          | 32-bit floating-point |

### uint128

A 128-bit value as a variant record with four views: two 64-bit halves (`Hi`, `Lo`), four 32-bit dwords, eight 16-bit words, and sixteen bytes.

### Pointer Types

`PuByte`, `PuInt8`, `PuInt16`, `PuInt32`, `PuInt64`, `PuInt128`, `PsInt8`, `PsInt16`, `PsInt32`, `PsInt64`, `PFloat`, `PDouble` — Pointer variants of the corresponding numeric types.

### Void

`Void = ^uInt32` — Generic untyped pointer used as the parameter type for ISR hook callbacks.

### Coordinate Types

`yord`, `xord` — `uint8` aliases for Y and X screen coordinates. `zord` — `uint16` alias for a combined coordinate.

### UBit Types

`UBit1` through `UBit31` — Subrange types constrained to N-bit unsigned values (0 to 2^N - 1). Used in bitpacked records for hardware register mapping. Note: `UBit8` is absent (use `uint8` directly).

### TBitMask / PBitMask

A bitpacked record of 8 Boolean fields (`b0`–`b7`), providing individual bit access to a byte.

### TMask / PMask

A bitpacked array of 8 Booleans.

### FPC Compiler-Required Types

| Type          | Description |
|---------------|-------------|
| SizeInt       | Signed pointer-sized integer (longint on 32-bit) |
| SizeUInt      | Unsigned pointer-sized integer (cardinal on 32-bit) |
| PtrInt        | Signed pointer-to-integer type |
| PtrUInt       | Unsigned pointer-to-integer type |
| TTypeKind     | RTTI type kind enumeration |
| jmp_buf       | Non-local jump buffer for i386 (EBX, ESI, EDI, BP, SP, PC) |
| TExceptAddr   | Exception address stack entry (buf, next, frametype) |
| TGuid         | 16-byte GUID/UUID in three variant layouts |
| FileRec       | Internal file descriptor record |
| TextRec       | Internal text file record with buffer |

## Variables

### AK_START / AK_END

```pascal
var AK_START : uint32; external name 'kernel_start';
var AK_END   : uint32; external name 'kernel_end';
```

Linker-defined symbols marking the physical start and end of the kernel image.

### ASURO_KERNEL_START / ASURO_KERNEL_END / ASURO_KERNEL_SIZE

Set by `init` to the virtual addresses corresponding to `AK_START` and `AK_END`, and the size in bytes.

### FPC Runtime Globals

`ExceptAddrStack`, `ExitCode`, `ErrorAddr`, `ErrorCode`, `ExitProc`, `StackBottom`, `StackLength`, `RandSeed` — Standard FPC system unit globals initialised to safe defaults by `init`.

## Functions and Procedures

### init

```pascal
procedure init();
```

Initialises kernel size variables from linker symbols and resets all FPC runtime globals to their zero/nil defaults.

### move

```pascal
procedure move(const source; var dest; count: SizeInt);
```

Copies `count` bytes from `source` to `dest`. Handles overlapping regions by copying backward when `dest` is at a higher address than `source`. Alias: `FPC_MOVE`.

### Trunc

```pascal
function Trunc(d: Double): int64;
```

Converts a double-precision floating-point value to a 64-bit integer by truncating toward zero using the x87 FPU. Alias: `FPC_TRUNC`.

### Round

```pascal
function Round(d: Double): int64;
```

Converts a double-precision floating-point value to a 64-bit integer using the FPU default round-to-nearest mode. Alias: `FPC_ROUND`.

### FPC Compiler Procedure Stubs

All `compilerproc` stubs are mapped to their standard `FPC_*` aliases:

| Procedure | Alias | Description |
|-----------|-------|-------------|
| fpc_initializeunits | FPC_INITIALIZEUNITS | No-op; boot sequence handles unit init |
| fpc_do_exit | FPC_DO_EXIT | CLI + HLT |
| fpc_handleerror | FPC_HANDLEERROR | Sets ErrorCode, CLI + HLT |
| fpc_rangeerror | FPC_RANGEERROR | HandleErrorInternal(201) |
| fpc_overflow | FPC_OVERFLOW | HandleErrorInternal(215) |
| fpc_divbyzero | FPC_DIVBYZERO | HandleErrorInternal(200) |
| fpc_objecterror | FPC_OBJECTERROR | HandleErrorInternal(210) |
| fpc_abstracterror | FPC_ABSTRACTERROR | HandleErrorInternal(211) |
| fpc_stackcheck | FPC_STACKCHECK | No-op |
| fpc_iocheck | FPC_IOCHECK | No-op |
| fpc_pushexceptaddr | FPC_PUSHEXCEPTADDR | Pushes onto ExceptAddrStack |
| fpc_popaddrstack | FPC_POPADDRSTACK | Pops from ExceptAddrStack |
| fpc_setjmp | FPC_SETJMP | Saves EBX/ESI/EDI/EBP/ESP/EIP into jmp_buf |
| fpc_longjmp | FPC_LONGJMP | Restores registers from jmp_buf |
| fpc_shortstr_assign | FPC_SHORTSTR_ASSIGN | Copies short string with length clamping |
| fpc_mul_int64 | FPC_MUL_INT64 | 64×64→64 multiply via three 32-bit MUL instructions |
| fpc_div_int64 | FPC_DIV_INT64 | Signed 64÷64 division with fast 32-bit path |
| fpc_mod_int64 | FPC_MOD_INT64 | Signed 64 modulo with fast 32-bit path |
| fpc_div_qword | FPC_DIV_QWORD | Unsigned 64÷64 division with fast 32-bit path |
| fpc_mod_qword | FPC_MOD_QWORD | Unsigned 64 modulo with fast 32-bit path |
| fpc_getmem | FPC_GETMEM | Delegates to kernel_kalloc |
| fpc_freemem | FPC_FREEMEM | Delegates to kernel_kfree |
| fpc_reraise | FPC_RERAISE | HandleErrorInternal(217) |
| fpc_raiseexception | FPC_RAISEEXCEPTION | HandleErrorInternal(217) |
| fpc_catches | FPC_CATCHES | Returns nil |
| fpc_doneexception | FPC_DONEEXCEPTION | No-op |

## Notes

- The 64-bit software division (`udiv64`) uses a shift-subtract binary long division algorithm. A fast path using the hardware 32-bit `DIV` instruction is taken when the divisor fits in 32 bits.
- The serial debug helpers (`serial_putch`, `serial_puthex8`, `serial_puthex32`, `serial_putstr`) are internal and not exported. They write directly to COM1 (port `$3F8`) without any dependency on the kernel I/O subsystem, making them safe for very early boot diagnostics.
- `fpc_getmem` and `fpc_freemem` are linked to external C-convention symbols `kernel_kalloc` and `kernel_kfree` defined in the heap allocator unit. This allows the FPC `New`/`Dispose` operators and dynamic arrays to use the kernel heap.
