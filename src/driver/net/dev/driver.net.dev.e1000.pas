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
	Driver->NetDev->driver.net.dev.e1000 - Intel driver.net.dev.e1000/I217/82577LM Network Card Driver.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit driver.net.dev.e1000;

interface

uses
    debug.tracer,
    io.syslog,
    io.stdio,
    core.strings,
    arch.x86.memory.virtual,
    memory.heap,
    driver.mgr,
    driver.types,
    core.util, arch.x86.util,
    arch.x86.idt,
    driver.bus.pci,
    driver.net,
    driver.net.types,
    driver.net.util,
    arch.x86.isr.mgr;

const
    INTEL_VEND      = $8086;
    E1000_DEV       = $100E;
    I217_DEV        = $153A;
    LM82577_DEV     = $10EA;

    REG_CTRL        = $0000;
    REG_STATUS      = $0008;
    REG_EEPROM      = $0014;
    REG_CTRL_EXT    = $0018;
    REG_IMASK       = $00D0;
    REG_RCTRL       = $0100;
    REG_RXDESCLO    = $2800;
    REG_RXDESCHI    = $2804;
    REG_RXDESCLEN   = $2808;
    REG_RXDESCHEAD  = $2810;
    REG_RXDESCTAIL  = $2818;
    
    REG_TCTRL       = $0400;
    REG_TXDESCLO    = $3800;
    REG_TXDESCHI    = $3804;
    REG_TXDESCLEN   = $3808;
    REG_TXDESCHEAD  = $3810;
    REG_TXDESCTAIL  = $3818;
    
    REG_RDTR         = $2820;      // RX Delay Timer Register
    REG_RXDCTL       = $3828;      // RX Descriptor Control
    REG_RADV         = $282C;      // RX Int. Absolute Delay Timer
    REG_RSRPD        = $2C00;      // RX Small Packet Detect Interrupt
       
    REG_TIPG         = $0410;      // Transmit Inter Packet Gap
    ECTRL_SLU        = $40;        //set link up
    
    RCTL_EN                 =       (1 SHL 1);    // Receiver Enable
    RCTL_SBP                =       (1 SHL 2);    // Store Bad Packets
    RCTL_UPE                =       (1 SHL 3);    // Unicast Promiscuous Enabled
    RCTL_MPE                =       (1 SHL 4);    // Multicast Promiscuous Enabled
    RCTL_LPE                =       (1 SHL 5);    // Long Packet Reception Enable
    RCTL_LBM_NONE           =       (0 SHL 6);    // No Loopback
    RCTL_LBM_PHY            =       (3 SHL 6);    // PHY or external SerDesc loopback
    RTCL_RDMTS_HALF         =       (0 SHL 8);    // Free Buffer Threshold is 1/2 of RDLEN
    RTCL_RDMTS_QUARTER      =       (1 SHL 8);    // Free Buffer Threshold is 1/4 of RDLEN
    RTCL_RDMTS_EIGHTH       =       (2 SHL 8);    // Free Buffer Threshold is 1/8 of RDLEN
    RCTL_MO_36              =       (0 SHL 12);   // Multicast Offset - bits 47:36
    RCTL_MO_35              =       (1 SHL 12);   // Multicast Offset - bits 46:35
    RCTL_MO_34              =       (2 SHL 12);   // Multicast Offset - bits 45:34
    RCTL_MO_32              =       (3 SHL 12);   // Multicast Offset - bits 43:32
    RCTL_BAM                =       (1 SHL 15);   // Broadcast Accept Mode
    RCTL_VFE                =       (1 SHL 18);   // VLAN Filter Enable
    RCTL_CFIEN              =       (1 SHL 19);   // Canonical Form Indicator Enable
    RCTL_CFI                =       (1 SHL 20);   // Canonical Form Indicator Bit Value
    RCTL_DPF                =       (1 SHL 22);   // Discard Pause Frames
    RCTL_PMCF               =       (1 SHL 23);   // Pass MAC Control Frames
    RCTL_SECRC              =       (1 SHL 26);   // Strip Ethernet CRC
    
    // Buffer Sizes
    RCTL_BSIZE_256          =       (3 SHL 16);
    RCTL_BSIZE_512          =       (2 SHL 16);
    RCTL_BSIZE_1024         =       (1 SHL 16);
    RCTL_BSIZE_2048         =       (0 SHL 16);
    RCTL_BSIZE_4096         =       ((3 SHL 16) OR (1 SHL 25));
    RCTL_BSIZE_8192         =       ((2 SHL 16) OR (1 SHL 25));
    RCTL_BSIZE_16384        =       ((1 SHL 16) OR (1 SHL 25));
    
    // Transmit Command
    CMD_EOP                 =       (1 SHL 0);    // End of Packet
    CMD_IFCS                =       (1 SHL 1);    // Insert FCS
    CMD_IC                  =       (1 SHL 2);    // Insert Checksum
    CMD_RS                  =       (1 SHL 3);    // Report Status
    CMD_RPS                 =       (1 SHL 4);    // Report Packet Sent
    CMD_VLE                 =       (1 SHL 6);    // VLAN Packet Enable
    CMD_IDE                 =       (1 SHL 7);    // Interrupt Delay Enable
       
    // TCTL Register
    TCTL_EN                 =       (1 SHL 1);    // Transmit Enable
    TCTL_PSP                =       (1 SHL 3);    // Pad Short Packets
    TCTL_CT_SHIFT           =       4;            // Collision Threshold
    TCTL_COLD_SHIFT         =       12;           // Collision Distance
    TCTL_SWXOFF             =       (1 SHL 22);   // Software XOFF Transmission
    TCTL_RTLC               =       (1 SHL 24);   // Re-transmit on Late Collision
    
    TSTA_DD                 =       (1 SHL 0);    // Descriptor Done
    TSTA_EC                 =       (1 SHL 1);    // Excess Collisions
    TSTA_LC                 =       (1 SHL 2);    // Late Collision
    LSTA_TU                 =       (1 SHL 3);    // Transmit Underrun

    E1000_NUM_RX_DESC       =       32;
    E1000_NUM_TX_DESC       =       8;

