unit netutils;

interface

uses
    tracer, util, nettypes, console, lmemorymanager;

procedure copyMAC(src : puint8; dst : puint8);
procedure copyIPv4(src : puint8; dst : puint8);
procedure writeMACAddress(mac : puint8; WND : HWND);
procedure writeIPv4Address(ip : puint8; WND : HWND);
function MACEqual(mac1 : puint8; mac2 : puint8) : boolean;
function IPEqual(ip1 : puint8; ip2 : puint8) : boolean;
function newPacketContext : PPacketContext;
procedure freePacketContext(p_context : PPacketContext);

implementation

function IPEqual(ip1 : puint8; ip2 : puint8) : boolean;
var
    i : uint8;

begin
    push_trace('netutils.IPEqual');
    IPEqual:= true;
    for i:=0 to 3 do begin
        if ip1[i] <> ip2[i] then begin
            IPEqual:= false;
            break;
        end;
    end;
    pop_trace;
end;

function MACEqual(mac1 : puint8; mac2 : puint8) : boolean;
var
    i : uint8;

begin
    push_trace('netutils.MACEqual');
    MACEqual:= true;
    for i:=0 to 5 do begin
        if mac1[i] <> mac2[i] then begin
            MACEqual:= false;
            break;
        end;
    end;
    pop_trace;
end;

procedure writeIPv4Address(ip : puint8; WND : HWND);
var
    i : integer;

begin
    push_trace('netutils.writeIPv4Address');
    console.writeintWND(ip[0], WND);
    for i:=1 to 3 do begin
        console.writestringWND('.', WND);
        console.writeintWND(ip[i], WND);
    end;
    console.writestringlnWND(' ', WND);   
    pop_trace;
end;

procedure writeMACAddress(mac : puint8; WND : HWND);
var
    i : integer;

begin
    push_trace('netutils.writeMACAddress');
    console.writehexpairWND(mac[0], WND);
    for i:=1 to 5 do begin
        console.writestringWND(':', WND);
        console.writehexpairWND(mac[i], WND);
    end;
    console.writestringlnWND(' ', WND);
    pop_trace;
end;

function newPacketContext : PPacketContext;
begin
    push_trace('netutils.newPacketContext');
    newPacketContext:= PPacketContext(kalloc(sizeof(TPacketContext)));
    memset(uint32(newPacketContext), 0, sizeof(TPacketContext));
    pop_trace;    
end;

procedure freePacketContext(p_context : PPacketContext);
begin
    push_trace('netutils.freePacketContext');
    kfree(void(p_context));
    pop_trace;
end;

procedure copyMAC(src : puint8; dst : puint8);
var
    i : uint8;

begin
    push_trace('netutils.copyMAC');
    for i:=0 to 5 do begin
        dst[i]:= src[i];
    end;
    pop_trace;
end;

procedure copyIPv4(src : puint8; dst : puint8);
var
    i : uint8;

begin
    push_trace('netutils.copyIPv4');
    for i:=0 to 3 do begin
        dst[i]:= src[i];
    end;
    pop_trace;
end;

end.