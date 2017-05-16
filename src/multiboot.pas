unit multiboot;
 
interface
 
uses
    types;

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
 
implementation
 
end.