type
    PE1000_rx_desc = ^TE1000_rx_desc;
    TE1000_rx_desc = bitpacked record
        address  : uint64;
        length   : uint16;
        checksum : uint16;
        status   : uint8;
        errors   : uint8;
        special  : uint16;
    end;

    PE1000_tx_desc = ^TE1000_tx_desc;
    TE1000_tx_desc = bitpacked record
        address : uint64;
        length  : uint16;
        cso     : uint8;
        cmd     : uint8;
        status  : uint8;
        css     : uint8;
        special : uint16;
    end;

    TCardType = (ctUnknown, ctE1000, ctI217, ct82577LM);

procedure init();
function getMACAddress : puint8;
function sendPacket(p_data : void; p_len : uint16) : sint32;
function readStatus : uint32;

implementation

var
    bus, slot, func : uint8;
    loaded : boolean;
    card_type : TCardType;
    bar_type : uint8;
    io_base  : uint16;
    mem_base : uint64;
    eeprom_exists : boolean;
    mac : array[0..5] of uint8;
    rx_descs : array[0..E1000_NUM_RX_DESC-1] of PE1000_rx_desc;
    tx_descs : array[0..E1000_NUM_TX_DESC-1] of PE1000_tx_desc;
    rx_buffs : array[0..E1000_NUM_RX_DESC-1] of puint8;
    rx_curr  : uint16;
    tx_curr  : uint16;
    mem_aloc : boolean = false;

procedure writeCommand(p_address : uint16; p_value : uint32);
var
    mem : puint32;

begin
    if (bar_type = 0) then begin
        mem:= puint32(mem_base + p_address);
        mem^:= p_value;
    end else begin
        outl(io_base + 0, p_address);
        outl(io_base + 4, p_address)
    end;
end;

function readCommand(p_address : uint16) : uint32;
var
    mem : puint32;

begin
    if (bar_type = 0) then begin
        mem:= puint32(mem_base + p_address);
        readCommand:= mem^;
    end else begin
        outl(io_base, p_address);
        readCommand:= inl(io_base + 4);
    end;   
end;

function readStatus : uint32;
begin
    readStatus:= readCommand(REG_STATUS);
end;

function detectEEPROM() : boolean;
var
    val, i : uint32;

