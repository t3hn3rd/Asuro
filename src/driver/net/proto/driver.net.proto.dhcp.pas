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
	Driver->Net->L5->DHCP - Dynamic Host Configuration Protocol Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.net.proto.dhcp;

interface

uses
    memory.heap, io.syslog,
    driver.net.types, driver.net.util, driver.net.proto.udp, driver.net,
    core.util, arch.x86.util, core.rand, core.ds.lists, debug.tracer, driver.net.proto.ipv4, driver.net.proto.arp;

type
    TDHCPOptions = PLinkedListBase;
    PDHCPOptions = ^PLinkedListBase;
    TDHCPOption = record
        Opcode          : TDHCPOpCode;
        Size            : uint32;
        Value           : void;
        Reverse_Endian  : boolean;
    end;
    PDHCPOption = ^TDHCPOption;

procedure register();
procedure DHCPDiscover();

implementation

type
    TFlipExclude = Array[0..255] of boolean;
    PFlipExclude = ^TFlipExclude;
    TDHCPConfiguration = record
        Transaction : uint32;
        Options     : array[0..255] of void;
    end;
    PDHCPConfiguation = ^TDHCPConfiguration;

var
    Configuration : PDHCPConfiguation;
    Socket        : PUDPBindContext = nil;
    FlipExclude   : PFlipExclude;

procedure nullConfiguration;
var
    i : uint8;

begin
    { Null the entire configuration ready for a new DISCOVER or REQUEST }
    if configuration <> nil then begin
        Configuration^.Transaction:= 0;
        for i:=0 to 255 do begin
            if Configuration^.Options[i] <> nil then begin
                kfree(Configuration^.Options[i]);
            end;
            Configuration^.Options[i]:= nil;
        end;
    end;
end;

function createHeader(): PDHCPHeader;
var
    result : PDHCPHeader;
    MAC    : puint8;

begin
    { Create a basic header with most values nulled, Hardware type & length is prefilled for ethernet }
    debug.tracer.push_trace('driver.net.proto.dhcp.newHeader');
    result:= PDHCPHeader(kalloc(sizeof(TDHCPHeader)));
    result^.Message_Type:= $01;
    result^.Hardware_Type:= $01;
    result^.Hardware_Address_Length:= $06;
    result^.Hops:= $00;
    result^.Transaction_ID:= Configuration^.Transaction;
    result^.Seconds_Elapsed:= $0000;
    result^.Bootp_Flags:= $0000;
    CopyIPv4(@NULL_IP[0], @result^.Client_IP[0]);
    CopyIPv4(@NULL_IP[0], @result^.Your_IP[0]);
    CopyIPv4(@NULL_IP[0], @result^.Server_IP[0]);
    CopyIPv4(@NULL_IP[0], @result^.Relay_Agent_IP[0]);
    MAC:= getMAC;
    CopyMAC(MAC, @result^.Client_MAC[0]);
    memset(uint32(@result^.Padding[0]), 0, 10);
    memset(uint32(@result^.Server_Hostname[0]), 0, 64);
    memset(uint32(@result^.Boot_File[0]), 0, 128);
    memcpy(uint32(@DHCP_MAGIC[0]), uint32(@result^.Magic_Cookie[0]), 4);
    createHeader:= result;
end;

function newOption(DHCPOptions : PDHCPOptions; Opcode : TDHCPOpCode; Data : void; Length : uint32; SwapEndian : Boolean) : PDHCPOption;
var
    Option : PDHCPOption;

begin
    { Add an option to the Options linkedlist, copy data[size] to the Option }
    debug.tracer.push_trace('driver.net.proto.dhcp.newOption');
    Option:= PDHCPOption(LL_Add(PLinkedListBase(DHCPOptions)));
    Option^.Opcode:= Opcode;
    Option^.Size:= Length;
    Option^.Reverse_Endian:= SwapEndian;
    if Length > 0 then begin
        Option^.Value:= kalloc(Length);
        memcpy(uint32(Data), uint32(Option^.Value), Length);
    end else begin
        Option^.Value:= nil;
    end;
    newOption:= Option;
