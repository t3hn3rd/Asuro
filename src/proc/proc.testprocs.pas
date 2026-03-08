{
    TestProcs - Temporary test processes for validating preemptive scheduling.

    Two processes that each print a message once per second via io.syslog,
    demonstrating concurrent preemptive execution.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit proc.testprocs;

interface

uses
    proc.types, proc.mgr, io.syslog, arch.x86.bda;

procedure init;

implementation

{ Simple busy-wait sleep: spin-yields until approx 'ticks' timer ticks
  have elapsed (timer runs at ~1024 Hz, so 1024 ticks ~ 1 second). }
procedure sleep_ticks(ticks : uint16);
var
    start, now, elapsed : uint16;
begin
    start := BDA^.Ticks;
    repeat
        proc_yield;
        now := BDA^.Ticks;
        if now >= start then
            elapsed := now - start
        else
            elapsed := (65535 - start) + now + 1;  { handle uint16 wrap }
    until elapsed >= ticks;
end;

procedure program1(ctx : PProcessContext);
begin
    while ctx^.PendingMsg <> smTerminate do begin
        io.syslog.logln('PROC1', 'Hello from program 1');
        sleep_ticks(1024);
    end;
end;

procedure program2(ctx : PProcessContext);
begin
    while ctx^.PendingMsg <> smTerminate do begin
        io.syslog.logln('PROC2', 'Hello from program 2');
        sleep_ticks(1024);
    end;
end;

procedure init;
begin
    proc.mgr.create('testproc1', @program1, nil, 1);
    proc.mgr.create('testproc2', @program2, nil, 1);
    io.syslog.logln('TESTPROCS', 'Two test processes created.');
end;

end.