begin
    val:= 0;
    writeCommand(REG_EEPROM, $1);
    for i:=0 to 1000 do begin
        if eeprom_exists then break;
        val:= readCommand(REG_EEPROM);
        if (val and $10) > 0 then eeprom_exists:= true else eeprom_exists:= false;
    end;
    detectEEPROM:= eeprom_exists;
end;

function EEPROMRead( address : uint8 ) : uint32;
var
    data : uint16;
    tmp  : uint32;

begin
    tmp:= 0;
    if (eeprom_exists) then begin
        writeCommand( REG_EEPROM, 1 OR (uint32(address) SHL 8) );
        while (tmp AND (1 SHL 4)) = 0 do begin
            tmp:= readCommand(REG_EEPROM); //Might be wrong?
        end;
    end else begin
        writeCommand( REG_EEPROM, 1 OR (uint32(address) SHL 2) );
        while (tmp AND (1 SHL 1)) = 0 do begin
            tmp:= readCommand(REG_EEPROM); //Might be wrong?
        end;
    end;
    data:= uint16( (tmp SHR 16) AND ($FFFF) );
    EEPROMRead:= data;
end;

function readMACAddress() : boolean;
var
    temp : uint32;
    mem_base_mac_8  : puint8;
    mem_base_mac_32 : puint32;
    res : boolean;
    i   : uint32;

begin
    push_trace('driver.net.dev.e1000.readMACAddress');
    res:= true;
    if (eeprom_exists) then begin
        temp:= EEPROMRead(0);
        mac[0]:= temp AND $FF;
        mac[1]:= temp SHR 8;
        temp:= EEPROMRead(1);
        mac[2]:= temp AND $FF;
        mac[3]:= temp SHR 8;
        temp:= EEPROMRead(2);
        mac[4]:= temp AND $FF;
        mac[5]:= temp SHR 8;
    end else begin
        mem_base_mac_8:= puint8(mem_base + $5400);
        mem_base_mac_32:= puint32(mem_base + $5400);
        if (mem_base_mac_32[0] <> 0) then begin
            for i:=0 to 6 do begin
                mac[i]:= mem_base_mac_8[i];
            end; 
        end else begin
            res:= false;
        end;
    end;
    readMACAddress:= res;
end;

procedure startLink();
var
    val : uint32;

begin
    val:= readCommand(REG_CTRL);
    writeCommand(REG_CTRL, val OR ECTRL_SLU);
end;

procedure rxinit();
var
    ptr    : puint8;
    outptr : puint8;
    descs  : PE1000_rx_desc;
    i      : uint32;

begin
    ptr:= puint8(kalloc(sizeof(TE1000_rx_desc) * E1000_NUM_RX_DESC + 16));
    descs:= PE1000_rx_desc(ptr);
    for i:=0 to E1000_NUM_RX_DESC do begin
        rx_descs[i]:= @descs[i];//PE1000_rx_desc(uint32(descs) + i*16);
        rx_buffs[i]:= puint8(kalloc(8192 + 16));
        rx_descs[i]^.address:= uint64(vtop(uint32(rx_buffs[i])));
        rx_descs[i]^.status:= 0;
    end;

    outptr:= puint8(vtop(uint32(ptr)));//puint8(uint32(ptr) - KERNEL_VIRTUAL_BASE);

    io.syslog.log('driver.net.dev.e1000 Driver', 'RX VMem: ');
    io.syslog.writehexln(uint32(ptr));
    io.syslog.log('driver.net.dev.e1000 Driver', 'RX Mem: ');
    io.syslog.writehexln(uint32(outptr));

    writeCommand(REG_TXDESCLO, uint32(uint64(outptr) SHR 32));
    writeCommand(REG_TXDESCHI, uint32(uint64(outptr) AND $FFFFFFFF));

    writeCommand(REG_RXDESCLO, uint32(outptr));
    writeCommand(REG_RXDESCHI, 0);

    writeCommand(REG_RXDESCLEN, E1000_NUM_RX_DESC * sizeof(TE1000_rx_desc));

    writeCommand(REG_RXDESCHEAD, 0);
    writeCommand(REG_RXDESCTAIL, E1000_NUM_RX_DESC-1);
    rx_curr:= 0;

    writeCommand(REG_RCTRL, RCTL_EN OR RCTL_SBP OR RCTL_UPE OR RCTL_MPE OR RCTL_LBM_NONE OR RTCL_RDMTS_HALF OR RCTL_BAM OR RCTL_SECRC OR RCTL_BSIZE_2048);
