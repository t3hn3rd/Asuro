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
	Include->Multiboot - Multiboot Structures & Access.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}
unit multiboot;
 
interface

const
        KERNEL_STACKSIZE = $4000;
        MULTIBOOT_BOOTLOADER_MAGIC = $2BADB002;
 
type
        Pelf_section_header_table_t = ^elf_section_header_table_t;
        elf_section_header_table_t = packed record
          num: uint32;
          size: uint32;
          addr: uint32;
          shndx: uint32;
        end;
 
        Pmultiboot_info_t = ^multiboot_info_t;
        multiboot_info_t = packed record
          flags: uint32;
          mem_lower: uint32;
          mem_upper: uint32;
          boot_device: uint32;
          cmdline: uint32;
          mods_count: uint32;
          mods_addr: uint32;
          elf_sec: elf_section_header_table_t;
          mmap_length: uint32;
          mmap_addr: uint32;
          drives_legnth : uint32;
          drives_addr: uint32;
          config_table : uint32;
          boot_loader_name : uint32;
          apm_table: uint32;
          vbe_control_info : uint32;
          vbe_mode_info : uint32;
          vbe_mode : uint16;
          vbe_interface_seg : uint16;
          vbe_interface_off : uint16;
          vbe_interface_len : uint16;
          framebuffer_addr  : uint64;
          framebuffer_pitch : uint32;
          framebuffer_width : uint32;
          framebuffer_height: uint32;
          framebuffer_bpp : uint8;
        end;
 
        Pmodule_t = ^module_t;
        module_t = packed record
          mod_start: uint32;
          mod_end: uint32;
          name: uint32;
          reserved: uint32;
        end;
 
        Pmemory_map_t = ^memory_map_t;
        memory_map_t = packed record
          size: uint32;
		      base_addr : uint64;
		      length : uint64;          
		      mtype: uint32;
        end;
 
var
   multibootinfo  : Pmultiboot_info_t = nil;
   multibootmagic : uint32;

implementation
 
end.
