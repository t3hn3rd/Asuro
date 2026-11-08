{
    Prog->Ping - ICMP Ping command.

    Sends 10 ICMP echo requests to a host, printing round-trip time
    for each reply. Sleeps 1 second between pings. Each invocation
    uses a heap-allocated state record so multiple terminals can app.ping
    concurrently without corrupting each other.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit app.ping;

interface

uses
    io.stdio, debug.tracer;

procedure init();

implementation

uses
    proc.types, driver.net.types, driver.net.proto.icmp, driver.net.util, core.strings,
    proc.mgr, core.util, arch.platform.cpu, memory.heap;

const
    PING_TIMEOUT_MS = 5000;  { 5-second timeout per app.ping }

type
    TPingResult = (prWaiting, prGotReply, prGotError);
    PPingState  = ^TPingState;
    TPingState  = record
        Result      : TPingResult;
        ReplyTimeMS : uint32;
        ErrorReason : TARPErrorCode;
        SendTime    : uint32;
        Address     : puint8;
    end;

procedure cleanup(handle: void);
var
    st: PPingState;
begin
    st := PPingState(handle);
    if st = nil then exit;
    driver.net.proto.icmp.cancelRequests(handle);
    kfree(void(st^.Address));
    kfree(handle);
end;

{ ---- ICMP callbacks (called from network recv context) ---- }

procedure on_reply(hdr : PICMPHeader; userData : void);
var
    st : PPingState;
    t2 : uint32;
begin
    st := PPingState(userData);
    if st = nil then exit;
    t2 := networkTicks;
    st^.ReplyTimeMS := (uint64(uint32(t2 - st^.SendTime)) * 1000) div 1024;
    st^.Result := prGotReply;
end;

procedure on_error(hdr : PICMPHeader; Reason : TARPErrorCode; userData : void);
var
    st : PPingState;
begin
    st := PPingState(userData);
    if st = nil then exit;
    st^.ErrorReason := Reason;
    st^.Result := prGotError;
end;

{ ---- Command entry point (runs as a process) ---- }

procedure run(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    ip_str   : pchar;
    ip       : puint8;
    i        : uint16;
    st       : PPingState;
    tStart   : uint32;
    tNow     : uint32;
    elapsed  : uint32;
    timeoutTicks : uint32;
begin
    if ParamCount(Params) < 1 then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'Usage: PING <ip>');
        exit;
    end;

    ip_str := getParam(0, Params);
    ip := stringToIPv4(ip_str);
    if ip = nil then begin
        io.stdio.bufWriteStrLn(stderr_buf, 'Invalid IP address.');
        exit;
    end;

    { Allocate per-invocation state so concurrent pings are safe }
    st := PPingState(kalloc(sizeof(TPingState)));
    if st = nil then begin
        kfree(void(ip));
        exit;
    end;
    st^.Address := ip;
    proc.mgr.bindResource(proc.mgr.CurrentProcess, rkCustom, void(st), @cleanup);
    timeoutTicks := (PING_TIMEOUT_MS * 1024) div 1000;

    for i := 0 to 9 do begin
        { Send ICMP echo request }
        st^.Result := prWaiting;
        st^.SendTime := networkTicks;
        driver.net.proto.icmp.sendICMPRequest(ip, i, 128, @on_reply, @on_error, void(st));

        { Spin-yield until callback fires or timeout }
        tStart := networkTicks;
        while st^.Result = prWaiting do begin
            proc.mgr.proc_yield;
            tNow := networkTicks;
            if tNow >= tStart then
                elapsed := tNow - tStart
            else
                elapsed := ($FFFFFFFF - tStart) + tNow + 1;
            if elapsed >= timeoutTicks then begin
                driver.net.proto.icmp.cancelRequests(void(st));
                st^.Result := prGotError;
                st^.ErrorReason := aecTimeout;
                break;
            end;
        end;

        { Display result }
        if st^.Result = prGotReply then begin
            io.stdio.bufWriteStr(stdout_buf, 'Ping Reply: ');
            io.stdio.bufWriteInt(stdout_buf, st^.ReplyTimeMS);
            io.stdio.bufWriteStrLn(stdout_buf, 'ms.');
        end else begin
            io.stdio.bufWriteStr(stderr_buf, 'Ping Error: ');
            case st^.ErrorReason of
                aecFailedToResolveHost: io.stdio.bufWriteStrLn(stderr_buf, 'Failed to resolve host.');
                aecNoRouteToHost:       io.stdio.bufWriteStrLn(stderr_buf, 'No route to host.');
                aecTimeout:             io.stdio.bufWriteStrLn(stderr_buf, 'Timeout expired.');
                aecTTLExpired:          io.stdio.bufWriteStrLn(stderr_buf, 'TTL Expired.');
            end;
        end;

        { Sleep 1 second between pings (except after last) }
        if i < 9 then
            proc.mgr.proc_sleep_ms(1000);
    end;

    { Clean up }
    proc.mgr.unbindResource(proc.mgr.CurrentProcess, void(st));
end;

procedure init();
begin
    debug.tracer.push_trace('ping.init');
    io.stdio.registerCommand('PING', @run, 'Ping a host.');
end;

end.
