{
    Prog->Ping - ICMP Ping command.

    Sends 10 ICMP echo requests to a host, printing round-trip time
    for each reply. Sleeps 1 second between pings. Each invocation
    uses a heap-allocated state record so multiple terminals can ping
    concurrently without corrupting each other.

    @author(Kieron Morris <kjm@kieronmorris.me>)
}
unit ping;

interface

uses
    stdio, tracer;

procedure init();

implementation

uses
    bios_data_area, nettypes, icmp, netutils, strings,
    processmanager, util, lmemorymanager;

const
    PING_TIMEOUT_MS = 5000;  { 5-second timeout per ping }

type
    TPingResult = (prWaiting, prGotReply, prGotError);
    PPingState  = ^TPingState;
    TPingState  = record
        Result      : TPingResult;
        ReplyTimeMS : uint64;
        ErrorReason : TARPErrorCode;
        SendTime    : uint64;
    end;

{ ---- ICMP callbacks (called from network recv context) ---- }

procedure on_reply(hdr : PICMPHeader; userData : void);
var
    st : PPingState;
    t2 : uint64;
begin
    st := PPingState(userData);
    if st = nil then exit;
    t2 := Counters.c64;
    st^.ReplyTimeMS := t2 - st^.SendTime;
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
        stdio.bufWriteStrLn(stderr_buf, 'Usage: PING <ip>');
        exit;
    end;

    ip_str := getParam(0, Params);
    ip := stringToIPv4(ip_str);
    if ip = nil then begin
        stdio.bufWriteStrLn(stderr_buf, 'Invalid IP address.');
        exit;
    end;

    { Allocate per-invocation state so concurrent pings are safe }
    st := PPingState(kalloc(sizeof(TPingState)));
    timeoutTicks := (PING_TIMEOUT_MS * 1024) div 1000;

    for i := 0 to 9 do begin
        { Send ICMP echo request }
        st^.Result := prWaiting;
        st^.SendTime := Counters.c64;
        icmp.sendICMPRequest(ip, i, 128, @on_reply, @on_error, void(st));

        { Spin-yield until callback fires or timeout }
        tStart := Counters.c32;
        while st^.Result = prWaiting do begin
            processmanager.proc_yield;
            tNow := Counters.c32;
            if tNow >= tStart then
                elapsed := tNow - tStart
            else
                elapsed := ($FFFFFFFF - tStart) + tNow + 1;
            if elapsed >= timeoutTicks then begin
                st^.Result := prGotError;
                st^.ErrorReason := aecTimeout;
                break;
            end;
        end;

        { Display result }
        if st^.Result = prGotReply then begin
            stdio.bufWriteStr(stdout_buf, 'Ping Reply: ');
            stdio.bufWriteInt(stdout_buf, st^.ReplyTimeMS);
            stdio.bufWriteStrLn(stdout_buf, 'ms.');
        end else begin
            stdio.bufWriteStr(stderr_buf, 'Ping Error: ');
            case st^.ErrorReason of
                aecFailedToResolveHost: stdio.bufWriteStrLn(stderr_buf, 'Failed to resolve host.');
                aecNoRouteToHost:       stdio.bufWriteStrLn(stderr_buf, 'No route to host.');
                aecTimeout:             stdio.bufWriteStrLn(stderr_buf, 'Timeout expired.');
                aecTTLExpired:          stdio.bufWriteStrLn(stderr_buf, 'TTL Expired.');
            end;
        end;

        { Sleep 1 second between pings (except after last) }
        if i < 9 then
            processmanager.proc_sleep_ms(1000);
    end;

    { Clean up }
    kfree(void(st));
    kfree(void(ip));
end;

procedure init();
begin
    tracer.push_trace('ping.init');
    stdio.registerCommand('PING', @run, 'Ping a host.');
end;

end.