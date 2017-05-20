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
    PageDirectory^[KERNEL_VIRTUAL_BASE + 1].Present:= True;
    PageDirectory^[KERNEL_VIRTUAL_BASE + 1].PageSize:= True;
    PageDirectory^[KERNEL_VIRTUAL_BASE + 1].Writable:= True;
    PageDirectory^[KERNEL_VIRTUAL_BASE + 1].Address:= (1 SHL 22);

    PageDirectory^[KERNEL_VIRTUAL_BASE + 2].Present:= True;
    PageDirectory^[KERNEL_VIRTUAL_BASE + 2].PageSize:= True;
    PageDirectory^[KERNEL_VIRTUAL_BASE + 2].Writable:= True;
    PageDirectory^[KERNEL_VIRTUAL_BASE + 2].Address:= (2 SHL 22);
    console.writestringln('VMM: INIT END.');
end;

function new_page(page_number : uint16) : boolean;
var
    block : uint16;
    page  : uint16;
    rldpd : uint32;

begin
    new_page:= false;
    if PageDirectory^[page_number].Present then exit;
    //if PageDirectory^[page_number].Reserved then exit;
    block:= pmemorymanager.new_block(uint32(PageDirectory));
    if block < 2 then begin
        GPF;
        exit;
    end else begin
        PageDirectory^[page_number].Present:= true;
        PageDirectory^[page_number].Address:= block;
        PageDirectory^[page_number].PageSize:= true;
        PageDirectory^[page_number].Writable:= true;
        rldpd:= uint32(PageDirectory) - KERNEL_VIRTUAL_BASE;
        asm
             mov eax, rldpd
             mov CR3, eax
        end;
        new_page:= true;
        console.writestringln('New Page Added:');

        console.writestring('- P:');
        console.writeword(page_number);
        console.writestring('-->B:');
        console.writewordln(block);
        
        console.writestring('- P:[');
        console.writeword(page_number SHL 22);
        console.writestring(' - ');
        console.writeword(((page_number+1) SHL 22)-1);
        console.writestring(']-->B:[');
        console.writeword(block SHL 22);
        console.writestring(' - ');
        console.writeword(((block+1) SHL 22)-1);
        console.writestringln(']');
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