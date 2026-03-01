unit texture;

interface

uses
    lmemorymanager, color;

type
    TTexture = packed record
        Width  : uint32; 
        Height : uint32; 
        Size   : uint32;
        Pixels : PRGB32;
    end;
    PTexture = ^TTexture;

Function newTexture(width, height: uint32): PTexture;

implementation

Function newTexture(width, height: uint32): PTexture;
var
    texture: PTexture;

begin
    texture:= PTexture(kalloc(sizeof(TTexture)));
    texture^.Pixels:= PRGB32(kalloc(width * height * sizeof(TRGB32)));
    texture^.Width:= width;
    texture^.Height:= height;
    texture^.Size:= width * height;
    newTexture:= texture;
end;

end.