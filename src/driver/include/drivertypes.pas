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
	Driver->Include->DriverTypes - Structs & Data Shared Across Drivers.
	
	@author(Aaron Hance <ah@aaronhance.me>)
}
unit drivertypes;

interface

const
    PCI_CONFIG_ADDRESS_PORT = $0CF8;
    PCI_CONFIG_DATA_PORT    = $0CFC;

    PCI_COMMAND_IO_SPACE    = $0001;
    PCI_COMMAND_MEM_SPACE   = $0002;
    PCI_COMMAND_BUS_MASTER  = $0004;
    PCI_COMMAND_SPECIAL_CYC = $0008;
    PCI_COMMAND_MEM_WRITE   = $0010;
    PCI_COMMAND_VGA_PALETTE = $0020;
    PCI_COMMAND_PARITY      = $0040;
    PCI_COMMAND_WAIT        = $0080;
    PCI_COMMAND_SERR        = $0100;
    PCI_COMMAND_FAST_BACK   = $0200;
    PCI_COMMAND_INT_DISABLE = $0400;
    PCI_COMMAND_SERR_ENABLE = $8000;

    PCI_CAP_ID_MSI           = $05;

    // Bits in the MSI Control register (16-bit):
    MSI_CONTROL_ENABLE       = 1 shl 0;  // Bit 0
    MSI_CONTROL_64BIT        = 1 shl 7;  // Bit 7
    MSI_CONTROL_PVMASK       = 1 shl 8;  // Bit 8 (optional: per-vector masking)
type

    PPCI_Device = ^TPCI_Device;
    TPCI_Device = bitpacked record
        bus                : uint8;
        slot               : uint8;
        func               : uint8;
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

    TDeviceArray = array[0..31] of TPCI_Device;


implementation


end.