end;

procedure deleteOption(DHCPOptions : PDHCPOptions; idx : uint32);
var
    Option : PDHCPOption;

begin
    { Remove an option from the linkedlsit }
    debug.tracer.push_trace('driver.net.proto.dhcp.deleteOptions');
    Option:= PDHCPOption(LL_Get(PLinkedListBase(DHCPOptions), idx));
    if Option <> nil then begin
        if Option^.Value <> nil then begin
            kfree(Option^.Value);
        end;
        LL_Delete(PLinkedListBase(DHCPOptions), idx);
    end;
end;

function getOption(DHCPOptions : PDHCPOptions; idx : uint32) : PDHCPOption;
begin
    { Get an option by index from the linkedlist }
    debug.tracer.push_trace('driver.net.proto.dhcp.getOption');
    getOption:= PDHCPOption(LL_Get(PLinkedListBase(DHCPOptions),idx));
end;

function newOptions : PDHCPOptions;
begin
    { Create a new Options LinkedList }
    debug.tracer.push_trace('driver.net.proto.dhcp.newOptions');
    newOptions:= PDHCPOptions(LL_New(sizeof(TDHCPOption)));
end;

procedure freeOptions(Options : PDHCPOptions);
begin
    { Free all options and free their underlying data buffers }
    debug.tracer.push_trace('driver.net.proto.dhcp.freeOptions');
    if Options <> nil then begin
        while LL_Size(PLinkedListBase(Options)) > 0 do begin
            deleteOption(Options, 0);
        end;
        LL_Free(PLinkedListBase(Options));
    end;
end;

function getOptionsCount(Options : PDHCPOptions) : uint32;
begin
    { Get the number of options in the linkedlist }
    debug.tracer.push_trace('driver.net.proto.dhcp.getOptionsCount');
    getOptionsCount:= LL_Size(PLinkedListBase(Options));
end;    

function calculateOptionsSize(Options : PDHCPOptions) : uint16;
var
    i : uint32;
    Option : PDHCPOption;
    OptionsSize : uint16;

begin
    { 
        Get the size of all options in the linkedlist 
        1 byte for the opcode
        1 byte for the length
        n bytes (specified by length) for the data
        total = foreach(element):(sizeof(opcode)+sizeof(length)+length)
    }
    debug.tracer.push_trace('driver.net.proto.dhcp.calculateOptionsSize');
    OptionsSize := 0;
    for i:=0 to getOptionsCount(Options)-1 do begin
        Option:= PDHCPOption(LL_Get(PLinkedListBase(Options),i));
        case Option^.Opcode of
            { PAD & END_VENDOR_OPTIONS are special cases as they are 1 byte in length with no size byte }
            PAD,END_VENDOR_OPTIONS : inc(OptionsSize,1);
            else inc(OptionsSize, 2 + Option^.Size);
        end;
    end;
    calculateOptionsSize:= OptionsSize;
end;

function getEndianCorrectValue16(Option : PDHCPOption) : uint16;
var
    Value : uint16;

begin
    { Get the value from an Option as an endian corrected (if applicable) uint16 }
    debug.tracer.push_trace('driver.net.proto.dhcp.getEndianCorrectValue16');
    Value:= PuInt16(Option^.Value)^;
    if Option^.Reverse_Endian then 
        getEndianCorrectValue16:= switchendian16(Value) 
    else 
        getEndianCorrectValue16:= Value;
end;

function getEndianCorrectValue32(Option : PDHCPOption) : uint32;
var
    Value : uint32;
begin
    { Get the value from an Option as an endian corrected (if applicable) uint32 }
    debug.tracer.push_trace('driver.net.proto.dhcp.getEndianCorrectValue32');
    Value:= puint32(Option^.Value)^;
    if Option^.Reverse_Endian then
        getEndianCorrectValue32:= switchendian32(Value)
    else
        getEndianCorrectValue32:= Value;
end;

function readOption8(Option : PDHCPOption) : uint8;
var
    read8 : puint8;
begin
    { Read the option data as an 8-bit value }
    read8:= puint8(Option^.Value);
    readOption8:= read8^;
