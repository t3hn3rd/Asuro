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
	VMemoryManager - Virtual Memory Management.
	
	@author(Kieron Morris <kjm@kieronmorris.me>)
}

unit vmemorymanager;

interface

uses
    util,
    pmemorymanager,
    syslog,
    tracer;

type
    PPageDirEntry = ^TPageDirEntry;
    TPageDirEntry = bitpacked record
        Present, 
        Writable, 
        UserMode, 
        WriteThrough,
        NotCacheable, 
        Accessed, 
        Reserved, 
        PageSize,
        GlobalPage: Boolean;
        Available: UBit3;
        Address: UBit20;
    end;

    TPageDirectory = Array[0..1023] of TPageDirEntry;
    PPageDirectory = ^TPageDirectory;

var
    KERNEL_PAGE_DIRECTORY : PPageDirectory;
    PageDirectory : PPageDirectory;

procedure init;
function new_page(page_number : uint16) : boolean;
function page_mappable(page_number : uint16) : boolean;
function map_page(page_number : uint16; block : uint16) : boolean;
function map_page_ex(page_number : uint16; block : uint16; PD : PPageDirectory) : boolean;
function new_page_at_address(address : uint32) : boolean;
procedure free_page(page_number : uint16);
procedure free_page_at_address(address : uint32);
function new_page_directory : uint32;
function new_kernel_mapped_page_directory : uint32;
function vtop(address : uint32) : uint32;

implementation

uses
    lmemorymanager;

function new_page_directory : uint32;
begin
     push_trace('vmemorymanager.new_page_directory');
     new_page_directory:= uint32(kalloc(sizeof(TPageDirectory)));
     pop_trace;
end;

function new_kernel_mapped_page_directory : uint32;
var
    PD : PPageDirectory;
    i  : uint32;

begin
    push_trace('vmemorymanager.new_kernel_mapped_page_directory');
    PD:= PPageDirectory(new_page_directory);
    for i:=KERNEL_PAGE_NUMBER to 1023 do begin
        PD^[i]:= KERNEL_PAGE_DIRECTORY^[i];
    end;
    new_kernel_mapped_page_directory:= uint32(PD);
    pop_trace;
end;

function load_current_page_directory : PPageDirectory;
var
    Directory : uint32;

begin
    push_trace('vmemorymanager.load_current_page_directory');
    asm
        MOV EAX, CR3
        MOV Directory, EAX
    end;
    Directory:= Directory + KERNEL_VIRTUAL_BASE;
    load_current_page_directory:= PPageDirectory(Directory);
    pop_trace;
end;

procedure init;
var
    i : uint32;

begin
    push_trace('vmemorymanager.init');
    syslog.logln('VMM','INIT BEGIN.');
    PageDirectory:= load_current_page_directory;
    KERNEL_PAGE_DIRECTORY:= PageDirectory;
    map_page(KERNEL_PAGE_NUMBER + 0, 0);
    map_page(KERNEL_PAGE_NUMBER + 1, 1);
    map_page(KERNEL_PAGE_NUMBER + 2, 2);
    map_page(KERNEL_PAGE_NUMBER + 3, 3);    
    syslog.logln('VMM','INIT END.');
    pop_trace;
end;

function map_page_ex(page_number : uint16; block : uint16; PD : PPageDirectory) : boolean;
var
    addr  : ubit20;
    page  : uint16;

begin
    push_trace('vmemorymanager.map_page_ex');
    map_page_ex:= false;
    PD^[page_number].Present:= true;
    addr:= block;
    PD^[page_number].Address:= addr SHL 10;
    PD^[page_number].PageSize:= true;
    PD^[page_number].Writable:= true;
    
    // console.writestringln('VMM: New Page Added:');

    // console.writestring('VMM: - P:');
    // console.writehex(page_number);
    // console.writestring('-->B:');
    // console.writehexln(block);
        
    // console.writestring('VMM: - P:[');
    // console.writehex(page_number SHL 22);
    // console.writestring(' - ');
    // console.writehex(((page_number+1) SHL 22));
    // console.writestring(']-->B:[');
    // console.writehex(block SHL 22);
    // console.writestring(' - ');
    // console.writehex(((block+1) SHL 22));
    // console.writestringln(']');
    
    map_page_ex:= true;
    pop_trace;
end;

function map_page(page_number : uint16; block : uint16) : boolean;
var
    rldpd : uint32;

begin
    push_trace('vmemorymanager.map_page');
    { Delegate to map_page_ex — no redundant direct PDE writes }
    map_page := map_page_ex(page_number, block, PageDirectory);
    { Reload CR3 to flush TLB }
    rldpd := uint32(PageDirectory) - KERNEL_VIRTUAL_BASE;
    asm
        mov eax, rldpd
        mov CR3, eax
    end;
    pop_trace;
end;

function vtop(address : uint32) : uint32;
var
    idx : uint32;
    paddress : uint32;
    loadd    : uint32;

begin
    push_trace('vmemorymanager.vtop');
    idx:= address SHR 22;
    paddress:= uint32(KERNEL_PAGE_DIRECTORY^[idx].address) SHL 12;
    loadd:= address AND $3FFFFF;
    vtop:= paddress + loadd;
    pop_trace;
end;

function new_page(page_number : uint16) : boolean;
var
    block : uint16;

begin
    push_trace('vmemorymanager.new_page');
    new_page := false;
    if not PageDirectory^[page_number].Present then begin
        if not PageDirectory^[page_number].Reserved then begin
            block := pmemorymanager.new_block(uint32(PageDirectory));
            if block = 0 then begin
                { OOM — PMM has no free blocks. Return false gracefully. }
                syslog.logln('VMM', 'ERROR: new_page failed — PMM OOM.');
            end else begin
                new_page := map_page(page_number, block);
            end;
        end;
    end;
    pop_trace;
end;

function page_mappable(page_number : uint16) : boolean;
begin
    push_trace('vmemorymanager.page_mappable');
    page_mappable := false;
    if not PageDirectory^[page_number].Present then begin
        if not PageDirectory^[page_number].Reserved then begin
            page_mappable := true;
        end;
    end;
    pop_trace;
end;

function new_page_at_address(address : uint32) : boolean;
var
    page_number : uint16;

begin
    push_trace('vmemorymanager.new_page_at_address');
    page_number:= address SHR 22;
    new_page_at_address:= new_page(page_number);
    pop_trace;
end;

procedure free_page(page_number : uint16);
var
    block : uint16;
    vaddr : uint32;

begin
    push_trace('vmemorymanager.free_page');
    if PageDirectory^[page_number].Present then begin
        { Recover block index: Address stores (block SHL 10), so SHR 10 gives block }
        block := PageDirectory^[page_number].Address SHR 10;
        { Clear the PDE before invalidating }
        PageDirectory^[page_number].Present    := false;
        PageDirectory^[page_number].Writable   := false;
        PageDirectory^[page_number].PageSize   := false;
        PageDirectory^[page_number].Address    := 0;
        { Invalidate TLB for this virtual address (invlpg needs a virtual addr) }
        vaddr := uint32(page_number) SHL 22;
        asm
            mov eax, vaddr
            invlpg [eax]
        end;
        { Return physical block to PMM }
        pmemorymanager.free_block(block, uint32(PageDirectory));
    end else begin
        GPF;
    end;
    pop_trace;
end;

procedure free_page_at_address(address : uint32);
var
    page_number : uint16;

begin
    push_trace('vmemorymanager.free_page_at_address');
    page_number:= address SHR 22;
    free_page(page_number);
    pop_trace;
end;

end.