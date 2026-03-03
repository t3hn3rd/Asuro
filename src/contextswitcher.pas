//  Copyright 2021 Kieron Morris
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
    ContextSwitcher - Custom IRQ0 handler for preemptive context switching.

    Replaces the default ISR_32 with a naked assembly stub that saves the
    interrupted context (PUSHAD + segment regs), calls a Pascal helper to
    dispatch timer hooks, send EOI, and run the scheduler, then restores
    the next process context (or idles) via the returned ESP.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit contextswitcher;

{$ASMMODE intel}

interface

uses
    idt, isrmanager, processmanager, proctypes, util, syslog, tracer;

{ Initialise: overwrite IDT gate 32 with our custom ISR. }
procedure init;

{ No idle ESP variable needed — idle is now a formal process (PID 0)
  with its SavedESP managed like any other process. }

implementation

{ -----------------------------------------------------------------------
  do_context_switch_work
  Pascal helper called from the assembly ISR.  Receives the current ESP
  (pointing to the GS..EFLAGS save area), dispatches timer hooks, sends
  EOI, runs the scheduler and returns the ESP for the next context.
  Uses register calling convention: saved_esp in EAX, result in EAX.
  ----------------------------------------------------------------------- }
function do_context_switch_work(saved_esp : uint32) : uint32;
var
    next : PProcessContext;
begin
    { 1. Save ESP into the current process }
    processmanager.CurrentProcess^.SavedESP := saved_esp;

    { 2. Dispatch all hooks registered on interrupt 32 (timer hooks).
         This fires TMR_0_ISR.Main which in turn fires BDA tick,
         graphics refresh, USB hotplug, etc. }
    isrmanager.dispatchHooks(32);

    { 3. Send End-Of-Interrupt to the master PIC }
    outb($20, $20);

    { 4. Pick the next process to run (always returns non-nil; idle as fallback) }
    next := processmanager.scheduler_pick_next;
    processmanager.CurrentProcess := next;

    { 5. Return the selected process ESP }
    do_context_switch_work := next^.SavedESP;
end;

{ -----------------------------------------------------------------------
  context_switch_isr
  Naked assembly ISR that replaces ISR_32 (IRQ0 / PIT timer).

  Stack on entry (pushed by CPU):
      [ESP+8] EFLAGS
      [ESP+4] CS
      [ESP+0] EIP

  We push general-purpose and segment registers, call the Pascal helper,
  switch ESP to the returned value, pop registers and IRETD.
  ----------------------------------------------------------------------- }
procedure context_switch_isr; assembler; nostackframe;
asm
    { Save all general-purpose registers (EAX,ECX,EDX,EBX,ESP,EBP,ESI,EDI) }
    pushad

    { Save segment registers }
    push ds
    push es
    push fs
    push gs

    { Load kernel data segments }
    mov ax, $10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    { Call Pascal helper: EAX = current ESP (register calling convention).
      Returns new ESP in EAX. }
    mov eax, esp
    call do_context_switch_work
    mov esp, eax

    { Restore segment registers }
    pop gs
    pop fs
    pop es
    pop ds

    { Restore general-purpose registers }
    popad

    { Return from interrupt }
    iretd
end;

{ -----------------------------------------------------------------------
  init
  Override IDT gate 32 with our custom ISR.  Must be called AFTER
  isrmanager.init so that the default gate has been set up first.
  ----------------------------------------------------------------------- }
procedure init;
begin
    idt.set_gate(32, uint32(@context_switch_isr), $08, ISR_RING_0);
    tracer.push_trace('contextswitcher.init');
end;

end.