end;

function readOption16(Option : PDHCPOption) : uint16;
var
    read16 : puint16;
begin
    { Read the option data as an 16-bit value }
    read16:= puint16(Option^.Value);
    readOption16:= read16^;
end;

function readOption32(Option : PDHCPOption) : uint32;
var
    read32 : puint32;
begin
    { Read the option data as an 32-bit value }
    read32:= puint32(Option^.Value);
    readOption32:= read32^;
end;

function getOptionByOpcode(Options : PDHCPOptions; Opcode : TDHCPOpCode) : PDHCPOption;
var
    Option : PDHCPOption;
    i      : uint16;

begin
    { Search the linked list for a given OpCode and return if found, nil if not. }
    getOptionByOpcode:= nil;
    for i:=0 to getOptionsCount(Options)-1 do begin
        Option:= getOption(Options, i);
        if Option^.Opcode = Opcode then begin
            getOptionByOpcode:= Option;
            break;
        end;
    end;
end;

function writeOptions(Header : PDHCPHeader; Options : PDHCPOptions; newLength : puint16) : PDHCPHeader;
var
    OptionsSize : uint16;
    TotalSize   : uint16;
    NewBuffer   : void;
    NewHeader   : PDHCPHeader;
    buffer      : puint8;
    read8       : puint8;
    read16      : puint16;
    read32      : puint32;
    Option      : PDHCPOption;
    i           : uint32;

begin
    debug.tracer.push_trace('driver.net.proto.dhcp.writeOptions');

    { Make room in our new packet buffer for the header + options }
    OptionsSize := calculateOptionsSize(Options);
    TotalSize:= OptionsSize + SizeOf(TDHCPHeader);
    NewBuffer:= kalloc(TotalSize);

    { Copy the header }
    NewHeader:= PDHCPHeader(NewBuffer);
    memcpy(uint32(Header), uint32(NewHeader), sizeof(TDHCPHeader));

    { Write Options }
    buffer:= puint8(NewBuffer);
    inc(buffer, SizeOf(TDHCPHeader));
    for i:=0 to getOptionsCount(Options)-1 do begin
        Option:= getOption(Options, i);
        case Option^.Opcode of
            { PAD & END_VENDOR_OPTIONS have a length of 0 & no length byte }
            PAD,END_VENDOR_OPTIONS:begin
                buffer^:= Ord(Option^.Opcode);
                inc(buffer);
            end;
            { Everything else follows the format: uint8(OpCode)->uint8(Length)->variable(Data) }
            else begin
                buffer^:= Ord(Option^.OpCode);
                inc(buffer);
                buffer^:= Option^.Size;
                inc(buffer);
                case Option^.Size of
                    { Try to read and write using a 16bit or 32bit pointer for speed, else do a memcpy }
                    2:begin
                        read16:= puint16(buffer);
                        read16^:= getEndianCorrectValue16(Option);
                    end;
                    4:begin
                        read32:= puint32(buffer);
                        read32^:= getEndianCorrectValue32(Option);
                    end;
                    else begin
                        memcpy(uint32(Option^.Value), uint32(buffer), Option^.Size);
                    end;
                end;
                inc(buffer, Option^.Size);
            end;
        end;
    end;
    { Return the new packet size a pointer to the packet (Header) }
    newLength^:= TotalSize;
    writeOptions:= PDHCPHeader(NewBuffer);
end;


procedure readOptions(DHCPOptions : PDHCPOptions; p_data : void; p_len : uint16);
var
    headerSize : uint32;
    buffer     : puint8;
    bufferEnd   : puint8;
    bufferStart : puint8;
    HaveOp      : boolean;
    HaveLen     : boolean;
    Opcode      : TDHCPOpCode;
    Length      : uint8;
    read32 : puint32;
    read16 : puint16;
    Option : PDHCPOption;