end;

procedure txinit();
var
    ptr    : puint8;
    outptr : puint8;
    descs  : PE1000_tx_desc;
    i      : uint32;

begin
    ptr:= puint8(kalloc(sizeof(TE1000_tx_desc) * (E1000_NUM_TX_DESC + 16))); 
    descs:= PE1000_tx_desc(ptr);
    for i:=0 to E1000_NUM_TX_DESC do begin
        tx_descs[i]:= @descs[i];//PE1000_tx_desc(uint32(descs + i*16));
        tx_descs[i]^.address:= 0;
        tx_descs[i]^.cmd:= 0;
        tx_descs[i]^.status:= TSTA_DD;
    end;
    
    outptr:= puint8(vtop(uint32(ptr))); //puint8(uint32(ptr) - KERNEL_VIRTUAL_BASE);

    io.syslog.writehexln(uint32(ptr));
    io.syslog.writehexln(uint32(outptr));

    writeCommand(REG_TXDESCHI, 0);
    writeCommand(REG_TXDESCLO, uint32(outptr));

    writeCommand(REG_TXDESCLEN, E1000_NUM_TX_DESC * sizeof(TE1000_tx_desc));

    writeCommand( REG_TXDESCHEAD, 0 );
    writeCommand( REG_TXDESCTAIL, 0 );
    tx_curr:= 0;
    writeCommand(REG_TCTRL, TCTL_EN OR TCTL_PSP OR (15 SHL TCTL_CT_SHIFT) OR (64 SHL TCTL_COLD_SHIFT) OR TCTL_RTLC);

    //The following is needed for I217 & 82577LM
    if (card_type = ct82577LM) OR (card_type = ctI217) then begin
        writeCommand(REG_TCTRL, $3003F0FA);
        writeCommand(REG_TIPG, $0060200A);
    end;
end;

procedure enableInturrupt();
begin
    writeCommand(REG_IMASK, $1F6DC);
    writeCommand(REG_IMASK, $FF AND NOT(4));
    readCommand($C0);
end;

procedure handleReceive();
var
    old_cur : uint16;
    got_packet : boolean;
    buf        : puint8;
    len        : uint16;
    i          : uint16;
    
begin
    while (rx_descs[rx_curr]^.status AND $1) > 0 do begin
        got_packet:= true;
        buf:= rx_buffs[rx_curr];
        len:= rx_descs[rx_curr]^.length;

        //Inject Packet into Network Stack
        driver.net.recv(void(buf), len);

        rx_descs[rx_curr]^.status:= 0;
        old_cur:= rx_curr;
        rx_curr:= (rx_curr + 1) mod E1000_NUM_RX_DESC;
        writeCommand(REG_RXDESCTAIL, old_cur);
    end;
end;

procedure writeCardType();
begin
    io.syslog.log('driver.net.dev.e1000 Driver', 'Card Type: ');
    case card_type of
        ctUnknown:io.syslog.writestringln('Unknown');
        ct82577LM:io.syslog.writestringln('82577LM');
        ctE1000:io.syslog.writestringln('Generic driver.net.dev.e1000');
        ctI217:io.syslog.writestringln('I217');
    end;
end;

procedure fire();
var
    status : uint32;
    data     : uint32;

begin
    status:= readCommand($C0);
    if (status AND $04) > 0 then begin
        startLink();
    end;
    if (Status AND $10) > 0 then begin
        //Good Threshold
    end;
    if (Status AND $80) > 0 then begin
        handleReceive();
    end; 
    //Clear the INT on the Device First by using write-1
    writeCommand(REG_IMASK, 1);
end;

