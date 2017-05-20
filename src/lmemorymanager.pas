unit lmemorymanager;

interface

uses
    util,
    vmemorymanager,
    console;

const
    ALLOC_SPACE = 8; //64-Bit Allocations 
    MAX_ENTRIES = $60000;
    DATA_OFFSET = $100000;

type
    THeapEntry = bitpacked record
        Present : Boolean;
        Root    : Boolean;
        Last    : Boolean;
        Resv1   : Boolean;
        Resv2   : Boolean;
        Resv3   : Boolean;
        Resv4   : Boolean;
        Resv5   : Boolean;
    end;
    THeapPage = packed record
        Next_Page : uint32;
        Prev_Page : uint32;
        Entries   : Array[0..MAX_ENTRIES-1] of THeapEntry;
    end;
    PHeapPage = ^THeapPage;

var
    Root_Page : PHeapPage;

procedure init;
function kalloc(size : uint32) : void;
procedure kfree(area : void);

implementation

function new_lmm_page() : uint32;
var
    i : integer;

begin
    i:= KERNEL_PAGE_NUMBER + 4;
    while not vmemorymanager.new_page(i) do begin
        i:= i + 1;
    end;
    new_lmm_page:= i SHL 22;
end;

function new_heap_page(CurrentPage : PHeapPage) : PHeapPage;
var
    i : integer;

begin
    new_heap_page:= PHeapPage(new_lmm_page);
    if CurrentPage <> nil then CurrentPage^.Next_Page:= uint32(new_heap_page);
    new_heap_page^.Next_Page:= 0;
    new_heap_page^.Prev_Page:= uint32(CurrentPage);
    For i:=0 to MAX_ENTRIES-1 do begin
        with new_heap_page^.Entries[i] do begin
            Present:= False;
            Root:= False;
            Last:= False;
        end;
    end;    
end;

procedure init;
var
    i : uint32;

begin
    Root_Page:= PHeapPage(new_lmm_page);
    Root_Page^.Next_Page:= 0;
    Root_Page^.Prev_Page:= 0;
    For i:=0 to MAX_ENTRIES-1 do begin
        Root_Page^.Entries[i].Present:= False;
        Root_Page^.Entries[i].Root:= False;
        Root_Page^.Entries[i].Last:= False;
    end; 
end;

function kalloc(size : uint32) : void;
var
   Heap_Entries : uint32;
   i, j         : uint32;
   hp           : PHeapPage;
   miss         : boolean;

begin
    Heap_Entries:= size div 8;
    If sint32(size-(Heap_Entries*8)) > 0 then Heap_Entries:= Heap_Entries + 1;
    hp:= Root_Page;
    kalloc:= nil;
    while kalloc = nil do begin
        for i:=0 to MAX_ENTRIES-1 do begin
            miss:= false;
            for j:=0 to Heap_Entries-1 do begin
                if hp^.Entries[i+j].Present then begin
                    miss:= true;
                    break;
                end;
            end;
            if not miss then begin
                kalloc:= void( uint32( hp ) + DATA_OFFSET + (i * 8) );
                for j:=0 to Heap_Entries-1 do begin
                    hp^.Entries[i+j].Present:= True;
                    if j = (Heap_Entries-1) then begin
                        hp^.Entries[i+j].Last:= True;
                    end;
                    if j = 0 then begin
                        hp^.Entries[i+j].Root:= True;
                    end;
                end;
                break;
            end;
        end;
        if kalloc = nil then begin
            if PHeapPage(hp^.Next_Page) = nil then begin
                new_heap_page(hp);
            end;
            hp:= PHeapPage(hp^.Next_Page);
        end;
    end;
end;

procedure kfree(area : void);
var
    hp : PHeapPage;
    entry : uint32;

begin
    hp:= PHeapPage((uint32(area) SHR 22) SHL 22);
    entry:= (uint32(area) - DATA_OFFSET - uint32(hp)) div 8;
    if hp^.Entries[entry].Present then begin
        while not hp^.Entries[entry].Root do begin
            entry:= entry - 1;
        end;
        While not hp^.Entries[entry].Last do begin
            hp^.Entries[entry].Present:= False;
            hp^.Entries[entry].Root:= False;
            hp^.Entries[entry].Last:= False;
            entry:= entry + 1;
        end;
        hp^.Entries[entry].Present:= False;
        hp^.Entries[entry].Root:= False;
        hp^.Entries[entry].Last:= False;
    end else begin
        GPF;
    end;
end;

end.