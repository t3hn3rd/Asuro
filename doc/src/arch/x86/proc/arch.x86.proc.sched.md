# arch.x86.proc.sched

Preemptive context switch ISR for the x86 round-robin scheduler.

## Overview

This unit implements the IRQ 0 (PIT timer, IDT vector 32) interrupt handler that performs preemptive context switching. It replaces the default ISR_32 stub installed by `arch.x86.isr.mgr` with a custom naked assembly procedure that saves the interrupted process's full register state (GPRs and segment registers) onto its kernel stack, calls a Pascal helper to dispatch timer hooks and run the scheduler, and then restores the selected next process's register state before returning from the interrupt.

The assembly ISR stores the current stack pointer in the process manager's `CurrentProcess.SavedESP` field and resumes execution using the ESP returned by the scheduler, enabling zero-copy context switching.

## Dependencies

- `arch.x86.idt`
- `arch.x86.isr.mgr`
- `proc.mgr`
- `proc.types`
- `core.util`
- `arch.x86.util`
- `io.syslog`
- `debug.tracer`

## Functions and Procedures

### init

```pascal
procedure init;
```

Installs `context_switch_isr` into IDT gate 32 (IRQ 0) using `arch.x86.idt.set_gate` with selector `$08` and `ISR_RING_0` flags. Must be called after `arch.x86.isr.mgr.init` so the default gate is already set before being overridden.

### do_context_switch_work (internal)

```pascal
function do_context_switch_work(saved_esp : uint32) : uint32;
```

Pascal helper called from the naked assembly ISR using the register calling convention (argument in EAX, result in EAX).

1. Saves `saved_esp` into `proc.mgr.CurrentProcess^.SavedESP`.
2. Calls `arch.x86.isr.mgr.dispatchHooks(32)` to fire all timer callbacks (BDA tick update, graphics refresh, etc.).
3. Sends EOI to the master 8259 PIC (port `$20`, value `$20`).
4. Calls `proc.mgr.scheduler_pick_next` to select the next process.
5. Updates `proc.mgr.CurrentProcess` to the selected process.
6. Returns the selected process's `SavedESP`.

### context_switch_isr (internal, naked)

```pascal
procedure context_switch_isr; assembler; nostackframe;
```

Naked assembly ISR. On entry, the CPU has pushed EIP, CS, and EFLAGS onto the current process stack.

Execution sequence:
1. `PUSHAD` — saves EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI.
2. Saves DS, ES, FS, GS.
3. Loads kernel data segment selectors (`$10`).
4. Passes ESP (pointing to the full saved-state block) to `do_context_switch_work`.
5. Replaces ESP with the returned value (the next process's saved ESP).
6. Restores GS, FS, ES, DS.
7. `POPAD` — restores general-purpose registers.
8. `IRETD` — resumes the next process.

## Notes

- The saved state layout on the stack (from lowest to highest address): DS, ES, FS, GS, PUSHAD frame (EDI,ESI,EBP,ESP,EBX,EDX,ECX,EAX), IRET frame (EIP, CS, EFLAGS).
- The idle process (PID 0) is a formal process entry in the process table with its own `SavedESP`, managed like any other process. There is no separate idle stack variable.
- This unit does not interact with `arch.x86.isr.tmr0` directly; timer hooks from tmr0 are fired via the `dispatchHooks(32)` call in `do_context_switch_work`.
- `init` must be called after the process manager is initialised and at least one process (the idle process) has been created.
