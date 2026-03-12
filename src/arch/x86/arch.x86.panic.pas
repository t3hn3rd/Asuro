{
    arch.x86.panic - x86-specific kernel panic bridge.

    Reads the saved interrupt register state (IntReg, IntErr, IntSpec)
    and packs it into a TRegisterSnapshot, then delegates to
    core.panic.panic() for architecture-agnostic display and halt.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit arch.x86.panic;

interface

uses
    boot.mgr,
    core.panic,
    io.syslog;

{ Register the x86 halt procedure with core.panic. Call after LVGL init. }
procedure init;

{ Build a register snapshot from IntReg/IntErr/IntSpec and trigger panic.
  Must be called AFTER correctInterruptRegisters(). }
procedure x86_panic(fault : pchar; info : pchar);

implementation

uses
    arch.x86.util,
    arch.x86.isr.types;

{ Helper: add a register entry to the snapshot and increment count. }
procedure addEntry(var snap : TRegisterSnapshot; name : pchar; value : uint32);
begin
    if snap.Count < MAX_REGISTER_ENTRIES then begin
        snap.Entries[snap.Count].Name := name;
        snap.Entries[snap.Count].Value := value;
        Inc(snap.Count);
    end;
end;

procedure x86_panic(fault : pchar; info : pchar);
var
    snap : TRegisterSnapshot;
begin
    snap.Count := 0;

    { Pack general-purpose registers from the saved interrupt frame }
    if IntReg <> nil then begin
        addEntry(snap, 'EBP', IntReg^.EBP);
        addEntry(snap, 'EAX', IntReg^.EAX);
        addEntry(snap, 'EBX', IntReg^.EBX);
        addEntry(snap, 'ECX', IntReg^.ECX);
        addEntry(snap, 'EDX', IntReg^.EDX);
        addEntry(snap, 'ESI', IntReg^.ESI);
        addEntry(snap, 'EDI', IntReg^.EDI);
        addEntry(snap, 'DS',  uint32(IntReg^.DS));
        addEntry(snap, 'ES',  uint32(IntReg^.ES));
        addEntry(snap, 'FS',  uint32(IntReg^.FS));
        addEntry(snap, 'GS',  uint32(IntReg^.GS));
    end;

    { Error code }
    if IntErr <> nil then
        addEntry(snap, 'ERROR', IntErr^.Error);

    { Special registers (EIP, CS, EFLAGS) }
    if IntSpec <> nil then begin
        addEntry(snap, 'EIP',    IntSpec^.EIP);
        addEntry(snap, 'CS',     IntSpec^.CS);
        addEntry(snap, 'EFLAGS', IntSpec^.EFLAGS);
    end;

    core.panic.panic(fault, info, @snap);
end;

procedure init;
begin
    io.syslog.logln('PANIC', 'Initializing x86 Panic Handler.');

    { Register x86 halt as the panic halt procedure }
    core.panic.registerHaltProc(@arch.x86.util.halt_and_catch_fire);

    io.syslog.logln('PANIC', 'Initialization complete.');
end;

initialization
    boot.mgr.registerBoot('arch.x86.panic', @init, 'Panic Screen', 'driver.video*');

end.