begin
    debug.tracer.push_trace('driver.net.proto.dhcp.register');

    { Get the beginning & end of the Options buffer }
    HeaderSize:= sizeOf(TDHCPHeader);
    bufferEnd:= puint8(uint32(p_data) + p_len);
    bufferStart:= puint8(uint32(p_data) + headerSize);
    
    { Buffer is our iterator }
    buffer:= bufferStart;

    HaveOp:= false;
    HaveLen:= false;
    
    while (uint32(buffer) < uint32(bufferEnd)) do begin
        { 
            If we have a length, read the value (bytes[length])
            If we have an Opcode read the length (bytes[1])
            If we have neither, read the opcode (bytes[1])
        }
        if HaveLen then begin
            { Get a new option LinkedList 'object' and store everything inside }
            Option:= newOption(DHCPOptions, Opcode, void(buffer), Length, not FlipExclude^[ord(Opcode)]);
            if Length = 2 then begin
                if Option^.Reverse_Endian then begin
                    read16:= puint16(Option^.Value);
                    read16^:= switchendian16(read16^);
                end;
            end;
            if Length = 4 then begin
                if Option^.Reverse_Endian then begin
                    read32:= puint32(Option^.Value);
                    read32^:= switchendian32(read32^);
                end;
            end;
            inc(buffer, Length);
            HaveOp:= false;
            HaveLen:= false;
        end else if HaveOp then begin
            Length:= buffer^;
            HaveLen:= true;
            inc(buffer);
        end else begin
            Opcode:= TDHCPOpCode(buffer^);
            case opcode of
                PAD,END_VENDOR_OPTIONS:begin
                    Length:= 0;
                    haveLen:= true;
                end;
            end;
            HaveOp:= true;
            inc(buffer)
        end;
    end;
end;

procedure processHeader(Header : PDHCPHeader);
begin
    { Switch endianness of any network-byte-order values }
    Header^.Transaction_ID:= switchendian32(Header^.Transaction_ID);
    Header^.Seconds_Elapsed:= switchendian16(Header^.Seconds_Elapsed);
    Header^.Bootp_Flags:= switchendian16(Header^.Bootp_Flags);
end;

procedure processPacket_NAK(Header : PDHCPHeader; Options : PDHCPOptions);
begin
    writeToLogLn('          L5/DHCP: Process NAK.');
    { Server provided a NAK, NULL configuration ready for next DISCOVER/Request } 
    nullConfiguration();  
end;

procedure processPacket_ACK(Header : PDHCPHeader; Options : PDHCPOptions);
var
    i : uint16;
    Option : PDHCPOption;
    read16 : puint16;
    read32 : puint32;
    cfgopt : void;

begin
    writeToLogLn('          L5/DHCP: Process ACK.');
    getIPv4Config^.UP:= false;
    
    //Copy new address
    Configuration^.Options[Ord(TDHCPOpCode.REQUESTED_IP_ADDRESS)]:= kalloc(sizeof(TIPv4Address));
    copyIPv4(@Header^.Your_IP[0], puint8(Configuration^.Options[Ord(TDHCPOpCode.REQUESTED_IP_ADDRESS)]));

    { Copy any given configuration data }
    for i:=0 to getOptionsCount(Options)-1 do begin
        Option:= getOption(Options, i);
        case Option^.Opcode of
            PAD,END_VENDOR_OPTIONS:begin
            end;
            else begin
                cfgopt:= kalloc(Option^.Size);
                Configuration^.Options[ord(Option^.Opcode)]:= cfgopt;
                memcpy(uint32(Option^.Value), uint32(cfgopt), Option^.Size);
            end;
        end;
    end;

    { Copy into IPv4 Configuration }
    if Configuration^.Options[Ord(TDHCPOpCode.REQUESTED_IP_ADDRESS)] <> nil then
        copyIPv4(puint8(Configuration^.Options[Ord(TDHCPOpCode.REQUESTED_IP_ADDRESS)]), puint8(@getIPv4Config^.address[0]));
    if Configuration^.Options[Ord(TDHCPOpCode.ROUTER)] <> nil then
        copyIpv4(puint8(Configuration^.Options[Ord(TDHCPOpCode.ROUTER)]),  puint8(@getIPv4Config^.Gateway[0]));
    if Configuration^.Options[Ord(TDHCPOpCode.SUBNET_MASK)] <> nil then
        copyIPv4(puint8(Configuration^.Options[Ord(TDHCPOpCode.SUBNET_MASK)]), puint8(@getIPv4Config^.Netmask[0]));

    driver.net.proto.arp.sendGratuitous;
    driver.net.proto.arp.sendRequest(@getIPv4Config^.Gateway[0]);

    getIPv4Config^.UP:= true;
