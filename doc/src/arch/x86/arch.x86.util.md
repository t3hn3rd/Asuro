# arch.x86.util

x86 I/O port access, low-level CPU control, timing, and arithmetic utilities.

## Overview

This unit collects all code that requires direct x86 assembly: port I/O, interrupt flag manipulation, TSC reads, system halt and reset, SSE memory copy, software sleep, bit rotation, and 64-by-32 division. It also exposes the kernel end pointer and stack address symbols from the linker script. Most other units in the x86 architecture layer depend on this unit for hardware access primitives.

## Dependencies

- `arch.x86.bda` (interface)
- `arch.x86.cpu`
- `arch.x86.isr.types`
- `driver.timer.rtc`
- `driver.io.serial`

## Variables

### endptr

```pascal
var endptr : uint32; external name '__end';
```

Linker-defined symbol marking the end of the kernel binary image in virtual memory.

### stack

```pascal
var stack : uint32; external name 'KERNEL_STACK';
```

Linker-defined symbol giving the address of the kernel stack.

## Functions and Procedures

### INTE

```pascal
function INTE : boolean;
```

Returns `true` if the interrupt enable flag (IF, EFLAGS bit 9) is currently set.

### CLI

```pascal
procedure CLI();
```

Disables maskable interrupts by executing the x86 `CLI` instruction.

### STI

```pascal
procedure STI();
```

Enables maskable interrupts by executing the x86 `STI` instruction.

### GPF

```pascal
procedure GPF();
```

Triggers a software General Protection Fault via `INT 13`. Used by subsystems to signal unrecoverable internal errors in a way that routes through the normal fault handler.

### outb

```pascal
procedure outb(port : uint16; val : uint8);
```

Writes an 8-bit value to an I/O port, followed by `io_wait`. Also exported as `util_outb`.

### outw

```pascal
procedure outw(port : uint16; val : uint16);
```

Writes a 16-bit value to an I/O port, followed by `io_wait`. Also exported as `util_outw`.

### outl

```pascal
procedure outl(port : uint16; val : uint32);
```

Writes a 32-bit value to an I/O port, followed by `io_wait`. Also exported as `util_outl`.

### inb

```pascal
function inb(port : uint16) : uint8;
```

Reads an 8-bit value from an I/O port, followed by `io_wait`. Also exported as `util_inb`.

### inw

```pascal
function inw(port : uint16) : uint16;
```

Reads a 16-bit value from an I/O port, followed by `io_wait`. Also exported as `util_inw`.

### inl

```pascal
function inl(port : uint16) : uint32;
```

Reads a 32-bit value from an I/O port, followed by `io_wait`. Also exported as `util_inl`.

### io_wait

```pascal
procedure io_wait;
```

Writes zero to port `$80` (a diagnostic port), providing a brief I/O delay used between successive port writes to slow-responding hardware.

### __SSE_128_memcpy

```pascal
procedure __SSE_128_memcpy(source : uint32; dest : uint32);
```

Copies 16 bytes from `source` to `dest` using a single `MOVAPS`/`XMM1` pair. Both addresses must be 16-byte aligned.

### halt_and_catch_fire

```pascal
procedure halt_and_catch_fire();
```

Disables interrupts (`CLI`) and halts the CPU (`HLT`). The processor will not resume. Used as the panic halt callback and exported as `util_halt_and_catch_fire`.

### halt_and_dont_catch_fire

```pascal
procedure halt_and_dont_catch_fire();
```

Spins in an infinite loop without halting the CPU. Exported as `util_halt_and_dont_catch_fire`. Useful when HLT would be incorrect (e.g., if an NMI handler must remain active).

### psleep

```pascal
procedure psleep(t : uint16);
```

Busy-waits for approximately `t` BDA timer ticks. If the timer ISR is not yet installed (detected by the tick counter not advancing within 50 000 iterations), falls back to a CPU busy-loop calibrated for roughly millisecond-scale delays per tick. Used for hardware settle times during early boot.

### sleep

```pascal
procedure sleep(seconds : uint32);
```

Waits for `seconds` RTC seconds by polling the RTC until the seconds field changes `seconds` times.

### get16bitcounter

```pascal
function get16bitcounter : uint16;
```

Returns the 16-bit system tick counter from `arch.x86.bda.Counters.c16`.

### get32bitcounter

```pascal
function get32bitcounter : uint32;
```

Returns the 32-bit system tick counter from `arch.x86.bda.Counters.c32`.

### get64bitcounter

```pascal
function get64bitcounter : uint64;
```

Returns the 64-bit system tick counter from `arch.x86.bda.Counters.c64`.

### getTSC

```pascal
function getTSC : uint64;
```

Reads the Time-Stamp Counter using the `RDTSC` instruction and returns the 64-bit result.

### div6432

```pascal
function div6432(dividend : uint64; divisor : uint32) : uint64;
```

Performs an unsigned 64-by-32 division using two 32-bit `DIV` instructions. Returns the 64-bit quotient. Used internally by `MsSinceSystemBoot`.

### MsSinceSystemBoot

```pascal
function MsSinceSystemBoot : uint64;
```

Returns the number of milliseconds elapsed since boot, computed as `TSC / (CPU_Hz / 1000)`.

### getESP

```pascal
function getESP : uint32;
```

Returns the current stack pointer value.

### RolDWord

```pascal
function RolDWord(AValue : uint32; Dist : uint8) : uint32;
```

Rotates `AValue` left by `Dist` bit positions using the x86 `ROL` instruction iteratively.

### RorDWord

```pascal
function RorDWord(AValue : uint32; Dist : uint8) : uint32;
```

Rotates `AValue` right by `Dist` bit positions using the x86 `ROR` instruction iteratively.

### resetSystem

```pascal
procedure resetSystem();
```

Performs a hardware reset by pulsing the keyboard controller reset line (port `$64`, command `$FE`). Disables interrupts before issuing the command, then calls `halt_and_catch_fire` as a fallback if the reset does not take effect immediately.

## Notes

- All port I/O procedures call `io_wait` after the port operation. Code that needs maximum throughput (e.g., bulk PIO transfers) should call the underlying assembly directly rather than using these wrappers.
- `psleep` is intended only for early boot hardware initialisation. Once the scheduler is running, use proper blocking mechanisms rather than busy-waiting.