procedure console_command_mac(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    writeMACAddress(@mac[0], stdout_buf);
end;

procedure console_command_sendtest(params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
var
    TestPacket : Array[0..41] of uint8 = (  $ff, $ff, $ff, $ff, $ff, $ff, { eth dest (broadcast) }
                                            $52, $54, $00, $12, $34, $56, { eth source }
                                            $08, $06,                     { eth type }
                                            $00, $01,                     { ARP htype }
                                            $08, $00,                     { ARP ptype }
                                            $06,                          { ARP hlen }
                                            $04,                          { ARP plen }
                                            $00, $01,                     { ARP opcode: ARP_REQUEST }
                                            $52, $54, $00, $12, $34, $56, { ARP hsrc }
                                            169, 254, 13, 37,             { ARP psrc }
                                            $00, $00, $00, $00, $00, $00, { ARP hdst }
                                            192, 168, 0, 128              { ARP pdst }
                                         );

begin
    TestPacket[6]:= mac[0];
    TestPacket[7]:= mac[1];
    TestPacket[8]:= mac[2];
    TestPacket[9]:= mac[3];
    TestPacket[10]:= mac[4];
    TestPacket[11]:= mac[5];

    TestPacket[22]:= mac[0];
    TestPacket[23]:= mac[1];
    TestPacket[24]:= mac[2];
    TestPacket[25]:= mac[3];
    TestPacket[26]:= mac[4];
    TestPacket[27]:= mac[5];
    sendPacket(void(@TestPacket[0]), 42);
    io.stdio.bufWriteStrLn(stdout_buf, 'driver.net.dev.e1000 ARP Testpacket Sent.');
    pop_trace;
end;

procedure terminal_command_e1000status(Params : PParamList; stdin_buf, stdout_buf, stderr_buf : POutBuf);
begin
    io.stdio.bufWriteStr(stdout_buf, 'Card: ');
    case card_type of
        ctUnknown:io.stdio.bufWriteStrLn(stdout_buf, 'Unknown');
        ctE1000:io.stdio.bufWriteStrLn(stdout_buf, 'driver.net.dev.e1000 Generic');
        ct82577LM:io.stdio.bufWriteStrLn(stdout_buf, '82577LM');
        ctI217:io.stdio.bufWriteStrLn(stdout_buf, 'I217');
        else io.stdio.bufWriteStrLn(stdout_buf, 'UNIDENTIFIED!!!');
    end;

    io.stdio.bufWriteStr(stdout_buf, 'Status: ');
    io.stdio.bufWriteHexLn(stdout_buf, readStatus);

    io.stdio.bufWriteStr(stdout_buf, 'CTRL: ');
    io.stdio.bufWriteHexLn(stdout_buf, readCommand(REG_CTRL));

    io.stdio.bufWriteStr(stdout_buf, 'TX Curr: ');
    io.stdio.bufWriteInt(stdout_buf, tx_curr);
    io.stdio.bufWriteStr(stdout_buf, '/');
    io.stdio.bufWriteIntLn(stdout_buf, E1000_NUM_TX_DESC);

    io.stdio.bufWriteStr(stdout_buf, 'RX Curr: ');
    io.stdio.bufWriteInt(stdout_buf, rx_curr);
    io.stdio.bufWriteStr(stdout_buf, '/');
    io.stdio.bufWriteIntLn(stdout_buf, E1000_NUM_RX_DESC);

    io.stdio.bufWriteStr(stdout_buf, 'RX MEM: ');
    io.stdio.bufWriteHexLn(stdout_buf, uint32(@rx_descs[0]));

    io.stdio.bufWriteStr(stdout_buf, 'TX MEM: ');
    io.stdio.bufWriteHexLn(stdout_buf, uint32(@tx_descs[0]));
end;

function load(ptr : void) : boolean;
var
    PCI_Info : PPCI_Device;
    i        : uint32;
    data     : uint32;
    iline    : uint8;

begin
    push_trace('driver.net.dev.e1000.load');

    io.syslog.logln('driver.net.dev.e1000 Driver', 'Load Start.');

    writeCardType();

    PCI_Info:= PPCI_Device(ptr);
    bar_type:= PCI_Info^.address0 AND $00000001;
    io_base:=  PCI_Info^.address0 AND $FFFFFFF0;
    mem_base:= PCI_INFO^.address0 AND $FFFFFFFC;

    { !!!!! Dirty way to alloc the pages, needs fixing !!!!! }
    kpalloc(io_base);
    kpalloc(mem_base);
    
    bus:= PCI_Info^.bus;
    slot:= PCI_Info^.slot;
    func:= PCI_Info^.func;
    setBusMaster(PCI_Info^.bus, PCI_Info^.slot, PCI_Info^.func, true);
    eeprom_exists:= false;
    
    detectEEPROM();
    if eeprom_exists then io.syslog.logln('driver.net.dev.e1000 Driver', 'EEPROM Exists: YES.') else io.syslog.logln('driver.net.dev.e1000 Driver', 'EEPROM Exists: NO.');
    if not readMACAddress() then begin
        io.syslog.logln('driver.net.dev.e1000 Driver', 'MAC Read Failed.');
        load:= false;
    end else begin
        io.syslog.log('driver.net.dev.e1000 Driver', 'MAC Address: ');
        io.syslog.writehexpair(mac[0]); io.syslog.writestring(':');
        io.syslog.writehexpair(mac[1]); io.syslog.writestring(':');
        io.syslog.writehexpair(mac[2]); io.syslog.writestring(':');
        io.syslog.writehexpair(mac[3]); io.syslog.writestring(':');
        io.syslog.writehexpair(mac[4]); io.syslog.writestring(':');
        io.syslog.writehexpair(mac[5]); io.syslog.writestringln('');

        startLink();

        for i:=0 to $80 do begin
            writeCommand($5200 + i*4, 0);
        end; 

        driver.net.registerNetworkCard(@sendPacket, getMACAddress());

        arch.x86.isr.mgr.registerISR(32 + PCI_Info^.interrupt_line, @fire);
        enableInturrupt();

        rxinit();
        txinit();

        load:= true;   

        if load then registercommand('E1000', @terminal_command_e1000status, 'driver.net.dev.e1000 Information.');
        if load then registercommand('MAC', @console_command_mac, 'Print MAC Address.');
    end;

    io.syslog.logln('driver.net.dev.e1000 Driver', 'Load Finish.');

    pop_trace;
end;

function loadE1000(ptr : void) : boolean;
begin
    loadE1000:= false;
    if not Loaded then begin
        card_type:= ctE1000;
        loadE1000:= load(ptr);
    end;
end;

function load82577LM(ptr : void) : boolean;
begin
    load82577LM:= false;
    if not Loaded then begin
        card_type:= ct82577LM;
        load82577LM:= load(ptr);
    end;
end;

function loadI217(ptr : void) : boolean;
begin
    loadI217:= false;
    if not Loaded then begin
        card_type:= ctI217;
        loadI217:= load(ptr);
    end;
end;

procedure init();
var
    dev : TDeviceIdentifier;

begin
    push_trace('driver.net.dev.e1000.init');
    card_type:= ctUnknown;
    dev.Bus:= biPCI;
    dev.id0:= INTEL_VEND;
    dev.id1:= idANY;
    dev.id2:= idANY;
    dev.id3:= idANY;
    dev.id4:= E1000_DEV;
    dev.ex:= nil;
    driver.mgr.register_driver('driver.net.dev.e1000 Ethernet Driver', @dev, @loadE1000);
    dev.id4:= I217_DEV;
    driver.mgr.register_driver('I217 Ethernet Driver', @dev, @loadI217);
    dev.id4:= LM82577_DEV;
    driver.mgr.register_driver('82577LM Ethernet Driver', @dev, @load82577LM);
    pop_trace;
end;

function getMACAddress : puint8;
begin
    getMACAddress:= puint8(@mac[0]);
end; 

function sendPacket(p_data : void; p_len : uint16) : sint32;
var
    old_cur : uint8;
    timeout : uint32;

begin
    tx_descs[tx_curr]^.address:= uint32(vtop(uint32(p_data)));
    tx_descs[tx_curr]^.length:= p_len;
    tx_descs[tx_curr]^.cmd:= CMD_EOP OR CMD_IFCS OR CMD_RS OR CMD_RPS;
    tx_descs[tx_curr]^.status:= 0;
    old_cur:= tx_curr;
    tx_curr:= (tx_curr + 1) MOD E1000_NUM_TX_DESC;
    writeCommand(REG_TXDESCTAIL, tx_curr);
    timeout:= 1000000;
    while ((tx_descs[old_cur]^.status AND $FF) = 0) and (timeout > 0) do begin
        dec(timeout);
    end;
    sendPacket:= 1;
    if timeout > 0 then sendPacket:= 0;
end;

end.
