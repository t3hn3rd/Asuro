unit arp;

interface

uses
    tracer, lmemorymanager,
    util, lists, console,
    net, nettypes, netutils,
    netlog,
    eth2, ipv4;

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

procedure send(hType : uint16; pType : uint16; op : uint16; p_context : PPacketContext);
var
    buf : void;
    hdr : PARPHeader;
    hSize, pSize : uint8;

begin
    push_trace('arp.send');
    writeToLogLn('        L3: arp.send');
    if p_context <> nil then begin
        buf:= kalloc(sizeof(TARPHeader));
        hdr:= PARPHeader(buf);
        case hType of
            $1 : hSize:= 6;
            else hSize:= 0;
        end;
        case pType of
            $8000 : pSize:= 4;
            else pSize:= 0;
        end;
        if (hSize > 0) and (pSize > 0) then begin
            hdr^.Hardware_Type_Hi:= hType SHR 8;
            hdr^.Hardware_Type_Lo:= hType AND $FF;
            hdr^.Protocol_Type_Hi:= pType SHR 8;
            hdr^.Protocol_Type_Lo:= pType AND $FF;
            hdr^.Hardware_Address_Length:= hSize;
            hdr^.Protocol_Address_Length:= pSize;
            hdr^.Operation_Hi:= op SHR 8;
            hdr^.Operation_Lo:= op AND $FF;
            copyMAC(@p_context^.MAC.Source[0], @hdr^.Source_Hardware[0]);
            copyIPv4(@p_context^.IP.Source[0], @hdr^.Source_Protocol[0]);
            copyMAC(@p_context^.MAC.Destination[0], @hdr^.Destination_Hardware[0]);
            copyIPv4(@p_context^.IP.Destination[0], @hdr^.Destination_Protocol[0]);
            //eth2.send(buf, sizeof(TARPHeader), p_context);
        end;
        kfree(buf);
    end;
end;

procedure recv(p_data : void; p_len : uint16; p_context : PPacketContext);
var
    Header       : PARPHeader;
    AHeader      : TARPAbstractHeader;
    CacheElement : PARPCacheRecord;
    Merge        : boolean;
    context      : PPacketContext;

begin
    push_trace('arp.recv');
    writeToLogLn('        L3: arp.recv');
    
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
    
    { Process ARP Packet }
    Merge:= false;
    CacheElement:= findCacheRecordByIP(@AHeader.Source_Protocol[0]);
    if CacheElement <> nil then begin
        copyMAC(@AHeader.Source_Hardware[0], @CacheElement^.MAC[0]);
        Merge:= true;
    end else begin
        if IPEqual(@AHeader.Destination_Protocol[0], @getIPv4Config^.Address[0]) then begin
            if not Merge then begin
                CacheElement:= PARPCacheRecord(LL_Add(Cache));
                CopyMAC(@AHeader.Source_Hardware[0], @CacheElement^.MAC[0]);
                copyIPv4(@AHeader.Source_Protocol[0], @CacheElement^.IP[0]);
            end;
            case AHeader.Operation of
                $1:begin { ARP Request }
                    writeToLogLn('            arp.recv.arp.req');
                    context:= newPacketContext;
                    //context^.
                    copyMAC(@AHeader.Source_Hardware[0], @context^.MAC.Destination[0]);
                    copyIPv4(@AHeader.Source_Protocol[0], @context^.IP.Destination[0]);
                    copyMAC(getMAC, @context^.MAC.Source[0]);
                    copyIPv4(@getIPv4Config^.Address[0], @context^.IP.Source[0]);
                    //send($1, $8000, $2, context);
                    freePacketContext(context);
                end;
                $2:begin { ARP Reply }
                    writeToLogLn('            arp.recv.arp.rep');
                end;
                $3:begin { RARP Request }
                    writeToLogLn('            arp.recv.rarp.req');
                end;
                $4:begin { RARP Reply }
                    writeToLogLn('            arp.recv.rarp.rep');
                end;
                $5:begin { DRARP Request }
                    writeToLogLn('            arp.recv.drarp.req');
                end;
                $6:begin { DRARP Reply }
                    writeToLogLn('            arp.recv.drarp.rep');
                end;
                $7:begin { DRARP Error }
                    writeToLogLn('            arp.recv.drarp.err');
                end;
                $8:begin { InARP Request }
                    writeToLogLn('            arp.recv.inarp.req');
                end;
                $9:begin { InARP Reply }
                    writeToLogLn('            arp.recv.inarp.rep');
                end;
            end;
        end;
    end;
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