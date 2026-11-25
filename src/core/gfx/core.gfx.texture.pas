unit core.gfx.texture;

interface

uses
    memory.heap, core.gfx.color;

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
    newTexture := nil;
    texture:= PTexture(kalloc(sizeof(TTexture)));
    if texture = nil then exit;
    texture^.Pixels:= PRGB32(kalloc(width * height * sizeof(TRGB32)));
    if texture^.Pixels = nil then begin
        kfree(void(texture));
        exit;
    end;
    texture^.Width:= width;
    texture^.Height:= height;
    texture^.Size:= width * height;
    newTexture:= texture;
end;

end.
