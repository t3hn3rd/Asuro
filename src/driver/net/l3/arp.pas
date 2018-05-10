unit arp;

interface

uses
    tracer,
    util, lists, console,
    nettypes, netutils,
    netlog,
    eth2;

type
    PARPCacheRecord = ^TARPCacheRecord;
    TARPCacheRecord = record
        MAC : TMACAddress;
        IP  : TIPv4Address;
    end;

procedure register;
function IPv4ToMAC(ip : puint8) : puint8;
function MACToIIPv4(mac : puint8) : puint8;

implementation

var
    Registered : Boolean = false;
    Cache      : PLinkedListBase;

function findCacheRecordByMAC(mac : puint8) : PARPCacheRecord;
var
    i : uint32;
    r : PARPCacheRecord;

begin
    push_trace('arp.findCacheRecordByMAC');
    findCacheRecordByMAC:= nil;
    for i:=0 to LL_Size(Cache)-1 do begin
        r:= PARPCacheRecord(LL_Get(Cache, i));
        if MACEqual(mac, @r^.MAC[0]) then begin
            findCacheRecordByMAC:= r;
            break;
        end;
    end;
    pop_trace;
end;

function findCacheRecordByIP(ip : puint8) : PARPCacheRecord;
var
    i : uint32;
    r : PARPCacheRecord;

begin
    push_trace('arp.findCacheRecordByIP');
    findCacheRecordByIP:= nil;
    for i:=0 to LL_Size(Cache)-1 do begin
        r:= PARPCacheRecord(LL_Get(Cache, i));
        if IPEqual(ip, @r^.IP[0]) then begin
            findCacheRecordByIP:= r;
            break;
        end;
    end;
    pop_trace;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header       : PARPHeader;
    AHeader      : TARPAbstractHeader;
    CacheElement : PARPCacheRecord;

begin
    push_trace('arp.recv');
    if getNetlogHWND <> 0 then writestringlnWND('arp.recv', getNetlogHWND);
    { Get our converted Header }
    Header:= PARPHeader(p_data);
    AHeader.Hardware_Type:= (Header^.Hardware_Type_Hi SHL 8) + Header^.Hardware_Type_Lo;
    AHeader.Protocol_Type:= (Header^.Protocol_Type_Hi SHL 8) + Header^.Protocol_Type_Lo;
    AHeader.Hardware_Address_Length:= Header^.Hardware_Address_Length;
    AHeader.Protocol_Address_Length:= Header^.Protocol_Address_Length;
    AHeader.Operation:= (Header^.Operation_Hi SHL 8) + Header^.Operation_Lo;
    copyMAC(@Header^.Source_Hardware[0], @AHeader.Source_Hardware[0]);
    copyIPv4(@Header^.Source_Protocol[0], @AHeader.Source_Protocol[0]);
    copyMAC(@Header^.Destination_Hardware[0], @AHeader.Destination_Hardware[0]);
    copyIPv4(@Header^.Destination_Protocol[0], @AHeader.Destination_Protocol[0]);
    case AHeader.Operation of
        $1:begin { ARP Request }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.arp.req', getNetlogHWND);
        end;
        $2:begin { ARP Reply }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.arp.rep', getNetlogHWND);
        end;
        $3:begin { RARP Request }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.rarp.req', getNetlogHWND);
        end;
        $4:begin { RARP Reply }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.rarp.rep', getNetlogHWND);
        end;
        $5:begin { DRARP Request }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.drarp.req', getNetlogHWND);
        end;
        $6:begin { DRARP Reply }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.drarp.rep', getNetlogHWND);
        end;
        $7:begin { DRARP Error }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.drarp.err', getNetlogHWND);
        end;
        $8:begin { InARP Request }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.inarp.req', getNetlogHWND);
        end;
        $9:begin { InARP Reply }
            if getNetlogHWND <> 0 then writestringlnWND('arp.recv.inarp.rep', getNetlogHWND);
        end;
    end;
    pop_trace;
end;

procedure register;
begin
    push_trace('arp.register');
    if not Registered then begin
        Cache:= LL_New(sizeof(TARPCacheRecord));
        eth2.registerType($0806, @recv);
        Registered:= true;
    end;
    pop_trace;
end;

function IPv4ToMAC(ip : puint8) : puint8;
var
     r : PARPCacheRecord;

begin
    push_trace('arp.IPv4ToMAC');
    register;
    IPv4ToMAC:= nil;
    r:= findCacheRecordByIP(ip);
    if r <> nil then begin
        IPv4ToMAC:= @r^.MAC[0];
    end;
    pop_trace;
end;

function MACToIIPv4(mac : puint8) : puint8;
var
     r : PARPCacheRecord;

begin
    push_trace('arp.MACToIPv4');
    register;
    MACToIIPv4:= nil;
    r:= findCacheRecordByMAC(mac);
    if r <> nil then begin
        MACToIIPv4:= @r^.IP[0];
    end;
    pop_trace;
end;

end.