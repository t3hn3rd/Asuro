# Exceptions, interrupts and scheduling

The long-mode IDT and TSS give double fault, NMI and machine check separate interrupt stacks (IST1, IST2 and IST3). The bootstrap stack and each emergency stack have a 4 KiB unmapped guard. Validation profiles probe each guard with a recoverable page fault. The deliberate overflow test pushes across the bootstrap guard and verifies the saved stack pointer, instruction pointer and IST1 frame. CR2 can retain an earlier fault address during double-fault delivery.

Assembly entry stubs normalize exception frames, save registers and preserve x87/SSE state across the handler. Fatal diagnostics write the frame and registers to COM1. The `ud`, `pf` and `df` profiles exercise fatal paths in VirtualBox. A separate QEMU verifier checks unsupported CPUs and injects NMI and machine check. [Fault test commands](../../../planning/x86_64.md#repeatable-virtualbox-fault-checks)

Hardware IRQs use the legacy PIC and PIT. OHCI, xHCI, AHCI and E1000 check the PCI interrupt line before starting their controllers. Native routing rejects IRQ0 (PIT), IRQ2 (PIC cascade), and lines outside the PIC range. The scheduler supplies its timer vector when it registers the context selector. The current PIT route uses vector 32. The native scheduler adapter saves the interrupted kernel stack, lets the shared scheduler select a process and restores the selected context. Kernel preemption and process return are exercised on this path. User-mode transitions, per-process address spaces and AVX context switching remain outside the supported configuration.

The native IRQ registry supports detaching individual handlers with
`unregisterIRQ`. Call it after quiescing the device and outside dispatch.
Removal leaves other handlers on the shared line registered.

## Native panic diagnostics

After framebuffer initialization a fatal exception displays its vector, error code, RIP, RSP, CR2 and recent trace history. The panic handler draws into the current 32-bpp front buffer with interrupts disabled and uses no heap allocation or LVGL calls. COM1 receives the full register frame even when the display is unavailable.

Use `TRACER list 5` to inspect recent entries. The tracer records call history, so a pop leaves the entry visible. Each of the following diagnostic commands halts the guest and requires a fresh boot.

| Command | Expected result |
| --- | --- |
| `BSOD test detail` | Displays the supplied reason and detail. |
| `DIV0` | Reports divide error, vector 0. |
| `PF` | Reports page fault, vector 14, with CR2 equal to 0x100000000. |
| `CRASHGFXD` | Raises a divide error in the graphics service and draws the panic screen directly to the framebuffer. |