end;

procedure processPacket_OFFER(Header : PDHCPHeader; Options : PDHCPOptions);
Var
    SendHeader  : PDHCPHeader;
    SendOptions : PDHCPOptions;
    SendMsgType : uint8;

    NewSendHeader : PDHCPHeader;
    NewHeaderSize : uint32;

    RequestParams : Array[0..3] of uint8;

    SendCtx     : PUDPSendContext;
    PacketCtx   : PPacketContext;

    MAC         : puint8;

    Option      : PDHCPOption;

begin
    io.syslog.logln('DHCP', 'Process OFFER.');  
    writeToLogLn('          L5/DHCP: Process OFFER.');
    { Check the Transaction ID matches our stored ID, discard if not. }
    if Header^.Transaction_ID = Configuration^.Transaction then begin
        io.syslog.logln('DHCP', 'XID Match');
        
        { Create a new header to the use in our DHCP REQUEST packet }
        SendHeader:= createHeader();
        CopyIPv4(@getIPv4Config^.Address[0], puint8(@SendHeader^.Client_IP[0]));
        CopyIPv4(puint8(@Header^.Server_IP[0]), puint8(@SendHeader^.Server_IP[0]));
        processHeader(SendHeader);

        { Setup Options }
        SendOptions:= newOptions();

        { Create a message type option and assign it the value REQUEST }
        SendMsgType:= ord(TDHCPMessageType.REQUEST);
        NewOption(SendOptions, TDHCPOpCode.DHCP_MESSAGE_TYPE, void(@SendMsgType), 1, false);

        { Create a Requested IP option and assign it the value from the OFFER packet header }
        NewOption(SendOptions, TDHCPOpCode.REQUESTED_IP_ADDRESS, void(@Header^.Your_IP[0]), 4, false);

        { Create a Server Identifier Option and assign it the value from the OFFER packet options }
        Option:= getOptionByOpcode(Options, TDHCPOpCode.SERVER_IDENTIFIER);
        if Option <> nil then begin
            NewOption(SendOptions, TDHCPOpCode.SERVER_IDENTIFIER, void(@Option^.Value[0]), 4, false);
        end;

        { Create a Parameter Request List, Request the following: Netmask, Gateway, DNS Name & DNS Server }
        RequestParams[0]:= Ord(TDHCPOpCode.SUBNET_MASK);
        RequestParams[1]:= Ord(TDHCPOpCode.ROUTER);
        RequestParams[2]:= Ord(TDHCPOpCode.DOMAIN_NAME);
        RequestParams[3]:= Ord(TDHCPOpCode.DNS_SERVER);
        NewOption(SendOptions, TDHCPOpCode.PARAMETER_REQUEST_LIST, void(@RequestParams[0]), 4, false);
        NewOption(SendOptions, TDHCPOpCode.END_VENDOR_OPTIONS, nil, 0, false);

        { Write the options to the header }
        NewSendHeader:= writeOptions(SendHeader, SendOptions, @NewHeaderSize);

        { Setup Packet Context (IPv4 & ETH2) & Copy in the correct details }
        MAC:= getMAC();
        packetCtx:= PPacketContext(Kalloc(sizeof(TPacketContext)));
        packetCtx^.TTL:= 128;

        { Copy over MAC - src: broadcast - dst: DHCP Server }
        copyMAC(MAC, @packetCtx^.MAC.Source[0]);
        copyMAC(@BROADCAST_MAC[0], @packetCtx^.MAC.Destination[0]);
        
        { Copy over IP - src: NULL - dst: Broadcast }
        CopyIPv4(@getIPv4Config^.Address[0], @packetCtx^.IP.Source[0]);
        copyIPv4(@BROADCAST_IP[0], @packetCtx^.IP.Destination[0]);

        { Setup UDPContext (UDP) & copy in the correct details }
        sendCtx:= PUDPSendContext(Kalloc(sizeof(TUDPSendContext)));
        sendCtx^.DstPort:= 67;
        sendCtx^.context:= packetCtx;
        sendCtx^.socket:= Socket;

        { Send the packet }
        driver.net.proto.udp.send(void(NewSendHeader), NewHeaderSize, sendCtx);

        { Free everything we allocated }
        freeOptions(SendOptions);
        kfree(void(NewSendHeader));
        kfree(void(SendHeader));
        kfree(void(packetCtx));
        kfree(void(sendCtx));
    end else begin
        io.syslog.logln('DHCP', 'XID Mismatch');  
    end;  
