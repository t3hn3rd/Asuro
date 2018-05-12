unit netutils;

interface

uses
    tracer, util, nettypes, console, lmemorymanager, lists, strings;

procedure copyMAC(src : puint8; dst : puint8);
procedure copyIPv4(src : puint8; dst : puint8);
function  stringToMAC(str : pchar) : puint8;
function  stringToIPv4(str : pchar) : puint8;
procedure writeMACAddress(mac : puint8; WND : HWND);
procedure writeIPv4Address(ip : puint8; WND : HWND);
procedure writeMACAddressEx(mac : puint8; WND : HWND);
procedure writeIPv4AddressEx(ip : puint8; WND : HWND);
function MACEqual(mac1 : puint8; mac2 : puint8) : boolean;
function IPEqual(ip1 : puint8; ip2 : puint8) : boolean;
function newPacketContext : PPacketContext;
procedure freePacketContext(p_context : PPacketContext);
function calculateChecksum(p_data : puint16; p_len : uint16) : uint16;
function verifyChecksum(p_data : puint16; p_len : uint16) : boolean;

implementation

function calculateChecksum(p_data : puint16; p_len : uint16) : uint16;
var
    sum   : uint32;
    dat   : puint16;
    carry : uint16;
    i     : uint32;
    l     : uint32;

begin
    dat:= p_data;
    sum:= 0;
    l:= p_len div 2;
    for i:=1 to l do begin
        sum:= sum + p_data^;
        inc(p_data);
    end;
    while (sum > $FFFF) do begin
        carry:= (sum AND $FFFF0000) SHR 16;
        sum:= (sum AND $FFFF);
        sum:= sum + carry;
    end;
    calculateChecksum:= not (sum AND $FFFF);
end;

function verifyChecksum(p_data : puint16; p_len : uint16) : boolean;
begin
    verifyChecksum:= calculateChecksum(p_data, p_len) = $0000;
end;

function  stringToMAC(str : pchar) : puint8;
var
    Mac_Delim : PLinkedListBase;
    i         : uint32;

begin
    stringToMac:= puint8(kalloc(6));
    Mac_Delim:= STRLL_FromString(str, ':');
    if STRLL_Size(Mac_Delim) >= 6 then begin
        for i:=0 to 5 do begin
            stringToMAC[i]:= stringToInt(STRLL_Get(Mac_Delim, i));
        end;
    end;
end;

function  stringToIPv4(str : pchar) : puint8;
var
    IP_Delim : PLinkedListBase;
    i        : uint32;

begin
    stringToIPv4:= puint8(kalloc(6));
    IP_Delim:= STRLL_FromString(str, '.');
    if STRLL_Size(IP_Delim) >= 4 then begin
        for i:=0 to 3 do begin
            stringToIPv4[i]:= stringToInt(STRLL_Get(IP_Delim, i));
        end;
    end;
end;

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

procedure writeIPv4AddressEx(ip : puint8; WND : HWND);
var
    i : integer;

begin
    push_trace('netutils.writeIPv4Address');
    console.writeintWND(ip[0], WND);
    for i:=1 to 3 do begin
        console.writestringWND('.', WND);
        console.writeintWND(ip[i], WND);
    end; 
end;

procedure writeMACAddressEx(mac : puint8; WND : HWND);
var
    i : integer;

begin
    push_trace('netutils.writeMACAddress');
    console.writehexpairWND(mac[0], WND);
    for i:=1 to 5 do begin
        console.writestringWND(':', WND);
        console.writehexpairWND(mac[i], WND);
    end;
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