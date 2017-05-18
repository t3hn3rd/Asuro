unit memorymanager;

interface

uses
    util,
    console;

const
    ALLOC_SPACE = 8; //64-Bit Allocations 
    MAX_ENTRIES = $FFFF;

procedure init;
function kalloc(size : uint32) : void;
procedure kfree(area : void);

type
    TBlock_Entry = packed record
        Present : Boolean;
        Length  : uint8;
    end;

implementation

var
    Memory_Start   : uint32;
    Memory_Manager : packed array[1..MAX_ENTRIES] of TBlock_Entry;

procedure init;
var
    i : uint32;

begin
    For i:=0 to MAX_ENTRIES-1 do begin
        Memory_Manager[i].Present:= False;
    end;
    Memory_Start:= uint32(@util.endptr);
end;

function kalloc(size : uint32) : void;
var
    blocks : uint8;
    rem    : uint32;
    i,j    : uint32;
    miss   : boolean;

begin
    blocks:= size div 8;
    rem:= size - (blocks * 8);
    if rem > 0 then blocks:= blocks + 1;
    kalloc:= nil;
    for i:=0 to MAX_ENTRIES-1 do begin
        miss:= false;
        for j:=0 to blocks-1 do begin
            if Memory_Manager[i+j].Present then begin
                miss:= true;
                break;
            end;
        end;
        if not miss then begin
            kalloc:= void(Memory_Start+(i * 8));
            for j:=0 to blocks-1 do begin
                Memory_Manager[i+j].Present:= true;
                Memory_Manager[i+j].Length:= 0;
                if j = 0 then Memory_Manager[i+j].Length:= blocks;
            end;
            console.writestring('Allocated ');
            console.writeint(blocks);
            console.writestring(' Block(s). [Block: ');
            console.writeint(i);
            console.writestringln(']');
            break;
        end;
    end;
end;

procedure kfree(area : void);
var
    Block   : uint32;
    bLength : uint8;
    i       : uint32;

begin
    if uint32(area) < Memory_Start then begin
         asm 
             INT 13 
         end;
    end;
    Block:= (uint32(Area) - Memory_Start) div 8;
    if Memory_Manager[Block].Present then begin
        If Memory_Manager[Block].Length > 0 then begin
            bLength:= Memory_Manager[Block].Length;
            for i:=0 to bLength-1 do begin
                Memory_Manager[Block+i].Present:= False;
            end;
            console.writestring('Freed ');
            console.writeint(bLength);
            console.writestring(' Block(s). [Block: ');
            console.writeint(Block);
            console.writestringln(']');
        end else begin
            asm 
               INT 13 
            end;
        end;
    end;
end;

end.