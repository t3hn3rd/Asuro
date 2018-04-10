unit arp;

interface

uses
    util, lists, console,
    nettypes, netutils,
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
    findCacheRecordByMAC:= nil;
    for i:=0 to LL_Size(Cache)-1 do begin
        r:= PARPCacheRecord(LL_Get(Cache, i));
        if MACEqual(mac, @r^.MAC[0]) then begin
            findCacheRecordByMAC:= r;
            exit;
        end;
    end;
end;

function findCacheRecordByIP(ip : puint8) : PARPCacheRecord;
var
    i : uint32;
    r : PARPCacheRecord;

begin
    findCacheRecordByIP:= nil;
    for i:=0 to LL_Size(Cache)-1 do begin
        r:= PARPCacheRecord(LL_Get(Cache, i));
        if IPEqual(ip, @r^.IP[0]) then begin
            findCacheRecordByIP:= r;
            exit;
        end;
    end;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header       : PARPHeader;
    AHeader      : TARPAbstractHeader;
    CacheElement : PARPCacheRecord;

begin
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
            //console.writestringln('ARP Request.');
        end;
        $2:begin { ARP Reply }
            //console.writestringln('ARP Reply.');
        end;
        $3:begin { RARP Request }
        
        end;
        $4:begin { RARP Reply }
        
        end;
        $5:begin { DRARP Request }
        
        end;
        $6:begin { DRARP Reply }
        
        end;
        $7:begin { DRARP Error }
        
        end;
        $8:begin { InARP Request }
        
        end;
        $9:begin { InARP Reply }
        
        end;
    end;
end;

procedure register;
begin
    if not Registered then begin
        Cache:= LL_New(sizeof(TARPCacheRecord));
        eth2.registerType($0806, @recv);
        Registered:= true;
    end;
end;

function IPv4ToMAC(ip : puint8) : puint8;
var
     r : PARPCacheRecord;

begin
    register;
    IPv4ToMAC:= nil;
    r:= findCacheRecordByIP(ip);
    if r <> nil then begin
        IPv4ToMAC:= @r^.MAC[0];
    end;
end;

function MACToIIPv4(mac : puint8) : puint8;
var
     r : PARPCacheRecord;

begin
    register;
    MACToIIPv4:= nil;
    r:= findCacheRecordByMAC(mac);
    if r <> nil then begin
        MACToIIPv4:= @r^.IP[0];
    end;
end;

end.