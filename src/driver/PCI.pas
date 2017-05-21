{ ************************************************
  * Asuro
  * Unit: Drivers/PCI
  * Description: PCI Driver
  ************************************************
  * Author: Aaron Hance
  * Contributors: 
  ************************************************ }

unit PCI

interface

uses
    system,
    util;

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

    TSub_Class_Codes record // first half sub device, second half prog id
        any_non_vga_compatible       : uint16 = $0000;
        any_vga_compatible           : uint16 = $0100;
        scsi_bus_controller          : uint16 = $0000;
        ide_controller               : uint16 = $01FF;
        floppy_controller            : uint16 = $0200;
        ipi_bus_controller           : uint16 = $0300;
        raid_controller              : uint16 = $0400;
        ata_single_dma               : uint16 = $0520;
        ata_chained_dma              : uint16 = $0530;
        serial_ata_ahci_vsi          : uint16 = $0600;
        serial_ata_ahci              : uint16 = $0601;
        serial_attached_scsi         : uint16 = $0700;
        other_mass_storage           : uint16 = $8000;
        ethernet_controller          : uint16 = $0000;
        token_ring_controller        : uint16 = $0100;
        fddi_controller              : uint16 = $0200;
        atm_controller               : uint16 = $0300;
        isdn_controller              : uint16 = $0400;
        worldfip_controller          : uint16 = $0500;
        picmg_multi_computing        : uint16 = $0600;
        other_network_controller     : uint16 = $8000;
        vga_compatible_controller    : uint16 = $0000;
        c8512_compatible_controller  : uint16 = $0001;
        xga_controller               : uint16 = $0100;
        c3d_controller               : uint16 = $0200;
        other_display_controller     : uint16 = $8000;
        video_device                 : uint16 = $0000;
        audio_device                 : uint16 = $0100;
        computer_telephony_device    : uint16 = $0200;
        other_multimedia_device      : uint16 = $8000;
        ram_controller               : uint16 = $0000;
        flash_controller             : uint16 = $0100;
        other_memory_controller      : uint16 = $8000;
        host_bridge                  : uint16 = $0100;
        isa_bridge                   : uint16 = $0200;
        eisa_bridge                  : uint16 = $0300;
        pci_2_pci_bridge             : uint16 = $0400;
        subtractive_pci_2_pci_bridge : uint16 = $0401;
        pcmcia_bridge                : uint16 = $0500;
        nubus_bridge                 : uint16 = $0600;
        cardbus_bridge               : uint16 = $0700;
        raceway_bridge               : uint16 = $0800;
        semi_pci_2_pci_bridge_p      : uint16 = $0940;
        semi_pci_2_pci_bridge_s      : uint16 = $0980;
        infiniband_2_pci_bridge      : uint16 = $0A00;
        other_bridge_device          : uint16 = $8000;
    end;

    TPCI_Config bitpacked record
        enable_bit      : boolean;
        reserved        : ubit7;
        bus_number      : uint8; 
        device_number   : ubit5;
        function_number : ubit3;
        register_offset : ubit6; 
        always_0        : ubit2;
    end;

    TPCI_BIST bitpacked record
        capable         : boolean;
        start           : boolean;
        reserved        : ubit2;
        completion_code : ubit3;
    end;

    TPCI_Header_Type bitpacked record
        MF          : boolean;
        header_type : ubit7;
    end;

    TPCI_Memory_BAR bitpacked record
        address : ubit28; //16-Byte aligned
        prefetchable : boolean;
        bar_type : ubit2;
        always_0 : boolean = 0; 
    end;

    TPCI_IO_BAR bitpacked record
        address : ubit30; //4-byte aligned
        reserved : boolean;
        always_0 : boolean = 0;
    end;

    TPCI_Device bitpacked record
        device_id      : uint16;
        vendor_id      : uint16;
        status         : uint16;
        command        : uint16;
        class_code     : uint8; 
        subclass_class : uint8; 
        prog_if        : uint8;
        revision_id    : uint8;
        BIST           : TPCI_BIST;
        header_type    : TPCI_Header_Type;
        latency_timer  : uint8;
        cache_size     : uint8;
        address0       : TPCI_Memory_BAR;
        address1       : TPCI_Memory_BAR;
        address2       : TPCI_Memory_BAR;
        address3       : TPCI_Memory_BAR;
        address4       : TPCI_Memory_BAR;
        address5       : TPCI_Memory_BAR;
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
    
    TPCI_Device_Bridge bitpacked record

    end;

    TCommand_Register bitpacked record
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

    TStatus_Register bitpacked record
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
        interrupt_status        : boolean
        reserved0               : ubit2;
    end;
    
var
    devices : array[0..(256 * 32)] of TPCI_Device;
    busses : array[0..256] of TPCI_Device_Bridge; 

    device_count, bus_count : uint16 = 0;

procedure init();
procedure loadConfig(bus : uint8; slot : uint8; func : uint8; offset : uint8);
function check_device(bus : uint8; device : uint8) : 
function get_vendor_ID() : uint16;
function get_function() : boolean;
function read_device_config();
function read_bridge_config();

implementation 

function init();
var
    i : uint16;
begin

    //enumerate all pci devices
    for i:=0 to 31 do begin
        check_and_get(0, i);
    end;

end;

procedure loadConfig(bus : uint8; slot : uint8; func : uint8; offset : uint8);
var
    packet : TPCI_Config;
begin
    packet.bus_number := bus;
    packet.device_number := slot;
    packet.function_number := func;
    packet.register_offset := offset;

    util.outl(0xCF8, packet);


end;

function check_device(bus : uint8; device : uint8) : boolean;
var
    i : uint8;
    vendor_id : uint16;
    isDevice : boolean;
begin

    loadConfig(bus, slot, 0, 0);

    vendor_id := get_vendor_ID();
    if vendor_id = $0xFFFF then exit;

    isDevice := get_function();
    if isDevice then begin 
        devices[device_count] := TPCI_Device(read_device_config);
        device_count := device_count + 1;
    end;
    else begin
        busses[bus_count] := TPCI_Device_Bridge(read_bridge_config);
    end;
end;

function get_vendor_ID(bus : uint8; device : uint8) : uint16;
begin
end;

end.