end;

procedure processPacket(p_data : void; p_len : uint16; context : PUDPPacketContext);
var
    Header  : PDHCPHeader;
    Options : PDHCPOptions;
    Option  : PDHCPOption;
    MAC     : puint8;
    i       : uint32;
    MsgType : uint8;

begin
    debug.tracer.push_trace('driver.net.proto.dhcp.processPacket.enter');
    writeToLogLn('          L5/DHCP: processPacket');
    io.syslog.logln('DHCP','processPacket');
    
    { Give access to header values & process to correct endianness. }
    Header:= PDHCPHeader(p_data);
    processHeader(Header);
    
    { Process Options }
    Options:= newOptions;
    readOptions(Options, p_data, p_len);

    { Check the frame is for us and then process }
    MAC:= getMAC;
    if MACEqual(@context^.PacketContext^.MAC.Destination[0], MAC) or MACEqual(@context^.PacketContext^.MAC.Destination[0], BROADCAST_MAC) then begin
        io.syslog.logln('DHCP','Frame is addressed to us.');
        { Check the message type is client specific }
        If Header^.Message_Type = $02 then begin
            io.syslog.logln('DHCP','Packet is a client packet.');

            { Iterate options to find DHCP_MESSAGE_TYPE }
            io.syslog.logln('DHCP','Searching for message type in Options');
            for i:=0 to getOptionsCount(Options)-1 do begin
                Option:= getOption(Options, i);
                if Option^.Opcode = DHCP_MESSAGE_TYPE then begin
                    break;
                end else begin
                    Option:= nil;
                end;
            end;
            io.syslog.logln('DHCP','Done searching for message type in Options');

            { Did we successfully get the DHCP_MESSAGE_TYPE option? }
            if Option <> nil then begin
                io.syslog.logln('DHCP','Found message type option.');
                { Read the value of DHCP_MESSAGE_TYPE }
                MsgType:= readOption8(Option);
                case TDHCPMessageType(MsgType) of
                    { Pass to the correct packet processing function }
                    TDHCPMessageType.OFFER:processPacket_OFFER(Header, Options);
                    TDHCPMessageType.PACK:processPacket_ACK(Header, Options);
                    TDHCPMessageType.NAK:processPacket_NAK(Header, Options);
                end;
            end else begin
                { Could not find the DHCP_MESSAGE_TYPE option }
                io.syslog.logln('DHCP','Could not find message type option.');
            end;
        end else begin
            { Packet is intended for a DHCP server }
            io.syslog.logln('DHCP','Packet is a server packet.');
        end;
    end else begin
        io.syslog.logln('DHCP', 'Packet is not addressed to us.');
    end;

    freeOptions(Options);
    debug.tracer.push_trace('driver.net.proto.dhcp.processPacket.exit');
end;

procedure DHCPDiscover();
var
    SendCtx     : PUDPSendContext;
    PacketCtx   : PPacketContext;
    Header      : PDHCPHeader;
    NewHeader   : PDHCPHeader;
    HeaderSize  : uint32; 
    Options     : PDHCPOptions;
    MsgType     : uint8;
    MAC         : puint8;

