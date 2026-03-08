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
	Driver->Net->L4->TCP - Transmission Control Protocol Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.net.tcp;

interface

uses
    debug.tracer, io.stdio,
    driver.net.types, driver.net.util,
    driver.net.ipv4;

procedure register();
function  connect(context : PTCPConnectContext) : PTCPSocket;
function  listen(context : PTCPListenContext) : PTCPSocket;
function  accept(listener : PTCPSocket) : PTCPSocket;
function  send(socket : PTCPSocket; p_data : void; p_len : uint16) : TTCPError;
function  close(socket : PTCPSocket) : TTCPError;
function  abort_connection(socket : PTCPSocket) : TTCPError;
procedure terminal_command_tcpconnect(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
procedure terminal_command_tcplisten(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
procedure terminal_command_tcphttp(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);

implementation

uses
    memory.heap, core.util, arch.x86.util, io.syslog, core.rand, core.ds.lists,
    driver.net, arch.x86.isr.tmr0, arch.x86.bda,
    core.strings, driver.net.arp,
    proc.mgr, proc.types;

const
    TCP_PROTOCOL_ID     = $06;
    TCP_DEFAULT_MSS     = 1460;
    TCP_DEFAULT_WINDOW  = 8192;
    TCP_MAX_RETRANS     = 5;
    TCP_RETRANS_TICKS   = 1024;   { 1 second at 1024 Hz }
    TCP_TIMEWAIT_TICKS  = 61440;  { ~60 seconds (2*MSL) at 1024 Hz }
    TCP_SYN_RETRANS_TICKS = 3072; { 3 seconds for SYN retransmit }

    { TCP Flags }
    TCP_FLAG_FIN = $001;
    TCP_FLAG_SYN = $002;
    TCP_FLAG_RST = $004;
    TCP_FLAG_PSH = $008;
    TCP_FLAG_ACK = $010;
    TCP_FLAG_URG = $020;

    { Phase 3 constants }
    TCP_DELAYED_ACK_TICKS = 205;     { ~200ms at 1024 Hz }
    TCP_KEEPALIVE_IDLE    = 30720;   { 30 seconds idle before first probe }
    TCP_KEEPALIVE_INTVL   = 10240;   { 10 seconds between probes }
    TCP_KEEPALIVE_PROBES  = 5;       { max probes before abort }
    TCP_ZWP_INITIAL       = 1024;    { 1 second initial zero-window probe }
    TCP_ZWP_MAX           = 61440;   { 60 second max zero-window probe }
    TCP_INITIAL_CWND_SEGS = 3;       { initial congestion window in segments }
    TCP_MIN_RTO           = 1024;    { 1 second minimum RTO }
    TCP_MAX_RTO           = 61440;   { 60 second maximum RTO }
    TCP_OOO_MAX           = 4;       { max out-of-order segment slots }
    TCP_MSS_OPT_KIND      = 2;       { TCP option kind for MSS }
    TCP_MSS_OPT_LEN       = 4;       { TCP option length for MSS }

var
    Connections : PDList;
    Registered  : Boolean = false;

{ ============================================================================ }
{  Utility: TCP Flag Helpers                                                   }
{ ============================================================================ }

function MakeDataOffFlags(dataoff : uint8; flags : uint16) : uint16;
{ Build the DataOff_Flags field: high nibble = dataoff, lower 12 bits = flags }
begin
    MakeDataOffFlags := ((uint16(dataoff) SHL 12) AND $F000) OR (flags AND $0FFF);
end;

function GetDataOffset(dataoff_flags : uint16) : uint8;
begin
    GetDataOffset := (switchendian16(dataoff_flags) SHR 12) AND $0F;
end;

function GetFlags(dataoff_flags : uint16) : uint16;
begin
    GetFlags := switchendian16(dataoff_flags) AND $0FFF;
end;

{ ============================================================================ }
{  Utility: TCP Checksum (RFC 793 - pseudo header based)                       }
{ ============================================================================ }

function CalculateChecksum(tcpData : void; tcpLen : uint16; srcIP, dstIP : puint8) : uint16;
var
    pseudoSize   : uint16;
    pseudoBuf    : void;
    pseudoHdr    : PTCPPseudoHeader;
    sum          : uint32;
    data16       : puint16;
    remaining    : uint16;
begin
    push_trace('driver.net.tcp.CalculateChecksum');
    pseudoSize := sizeof(TTCPPseudoHeader) + tcpLen;
    { Pad to even length for checksum }
    if (pseudoSize mod 2) = 1 then
        pseudoSize := pseudoSize + 1;

    pseudoBuf := kalloc(pseudoSize);
    memset(uint32(pseudoBuf), 0, pseudoSize);

    pseudoHdr := PTCPPseudoHeader(pseudoBuf);
    memcpy(uint32(srcIP), uint32(@pseudoHdr^.Source_IP), 4);
    memcpy(uint32(dstIP), uint32(@pseudoHdr^.Destination_IP), 4);
    pseudoHdr^.Reserved := 0;
    pseudoHdr^.Protocol := TCP_PROTOCOL_ID;
    pseudoHdr^.TCP_Length := switchendian16(tcpLen);

    memcpy(uint32(tcpData), uint32(pseudoBuf) + sizeof(TTCPPseudoHeader), tcpLen);

    { Compute one's complement sum }
    sum := 0;
    data16 := puint16(pseudoBuf);
    remaining := pseudoSize;
    while remaining > 1 do begin
        sum := sum + data16^;
        inc(data16);
        remaining := remaining - 2;
    end;

    { Fold carries }
    while (sum AND $FFFF0000) <> 0 do
        sum := (sum AND $FFFF) + (sum SHR 16);

    CalculateChecksum := uint16(NOT sum);
    kfree(pseudoBuf);
end;

{ ============================================================================ }
{  TCB Management                                                              }
{ ============================================================================ }

function CreateTCB : PTCB;
var
    tcb : PTCB;
    i   : uint32;
begin
    push_trace('driver.net.tcp.CreateTCB');
    tcb := PTCB(kalloc(sizeof(TTCB)));
    memset(uint32(tcb), 0, sizeof(TTCB));
    tcb^.State := tssClosed;
    tcb^.RCV_WND := TCP_DEFAULT_WINDOW;
    tcb^.SendBufSize := TCP_DEFAULT_WINDOW;
    tcb^.RecvBufSize := TCP_DEFAULT_WINDOW;
    tcb^.SendBuf := kalloc(TCP_DEFAULT_WINDOW);
    tcb^.RecvBuf := kalloc(TCP_DEFAULT_WINDOW);
    tcb^.SendBufLen := 0;
    tcb^.RecvBufLen := 0;
    tcb^.Active := true;

    { Phase 2: Backlog }
    tcb^.BacklogQueue := nil;
    tcb^.BacklogMax := 0;
    tcb^.BacklogCount := 0;

    { Phase 3: Delayed ACK }
    tcb^.DelayedAckPending := false;
    tcb^.DelayedAckTimer := 0;

    { Phase 3: Nagle (enabled by default) }
    tcb^.NagleEnabled := true;

    { Phase 3: RTT estimation }
    tcb^.SRTT := 0;
    tcb^.RTTVAR := 0;
    tcb^.RTO := TCP_RETRANS_TICKS;  { default 1 second }
    tcb^.RTTMeasuring := false;
    tcb^.RTTSeqNum := 0;
    tcb^.RTTStartTime := 0;

    { Phase 3: Congestion control }
    tcb^.CongWnd := TCP_INITIAL_CWND_SEGS * TCP_DEFAULT_MSS;
    tcb^.SSThresh := 65535;

    { Phase 3: Zero-window probing }
    tcb^.ZWPTimer := 0;
    tcb^.ZWPCount := 0;

    { Phase 3: MSS }
    tcb^.RemoteMSS := TCP_DEFAULT_MSS;

    { Phase 3: Keep-alive }
    tcb^.KeepAliveEnabled := true;
    tcb^.KeepAliveTimer := 0;
    tcb^.KeepAliveCount := 0;
    tcb^.KeepAliveIdle := TCP_KEEPALIVE_IDLE;

    { Phase 3: Out-of-order }
    for i := 0 to TCP_OOO_MAX - 1 do begin
        tcb^.OOOSegments[i].Valid := false;
        tcb^.OOOSegments[i].Data := nil;
        tcb^.OOOSegments[i].DataLen := 0;
        tcb^.OOOSegments[i].SeqNum := 0;
    end;

    CreateTCB := tcb;
end;

function CreateSocket(tcb : PTCB; onRecv : TTCPReceiveCallback; onEvt : TTCPEventCallback; userData : void) : PTCPSocket;
var
    sock : PTCPSocket;
begin
    push_trace('driver.net.tcp.CreateSocket');
    sock := PTCPSocket(kalloc(sizeof(TTCPSocket)));
    sock^.TCB := tcb;
    sock^.OnReceive := onRecv;
    sock^.OnEvent := onEvt;
    sock^.UserData := userData;
    sock^.OwnerPID := 0;
    tcb^.Socket := sock;
    CreateSocket := sock;
end;

procedure DestroyTCB(tcb : PTCB);
var
    i : uint32;
begin
    push_trace('driver.net.tcp.DestroyTCB');
    if tcb <> nil then begin
        if tcb^.SendBuf <> nil then kfree(tcb^.SendBuf);
        if tcb^.RecvBuf <> nil then kfree(tcb^.RecvBuf);
        if tcb^.RetransBuf <> nil then kfree(tcb^.RetransBuf);
        { Free OOO segment data }
        for i := 0 to TCP_OOO_MAX - 1 do begin
            if tcb^.OOOSegments[i].Valid and (tcb^.OOOSegments[i].Data <> nil) then
                kfree(tcb^.OOOSegments[i].Data);
        end;
        { Free backlog queue if listen socket }
        if tcb^.BacklogQueue <> nil then
            DL_Free(PDList(tcb^.BacklogQueue));
        tcb^.Active := false;
        kfree(void(tcb));
    end;
end;

procedure socket_cleanup(handle : void);
var
    sock : PTCPSocket;
begin
    sock := PTCPSocket(handle);
    if sock = nil then exit;
    sock^.OwnerPID := 0;  { Prevent DestroySocket from trying to unbind again }
    abort_connection(sock);
end;

procedure DestroySocket(sock : PTCPSocket);
var
    owner : PProcessContext;
begin
    push_trace('driver.net.tcp.DestroySocket');
    if sock <> nil then begin
        { Remove resource binding from owning process }
        if sock^.OwnerPID <> 0 then begin
            owner := proc.mgr.findByID(sock^.OwnerPID);
            sock^.OwnerPID := 0;
            if owner <> nil then
                proc.mgr.unbindResourceNoCleanup(owner, void(sock));
        end;
        if sock^.TCB <> nil then begin
            sock^.TCB^.Socket := nil;
            DestroyTCB(sock^.TCB);
        end;
        kfree(void(sock));
    end;
end;

function FindTCB(localPort, remotePort : uint16; remoteIP : puint8) : PTCB;
var
    i    : uint32;
    tcb  : PTCB;
    p    : void;
begin
    push_trace('driver.net.tcp.FindTCB');
    FindTCB := nil;
    if Connections = nil then exit;
    for i := 0 to DL_Size(Connections) - 1 do begin
        p := DL_Get(Connections, i);
        if p <> nil then begin
            tcb := PTCB(puint32(p)^);
            if tcb <> nil then begin
                if tcb^.Active then begin
                    if (tcb^.LocalPort = localPort) and
                       (tcb^.RemotePort = remotePort) and
                       IPEqual(@tcb^.RemoteIP[0], remoteIP) then begin
                        FindTCB := tcb;
                        exit;
                    end;
                end;
            end;
        end;
    end;
end;

function FindListenTCB(localPort : uint16) : PTCB;
var
    i    : uint32;
    tcb  : PTCB;
    p    : void;
begin
    push_trace('driver.net.tcp.FindListenTCB');
    FindListenTCB := nil;
    if Connections = nil then exit;
    for i := 0 to DL_Size(Connections) - 1 do begin
        p := DL_Get(Connections, i);
        if p <> nil then begin
            tcb := PTCB(puint32(p)^);
            if tcb <> nil then begin
                if tcb^.Active and (tcb^.State = tssListen) and (tcb^.LocalPort = localPort) then begin
                    FindListenTCB := tcb;
                    exit;
                end;
            end;
        end;
    end;
end;

procedure AddTCB(tcb : PTCB);
var
    p : puint32;
begin
    push_trace('driver.net.tcp.AddTCB');
    if Connections = nil then
        Connections := DL_New(sizeof(uint32));
    p := puint32(DL_Add(Connections));
    p^ := uint32(tcb);
end;

procedure RemoveTCB(tcb : PTCB);
var
    i   : uint32;
    p   : void;
    cur : PTCB;
begin
    push_trace('driver.net.tcp.RemoveTCB');
    if Connections = nil then exit;
    for i := 0 to DL_Size(Connections) - 1 do begin
        p := DL_Get(Connections, i);
        if p <> nil then begin
            cur := PTCB(puint32(p)^);
            if cur = tcb then begin
                DL_Delete(Connections, i);
                exit;
            end;
        end;
    end;
end;

function GenerateISN : uint32;
begin
    GenerateISN := rand32();
end;

function AllocEphemeralPort : uint16;
var
    port : uint16;
    i    : uint32;
begin
    push_trace('driver.net.tcp.AllocEphemeralPort');
    { Try random ports in ephemeral range 49152-65535 }
    for i := 0 to 1000 do begin
        port := 49152 + (rand16 mod 16384);
        if FindTCB(port, 0, @NULL_IP[0]) = nil then begin
            AllocEphemeralPort := port;
            exit;
        end;
    end;
    AllocEphemeralPort := 0; { failed }
end;

{ ============================================================================ }
{  Phase 2: Backlog Helpers                                                    }
{ ============================================================================ }

function CountPendingForPort(localPort : uint16) : uint32;
var
    i   : uint32;
    tcb : PTCB;
    p   : void;
begin
    push_trace('driver.net.tcp.CountPendingForPort');
    CountPendingForPort := 0;
    if Connections = nil then exit;
    for i := 0 to DL_Size(Connections) - 1 do begin
        p := DL_Get(Connections, i);
        if p <> nil then begin
            tcb := PTCB(puint32(p)^);
            if (tcb <> nil) and tcb^.Active and
               (tcb^.LocalPort = localPort) and
               (tcb^.State = tssSynReceived) then
                CountPendingForPort := CountPendingForPort + 1;
        end;
    end;
end;

function FindAcceptable(localPort : uint16) : PTCB;
{ Find the first ESTABLISHED connection spawned from a listen on localPort
  that has not yet been accepted (Socket^.UserData used as accept flag) }
var
    i   : uint32;
    tcb : PTCB;
    p   : void;
begin
    push_trace('driver.net.tcp.FindAcceptable');
    FindAcceptable := nil;
    if Connections = nil then exit;
    for i := 0 to DL_Size(Connections) - 1 do begin
        p := DL_Get(Connections, i);
        if p <> nil then begin
            tcb := PTCB(puint32(p)^);
            if (tcb <> nil) and tcb^.Active and
               (tcb^.LocalPort = localPort) and
               (tcb^.State = tssEstablished) and
               (tcb^.RemotePort <> 0) then begin
                FindAcceptable := tcb;
                exit;
            end;
        end;
    end;
end;

{ ============================================================================ }
{  Phase 3: MSS Option Helpers                                                 }
{ ============================================================================ }

function ParseMSSOption(opts : puint8; optsLen : uint16) : uint16;
{ Parse TCP options to find MSS value. Returns 0 if not found. }
var
    idx    : uint16;
    kind   : uint8;
    optLen : uint8;
begin
    push_trace('driver.net.tcp.ParseMSSOption');
    ParseMSSOption := 0;
    idx := 0;
    while idx < optsLen do begin
        kind := opts[idx];
        if kind = 0 then exit;  { End of options }
        if kind = 1 then begin  { NOP }
            inc(idx);
            continue;
        end;
        if (idx + 1) >= optsLen then exit;
        optLen := opts[idx + 1];
        if optLen < 2 then exit; { malformed }
        if (kind = TCP_MSS_OPT_KIND) and (optLen = TCP_MSS_OPT_LEN) and ((idx + 3) < optsLen) then begin
            ParseMSSOption := (uint16(opts[idx + 2]) SHL 8) OR uint16(opts[idx + 3]);
            exit;
        end;
        idx := idx + optLen;
    end;
end;

{ ============================================================================ }
{  Phase 3: RTT Estimation (Jacobson/Karels)                                   }
{ ============================================================================ }

procedure UpdateRTT(tcb : PTCB; measured : uint32);
var
    delta : sint32;
    rto   : uint32;
begin
    push_trace('driver.net.tcp.UpdateRTT');
    if tcb^.SRTT = 0 then begin
        { First measurement }
        tcb^.SRTT := measured SHL 3;     { SRTT = R * 8 }
        tcb^.RTTVAR := measured SHL 1;   { RTTVAR = R * 2 }
    end else begin
        { Subsequent measurement }
        delta := sint32(tcb^.SRTT SHR 3) - sint32(measured);
        if delta < 0 then delta := -delta;
        tcb^.RTTVAR := tcb^.RTTVAR - (tcb^.RTTVAR SHR 2) + uint32(delta);
        tcb^.SRTT := tcb^.SRTT - (tcb^.SRTT SHR 3) + measured;
    end;
    { RTO = SRTT/8 + max(1, RTTVAR) }
    rto := (tcb^.SRTT SHR 3) + tcb^.RTTVAR;
    if rto < TCP_MIN_RTO then rto := TCP_MIN_RTO;
    if rto > TCP_MAX_RTO then rto := TCP_MAX_RTO;
    tcb^.RTO := rto;
end;

{ ============================================================================ }
{  Phase 3: Out-of-Order Segment Helpers                                       }
{ ============================================================================ }

procedure InsertOOOSegment(tcb : PTCB; seqNum : uint32; payload : void; payloadLen : uint16);
var
    i     : uint32;
    oldest: uint32;
    oldIdx: uint32;
begin
    push_trace('driver.net.tcp.InsertOOOSegment');
    { Check for duplicate }
    for i := 0 to TCP_OOO_MAX - 1 do begin
        if tcb^.OOOSegments[i].Valid and (tcb^.OOOSegments[i].SeqNum = seqNum) then
            exit; { already buffered }
    end;
    { Find empty slot }
    for i := 0 to TCP_OOO_MAX - 1 do begin
        if not tcb^.OOOSegments[i].Valid then begin
            tcb^.OOOSegments[i].SeqNum := seqNum;
            tcb^.OOOSegments[i].Data := kalloc(payloadLen);
            memcpy(uint32(payload), uint32(tcb^.OOOSegments[i].Data), payloadLen);
            tcb^.OOOSegments[i].DataLen := payloadLen;
            tcb^.OOOSegments[i].Valid := true;
            exit;
        end;
    end;
    { All slots full - evict the one with the highest seq (farthest ahead) }
    oldest := 0;
    oldIdx := 0;
    for i := 0 to TCP_OOO_MAX - 1 do begin
        if tcb^.OOOSegments[i].SeqNum > oldest then begin
            oldest := tcb^.OOOSegments[i].SeqNum;
            oldIdx := i;
        end;
    end;
    if tcb^.OOOSegments[oldIdx].Data <> nil then
        kfree(tcb^.OOOSegments[oldIdx].Data);
    tcb^.OOOSegments[oldIdx].SeqNum := seqNum;
    tcb^.OOOSegments[oldIdx].Data := kalloc(payloadLen);
    memcpy(uint32(payload), uint32(tcb^.OOOSegments[oldIdx].Data), payloadLen);
    tcb^.OOOSegments[oldIdx].DataLen := payloadLen;
    tcb^.OOOSegments[oldIdx].Valid := true;
end;

function FlushOOOSegments(tcb : PTCB) : boolean;
{ Try to deliver buffered OOO segments that are now in-order.
  Returns true if any segments were flushed. }
var
    i       : uint32;
    flushed : boolean;
    found   : boolean;
    copyLen : uint16;
begin
    push_trace('driver.net.tcp.FlushOOOSegments');
    flushed := false;
    repeat
        found := false;
        for i := 0 to TCP_OOO_MAX - 1 do begin
            if tcb^.OOOSegments[i].Valid and (tcb^.OOOSegments[i].SeqNum = tcb^.RCV_NXT) then begin
                { This segment is now in-order }
                copyLen := tcb^.OOOSegments[i].DataLen;
                if copyLen > (tcb^.RecvBufSize - tcb^.RecvBufLen) then
                    copyLen := tcb^.RecvBufSize - tcb^.RecvBufLen;
                if copyLen > 0 then begin
                    memcpy(uint32(tcb^.OOOSegments[i].Data),
                           uint32(tcb^.RecvBuf) + tcb^.RecvBufLen, copyLen);
                    tcb^.RecvBufLen := tcb^.RecvBufLen + copyLen;
                    tcb^.RCV_NXT := tcb^.RCV_NXT + copyLen;
                    tcb^.RCV_WND := tcb^.RecvBufSize - tcb^.RecvBufLen;
                end;
                { Free OOO slot }
                if tcb^.OOOSegments[i].Data <> nil then
                    kfree(tcb^.OOOSegments[i].Data);
                tcb^.OOOSegments[i].Data := nil;
                tcb^.OOOSegments[i].Valid := false;
                flushed := true;
                found := true;
            end;
        end;
    until not found;
    FlushOOOSegments := flushed;
end;

{ ============================================================================ }
{  Segment Sending                                                             }
{ ============================================================================ }

procedure SendSegment(tcb : PTCB; flags : uint16; payload : void; payloadLen : uint16);
var
    hdr      : PTCPHeader;
    buffer   : void;
    totalLen : uint16;
    hdrLen   : uint16;
    context  : PPacketContext;
    chk      : uint16;
    opts     : puint8;
    isSYN    : boolean;
begin
    push_trace('driver.net.tcp.SendSegment');
    isSYN := (flags AND TCP_FLAG_SYN) <> 0;

    { Header size: 24 bytes if SYN (with MSS option), 20 otherwise }
    if isSYN then
        hdrLen := 24
    else
        hdrLen := sizeof(TTCPHeader);

    totalLen := hdrLen + payloadLen;
    buffer := kalloc(totalLen);
    memset(uint32(buffer), 0, totalLen);

    hdr := PTCPHeader(buffer);
    hdr^.SrcPort := switchendian16(tcb^.LocalPort);
    hdr^.DstPort := switchendian16(tcb^.RemotePort);
    hdr^.SeqNum  := switchendian32(tcb^.SND_NXT);
    hdr^.AckNum  := switchendian32(tcb^.RCV_NXT);

    if isSYN then begin
        { Data offset = 6 (24 bytes), includes MSS option }
        hdr^.DataOff_Flags := switchendian16(MakeDataOffFlags(6, flags));
        { Write MSS option after 20-byte header: Kind=2, Len=4, MSS }
        opts := puint8(uint32(buffer) + sizeof(TTCPHeader));
        opts[0] := TCP_MSS_OPT_KIND;
        opts[1] := TCP_MSS_OPT_LEN;
        opts[2] := uint8(TCP_DEFAULT_MSS SHR 8);
        opts[3] := uint8(TCP_DEFAULT_MSS AND $FF);
    end else begin
        hdr^.DataOff_Flags := switchendian16(MakeDataOffFlags(5, flags));
    end;

    hdr^.Window    := switchendian16(tcb^.RCV_WND);
    hdr^.Checksum  := 0;
    hdr^.UrgentPtr := 0;

    if (payload <> nil) and (payloadLen > 0) then
        memcpy(uint32(payload), uint32(buffer) + hdrLen, payloadLen);

    { Calculate checksum }
    chk := CalculateChecksum(buffer, totalLen, @tcb^.LocalIP[0], @tcb^.RemoteIP[0]);
    hdr^.Checksum := chk;

    { Build IPv4 context }
    context := newPacketContext;
    copyIPv4(@tcb^.LocalIP[0], @context^.IP.Source[0]);
    copyIPv4(@tcb^.RemoteIP[0], @context^.IP.Destination[0]);
    context^.Protocol.L4 := TCP_PROTOCOL_ID;
    context^.TTL := 64;

    { Resolve MAC via ARP - use source MAC from NIC }
    copyMAC(driver.net.getMAC, @context^.MAC.Source[0]);
    copyMAC(@tcb^.RemoteMAC[0], @context^.MAC.Destination[0]);

    { Clear delayed ACK if we're sending (piggyback) }
    if (flags AND TCP_FLAG_ACK) <> 0 then begin
        tcb^.DelayedAckPending := false;
        tcb^.DelayedAckTimer := 0;
    end;

    { Start RTT measurement if not already measuring and this carries data/SYN }
    if (not tcb^.RTTMeasuring) and
       ((payloadLen > 0) or isSYN) then begin
        tcb^.RTTMeasuring := true;
        tcb^.RTTSeqNum := tcb^.SND_NXT + payloadLen;
        if isSYN then tcb^.RTTSeqNum := tcb^.SND_NXT + 1;
        tcb^.RTTStartTime := Counters.c32;
    end;

    { Reset keep-alive timer on any send }
    if tcb^.KeepAliveEnabled and (tcb^.State = tssEstablished) then begin
        tcb^.KeepAliveTimer := tcb^.KeepAliveIdle;
        tcb^.KeepAliveCount := 0;
    end;

    driver.net.ipv4.send(buffer, totalLen, context);

    { Save retransmission buffer if this is a data or SYN/FIN segment }
    if ((flags AND (TCP_FLAG_SYN OR TCP_FLAG_FIN)) <> 0) or (payloadLen > 0) then begin
        if tcb^.RetransBuf <> nil then kfree(tcb^.RetransBuf);
        tcb^.RetransBuf := kalloc(totalLen);
        memcpy(uint32(buffer), uint32(tcb^.RetransBuf), totalLen);
        tcb^.RetransBufLen := totalLen;
        tcb^.RetransTimer := tcb^.RTO;  { Use adaptive RTO }
        tcb^.RetransCount := 0;
        tcb^.LastSendTime := Counters.c32;
    end;

    freePacketContext(context);
    kfree(buffer);
end;

procedure SendRST(localPort, remotePort : uint16; localIP, remoteIP : puint8; seqNum, ackNum : uint32);
var
    hdr     : TTCPHeader;
    buffer  : void;
    context : PPacketContext;
    chk     : uint16;
begin
    push_trace('driver.net.tcp.SendRST');
    buffer := kalloc(sizeof(TTCPHeader));
    memset(uint32(buffer), 0, sizeof(TTCPHeader));

    hdr.SrcPort := switchendian16(localPort);
    hdr.DstPort := switchendian16(remotePort);
    hdr.SeqNum  := switchendian32(seqNum);
    hdr.AckNum  := switchendian32(ackNum);
    hdr.DataOff_Flags := switchendian16(MakeDataOffFlags(5, TCP_FLAG_RST OR TCP_FLAG_ACK));
    hdr.Window    := 0;
    hdr.Checksum  := 0;
    hdr.UrgentPtr := 0;

    memcpy(uint32(@hdr), uint32(buffer), sizeof(TTCPHeader));

    chk := CalculateChecksum(buffer, sizeof(TTCPHeader), localIP, remoteIP);
    PTCPHeader(buffer)^.Checksum := chk;

    context := newPacketContext;
    copyIPv4(localIP, @context^.IP.Source[0]);
    copyIPv4(remoteIP, @context^.IP.Destination[0]);
    context^.Protocol.L4 := TCP_PROTOCOL_ID;
    context^.TTL := 64;
    copyMAC(driver.net.getMAC, @context^.MAC.Source[0]);
    { RST has no TCB; resolve destination MAC via ARP }
    if sameSubnetIPv4(remoteIP, @getIPv4Config^.Address[0], @getIPv4Config^.Netmask[0]) then
        copyMAC(driver.net.arp.resolveIP(remoteIP), @context^.MAC.Destination[0])
    else
        copyMAC(driver.net.arp.resolveIP(@getIPv4Config^.Gateway[0]), @context^.MAC.Destination[0]);

    driver.net.ipv4.send(buffer, sizeof(TTCPHeader), context);
    freePacketContext(context);
    kfree(buffer);
end;

{ ============================================================================ }
{  State Machine: Process Incoming Segment                                     }
{ ============================================================================ }

procedure ProcessSegment(tcb : PTCB; hdr : PTCPHeader; payload : void; payloadLen : uint16);
var
    flags    : uint16;
    seqNum   : uint32;
    ackNum   : uint32;
    copyLen  : uint16;
    dataOff  : uint8;
    optsPtr  : puint8;
    optsLen  : uint16;
    mss      : uint16;
    rttSample: uint32;
    acked    : uint32;
    effMSS   : uint16;
begin
    push_trace('driver.net.tcp.ProcessSegment');
    flags  := GetFlags(hdr^.DataOff_Flags);
    seqNum := switchendian32(hdr^.SeqNum);
    ackNum := switchendian32(hdr^.AckNum);
    dataOff := GetDataOffset(hdr^.DataOff_Flags);

    { Parse options pointer }
    if dataOff > 5 then begin
        optsPtr := puint8(uint32(hdr) + sizeof(TTCPHeader));
        optsLen := (dataOff - 5) * 4;
    end else begin
        optsPtr := nil;
        optsLen := 0;
    end;

    { RST handling - applies to all states }
    if (flags AND TCP_FLAG_RST) <> 0 then begin
        tcb^.State := tssClosed;
        if (tcb^.Socket <> nil) and (tcb^.Socket^.OnEvent <> nil) then
            tcb^.Socket^.OnEvent(tcb^.Socket, tteReset);
        RemoveTCB(tcb);
        DestroySocket(tcb^.Socket);
        exit;
    end;

    case tcb^.State of
        tssSynSent: begin
            { Expecting SYN+ACK }
            if ((flags AND TCP_FLAG_SYN) <> 0) and ((flags AND TCP_FLAG_ACK) <> 0) then begin
                { Verify ACK number }
                if ackNum = tcb^.SND_NXT then begin
                    tcb^.IRS := seqNum;
                    tcb^.RCV_NXT := seqNum + 1;
                    tcb^.SND_UNA := ackNum;
                    tcb^.SND_WND := switchendian16(hdr^.Window);

                    { Parse MSS option from SYN-ACK }
                    if (optsPtr <> nil) and (optsLen > 0) then begin
                        mss := ParseMSSOption(optsPtr, optsLen);
                        if mss > 0 then
                            tcb^.RemoteMSS := mss;
                    end;

                    { RTT measurement complete }
                    if tcb^.RTTMeasuring then begin
                        rttSample := Counters.c32 - tcb^.RTTStartTime;
                        if rttSample > 0 then
                            UpdateRTT(tcb, rttSample);
                        tcb^.RTTMeasuring := false;
                    end;

                    { Initialize congestion window based on remote MSS }
                    effMSS := tcb^.RemoteMSS;
                    if effMSS > TCP_DEFAULT_MSS then effMSS := TCP_DEFAULT_MSS;
                    tcb^.CongWnd := TCP_INITIAL_CWND_SEGS * effMSS;
                    tcb^.SSThresh := 65535;

                    { Clear retransmission }
                    if tcb^.RetransBuf <> nil then begin
                        kfree(tcb^.RetransBuf);
                        tcb^.RetransBuf := nil;
                        tcb^.RetransBufLen := 0;
                    end;
                    tcb^.RetransTimer := 0;
                    tcb^.RetransCount := 0;

                    { Send ACK, transition to ESTABLISHED }
                    tcb^.State := tssEstablished;
                    SendSegment(tcb, TCP_FLAG_ACK, nil, 0);

                    { Start keep-alive timer }
                    if tcb^.KeepAliveEnabled then
                        tcb^.KeepAliveTimer := tcb^.KeepAliveIdle;

                    if (tcb^.Socket <> nil) and (tcb^.Socket^.OnEvent <> nil) then
                        tcb^.Socket^.OnEvent(tcb^.Socket, tteConnected);
                end;
            end else if (flags AND TCP_FLAG_SYN) <> 0 then begin
                { Simultaneous open: received SYN without ACK }
                tcb^.IRS := seqNum;
                tcb^.RCV_NXT := seqNum + 1;

                { Parse MSS option }
                if (optsPtr <> nil) and (optsLen > 0) then begin
                    mss := ParseMSSOption(optsPtr, optsLen);
                    if mss > 0 then
                        tcb^.RemoteMSS := mss;
                end;

                tcb^.State := tssSynReceived;
                SendSegment(tcb, TCP_FLAG_SYN OR TCP_FLAG_ACK, nil, 0);
            end;
        end;

        tssSynReceived: begin
            if (flags AND TCP_FLAG_ACK) <> 0 then begin
                if ackNum = tcb^.SND_NXT then begin
                    tcb^.SND_UNA := ackNum;
                    tcb^.SND_WND := switchendian16(hdr^.Window);

                    { RTT measurement }
                    if tcb^.RTTMeasuring then begin
                        rttSample := Counters.c32 - tcb^.RTTStartTime;
                        if rttSample > 0 then
                            UpdateRTT(tcb, rttSample);
                        tcb^.RTTMeasuring := false;
                    end;

                    if tcb^.RetransBuf <> nil then begin
                        kfree(tcb^.RetransBuf);
                        tcb^.RetransBuf := nil;
                        tcb^.RetransBufLen := 0;
                    end;
                    tcb^.RetransTimer := 0;
                    tcb^.RetransCount := 0;

                    tcb^.State := tssEstablished;

                    { Start keep-alive }
                    if tcb^.KeepAliveEnabled then
                        tcb^.KeepAliveTimer := tcb^.KeepAliveIdle;

                    if (tcb^.Socket <> nil) and (tcb^.Socket^.OnEvent <> nil) then
                        tcb^.Socket^.OnEvent(tcb^.Socket, tteConnected);
                end;
            end;
        end;

        tssEstablished: begin
            { Process ACK }
            if (flags AND TCP_FLAG_ACK) <> 0 then begin
                if (ackNum > tcb^.SND_UNA) and (ackNum <= tcb^.SND_NXT) then begin
                    acked := ackNum - tcb^.SND_UNA;
                    tcb^.SND_UNA := ackNum;
                    tcb^.SND_WND := switchendian16(hdr^.Window);

                    { RTT measurement: complete if ACK covers timed segment }
                    if tcb^.RTTMeasuring and (ackNum >= tcb^.RTTSeqNum) then begin
                        rttSample := Counters.c32 - tcb^.RTTStartTime;
                        if rttSample > 0 then
                            UpdateRTT(tcb, rttSample);
                        tcb^.RTTMeasuring := false;
                    end;

                    { Congestion control: advance window }
                    effMSS := tcb^.RemoteMSS;
                    if effMSS > TCP_DEFAULT_MSS then effMSS := TCP_DEFAULT_MSS;
                    if tcb^.CongWnd < tcb^.SSThresh then begin
                        { Slow start: increase by MSS for each ACK }
                        tcb^.CongWnd := tcb^.CongWnd + effMSS;
                    end else begin
                        { Congestion avoidance: increase by MSS*MSS/CongWnd }
                        if tcb^.CongWnd > 0 then
                            tcb^.CongWnd := tcb^.CongWnd + (uint32(effMSS) * uint32(effMSS)) div tcb^.CongWnd;
                    end;

                    { Clear zero-window probe state if window opened }
                    if tcb^.SND_WND > 0 then begin
                        tcb^.ZWPTimer := 0;
                        tcb^.ZWPCount := 0;
                    end;

                    { If all data acknowledged, clear retransmission }
                    if tcb^.SND_UNA = tcb^.SND_NXT then begin
                        if tcb^.RetransBuf <> nil then begin
                            kfree(tcb^.RetransBuf);
                            tcb^.RetransBuf := nil;
                            tcb^.RetransBufLen := 0;
                        end;
                        tcb^.RetransTimer := 0;
                        tcb^.RetransCount := 0;
                    end;

                    { Nagle: if we have buffered data and ACK arrived, flush }
                    if tcb^.NagleEnabled and (tcb^.SendBufLen > 0) and
                       (tcb^.SND_UNA = tcb^.SND_NXT) then begin
                        { All previous data ACKed - send buffered data }
                        effMSS := tcb^.RemoteMSS;
                        if effMSS > TCP_DEFAULT_MSS then effMSS := TCP_DEFAULT_MSS;
                        copyLen := tcb^.SendBufLen;
                        if copyLen > effMSS then copyLen := effMSS;
                        if (tcb^.SND_WND > 0) and (copyLen > tcb^.SND_WND) then
                            copyLen := tcb^.SND_WND;
                        SendSegment(tcb, TCP_FLAG_ACK OR TCP_FLAG_PSH, tcb^.SendBuf, copyLen);
                        tcb^.SND_NXT := tcb^.SND_NXT + copyLen;
                        { Shift remaining data in send buffer }
                        if copyLen < tcb^.SendBufLen then begin
                            memcpy(uint32(tcb^.SendBuf) + copyLen,
                                   uint32(tcb^.SendBuf),
                                   tcb^.SendBufLen - copyLen);
                        end;
                        tcb^.SendBufLen := tcb^.SendBufLen - copyLen;
                    end;

                    { Reset keep-alive on activity }
                    if tcb^.KeepAliveEnabled then begin
                        tcb^.KeepAliveTimer := tcb^.KeepAliveIdle;
                        tcb^.KeepAliveCount := 0;
                    end;
                end;
            end;

            { Process incoming data }
            if payloadLen > 0 then begin
                if seqNum = tcb^.RCV_NXT then begin
                    { In-order data }
                    copyLen := payloadLen;
                    if copyLen > (tcb^.RecvBufSize - tcb^.RecvBufLen) then
                        copyLen := tcb^.RecvBufSize - tcb^.RecvBufLen;

                    if copyLen > 0 then begin
                        memcpy(uint32(payload), uint32(tcb^.RecvBuf) + tcb^.RecvBufLen, copyLen);
                        tcb^.RecvBufLen := tcb^.RecvBufLen + copyLen;
                        tcb^.RCV_NXT := tcb^.RCV_NXT + copyLen;
                        tcb^.RCV_WND := tcb^.RecvBufSize - tcb^.RecvBufLen;
                    end;

                    { Flush any OOO segments that are now contiguous }
                    FlushOOOSegments(tcb);

                    { Delayed ACK: schedule ACK instead of sending immediately }
                    if tcb^.DelayedAckPending then begin
                        { Second segment arrived before ACK - send immediately }
                        tcb^.DelayedAckPending := false;
                        tcb^.DelayedAckTimer := 0;
                        SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
                    end else begin
                        tcb^.DelayedAckPending := true;
                        tcb^.DelayedAckTimer := TCP_DELAYED_ACK_TICKS;
                    end;

                    { Deliver to user callback }
                    if (tcb^.Socket <> nil) and (tcb^.Socket^.OnReceive <> nil) then begin
                        tcb^.Socket^.OnReceive(tcb^.Socket, tcb^.RecvBuf, tcb^.RecvBufLen);
                        tcb^.RecvBufLen := 0;
                        tcb^.RCV_WND := tcb^.RecvBufSize;
                    end;

                    { Reset keep-alive on data received }
                    if tcb^.KeepAliveEnabled then begin
                        tcb^.KeepAliveTimer := tcb^.KeepAliveIdle;
                        tcb^.KeepAliveCount := 0;
                    end;
                end else if seqNum > tcb^.RCV_NXT then begin
                    { Out-of-order segment - buffer it }
                    InsertOOOSegment(tcb, seqNum, payload, payloadLen);
                    { Send duplicate ACK (signals sender about gap) }
                    SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
                end;
                { Segments with seqNum < RCV_NXT are old duplicates - ignore }
            end;

            { Process FIN }
            if (flags AND TCP_FLAG_FIN) <> 0 then begin
                tcb^.RCV_NXT := tcb^.RCV_NXT + 1;
                tcb^.State := tssCloseWait;
                tcb^.DelayedAckPending := false;
                tcb^.DelayedAckTimer := 0;
                SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
                if (tcb^.Socket <> nil) and (tcb^.Socket^.OnEvent <> nil) then
                    tcb^.Socket^.OnEvent(tcb^.Socket, tteDisconnected);
            end;
        end;

        tssFinWait1: begin
            if (flags AND TCP_FLAG_ACK) <> 0 then begin
                if ackNum = tcb^.FIN_Seq + 1 then begin
                    { Our FIN has been ACKed }
                    if tcb^.RetransBuf <> nil then begin
                        kfree(tcb^.RetransBuf);
                        tcb^.RetransBuf := nil;
                        tcb^.RetransBufLen := 0;
                    end;
                    tcb^.RetransTimer := 0;

                    if (flags AND TCP_FLAG_FIN) <> 0 then begin
                        { Simultaneous close }
                        tcb^.RCV_NXT := switchendian32(hdr^.SeqNum) + 1;
                        tcb^.State := tssTimeWait;
                        tcb^.TimeWaitTimer := TCP_TIMEWAIT_TICKS;
                        SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
                    end else begin
                        tcb^.State := tssFinWait2;
                    end;
                end;
            end;
            if ((flags AND TCP_FLAG_FIN) <> 0) and (tcb^.State = tssFinWait1) then begin
                { FIN received but our FIN not yet ACKed }
                tcb^.RCV_NXT := switchendian32(hdr^.SeqNum) + 1;
                tcb^.State := tssClosing;
                SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
            end;
        end;

        tssFinWait2: begin
            if (flags AND TCP_FLAG_FIN) <> 0 then begin
                tcb^.RCV_NXT := switchendian32(hdr^.SeqNum) + 1;
                tcb^.State := tssTimeWait;
                tcb^.TimeWaitTimer := TCP_TIMEWAIT_TICKS;
                SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
            end;
        end;

        tssClosing: begin
            if (flags AND TCP_FLAG_ACK) <> 0 then begin
                if ackNum = tcb^.FIN_Seq + 1 then begin
                    tcb^.State := tssTimeWait;
                    tcb^.TimeWaitTimer := TCP_TIMEWAIT_TICKS;
                end;
            end;
        end;

        tssLastAck: begin
            if (flags AND TCP_FLAG_ACK) <> 0 then begin
                if ackNum = tcb^.FIN_Seq + 1 then begin
                    tcb^.State := tssClosed;
                    RemoveTCB(tcb);
                    DestroySocket(tcb^.Socket);
                end;
            end;
        end;

        tssTimeWait: begin
            { If we receive a retransmitted FIN, re-ACK it }
            if (flags AND TCP_FLAG_FIN) <> 0 then begin
                SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
                tcb^.TimeWaitTimer := TCP_TIMEWAIT_TICKS;
            end;
        end;

        tssListen: begin
            { Handled in ProcessPacket directly }
        end;

        tssClosed: begin
            { Ignore }
        end;
    end;
end;

{ ============================================================================ }
{  Incoming Packet Processing (called by IPv4)                                 }
{ ============================================================================ }

procedure ProcessPacket(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    hdr        : PTCPHeader;
    dataOff    : uint8;
    payload    : void;
    payloadLen : uint16;
    tcb        : PTCB;
    listenTcb  : PTCB;
    newTcb     : PTCB;
    localPort  : uint16;
    remotePort : uint16;
    flags      : uint16;
    seqNum     : uint32;
    optsPtr    : puint8;
    optsLen    : uint16;
    mss        : uint16;
begin
    push_trace('driver.net.tcp.ProcessPacket');
    if p_len < sizeof(TTCPHeader) then exit;

    hdr := PTCPHeader(p_data);
    localPort  := switchendian16(hdr^.DstPort);
    remotePort := switchendian16(hdr^.SrcPort);

    dataOff := GetDataOffset(hdr^.DataOff_Flags);
    if dataOff < 5 then exit;

    payload := void(puint8(p_data) + (dataOff * 4));
    payloadLen := p_len - (dataOff * 4);

    flags := GetFlags(hdr^.DataOff_Flags);
    seqNum := switchendian32(hdr^.SeqNum);

    { Look up existing connection }
    tcb := FindTCB(localPort, remotePort, @p_context^.IP.Source[0]);
    if tcb <> nil then begin
        ProcessSegment(tcb, hdr, payload, payloadLen);
        exit;
    end;

    { Check for listening socket (passive OPEN) }
    if (flags AND TCP_FLAG_SYN) <> 0 then begin
        listenTcb := FindListenTCB(localPort);
        if listenTcb <> nil then begin
            { Phase 2: Backlog enforcement }
            if (listenTcb^.BacklogMax > 0) and
               (CountPendingForPort(localPort) >= listenTcb^.BacklogMax) then
                exit; { drop SYN - backlog full }

            { Create new TCB for incoming connection }
            newTcb := CreateTCB;
            copyIPv4(@getIPv4Config^.Address[0], @newTcb^.LocalIP[0]);
            copyIPv4(@p_context^.IP.Source[0], @newTcb^.RemoteIP[0]);
            newTcb^.LocalPort := localPort;
            newTcb^.RemotePort := remotePort;
            newTcb^.IRS := seqNum;
            newTcb^.RCV_NXT := seqNum + 1;
            newTcb^.ISS := GenerateISN;
            newTcb^.SND_NXT := newTcb^.ISS;
            newTcb^.SND_UNA := newTcb^.ISS;
            newTcb^.SND_WND := switchendian16(hdr^.Window);
            newTcb^.State := tssSynReceived;

            { Copy remote MAC from incoming packet context }
            copyMAC(@p_context^.MAC.Source[0], @newTcb^.RemoteMAC[0]);

            { Parse MSS option from SYN }
            if dataOff > 5 then begin
                optsPtr := puint8(uint32(p_data) + sizeof(TTCPHeader));
                optsLen := (dataOff - 5) * 4;
                mss := ParseMSSOption(optsPtr, optsLen);
                if mss > 0 then
                    newTcb^.RemoteMSS := mss;
            end;

            { Initialize congestion window based on remote MSS }
            mss := newTcb^.RemoteMSS;
            if mss > TCP_DEFAULT_MSS then mss := TCP_DEFAULT_MSS;
            newTcb^.CongWnd := TCP_INITIAL_CWND_SEGS * mss;

            { Inherit callbacks from listen socket }
            CreateSocket(newTcb, listenTcb^.Socket^.OnReceive,
                        listenTcb^.Socket^.OnEvent,
                        listenTcb^.Socket^.UserData);

            AddTCB(newTcb);

            { Send SYN+ACK (includes MSS option via SendSegment) }
            SendSegment(newTcb, TCP_FLAG_SYN OR TCP_FLAG_ACK, nil, 0);
            newTcb^.SND_NXT := newTcb^.SND_NXT + 1;
            exit;
        end;
    end;

    { No matching connection or listener - send RST }
    if (flags AND TCP_FLAG_RST) = 0 then begin
        if (flags AND TCP_FLAG_ACK) <> 0 then begin
            SendRST(localPort, remotePort,
                    @p_context^.IP.Destination[0], @p_context^.IP.Source[0],
                    switchendian32(hdr^.AckNum), 0);
        end else begin
            SendRST(localPort, remotePort,
                    @p_context^.IP.Destination[0], @p_context^.IP.Source[0],
                    0, seqNum + payloadLen);
        end;
    end;
end;

{ ============================================================================ }
{  Timer Tick (called at 1024 Hz from arch.x86.isr.tmr0)                              }
{ ============================================================================ }

procedure TimerTick(data : void);
var
    i        : uint32;
    tcb      : PTCB;
    p        : void;
    context  : PPacketContext;
    count    : uint32;
    effMSS   : uint16;
begin
    if Connections = nil then exit;
    count := DL_Size(Connections);
    if count = 0 then exit;

    i := 0;
    while i < count do begin
        p := DL_Get(Connections, i);
        if p <> nil then begin
            tcb := PTCB(puint32(p)^);
            if (tcb <> nil) and tcb^.Active then begin

                { Delayed ACK timer }
                if tcb^.DelayedAckPending and (tcb^.State = tssEstablished) then begin
                    if tcb^.DelayedAckTimer > 0 then
                        tcb^.DelayedAckTimer := tcb^.DelayedAckTimer - 1;
                    if tcb^.DelayedAckTimer = 0 then begin
                        tcb^.DelayedAckPending := false;
                        SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
                    end;
                end;

                { Retransmission timer }
                if (tcb^.RetransTimer > 0) and (tcb^.RetransBuf <> nil) then begin
                    tcb^.RetransTimer := tcb^.RetransTimer - 1;
                    if tcb^.RetransTimer = 0 then begin
                        if tcb^.RetransCount < TCP_MAX_RETRANS then begin
                            { Congestion: on timeout, reduce window }
                            effMSS := tcb^.RemoteMSS;
                            if effMSS > TCP_DEFAULT_MSS then effMSS := TCP_DEFAULT_MSS;
                            tcb^.SSThresh := tcb^.CongWnd SHR 1;
                            if tcb^.SSThresh < (uint32(effMSS) * 2) then
                                tcb^.SSThresh := uint32(effMSS) * 2;
                            tcb^.CongWnd := effMSS; { reset to 1 segment }

                            { Retransmit }
                            tcb^.RetransCount := tcb^.RetransCount + 1;
                            context := newPacketContext;
                            copyIPv4(@tcb^.LocalIP[0], @context^.IP.Source[0]);
                            copyIPv4(@tcb^.RemoteIP[0], @context^.IP.Destination[0]);
                            context^.Protocol.L4 := TCP_PROTOCOL_ID;
                            context^.TTL := 64;
                            copyMAC(driver.net.getMAC, @context^.MAC.Source[0]);
                            copyMAC(@tcb^.RemoteMAC[0], @context^.MAC.Destination[0]);
                            driver.net.ipv4.send(tcb^.RetransBuf, tcb^.RetransBufLen, context);
                            freePacketContext(context);

                            { Invalidate RTT measurement (Karn's algorithm) }
                            tcb^.RTTMeasuring := false;

                            { Exponential backoff on RTO }
                            tcb^.RetransTimer := tcb^.RTO * (uint32(1) SHL tcb^.RetransCount);
                            if tcb^.RetransTimer > TCP_MAX_RTO then
                                tcb^.RetransTimer := TCP_MAX_RTO;
                        end else begin
                            { Max retransmissions reached - timeout }
                            tcb^.State := tssClosed;
                            if (tcb^.Socket <> nil) and (tcb^.Socket^.OnEvent <> nil) then
                                tcb^.Socket^.OnEvent(tcb^.Socket, tteTimeout);
                            RemoveTCB(tcb);
                            DestroySocket(tcb^.Socket);
                            count := DL_Size(Connections);
                            i := 0;
                            continue;
                        end;
                    end;
                end;

                { TIME_WAIT timer }
                if (tcb^.State = tssTimeWait) and (tcb^.TimeWaitTimer > 0) then begin
                    tcb^.TimeWaitTimer := tcb^.TimeWaitTimer - 1;
                    if tcb^.TimeWaitTimer = 0 then begin
                        tcb^.State := tssClosed;
                        RemoveTCB(tcb);
                        DestroySocket(tcb^.Socket);
                        count := DL_Size(Connections);
                        i := 0;
                        continue;
                    end;
                end;

                { Zero-window probing }
                if (tcb^.State = tssEstablished) and (tcb^.SND_WND = 0) and
                   (tcb^.SendBufLen > 0) then begin
                    if tcb^.ZWPTimer = 0 then
                        tcb^.ZWPTimer := TCP_ZWP_INITIAL;
                    tcb^.ZWPTimer := tcb^.ZWPTimer - 1;
                    if tcb^.ZWPTimer = 0 then begin
                        { Send 1-byte probe }
                        SendSegment(tcb, TCP_FLAG_ACK, tcb^.SendBuf, 1);
                        tcb^.ZWPCount := tcb^.ZWPCount + 1;
                        { Exponential backoff capped at max }
                        tcb^.ZWPTimer := TCP_ZWP_INITIAL * (uint32(1) SHL tcb^.ZWPCount);
                        if tcb^.ZWPTimer > TCP_ZWP_MAX then
                            tcb^.ZWPTimer := TCP_ZWP_MAX;
                    end;
                end;

                { Keep-alive timer }
                if tcb^.KeepAliveEnabled and (tcb^.State = tssEstablished) then begin
                    if tcb^.KeepAliveTimer > 0 then begin
                        tcb^.KeepAliveTimer := tcb^.KeepAliveTimer - 1;
                        if tcb^.KeepAliveTimer = 0 then begin
                            if tcb^.KeepAliveCount < TCP_KEEPALIVE_PROBES then begin
                                { Send keep-alive probe: ACK with SeqNum = SND_UNA - 1 }
                                { We do this by temporarily adjusting SND_NXT }
                                tcb^.SND_NXT := tcb^.SND_UNA - 1;
                                SendSegment(tcb, TCP_FLAG_ACK, nil, 0);
                                tcb^.SND_NXT := tcb^.SND_UNA;
                                tcb^.KeepAliveCount := tcb^.KeepAliveCount + 1;
                                tcb^.KeepAliveTimer := TCP_KEEPALIVE_INTVL;
                            end else begin
                                { No response after max probes - abort }
                                tcb^.State := tssClosed;
                                if (tcb^.Socket <> nil) and (tcb^.Socket^.OnEvent <> nil) then
                                    tcb^.Socket^.OnEvent(tcb^.Socket, tteTimeout);
                                RemoveTCB(tcb);
                                DestroySocket(tcb^.Socket);
                                count := DL_Size(Connections);
                                i := 0;
                                continue;
                            end;
                        end;
                    end;
                end;

            end;
        end;
        inc(i);
    end;
end;

{ ============================================================================ }
{  Public API                                                                  }
{ ============================================================================ }

function connect(context : PTCPConnectContext) : PTCPSocket;
var
    tcb    : PTCB;
    sock   : PTCPSocket;
begin
    push_trace('driver.net.tcp.connect');
    connect := nil;
    if context = nil then exit;

    tcb := CreateTCB;
    if tcb = nil then exit;

    { Assign local address }
    copyIPv4(@getIPv4Config^.Address[0], @tcb^.LocalIP[0]);
    copyIPv4(@context^.RemoteIP[0], @tcb^.RemoteIP[0]);

    if context^.LocalPort <> 0 then
        tcb^.LocalPort := context^.LocalPort
    else
        tcb^.LocalPort := AllocEphemeralPort;

    if tcb^.LocalPort = 0 then begin
        DestroyTCB(tcb);
        exit;
    end;

    tcb^.RemotePort := context^.RemotePort;

    { Resolve destination MAC }
    if sameSubnetIPv4(@context^.RemoteIP[0], @getIPv4Config^.Address[0], @getIPv4Config^.Netmask[0]) then
        copyMAC(driver.net.arp.resolveIP(@context^.RemoteIP[0]), @tcb^.RemoteMAC[0])
    else
        copyMAC(driver.net.arp.resolveIP(@getIPv4Config^.Gateway[0]), @tcb^.RemoteMAC[0]);

    { Generate ISN }
    tcb^.ISS := GenerateISN;
    tcb^.SND_NXT := tcb^.ISS;
    tcb^.SND_UNA := tcb^.ISS;

    sock := CreateSocket(tcb, context^.OnReceive, context^.OnEvent, context^.UserData);

    { Auto-bind socket to calling process for cleanup on process death }
    if proc.mgr.CurrentProcess <> nil then begin
        sock^.OwnerPID := proc.mgr.CurrentProcess^.ProcessID;
        proc.mgr.bindResource(proc.mgr.CurrentProcess, rkSocket, void(sock), @socket_cleanup);
    end;

    AddTCB(tcb);

    { Send SYN (includes MSS option via SendSegment) }
    tcb^.State := tssSynSent;
    SendSegment(tcb, TCP_FLAG_SYN, nil, 0);
    tcb^.SND_NXT := tcb^.SND_NXT + 1;

    connect := sock;
end;

function listen(context : PTCPListenContext) : PTCPSocket;
var
    tcb  : PTCB;
    sock : PTCPSocket;
begin
    push_trace('driver.net.tcp.listen');
    listen := nil;
    if context = nil then exit;

    tcb := CreateTCB;
    if tcb = nil then exit;

    copyIPv4(@getIPv4Config^.Address[0], @tcb^.LocalIP[0]);
    memset(uint32(@tcb^.RemoteIP[0]), 0, 4);
    tcb^.LocalPort := context^.LocalPort;
    tcb^.RemotePort := 0;
    tcb^.State := tssListen;

    { Phase 2: Listen backlog }
    tcb^.BacklogMax := context^.Backlog;
    if tcb^.BacklogMax = 0 then tcb^.BacklogMax := 5; { default backlog }

    sock := CreateSocket(tcb, context^.OnReceive, context^.OnEvent, context^.UserData);

    { Auto-bind socket to calling process for cleanup on process death }
    if proc.mgr.CurrentProcess <> nil then begin
        sock^.OwnerPID := proc.mgr.CurrentProcess^.ProcessID;
        proc.mgr.bindResource(proc.mgr.CurrentProcess, rkSocket, void(sock), @socket_cleanup);
    end;

    AddTCB(tcb);

    listen := sock;
end;

function accept(listener : PTCPSocket) : PTCPSocket;
var
    tcb      : PTCB;
    childTcb : PTCB;
begin
    push_trace('driver.net.tcp.accept');
    accept := nil;
    if listener = nil then exit;
    if listener^.TCB = nil then exit;

    tcb := listener^.TCB;
    if tcb^.State <> tssListen then exit;

    { Find the first ESTABLISHED child connection on this port }
    childTcb := FindAcceptable(tcb^.LocalPort);
    if childTcb <> nil then
        accept := childTcb^.Socket;
end;

function send(socket : PTCPSocket; p_data : void; p_len : uint16) : TTCPError;
var
    tcb     : PTCB;
    sendLen : uint16;
    effWnd  : uint32;
    effMSS  : uint16;
    canSend : boolean;
    copyLen : uint16;
begin
    push_trace('driver.net.tcp.send');
    send := tteGenericError;
    if socket = nil then exit;
    if socket^.TCB = nil then exit;

    tcb := socket^.TCB;
    if tcb^.State <> tssEstablished then begin
        send := tteInvalidState;
        exit;
    end;

    if (p_data = nil) or (p_len = 0) then begin
        send := tteOK;
        exit;
    end;

    effMSS := tcb^.RemoteMSS;
    if effMSS > TCP_DEFAULT_MSS then effMSS := TCP_DEFAULT_MSS;

    { Effective send window = min(SND_WND, CongWnd) }
    effWnd := tcb^.SND_WND;
    if tcb^.CongWnd < effWnd then
        effWnd := tcb^.CongWnd;

    { Nagle's algorithm: if enabled and there's unACKed data and data < MSS, buffer it }
    if tcb^.NagleEnabled and (tcb^.SND_UNA < tcb^.SND_NXT) and (p_len < effMSS) then begin
        { Buffer the data in the send buffer }
        copyLen := p_len;
        if copyLen > (tcb^.SendBufSize - tcb^.SendBufLen) then
            copyLen := tcb^.SendBufSize - tcb^.SendBufLen;
        if copyLen > 0 then begin
            memcpy(uint32(p_data), uint32(tcb^.SendBuf) + tcb^.SendBufLen, copyLen);
            tcb^.SendBufLen := tcb^.SendBufLen + copyLen;
        end;
        send := tteOK;
        exit;
    end;

    { Determine how much to send }
    sendLen := p_len;
    if sendLen > effMSS then
        sendLen := effMSS;
    if (effWnd > 0) and (sendLen > uint16(effWnd)) then
        sendLen := uint16(effWnd);

    { If window is zero, buffer data for later (zero-window probing will handle it) }
    if effWnd = 0 then begin
        copyLen := p_len;
        if copyLen > (tcb^.SendBufSize - tcb^.SendBufLen) then
            copyLen := tcb^.SendBufSize - tcb^.SendBufLen;
        if copyLen > 0 then begin
            memcpy(uint32(p_data), uint32(tcb^.SendBuf) + tcb^.SendBufLen, copyLen);
            tcb^.SendBufLen := tcb^.SendBufLen + copyLen;
        end;
        send := tteOK;
        exit;
    end;

    SendSegment(tcb, TCP_FLAG_ACK OR TCP_FLAG_PSH, p_data, sendLen);
    tcb^.SND_NXT := tcb^.SND_NXT + sendLen;

    send := tteOK;
end;

function close(socket : PTCPSocket) : TTCPError;
var
    tcb : PTCB;
begin
    push_trace('driver.net.tcp.close');
    close := tteGenericError;
    if socket = nil then exit;
    if socket^.TCB = nil then exit;

    tcb := socket^.TCB;

    { Flush any buffered send data before closing }
    if (tcb^.State = tssEstablished) and (tcb^.SendBufLen > 0) then begin
        SendSegment(tcb, TCP_FLAG_ACK OR TCP_FLAG_PSH, tcb^.SendBuf, tcb^.SendBufLen);
        tcb^.SND_NXT := tcb^.SND_NXT + tcb^.SendBufLen;
        tcb^.SendBufLen := 0;
    end;

    case tcb^.State of
        tssEstablished: begin
            { Active close: send FIN }
            tcb^.FIN_Seq := tcb^.SND_NXT;
            SendSegment(tcb, TCP_FLAG_FIN OR TCP_FLAG_ACK, nil, 0);
            tcb^.SND_NXT := tcb^.SND_NXT + 1;
            tcb^.State := tssFinWait1;
            close := tteOK;
        end;

        tssCloseWait: begin
            { Passive close response: send our FIN }
            tcb^.FIN_Seq := tcb^.SND_NXT;
            SendSegment(tcb, TCP_FLAG_FIN OR TCP_FLAG_ACK, nil, 0);
            tcb^.SND_NXT := tcb^.SND_NXT + 1;
            tcb^.State := tssLastAck;
            close := tteOK;
        end;

        tssSynSent, tssSynReceived: begin
            tcb^.State := tssClosed;
            RemoveTCB(tcb);
            DestroySocket(socket);
            close := tteOK;
        end;

        tssClosed: begin
            close := tteOK;
        end;
    else
        close := tteConnectionClosing;
    end;
end;

function abort_connection(socket : PTCPSocket) : TTCPError;
var
    tcb : PTCB;
begin
    push_trace('driver.net.tcp.abort_connection');
    abort_connection := tteGenericError;
    if socket = nil then exit;
    if socket^.TCB = nil then exit;

    tcb := socket^.TCB;
    if tcb^.State <> tssClosed then begin
        SendRST(tcb^.LocalPort, tcb^.RemotePort,
                @tcb^.LocalIP[0], @tcb^.RemoteIP[0],
                tcb^.SND_NXT, tcb^.RCV_NXT);
    end;

    tcb^.State := tssClosed;
    RemoveTCB(tcb);
    DestroySocket(socket);
    abort_connection := tteOK;
end;

{ ============================================================================ }
{  Terminal Commands                                                           }
{ ============================================================================ }

var
    TCPTEST_Socket   : PTCPSocket;
    TCPLISTEN_Socket : PTCPSocket;
    TCPHTTP_Socket   : PTCPSocket;

const
    TCPTEST_HELLO : Array[0..12] of char = 'Hello, World!';

{ --- tcpconnect callbacks --- }

procedure tcpconnect_on_recv(socket : PTCPSocket; p_data : void; p_len : uint16);
var
    buf : puint8;
    i   : uint16;
begin
    buf := puint8(p_data);
    io.syslog.writestring('[TCP Recv] ');
    for i := 0 to p_len - 1 do
        io.syslog.logChar(char(buf[i]));
    io.syslog.writestringln('');
end;

procedure tcpconnect_on_event(socket : PTCPSocket; event : TTCPEvent);
begin
    push_trace('driver.net.tcp.tcpconnect_on_event');
    case event of
        tteConnected: begin
            io.syslog.logln('TCP', 'Connected! Sending Hello, World!...');
            send(socket, void(@TCPTEST_HELLO[0]), 13);
        end;
        tteDisconnected:
            io.syslog.logln('TCP', 'Disconnected by remote host.');
        tteReset:
            io.syslog.logln('TCP', 'Connection reset by remote host.');
        tteTimeout:
            io.syslog.logln('TCP', 'Connection timed out.');
    end;
end;

procedure terminal_command_tcpconnect(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    ip_str   : pchar;
    port_str : pchar;
    ip       : puint8;
    port     : uint16;
    dest_mac : puint8;
    ctx      : TTCPConnectContext;
begin
    push_trace('driver.net.tcp.terminal_command_tcpconnect');
    if paramCount(params) < 2 then begin
        io.syslog.logln('TCP', 'Usage: tcpconnect <ip> <port>');
        exit;
    end;

    ip_str   := getParam(0, params);
    port_str := getParam(1, params);
    ip       := stringToIPv4(ip_str);
    port     := uint16(stringToInt(port_str));

    if ip = nil then begin
        io.syslog.logln('TCP', 'Invalid IP address.');
        exit;
    end;

    if port = 0 then begin
        io.syslog.logln('TCP', 'Invalid port number.');
        kfree(void(ip));
        exit;
    end;

    { Resolve MAC before connecting }
    if sameSubnetIPv4(ip, @getIPv4Config^.Address[0], @getIPv4Config^.Netmask[0]) then
        dest_mac := driver.net.arp.resolveIP(ip)
    else
        dest_mac := driver.net.arp.resolveIP(@getIPv4Config^.Gateway[0]);

    if dest_mac = nil then begin
        io.syslog.logln('TCP', 'Failed to resolve MAC address for target.');
        kfree(void(ip));
        exit;
    end;

    copyIPv4(ip, @ctx.RemoteIP[0]);
    ctx.RemotePort := port;
    ctx.LocalPort  := 0;
    ctx.OnReceive  := @tcpconnect_on_recv;
    ctx.OnEvent    := @tcpconnect_on_event;
    ctx.UserData   := nil;

    io.syslog.logln('TCP', 'Connecting...');

    TCPTEST_Socket := connect(@ctx);

    if TCPTEST_Socket = nil then
        io.syslog.logln('TCP', 'Failed to initiate connection.');

    kfree(void(ip));
end;

{ --- tcplisten callbacks --- }

procedure tcplisten_on_recv(socket : PTCPSocket; p_data : void; p_len : uint16);
var
    buf : puint8;
    i   : uint16;
begin
    push_trace('driver.net.tcp.tcplisten_on_recv');
    buf := puint8(p_data);
    io.syslog.writestring('[TCP Listen Recv] ');
    for i := 0 to p_len - 1 do
        io.syslog.logChar(char(buf[i]));
    io.syslog.writestringln('');
end;

procedure tcplisten_on_event(socket : PTCPSocket; event : TTCPEvent);
begin
    push_trace('driver.net.tcp.tcplisten_on_event');
    case event of
        tteConnected:
            io.syslog.logln('TCP', 'Listen: client connected.');
        tteDisconnected:
            io.syslog.logln('TCP', 'Listen: client disconnected.');
        tteReset:
            io.syslog.logln('TCP', 'Listen: connection reset.');
        tteTimeout:
            io.syslog.logln('TCP', 'Listen: connection timed out.');
    end;
end;

procedure terminal_command_tcplisten(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    port_str : pchar;
    port     : uint16;
    ctx      : TTCPListenContext;
begin
    push_trace('driver.net.tcp.terminal_command_tcplisten');
    if paramCount(params) < 1 then begin
        io.syslog.logln('TCP', 'Usage: tcplisten <port>');
        exit;
    end;

    port_str := getParam(0, params);
    port     := uint16(stringToInt(port_str));

    if port = 0 then begin
        io.syslog.logln('TCP', 'Invalid port number.');
        exit;
    end;

    ctx.LocalPort := port;
    ctx.OnReceive := @tcplisten_on_recv;
    ctx.OnEvent   := @tcplisten_on_event;
    ctx.UserData  := nil;
    ctx.Backlog   := 1;

    io.syslog.logln('TCP', 'Listening on port...');

    TCPLISTEN_Socket := listen(@ctx);

    if TCPLISTEN_Socket = nil then
        io.syslog.logln('TCP', 'Failed to start listener.');
end;

{ --- tcphttp callbacks --- }

var
    TCPHTTP_Host : array[0..63] of char;

procedure tcphttp_on_recv(socket : PTCPSocket; p_data : void; p_len : uint16);
var
    buf : puint8;
    i   : uint16;
begin
    push_trace('driver.net.tcp.tcphttp_on_recv');
    buf := puint8(p_data);
    io.syslog.writestring('[HTTP Response] ');
    for i := 0 to p_len - 1 do
        io.syslog.logChar(char(buf[i]));
    io.syslog.writestringln('');
end;

procedure tcphttp_on_event(socket : PTCPSocket; event : TTCPEvent);
var
    req     : array[0..255] of char;
    reqLen  : uint16;
    i       : uint16;
    src     : pchar;
begin
    push_trace('driver.net.tcp.tcphttp_on_event');
    case event of
        tteConnected: begin
            io.syslog.logln('TCP', 'HTTP: Connected, sending GET request...');
            { Build: GET / HTTP/1.0\r\nHost: <host>\r\nConnection: close\r\n\r\n }
            reqLen := 0;
            src := 'GET / HTTP/1.0'#13#10'Host: ';
            i := 0;
            while src[i] <> #0 do begin
                req[reqLen] := src[i];
                inc(reqLen);
                inc(i);
            end;
            { Append host }
            i := 0;
            while (TCPHTTP_Host[i] <> #0) and (i < 64) do begin
                req[reqLen] := TCPHTTP_Host[i];
                inc(reqLen);
                inc(i);
            end;
            src := #13#10'Connection: close'#13#10#13#10;
            i := 0;
            while src[i] <> #0 do begin
                req[reqLen] := src[i];
                inc(reqLen);
                inc(i);
            end;
            send(socket, @req[0], reqLen);
        end;
        tteDisconnected:
            io.syslog.logln('TCP', 'HTTP: Connection closed by server.');
        tteReset:
            io.syslog.logln('TCP', 'HTTP: Connection reset.');
        tteTimeout:
            io.syslog.logln('TCP', 'HTTP: Connection timed out.');
    end;
end;

procedure terminal_command_tcphttp(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    ip_str   : pchar;
    port     : uint16;
    ip       : puint8;
    ctx      : TTCPConnectContext;
    i        : uint16;
begin
    push_trace('driver.net.tcp.terminal_command_tcphttp');
    if paramCount(params) < 1 then begin
        io.syslog.logln('TCP', 'Usage: tcphttp <ip> [port]');
        exit;
    end;

    ip_str := getParam(0, params);
    ip := stringToIPv4(ip_str);

    if ip = nil then begin
        io.syslog.logln('TCP', 'Invalid IP address.');
        exit;
    end;

    port := 80;
    if paramCount(params) >= 2 then
        port := uint16(stringToInt(getParam(1, params)));

    { Store host string for HTTP Host header }
    memset(uint32(@TCPHTTP_Host[0]), 0, 64);
    i := 0;
    while (ip_str[i] <> #0) and (i < 63) do begin
        TCPHTTP_Host[i] := ip_str[i];
        inc(i);
    end;

    copyIPv4(ip, @ctx.RemoteIP[0]);
    ctx.RemotePort := port;
    ctx.LocalPort  := 0;
    ctx.OnReceive  := @tcphttp_on_recv;
    ctx.OnEvent    := @tcphttp_on_event;
    ctx.UserData   := nil;

    io.syslog.logln('TCP', 'HTTP: Connecting...');

    TCPHTTP_Socket := connect(@ctx);

    if TCPHTTP_Socket = nil then
        io.syslog.logln('TCP', 'HTTP: Failed to initiate connection.');

    kfree(void(ip));
end;

{ ============================================================================ }
{  Registration                                                                }
{ ============================================================================ }

procedure register();
begin
    push_trace('driver.net.tcp.register');
    writeToLogLn('        L4/TCP: register');
    if not Registered then begin
        Connections := DL_New(sizeof(uint32));
        driver.net.ipv4.registerProtocol(TCP_PROTOCOL_ID, @ProcessPacket);
        arch.x86.isr.tmr0.hook(uint32(@TimerTick));
        Registered := true;
        io.syslog.logln('TCP', 'TCP registered.');
    end;
end;

end.