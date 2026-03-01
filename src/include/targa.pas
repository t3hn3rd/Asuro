unit targa;

interface

uses
    lmemorymanager, texture;

type
    TTARGAColor = packed record
      b, g, r, a: uint8;
    end;
    PTARGAColor = ^TTARGAColor;

    TTARGAHeader = packed record
        Magic: uint8;
        ColorMapType: uint8;
        ImageType: uint8;
        ColorMapOrigin: uint16;
        ColorMapLength: uint16;
        ColorMapDepth: uint8;
        XOrigin: uint16;
        YOrigin: uint16;
        Width: uint16;
        Height: uint16;
        PixelDepth: uint8;
        ImageDescriptor: uint8;
        Data : PTARGAColor;
    end;
    PTARGAHeader = ^TTARGAHeader;

Function Parse(buffer : puint8; len : uint32) : PTexture;

implementation

Function Parse(buffer : puint8; len : uint32) : PTexture;
var
    header : PTARGAHeader;
    i, j : uint32;
    data : PTARGAColor;
    tex : PTexture;

begin
    if (len < sizeof(TTARGAHeader)) then exit;

    header := PTARGAHeader(buffer);
    if (header^.Magic <> $0) or (header^.ImageType <> 2) or (header^.PixelDepth <> 32) then exit;
    
    //Create a new texture
    tex:= texture.newTexture(header^.Width, header^.Height);
    tex^.Width:= header^.Width;
    tex^.Height:= header^.Height;
    
    //Copy the data
    data := PTARGAColor(header^.Data);
    for i := 0 to header^.Height - 1 do begin
        for j := 0 to header^.Width - 1 do begin
            tex^.Pixels[i * header^.Width + j].r := data^.r;
            tex^.Pixels[i * header^.Width + j].g := data^.g;
            tex^.Pixels[i * header^.Width + j].b := data^.b;
            tex^.Pixels[i * header^.Width + j].a := data^.a;
        end;
    end;

    Parse := tex;
end;

end.