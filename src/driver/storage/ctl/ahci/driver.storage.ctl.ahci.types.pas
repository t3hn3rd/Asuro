//  Copyright 2021 Aaron Hance
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
	Drivers->Storage->driver.storage.ctl.ahci->driver.storage.ctl.ahci.types - driver.storage.ctl.ahci Driver Types.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit driver.storage.ctl.ahci.types;
interface
uses
    io.syslog,
    driver.mgr,
    driver.types,
    driver.storage.ctl.ide.types,
    core.ds.lists,
    memory.heap,
    driver.bus.pci,
    core.util, arch.x86.util,
    arch.x86.memory.virtual;

const
    AHCI_CONTROLLER_MODE = $80000000;

    CMD_LIST_ALIGN = 1024;
    CMD_TBL_ALIGN = 128;

    NUM_CMD_ENTRIES = 32;

    //device type signatures
    SATA_SIG_ATA = $00000101;
    SATA_SIG_ATAPI = $EB140101;
    SATA_SIG_SEMB = $C33C0101;
    SATA_SIG_PM = $96690101;



type

    { 
        driver.storage.ctl.ahci Host Bus Adapter (HBA) Memory-Mapped Register Interface
        This structure is used to access the driver.storage.ctl.ahci HBA's memory-mapped registers. 
        The driver.storage.ctl.ahci HBA's memory-mapped registers are used to configure the HBA and
        to issue commands to the SATA devices connected to the HBA.

        The driver.storage.ctl.ahci HBA's memory-mapped registers are accessed by reading and writing
        to the HBA's memory-mapped I/O space. The HBA's memory-mapped I/O space is
        typically mapped to a region of physical memory by the system's BIOS or
        UEFI firmware. The HBA's memory-mapped I/O space is typically mapped to a
        region of physical memory that is accessible to the system's CPU(s) and
        other devices.
    }
    THBA_Port = bitpacked record 
        cmdl_basel: uint32;     // Command List Base Address Lower 32-bits
        cmdl_baseu: uint32;     // Command List Base Address Upper 32-bits
        fis_basel: uint32;      // FIS Base Address Lower 32-bits
        fis_baseu: uint32;      // FIS Base Address Upper 32-bits
        int_status: uint32;     // Interrupt Status
        int_enable: uint32;     // Interrupt Enable
        cmd: uint32;            // Command and Status
        rsv0: uint32;           // Reserved
        tfd: uint32;            // Task File Data
        signature: uint32;      // Signature
        sata_status: uint32;    // SATA Status (SCR0:SStatus)
        sata_ctrl: uint32;      // SATA Control (SCR2:SControl)
        sata_error: uint32;     // SATA Error (SCR1:SError)
        sata_active: uint32;    // SATA Active
        cmd_issue: uint32;      // Command Issue
        sata_noti: uint32;      // SATA Notification
        fis_switch_ctrl: uint32;// FIS-based Switch Control
        rsv1: array[0..10] of uint32;
        vendor: array[0..3] of uint32;
    end;

    PHBA_Port = ^THBA_Port;

    { 
        driver.storage.ctl.ahci Host Bus Adapter (HBA) Memory-Mapped Register Interface
        This structure is used to access the driver.storage.ctl.ahci's memory-mapped registers.
        The driver.storage.ctl.ahci's memory-mapped registers are used to configure the HBA and to
        issue commands to the SATA devices connected to the HBA.
    }
    THBA_Memory = bitpacked record 
        capabilites: uint32;    // Host Capabilities
        global_ctrl: uint32;    // Global Host Control
        int_status: uint32;     // Interrupt Status
        ports_implimented: uint32;// Ports Implemented 
        version: uint32;        // Version
        ccc_control: uint32;    // Command Completion Coalescing Control
        ccc_ports: uint32;      // Command Completion Coalescing Ports
        em_location: uint32;    // Enclosure Management Location
        em_control: uint32;     // Enclosure Management Control
        capabilites2: uint32;   // Host Capabilities Extended
        bohc: uint32;           // BIOS/OS Handoff Control and Status

        //0x2c to 0x9f reserved
        rsv0: array[0..115] of uint8;

        //vendor specific
        vendor: array[0..95] of uint8;

        //port registers
        ports: array[0..31] of THBA_Port;
      
    end;

    PHBA_Memory = ^THBA_Memory;

    { 
        driver.storage.ctl.ahci Host Bus Adapter (HBA) FIS (Frame Information Structure) Interface
        This structure is used to access the driver.storage.ctl.ahci HBA's FIS (Frame Information Structure)
        memory-mapped registers. RX
    }
    THBA_FIS = bitpacked record 
        dsfis: array[0..$1F] of uint32; // DMA Setup FIS
        rsv0: array[0..$1F] of uint32;
        psfis: array[0..$1F] of uint32; // PIO Setup FIS
        rsv1: array[0..$1F] of uint32;
        rfis: array[0..$1F] of uint32;  // D2H Register FIS
        rsv2: array[0..$1F] of uint32;
        sdbfis: array[0..$F] of uint32; // Set Device Bits FIS
        ufis: array[0..$1F] of uint32;  // Unknown FIS
        rsv3: array[0..$67] of uint32;
    end;

    PHBA_FIS = ^THBA_FIS;

    //enum fis type
    TFISType = (
        FIS_TYPE_REG_H2D = $27, // Register FIS - Host to Device
        FIS_TYPE_REG_D2H = $34, // Register FIS - Device to Host
        FIS_TYPE_DMA_ACT = $39, // DMA Activate FIS - Device to Host
        FIS_TYPE_DMA_SETUP = $41, // DMA Setup FIS - Bidirectional
        FIS_TYPE_DATA = $46, // Data FIS - Bidirectional
        FIS_TYPE_BIST = $58, // BIST Activate FIS - Bidirectional
        FIS_TYPE_PIO_SETUP = $5F, // PIO Setup FIS - Device to Host
        FIS_TYPE_DEV_BITS = $A1 // Set Device Bits FIS - Device to Host
    );

    { 
        driver.storage.ctl.ahci Host Bus Adapter (HBA) FIS (Frame Information Structure) Interface
        This structure is used to access the driver.storage.ctl.ahci HBA's FIS (Frame Information Structure)
    }
    THBA_FIS_REG_H2D = bitpacked record 
        fis_type: uint8;         // FIS Type
        // pmport: uint8;           // Port Multiplier Port is pmport:4 and rsv0:3 and i:1
        pmport: ubit4;           // Port Multiplier Port
        rsv: ubit3;             // Reserved
        c: ubit1;                // command or control
        command: uint8;          // Command
        featurel: uint8;         // Feature Lower 8-bits
        lba0: uint8;             // LBA0
        lba1: uint8;             // LBA1
        lba2: uint8;             // LBA2
        device: uint8;           // Device
        lba3: uint8;             // LBA3
        lba4: uint8;             // LBA4
        lba5: uint8;             // LBA5
        featureh: uint8;         // Feature Upper 8-bits
        countl: uint8;           // Count Lower 8-bits
        counth: uint8;           // Count Upper 8-bits
        icc: uint8;              // Isochronous Command Completion
        control: uint8;          // Control
        rsv0: array[0..3] of uint8;
    end;

    PHBA_FIS_REG_H2D = ^THBA_FIS_REG_H2D;



    { 
        driver.storage.ctl.ahci Host Bus Adapter (HBA) Command Header Interface
    }
    THBA_CMD_HEADER = bitpacked record 
        cmd_fis_length: UBit5;   // Command FIS Length
        atapi: UBit1;            // ATAPI
        wrt: UBit1;            // Write
        prefetchable: UBit1;     // Prefetchable

        reset: UBit1;            // Reset
        bist: UBit1;             // BIST
        clear_busy: UBit1;       // Clear Busy
        reserved0: UBit1;        // Reserved
        port_multiplier: UBit4;  // Port Multiplier Port

        prdtl: uint16;           // Physical Region Descriptor Table Length
        prdbc: uint32;           // Physical Region Descriptor Byte Count
        cmd_table_base: uint32;  // Command Table Base Address
        cmd_table_baseu: uint32; // Command Table Base Address Upper 32-bits
        rsv0: array[0..3] of uint32;
    end;

    PHBA_CMD_HEADER = ^THBA_CMD_HEADER;

    { 
        driver.storage.ctl.ahci Host Bus Adapter (HBA) Command Table Interface
    }
    THBA_PRD = bitpacked record 
        dba: uint32;             // Data Base Address
        dbau: uint32;            // Data Base Address Upper 32-bits
        rsv0: uint32;            // Reserved
        dbc: ubit22;             // Data Byte Count
        reserved: ubit9;         // Reserved
        int: ubit1;        // Interrupt
        // dbc: uint32;             // Data Byte Count, bit 1 is Interrupt, then 22 bits of Byte Count, then 9 bits of Reserved
    end;

    TPRDT = array[0..31] of THBA_PRD;
    PPRDT = ^TPRDT;

    { 
        driver.storage.ctl.ahci Host Bus Adapter (HBA) Command Table Interface
    }
    THBA_CMD_TABLE = bitpacked record 
        cmd_fis: array[0..63] of uint8; // Command FIS
        acmd: array[0..15] of uint8;    // ATAPI Command
        rsv0: array[0..47] of uint8;
        prdt: array[0..31] of THBA_PRD;                    // Physical Region Descriptor Table
    end;

    PHBA_CMD_TABLE = ^THBA_CMD_TABLE;

    TCMD_LIST = array[0..255] of THBA_CMD_HEADER;
    PCMD_LIST = ^TCMD_LIST;

    //////////////////////////////////////////
    //////////// Asuro driver.storage.ctl.ahci core.types ////////////
    //////////////////////////////////////////

    {
        Device type enum
    }
    TDeviceType = (
        SATA = 1,
        ATAPI = 2,
        SEMB,
        PM
    );

    { Callback signature fired from IRQ context when an async I/O command completes.
      Must be very short — set a flag or post to a queue.
      Never call kalloc/kfree/VFS from within this callback. }
    TIOCompletion = procedure(success : boolean; userdata : puint32);

    { Per-slot pending operation — one entry per HBA command slot }
    TPendingOp = record
        inUse      : boolean;
        completion : TIOCompletion;
        userdata   : puint32;
    end;

    {
        driver.storage.ctl.ahci device reference.
        Declared as a plain record (not bitpacked) so that procedure-pointer fields
        in TPendingOp are safe to store and call.
    }
    TAHCI_Device = record
        port         : PHBA_Port;
        device_type  : TDeviceType;
        ata_info     : TIdentResponse;
        supportsNCQ  : boolean;
        queueDepth   : uint32;       { safe active depth for this device }
        slotCount    : uint32;       { controller slot count from CAP.NCS + 1 }
        command_list : PHBA_CMD_HEADER;
        fis          : PHBA_FIS;
        command_table: PHBA_CMD_TABLE;
        { One pending-operation slot per HBA command slot (driver.storage.ctl.ahci supports up to 32) }
        pending      : array[0..31] of TPendingOp;
    end;

    PAHCI_Device = ^TAHCI_Device;

    {
        controller reference
        Declared as a plain record (not bitpacked) because it embeds TAHCI_Device
        which contains procedure-pointer fields.
    }
    TAHCI_Controller = record
        pci_device : PPCI_Device;
        mio: PHBA_Memory;
        ata_info : TIdentResponse;
        devices : array[0..31] of TAHCI_Device;
    end;

    PAHCI_Controller = ^TAHCI_Controller;

     
 function get_device_type(sig : uint32) : TDeviceType;
//  function get_device_type_string(deive_type : TDeviceType) : string;

implementation

function get_device_type(sig : uint32) : TDeviceType;
begin
    case sig of
        SATA_SIG_ATA: begin
            get_device_type := SATA;
        end;
        SATA_SIG_ATAPI: begin
            get_device_type := ATAPI;
        end;
        SATA_SIG_SEMB: begin
            get_device_type := SEMB;
        end;
        SATA_SIG_PM: begin
            get_device_type := PM;
        end;
    end;
end;

// function get_device_type_string(deive_type : TDeviceType) : string;
// begin
//     case deive_type of
//         SATA: begin
//             get_device_type_string := 'SATA';
//         end;
//         ATAPI: begin
//             get_device_type_string := 'ATAPI';
//         end;
//         SEMB: begin
//             get_device_type_string := 'SEMB';
//         end;
//         PM: begin
//             get_device_type_string := 'PM';
//         end;
//     end;
// end;

end.
