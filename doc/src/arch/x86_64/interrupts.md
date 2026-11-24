# Exceptions, interrupts and scheduling

The long-mode IDT and TSS give double fault, NMI and machine check separate interrupt stacks (IST1, IST2 and IST3). The bootstrap stack and each emergency stack have a 4 KiB unmapped guard. Boot probes each guard with a recoverable page fault. The deliberate overflow test pushes across the bootstrap guard and verifies the saved stack pointer, instruction pointer and IST1 frame. CR2 can retain an earlier fault address during double-fault delivery.

Assembly entry stubs normalize exception frames, save registers and preserve x87/SSE state across the handler. Fatal diagnostics write the frame and registers to COM1. The `ud`, `pf` and `df` profiles exercise fatal paths in VirtualBox. A separate QEMU verifier checks unsupported CPUs and injects NMI and machine check. [Fault test commands](../../../planning/x86_64.md#repeatable-virtualbox-fault-checks)

Hardware IRQs use the legacy PIC and PIT. The native scheduler adapter saves the interrupted kernel stack, lets the shared scheduler select a process and restores the selected context. Kernel preemption and process return are exercised on this path. User-mode transitions, per-process address spaces and AVX context switching remain outside the supported configuration.
