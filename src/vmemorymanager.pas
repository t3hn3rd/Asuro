unit vmemorymanager;

interface

uses
    util,
    pmemorymanager,
    console;

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
    PageDirectory : PPageDirectory;

procedure init;
function new_page(page_number : uint16) : boolean;
function map_page(page_number : uint16; block : uint16) : boolean;
function new_page_at_address(address : uint32) : boolean;
procedure free_page(page_number : uint16);
procedure free_page_at_address(address : uint32);

implementation

function load_current_page_directory : PPageDirectory;
var
    Directory : uint32;

begin
    asm
        MOV EAX, CR3
        MOV Directory, EAX
    end;
    Directory:= Directory + KERNEL_VIRTUAL_BASE;
    load_current_page_directory:= PPageDirectory(Directory);
end;

procedure init;
var
    i : uint32;

begin
    console.writestringln('VMM: INIT BEGIN.');
    PageDirectory:= load_current_page_directory;
    map_page(KERNEL_PAGE_NUMBER + 1, 1);
    map_page(KERNEL_PAGE_NUMBER + 2, 2);
    map_page(KERNEL_PAGE_NUMBER + 3, 3);
    console.writestringln('VMM: INIT END.');
end;

function map_page(page_number : uint16; block : uint16) : boolean;
var
    addr  : ubit20;
    page  : uint16;
    rldpd : uint32;

begin
    map_page:= false;
    PageDirectory^[page_number].Present:= true;
    addr:= block;
    PageDirectory^[page_number].Address:= addr SHL 10;
    PageDirectory^[page_number].PageSize:= true;
    PageDirectory^[page_number].Writable:= true;
    rldpd:= uint32(PageDirectory) - KERNEL_VIRTUAL_BASE;
    asm
        mov eax, rldpd
        mov CR3, eax
    end;
    console.writestringln('VMM: New Page Added:');

    console.writestring('VMM: - P:');
    console.writehex(page_number);
    console.writestring('-->B:');
    console.writehexln(block);
        
    console.writestring('VMM: - P:[');
    console.writehex(page_number SHL 22);
    console.writestring(' - ');
    console.writehex(((page_number+1) SHL 22));
    console.writestring(']-->B:[');
    console.writehex(block SHL 22);
    console.writestring(' - ');
    console.writehex(((block+1) SHL 22));
    console.writestringln(']');
    map_page:= true;
end;

function new_page(page_number : uint16) : boolean;
var
    block : uint16;

begin
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
end;

function new_page_at_address(address : uint32) : boolean;
var
    page_number : uint16;

begin
    page_number:= address SHR 22;
    new_page_at_address:= new_page(page_number);
end;

procedure free_page(page_number : uint16);
var
    block : uint16;

begin
    if PageDirectory^[page_number].Present then begin
        block:= PageDirectory^[page_number].Address;
        asm
            invlpg [page_number]
        end;
        pmemorymanager.free_block(block, uint32(PageDirectory));
    end else begin
        GPF;
    end;
end;

procedure free_page_at_address(address : uint32);
var
    page_number : uint16;

begin
    page_number:= address SHR 22;
    free_page(page_number);
end;

end.