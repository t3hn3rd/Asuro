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
    console.writestringln('VMM: INIT END.');
end;

function new_page(page_number : uint16) : boolean;
var
    block : uint16;
    page  : uint16;

begin
    new_page:= false;
    if PageDirectory^[block].Present then exit;
    if PageDirectory^[block].Reserved then exit;
    block:= pmemorymanager.newblock(uint32(PageDirectory));
    if block < 2 then begin
        GPF;
        exit;
    end else begin
        PageDirectory^[block].Present:= true;
        PageDirectory^[block].Address:= block;
        PageDirectory^[block].PageSize:= true;
        new_page:= true;
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
begin
    if PageDirectory^[page_number].Present then begin
        asm
            invlpg [page_number]
        end;    
    end else begin
        GPF;
    end;
end;

function free_page_at_address(address : uint32);
var
    page_number : uint16;

begin
    page_number:= address SHR 22;
    free_page(page_number);
end;

end.