{ ************************************************
  * Asuro
  * Unit: VMemoryManager
  * Description: Manages Pages of Virtual Memory
  ************************************************
  * Author: K Morris
  * Contributors: 
  ************************************************ }

unit vmemorymanager;

interface

uses
    util,
    pmemorymanager,
    console,
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
    console.outputln('VMM','INIT BEGIN.');
    PageDirectory:= load_current_page_directory;
    KERNEL_PAGE_DIRECTORY:= PageDirectory;
    map_page(KERNEL_PAGE_NUMBER + 0, 0);
    map_page(KERNEL_PAGE_NUMBER + 1, 1);
    map_page(KERNEL_PAGE_NUMBER + 2, 2);
    map_page(KERNEL_PAGE_NUMBER + 3, 3);    
    console.outputln('VMM','INIT END.');
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
    addr  : ubit20;
    page  : uint16;
    rldpd : uint32;

begin
    push_trace('vmemorymanager.map_page');
    map_page:= false; 
    PageDirectory^[page_number].Present:= true;
    addr:= block;
    PageDirectory^[page_number].Address:= addr SHL 10;
    PageDirectory^[page_number].PageSize:= true;
    PageDirectory^[page_number].Writable:= true;
    map_page:= map_page_ex(page_number, block, PageDirectory);
    rldpd:= uint32(PageDirectory) - KERNEL_VIRTUAL_BASE;
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
    loadd:= address AND $FFFFFF;
    vtop:= paddress + loadd;
    pop_trace;
end;

function new_page(page_number : uint16) : boolean;
var
    block : uint16;

begin
    push_trace('vmemorymanager.new_page');
    new_page:= false;
    if PageDirectory^[page_number].Present then exit;
    if PageDirectory^[page_number].Reserved then exit;
    block:= pmemorymanager.new_block(uint32(PageDirectory));
    if block < 2 then begin
        GPF;
        exit;
    end else begin
        new_page:= map_page(page_number, block);
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

begin
    push_trace('vmemorymanager.free_page');
    if PageDirectory^[page_number].Present then begin
        block:= PageDirectory^[page_number].Address;
        asm
            invlpg [page_number]
        end;
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