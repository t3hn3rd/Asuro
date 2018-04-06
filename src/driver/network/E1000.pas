unit E1000;

interface

uses
    console,
    strings,
    vmemorymanager,
    lmemorymanager,
    drivermanagement;

const
    INTEL_VEND  = $8086;
    E1000_DEV   = $100E;
    I217_DEV    = $153A;
    LM82577_DEV = $10EA;

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

procedure init();
procedure fire();
function getMACAddress : uint8;
function sendPacket(p_data : void; p_len : uint16) : sint32;

implementation

var
    bar_type : uint8;
    io_base  : uint16;
    mem_base : uint64;
    eeprom_exists : boolean;
    mac : array[0..5] of uint8;
    rx_descs : array[0..65535] of TE1000_rx_desc;
    tx_descs : array[0..65535] of TE1000_tx_desc;
    rx_curr  : uint16;
    tx_curr  : uint16;

procedure writeCommand(p_address : uint16; p_value : uint32);
begin
    
end;

function readCommand(p_address : uint16) : uint32;
begin
    
end;

function detectEEPROM() : boolean;
begin

end;

function EEPROMRead( address : uint8 ) : uint32;
begin

end;

function readMACAddress() : boolean;
begin

end;

procedure startLink();
begin

end;

procedure rxinit();
begin

end;

procedure txinit();
begin

end;

procedure enableInturrupt();
begin

end;

procedure handleReceive();
begin

end;

function load(ptr : void) : boolean;
begin
    load:= true;
end;

procedure init();
var
    dev : TDeviceIdentifier;

begin
    dev.Bus:= biPCI;
    dev.id0:= INTEL_VEND;
    dev.id1:= idANY;
    dev.id2:= idANY;
    dev.id3:= idANY;
    dev.id4:= E1000_DEV;
    dev.ex:= nil;
    drivermanagement.register_driver('E1000 Ethernet Driver', @dev, @load);
    dev.id4:= I217_DEV;
    drivermanagement.register_driver('I217 Ethernet Driver', @dev, @load);
    dev.id4:= LM82577_DEV;
    drivermanagement.register_driver('82577LM Ethernet Driver', @dev, @load);
end;

procedure fire();
begin

end;

function getMACAddress : uint8;
begin

end; 

function sendPacket(p_data : void; p_len : uint16) : sint32;
begin

end;

end.