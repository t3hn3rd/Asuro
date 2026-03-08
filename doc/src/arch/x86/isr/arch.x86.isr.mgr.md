# arch.x86.isr.mgr

Interrupt Service Routine registration, dispatch, and IDT gate management.

## Overview

This unit is the central ISR management layer. It maintains a two-dimensional hook table indexed by interrupt vector number and hook slot, installs naked assembly stubs (`ISR_0` through `ISR_255`) in the IDT for all 256 vectors, and dispatches registered callbacks when interrupts fire. It also handles End-of-Interrupt (EOI) signalling to both the 8259 PIC and, when present, the Local APIC.

Each ISR stub is declared with the Free Pascal `interrupt` directive, which causes the compiler to generate PUSHAD/POPAD prologue and epilogue code and use IRETD to return. The stub saves EBP into the global `IntReg` pointer before calling the common dispatch function `ISR_N`.

## Dependencies

- `arch.x86.isr`
- `arch.x86.idt`
- `arch.x86.isr.types`
- `core.util`
- `arch.x86.util`
- `io.syslog` (implementation)
- `arch.x86.isr.ioapic` (implementation)

## Constants

`MAX_HOOKS` is imported from `arch.x86.isr.types` and defines the maximum number of callbacks per vector.

## Types

### TISRHook

```pascal
TISRHook = procedure();
```

Type of a no-argument, no-return ISR callback procedure.

### TISRNHookArray

```pascal
TISRNHookArray = Array[0..MAX_HOOKS] of TISRHook;
```

Array of hook callbacks for a single interrupt vector.

### TISRHookArray

```pascal
TISRHookArray = Array[0..255] of TISRNHookArray;
```

Two-dimensional array of all hook callbacks, indexed by vector number then hook slot.

## Functions and Procedures

### init

```pascal
procedure init;
```

Installs assembly ISR stubs for all 256 vectors into the IDT using `arch.x86.idt.set_gate` with selector `$08` and `ISR_RING_0` flags. All hook slots are initialised to `nil` during unit startup.

### registerISR

```pascal
procedure registerISR(INT_N : uint8; callback : TISRHook);
```

Registers a callback for interrupt vector `INT_N`. Scans the hook slot array for the first empty slot (nil entry) and assigns `callback` to it. Up to `MAX_HOOKS` callbacks may be registered per vector.

- `INT_N` — The IDT vector number (0–255).
- `callback` — The procedure to invoke when the interrupt fires.

### dispatchHooks

```pascal
procedure dispatchHooks(INT_N : uint8);
```

Iterates through all `MAX_HOOKS` slots for vector `INT_N` and calls each non-nil callback. Does not send EOI. Used by the context switch ISR (`arch.x86.proc.sched`) to fire timer hooks before sending EOI independently.

## Notes

- The internal `ISR_N` procedure dispatches all hooks for a given vector, sends a Local APIC EOI via `arch.x86.isr.ioapic.lapic_eoi`, and then sends an 8259 EOI. For slave PIC interrupts (vectors 40–47), the slave EOI (`$A0`) is sent before the master EOI (`$20`).
- The context switch ISR (`arch.x86.proc.sched.context_switch_isr`) replaces IDT gate 32 after `init` is called and manages its own EOI, bypassing `ISR_N` for the timer vector.
- The `interrupt` procedure directive on each ISR stub causes Free Pascal to generate the correct PUSHAD/POPAD frame and IRETD. The EBP register at the start of this frame is saved to `IntReg` so that fault handlers can locate the saved register state.
