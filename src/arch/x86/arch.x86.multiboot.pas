//  Copyright 2021 Kieron Morris & Aaron Hance
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
unit arch.x86.multiboot;
 
interface

uses boot.multiboot;

const
        KERNEL_STACKSIZE = $4000;
        MULTIBOOT_BOOTLOADER_MAGIC = $2BADB002;
 
type
    elf_section_header_table_t = boot.multiboot.elf_section_header_table_t;
    Pelf_section_header_table_t = boot.multiboot.Pelf_section_header_table_t;
    multiboot_info_t = boot.multiboot.multiboot_info_t;
    Pmultiboot_info_t = boot.multiboot.Pmultiboot_info_t;
    module_t = boot.multiboot.module_t;
    Pmodule_t = boot.multiboot.Pmodule_t;
    memory_map_t = boot.multiboot.memory_map_t;
    Pmemory_map_t = boot.multiboot.Pmemory_map_t;

var
   multibootinfo  : Pmultiboot_info_t = nil;
   multibootmagic : uint32;

implementation
 
end.
