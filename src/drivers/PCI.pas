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

    TPCI_Device_class record
        class_code  : uint8;
        sub_classes : array[256] of uint8;
        prog_if     : array[256] of uint8;
    end;

    TPCI_Config bitpacked record
        enable_bit      : uint8; //first bit enables, rest reserved
        bus_number      : uint8; 
        df_number       : uint8; // 5bits device number, 3bits function number
        register_offset : uint8; //last 2bits should be 00
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
    end;
    
var
    classes: array [255] of TPCI_Device_class;

procedure init();

implementation 

    procedure init();
    begin
    end;


end.