begin
    debug.tracer.push_trace('driver.net.proto.dhcp.DHCPDiscover.begin');
    writeToLogLn('          L5/DHCP: DHCPDiscover');
    { Ensure we have a socket bound. }
    if Socket <> nil then begin    
        { Clear any current configuration }
        nullConfiguration();

        { Setup our Transaction ID }
        Configuration^.Transaction:= rand32();
        
        { Setup header }
        Header:= createHeader();
        processHeader(Header);

        { Setup options }
        Options:= newOptions;
        MsgType:= Ord(TDHCPMessageType.DISCOVER);
        newOption(Options, DHCP_MESSAGE_TYPE, void(@MsgType), 1, false);
        NewOption(Options, END_VENDOR_OPTIONS, nil, 0, false);

        { Write options to header }
        NewHeader:= writeOptions(Header, Options, @HeaderSize);

        { Setup Packet Context (IPv4 & ETH2) }
        packetCtx:= PPacketContext(Kalloc(sizeof(TPacketContext)));
        packetCtx^.TTL:= 128;
        copyMAC(@BROADCAST_MAC[0], @packetCtx^.MAC.Destination[0]);
        MAC:= getMAC;
        copyMAC(MAC, @packetCtx^.MAC.Source[0]);
        CopyIPv4(@getIPv4Config^.Address[0], @packetCtx^.IP.Source[0]);
        copyIPv4(@BROADCAST_IP[0], @packetCtx^.IP.Destination[0]);

        { Setup UDPContext (UDP) }
        sendCtx:= PUDPSendContext(Kalloc(sizeof(TUDPSendContext)));
        sendCtx^.DstPort:= 67;
        sendCtx^.context:= packetCtx;
        sendCtx^.socket:= Socket;

        { NET UP }
        getIPv4Config^.UP:= true;

        { Send }
        driver.net.proto.udp.send(void(NewHeader), HeaderSize, sendCtx);

        { Free }
        kfree(void(PacketCtx));
        kfree(void(sendCtx));
        kfree(void(Header));
        kfree(void(NewHeader));
        freeOptions(Options);
    end;
    debug.tracer.push_trace('driver.net.proto.dhcp.DHCPDiscover.exit');
end;

procedure bind();
begin
    { Bind our socket, free the socket in case of failure }
    Socket:= PUDPBindContext(Kalloc(sizeof(TUDPBindContext)));
    Socket^.Port:= 68;
    Socket^.Callback:= @processPacket;
    Socket^.UID:= rand32;
    case driver.net.proto.udp.bind(Socket) of
        tueOK:io.syslog.logln('DHCP', 'Successfully bound port 68.');
        else begin
            kfree(void(Socket));
            Socket:= nil;
            io.syslog.logln('DHCP', 'Failed to bind port 68.');
        end;
    end;
end;

procedure register();
var
    i : uint8;

