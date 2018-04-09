unit ipv4;

interface

uses
    util, console,
    nettypes, netutils,
    eth2;

procedure registerProtocol(Protocol_ID : uint8; recv_callback : TRecvCallback);
procedure register;

implementation

var
    Registered : Boolean = false;
    Protocols : Array[0..255] of TRecvCallback;

procedure recv(p_data : void; p_len : uint16);
var
    Header  : PIPV4Header;
    AHeader : TIPV4AbstractHeader;
    i       : Integer;

    buf     : puint8;
    len     : uint16;

begin
    console.outputln('net.ipv4', 'RECV.');
    Header:= PIPV4Header(p_data);
    AHeader.version:= Header^.version;
    AHeader.header_len:= Header^.header_len;
    AHeader.ToS:= Header^.ToS;
    AHeader.total_len:= (Header^.total_len_Hi SHL 8) + Header^.total_len_Lo;
    AHeader.identifier:= (Header^.identifier_Hi SHL 8) + Header^.identifier_Lo;
    AHeader.Flags.RS:= false;
    AHeader.Flags.DF:= (Header^.Flags AND $2) > 0;
    AHeader.Flags.MF:= (Header^.Flags AND $1) > 0;
    AHeader.Fragment_Off:= Header^.Fragment_Off;
    AHeader.TTL:= Header^.TTL;
    AHeader.Protocol:= Header^.Protocol;
    AHeader.HDR_CHK:= (Header^.HDR_CHK_Hi SHL 8) + Header^.HDR_CHK_Lo;
    for i:=0 to 3 do begin
        AHeader.Src[i]:= Header^.Src[i];
        AHeader.Dst[i]:= Header^.Dst[i];
    end;
    AHeader.Options:= Header^.Options;

    console.output('net.ipv4', 'Source: ');
    writeIPv4Address(puint8(@AHeader.Src[0]));
    console.output('net.ipv4', 'Dest: ');
    writeIPv4Address(puint8(@AHeader.Dst[0]));

    buf:= puint8(p_data);
    buf:= buf + AHeader.header_len;
    len:= p_len - AHeader.header_len;

    if Protocols[AHeader.Protocol] <> nil then Protocols[AHeader.Protocol](void(buf), len);
end;

procedure register;
var
    i : uint8;

begin
    if not Registered then begin
        for i:=0 to 255 do begin
            Protocols[i]:= nil;
        end;
        eth2.registerType($0800, @recv);
        Registered:= true;
    end;
end;

procedure registerProtocol(Protocol_ID : uint8; recv_callback : TRecvCallback);
begin
    register;
    if Protocols[Protocol_ID] = nil then Protocols[Protocol_ID]:= recv_callback;
end;

end.