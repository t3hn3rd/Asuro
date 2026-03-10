{
    Prog->Ping - ICMP Ping command.

    Sends 10 ICMP echo requests to a host, printing round-trip time
    for each reply. Sleeps 1 second between pings. Each invocation
    uses a heap-allocated state record so multiple terminals can app.ping
    concurrently without corrupting each other.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.divzero;

interface

uses
    io.stdio, debug.tracer;

procedure init();

implementation

uses
    arch.x86.bda, driver.net.types, driver.net.proto.icmp, driver.net.util, core.strings,
    proc.mgr, core.util, arch.x86.util, memory.heap, svc.gfxd;

{ ---- Command entry point (runs as a process) ---- }

procedure run_div0(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    asm
        XOR EAX, EAX
        DIV EAX  { this will trigger a divide by zero exception (interrupt 0) }
    end;
end;

procedure run_pf(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    asm
        MOV EAX, $DEADBEEF
        MOV [EAX], EAX  { this will trigger a page fault (interrupt 14) }
    end;
end;

procedure run_div0_gfxd(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    svc.gfxd.SHOULD_CRASH := true;  { set flag to trigger crash in graphics service }
end;

procedure init();
begin
    debug.tracer.push_trace('divzero.init');
    io.stdio.registerCommand('DIV0', @run_div0, 'Force a divide by zero exception.');
    io.stdio.registerCommand('PF', @run_pf, 'Force a page fault.');
    io.stdio.registerCommand('CRASHGFXD', @run_div0_gfxd, 'Force a divide by zero exception in the graphics service.');
end;

end.