begin
    debug.tracer.push_trace('driver.net.proto.dhcp.register');
    writeToLogLn('          L5/DHCP: register');
    io.syslog.logln('DHCP', 'Register begin.');
    
    { Kalloc our Configuration Data }
    Configuration:= PDHCPConfiguation(kalloc(sizeof(TDHCPConfiguration)));

    { Null Existing Coniguration }
    for i:=0 to 255 do begin
        Configuration^.Options[i] := nil;
    end;
    nullConfiguration();

    { Clear FlipExclude Table }
    FlipExclude:= PFlipExclude(kalloc(sizeof(TFlipExclude)));
    for i:=0 to 255 do begin
        FlipExclude^[i]:= false;
    end;

    { Set FlipExclude Table up to exclude certain OPCode from EndianFlips }
    FlipExclude^[ord(PAD)]:= true;
    FlipExclude^[ord(SUBNET_MASK)]:= true;
    FlipExclude^[ord(ROUTER)]:= true;
    FlipExclude^[ord(TIME_SERVER)]:= true;
    FlipExclude^[ord(NAME_SERVER)]:= true;
    FlipExclude^[ord(DNS_SERVER)]:= true;
    FlipExclude^[ord(LOG_SERVER)]:= true;
    FlipExclude^[ord(COOKIE_SERVER)]:= true;
    FlipExclude^[ord(LPR_SERVER)]:= true;
    FlipExclude^[ord(IMPRESS_SERVER)]:= true;
    FlipExclude^[ord(RESOURCE_LOCATION_SERVER)]:= true;
    FlipExclude^[ord(HOST_NAME)]:= true;
    FlipExclude^[ord(MERIT_DUMP_FILE)]:= true;
    FlipExclude^[ord(DOMAIN_NAME)]:= true;
    FlipExclude^[ord(SWAP_SERVER)]:= true;
    FlipExclude^[ord(ROOT_PATH)]:= true;
    FlipExclude^[ord(EXTENSIONS_PATH)]:= true;
    FlipExclude^[ord(END_VENDOR_OPTIONS)]:= true;
    FlipExclude^[ord(BROADCAST_ADDRESS)]:= true;
    FlipExclude^[ord(ROUTER_SOLICITATION_ADDRESS)]:= true;
    FlipExclude^[ord(STATIC_ROUTE)]:= true;
    FlipExclude^[ord(NETWORK_INFORMATION_SERVICE_DOMAIN)]:= true;
    FlipExclude^[ord(NETWORK_INFORMATION_SERVERS)]:= true;
    FlipExclude^[ord(NTP_SERVERS)]:= true;
    FlipExclude^[ord(VENDOR_SPECIFIC_INFORMATION)]:= true;
    FlipExclude^[ord(NETBIOS_OVER_TCP_NAME_SERVER)]:= true;
    FlipExclude^[ord(NETBIOS_OVER_TCP_DATAGRAM_DISTRIBUTION_SERVER)]:= true;
    FlipExclude^[ord(NETBIOS_OVER_TCP_SCOPE)]:= true;
    FlipExclude^[ord(X_WINDOW_SYSTEM_FONT_SERVER)]:= true;
    FlipExclude^[ord(X_WINDOW_SYSTEM_DISPLAY_MANAGER)]:= true;
    FlipExclude^[ord(NETWORK_INFORMATION_SERVICE_PLUS_DOMAIN)]:= true;
    FlipExclude^[ord(NETWORK_INFORMATION_SERVICE_PLUS_SERVERS)]:= true;
    FlipExclude^[ord(MOBILE_IP_HOME_AGENT)]:= true;
    FlipExclude^[ord(SMTP_SERVER)]:= true;
    FlipExclude^[ord(POP3_SERVER)]:= true;
    FlipExclude^[ord(NNTP_SERVER)]:= true;
    FlipExclude^[ord(DEFAULT_WWW_SERVER)]:= true;
    FlipExclude^[ord(DEFAULT_FINGER_SERVER)]:= true;
    FlipExclude^[ord(DEFAULT_IRC_SERVER)]:= true;
    FlipExclude^[ord(STREETTALK_SERVER)]:= true;
    FlipExclude^[ord(STDA_SERVER)]:= true;
    FlipExclude^[ord(REQUESTED_IP_ADDRESS)]:= true;
    FlipExclude^[ord(SERVER_IDENTIFIER)]:= true;
    FlipExclude^[ord(PARAMETER_REQUEST_LIST)]:= true;
    FlipExclude^[ord(VENDOR_CLASS_IDENTIFIER)]:= true;
    FlipExclude^[ord(CLIENT_IDENTIFIER)]:= true;
    FlipExclude^[ord(TFTP_SERVER_NAME)]:= true;
    FlipExclude^[ord(BOOTFILE_NAME)]:= true;
    FlipExclude^[ord(RELAY_AGENT_INFORMATION)]:= true;
    FlipExclude^[ord(NDS_SERVERS)]:= true;
    FlipExclude^[ord(NDS_TREE_NAME)]:= true;
    FlipExclude^[ord(NDS_CONTEXT)]:= true;
    FlipExclude^[ord(POSIX_TIMEZONE)]:= true;
    FlipExclude^[ord(TZ_TIMEZONE)]:= true;
    FlipExclude^[ord(DOMAIN_SEARCH)]:= true;
    FlipExclude^[ord(CLASSLESS_STATIC_ROUTE)]:= true;

    { Bind to port 68 }
    bind();

    io.syslog.logln('DHCP', 'Register end.');
end;

end.