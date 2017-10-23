{ ************************************************
  * Asuro
  * Unit: Drivers/PCI
  * Description: PCI Driver
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit PCI;

interface

uses
    util,
    console;

type 

    TClass_Code = (
        LEGACY, MASS_STORAGE_CONTROLLER, NETWORK_CONTROLLER,
        DISPLAY_CONTROLLER, MULTIMEDIA_CONTROLLER, MEMORY_CONTROLLER,
        BRIDGE_DEVICE, SIMPLE_COMM_CONTROLLER, BASE_SYS_PERIPHERALS,
        INPUT_DEVICE, DOCKING_STATION, PROCESSOR, SERIAL_BUS_CONTROLLER,
        WIRELESS_CONTROLLER, INTELLIGENT_IO_CONTROLLER,
        SATELLITE_COMM_CONTROLLER, ENCRYPTION_CONTROLLER, 
        SIGNAL_PROCESSING_CONTROLLER, RESERVED
    ); // 0XFF = OTHER DEVICE

    // TSub_Class_Codes = record // first half sub device, second half prog id
    //     any_non_vga_compatible       : uint16 = $0000;
    //     any_vga_compatible           : uint16 = $0100;
    //     scsi_bus_controller          : uint16 = $0000;
    //     ide_controller               : uint16 = $01FF;
    //     floppy_controller            : uint16 = $0200;
    //     ipi_bus_controller           : uint16 = $0300;
    //     raid_controller              : uint16 = $0400;
    //     ata_single_dma               : uint16 = $0520;
    //     ata_chained_dma              : uint16 = $0530;
    //     serial_ata_ahci_vsi          : uint16 = $0600;
    //     serial_ata_ahci              : uint16 = $0601;
    //     serial_attached_scsi         : uint16 = $0700;
    //     other_mass_storage           : uint16 = $8000;
    //     ethernet_controller          : uint16 = $0000;
    //     token_ring_controller        : uint16 = $0100;
    //     fddi_controller              : uint16 = $0200;
    //     atm_controller               : uint16 = $0300;
    //     isdn_controller              : uint16 = $0400;
    //     worldfip_controller          : uint16 = $0500;
    //     picmg_multi_computing        : uint16 = $0600;
    //     other_network_controller     : uint16 = $8000;
    //     vga_compatible_controller    : uint16 = $0000;
    //     c8512_compatible_controller  : uint16 = $0001;
    //     xga_controller               : uint16 = $0100;
    //     c3d_controller               : uint16 = $0200;
    //     other_display_controller     : uint16 = $8000;
    //     video_device                 : uint16 = $0000;
    //     audio_device                 : uint16 = $0100;
    //     computer_telephony_device    : uint16 = $0200;
    //     other_multimedia_device      : uint16 = $8000;
    //     ram_controller               : uint16 = $0000;
    //     flash_controller             : uint16 = $0100;
    //     other_memory_controller      : uint16 = $8000;
    //     host_bridge                  : uint16 = $0100;
    //     isa_bridge                   : uint16 = $0200;
    //     eisa_bridge                  : uint16 = $0300;
    //     pci_2_pci_bridge             : uint16 = $0400;
    //     subtractive_pci_2_pci_bridge : uint16 = $0401;
    //     pcmcia_bridge                : uint16 = $0500;
    //     nubus_bridge                 : uint16 = $0600;
    //     cardbus_bridge               : uint16 = $0700;
    //     raceway_bridge               : uint16 = $0800;
    //     semi_pci_2_pci_bridge_p      : uint16 = $0940;
    //     semi_pci_2_pci_bridge_s      : uint16 = $0980;
    //     infiniband_2_pci_bridge      : uint16 = $0A00;
    //     other_bridge_device          : uint16 = $8000;
    // end;

    TPCI_Config = bitpacked record
        enable_bit      : boolean;
        reserved        : ubit7;
        bus_number      : uint8; 
        device_number   : ubit5;
        function_number : ubit3;
        register_offset : ubit6; 
        always_0        : ubit2;
    end;

    TPCI_BIST = bitpacked record
        capable         : boolean;
        start           : boolean;
        reserved        : ubit2;
        completion_code : ubit3;
    end;

    TPCI_Header_Type = bitpacked record
        always_0    : boolean;
        MF          : boolean;
        header_type : ubit7;
    end;

    TPCI_Memory_BAR = bitpacked record
        address : ubit28; //16-Byte aligned
        prefetchable : boolean;
        bar_type : ubit2;
        always_0 : boolean; 
    end;

    TPCI_IO_BAR = bitpacked record
        address : ubit30; //4-byte aligned
        reserved : boolean;
        always_0 : boolean;
    end;

    TPCI_Device = packed record
        device_id      : uint16;
        vendor_id      : uint16;
        status         : uint16;
        command        : uint16;
        class_code     : uint8; 
        subclass_class : uint8; 
        prog_if        : uint8;
        revision_id    : uint8;
        BIST           : uint8;
        header_type    : uint8;
        latency_timer  : uint8;
        cache_size     : uint8;
        address0       : uint32;
        address1       : uint32;
        address2       : uint32;
        address3       : uint32;
        address4       : uint32;
        address5       : uint32;
        CIS_pointer    : uint32;
        subsystem_id   : uint16;
        subsystem_vid  : uint16;
        exp_rom_addr   : uint32;
        reserved0      : uint16;
        reserved1      : uint8;
        capabilities   : uint8;
        reserved2      : uint32;
        max_latency    : uint8;
        min_grant      : uint8;
        interrupt_pin  : uint8;
        interrupt_line : uint8;
    end;       
    
    TPCI_Device_Bridge = bitpacked record
        device_id          : uint16;
        vendor_id          : uint16;
        status             : uint16;
        command            : uint16;
        class_code         : uint8; 
        subclass_class     : uint8; 
        prog_if            : uint8;
        revision_id        : uint8;
        BIST               : uint8;
        header_type        : uint8;
        latency_timer      : uint8;
        cache_size         : uint8;
        address0           : uint32;
        address1           : uint32;
        latency_timer2     : uint8;
        subordinate_bus    : uint8;
        secondery_bus      : uint8;
        primary_bus        : uint8;
        secondery_status   : uint16;
        io_limit           : uint8;
        io_base            : uint8;
        memory_limit       : uint16;
        memory_base        : uint16;
        pref_memory_limit  : uint16;
        pref_memory_base   : uint16;
        pref_base_upper    : uint32;
        pref_limit_upper   : uint32;
        io_limit_upper     : uint16;
        io_base_upper      : uint16;
        reserved           : uint16;
        reserved0          : uint8;
        capability_pointer : uint8;
        epx_rom_addr       : uint32;
        bridge_control     : uint16;
        interrupt_pin      : uint8;
        interrupt_line     : uint8;
    end;

    TCommand_Register = bitpacked record
        reserved            : ubit5;
        interupt_disable    : boolean;
        fast_b2b_enable     : boolean;
        seer_enable         : boolean;
        reserved0           : boolean;
        parity_err_response : boolean;
        VGA_palette_snoop   : boolean;
        mem_wai_enable      : boolean;
        special_cycles      : boolean;
        bus_master          : boolean;
        memory_space        : boolean;
        io_space            : boolean;
    end;

    TStatus_Register = bitpacked record
        detected_parity_error,
        signaled_sys_error,
        received_master_abort,
        received_target_abort,
        signaled_target_abort   : boolean;
        DEVSEL_timing           : ubit2;
        master_data_parity_error,
        fast_b2b_capable,
        reserved,
        c66Mhz_compatible,
        capabilities_list,
        interrupt_status        : boolean;
        reserved0               : ubit2;
    end;
    
var
    devices : array[0..8191] of TPCI_Device;
    busses : array[0..256] of TPCI_Device_Bridge; 

    device_count : uint16 = 0;
    bus_count : uint16 = 0;

procedure init();
procedure loadConfig(bus : uint8; slot : uint8; func : uint8; offset : uint8);
function check_device(bus : uint8; device : uint8; func : uint8) : boolean;

function get_vendor_ID(bus : uint8; slot : uint8; func : uint8; offset : uint8) : uint16;
function isDevice(bus : uint8; slot : uint8; func : uint8; offset : uint8) : ubit2;

function read8(bus : uint8; slot : uint8; func : uint8; offset : uint8; part : uint8) : uint8;
function read16(bus : uint8; slot : uint8; func : uint8; offset : uint8; part : uint8) : uint16;
function read32(bus : uint8; slot : uint8; func : uint8; offset : uint8) : uint32;

function read_device_config(bus : uint8; slot : uint8; func : uint8; offset : uint8) : TPCI_Device;
//function read_bridge_config() : TPCI_Device_Bridge;

implementation 

procedure init();
var
    i : uint16;
    ii : uint16;
    iii : uint8;
begin
    //enumerate pci bus 
    for ii:=0 to 256 do begin
        for i:=0 to 31 do begin
            check_device(ii, i, 0);
        end;
    end;

end;

procedure loadConfig(bus : uint8; slot : uint8; func : uint8; offset : uint8);
var
    packet : TPCI_Config;
    packetI : uint32;
begin
    packetI := ($1 shl 31);
    packetI := packetI or (bus shl 16);
    packetI := packetI or ((slot) shl 11);
    packetI := packetI or ((func) shl 8);
    packetI := packetI or ((offset) shl 2);

    outl($CF8, uint32(packetI)); 
end;

function check_device(bus : uint8; device : uint8; func : uint8) : boolean; 
var
    vendor_id : uint16;
    isDeviceb : uint8;
    i : uint8;
begin

    vendor_id := get_vendor_ID(bus, device, 0, 0);
    if vendor_id = $FFFF then exit;

    isDeviceb := isDevice(bus, device, 0, 8);
    if isDeviceb >= 0 then begin 
        devices[device_count] := read_device_config(bus, device, 0, 0);
        device_count := device_count + 1;
         if devices[device_count - 1].header_type and $80 <> 0 then begin
             for i:=0 to 8 do begin 
            // console.writechar(char(21));
                 vendor_id := get_vendor_ID(bus, device, i, 0);
                 //if vendor_id = $FFFF then exit(false);
                 devices[device_count] := read_device_config(bus, device, i, 0);
                 device_count := device_count + 1;
             end;
         end;
        check_device := true;
    end else begin
        //console.writestringln('PCI: Nested bus found');
        //busses[bus_count] := read_bridge_config();
        bus_count := bus_count + 1;
        check_device := false;
    end;
end;

function get_vendor_ID(bus : uint8; slot : uint8; func : uint8; offset : uint8) : uint16;
begin
    get_vendor_ID := read16(bus, slot, func, offset, 0);
end;

function isDevice(bus : uint8; slot : uint8; func : uint8; offset : uint8) : ubit2;
var 
    tmp : uint8;
begin
    loadConfig(bus, slot, func, 0);
    read8(bus, slot, func, 0, 2);
    loadConfig(bus, slot, func, 1);
    read8(bus, slot, func, 1, 2);
    loadConfig(bus, slot, func, 2);
    tmp := read8(bus, slot, func, 2, 3);
    if(tmp = $06) then begin
        isDevice := 0;
        exit;
    end;

    isDevice := 1;
end;

function read32(bus : uint8; slot : uint8; func : uint8; offset : uint8) : uint32;
begin
    read32 := inl($CFC);
end;

function read16(bus : uint8; slot : uint8; func : uint8; offset : uint8; part : uint8) : uint16;
var
    input : uint32;

begin
    input:= read32(bus, slot, func, offset);
    input:= input SHR (part * 16);
    input:= input and $0000FFFF;
    read16:= input;
end;

function read8(bus : uint8; slot : uint8; func : uint8; offset : uint8; part : uint8) : uint8;
var
    input : uint32;

begin
    input:= read32(bus, slot, func, offset);
    input:= input SHR (part * 8);
    input:= input and $000000FF;
    read8:= input;
end;


function read_device_config(bus : uint8; slot : uint8; func : uint8; offset : uint8) : TPCI_Device;
var
    tmp : TPCI_Device;
    i : uint16;
    off : uint32;

begin
    memset(uint32(@tmp), 0, sizeof(TPCI_Device));

    off:= offset;
    loadConfig(bus, slot, func, 0);
    tmp.device_id      := read16(bus, slot, func, off, 1);
    tmp.vendor_id      := read16(bus, slot, func, off, 0);

    loadConfig(bus, slot, func, 1);
    tmp.status         := read16(bus, slot, func, off, 1);
    tmp.command        := read16(bus, slot, func, off, 0);

    loadConfig(bus, slot, func, 2);
    tmp.class_code     := read8(bus, slot, func, off, 3);
    tmp.subclass_class := read8(bus, slot, func, off, 2);
    tmp.prog_if        := read8(bus, slot, func, off, 1);
    tmp.revision_id    := read8(bus, slot, func, off, 0);

    loadConfig(bus, slot, func, 3);
    tmp.BIST           := read8(bus, slot, func, off, 3);
    tmp.header_type    := read8(bus, slot, func, off, 2);
    tmp.latency_timer  := read8(bus, slot, func, off, 1);
    tmp.cache_size     := read8(bus, slot, func, off, 0);
    
    loadConfig(bus, slot, func, 4);
    tmp.address0       := read32(bus, slot, func, off);
    loadConfig(bus, slot, func, 5);
    tmp.address1       := read32(bus, slot, func, off);  
    loadConfig(bus, slot, func, 6);
    tmp.address2       := read32(bus, slot, func, off);  
    loadConfig(bus, slot, func, 7);
    tmp.address3       := read32(bus, slot, func, off);  
    loadConfig(bus, slot, func, 8);
    tmp.address4       := read32(bus, slot, func, off);  
    loadConfig(bus, slot, func, 9);
    tmp.address5       := read32(bus, slot, func, off);  

    loadConfig(bus, slot, func, 10);
    tmp.CIS_pointer    := read32(bus, slot, func, off);  

    loadConfig(bus, slot, func, 11);
    tmp.subsystem_id   := read16(bus, slot, func, off, 2);
    tmp.subsystem_vid  := read16(bus, slot, func, off, 0); 

    loadConfig(bus, slot, func, 12);
    tmp.exp_rom_addr   := read32(bus, slot, func, off);  

    loadConfig(bus, slot, func, 13);
    tmp.reserved0      := read16(bus, slot, func, off, 3);
    tmp.reserved1      := read8(bus, slot, func, off, 1);
    tmp.capabilities   := read8(bus, slot, func, off, 0);

    loadConfig(bus, slot, func, 14);
    tmp.reserved2      := read32(bus, slot, func, off);  

    loadConfig(bus, slot, func, 15);
    tmp.max_latency    := read8(bus, slot, func, off, 3);
    tmp.min_grant      := read8(bus, slot, func, off, 2); 
    tmp.interrupt_pin  := read8(bus, slot, func, off, 1); 
    tmp.interrupt_line := read8(bus, slot, func, off, 0);

    if(tmp.vendor_id <> $FFFF) then begin

            console.writestring('PCI: Found Device: ');
            console.writehex(slot);
            console.writestring('  ');
            console.writehex(tmp.device_id);        
            console.writestring('  ');        
            console.writehex(tmp.vendor_id);        
            console.writestring('  ');
            console.writehex(tmp.class_code);        
            console.writestring('  ');
            console.writehexln(tmp.subclass_class);
        

        if tmp.class_code = 1 then begin
            console.writestringln('-Device is MASS_STORAGE_CONTROLLER ');
        end; 
        if tmp.class_code = 2 then begin
            console.writestringln('-Device is NETWORK_CONTROLLER ');
        end; 
        if tmp.class_code = 3 then begin
            console.writestringln('-Device is DISPLAY_CONTROLLER ');
        end; 
    end;

        //psleep(300); 

    read_device_config := tmp;
end;

// function read_bridge_config() : TPCI_Device_Bridge;
// begin
//     read_bridge_config.placeholder = $FF;
// end;

end.

