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
        IDLength: uint8;
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
    end;
    PTARGAHeader = ^TTARGAHeader;

Function Parse(buffer : puint8; len : uint32) : PTexture;

implementation

Function Parse(buffer : puint8; len : uint32) : PTexture;
var
    header : PTARGAHeader;
    src    : PTARGAColor;
    tex    : PTexture;
    x, y   : uint32;
    dstRow : uint32;
    topDown: boolean;

begin
    Parse := nil;
    if len < sizeof(TTARGAHeader) then exit;

    header := PTARGAHeader(buffer);
    if (header^.ImageType <> 2) or (header^.PixelDepth <> 32) then exit;

    { Pixel data starts after the 18-byte header + any ID field. }
    src := PTARGAColor(buffer + sizeof(TTARGAHeader) + header^.IDLength);

    { Bit 5 of ImageDescriptor: 1 = top-to-bottom, 0 = bottom-to-top. }
    topDown := (header^.ImageDescriptor AND $20) <> 0;

    tex := texture.newTexture(header^.Width, header^.Height);

    for y := 0 to header^.Height - 1 do begin
        { Flip vertically when origin is bottom-left (the TGA default). }
        if topDown then
            dstRow := y
        else
            dstRow := (header^.Height - 1) - y;

        for x := 0 to header^.Width - 1 do begin
            tex^.Pixels[dstRow * header^.Width + x].b := src^.b;
            tex^.Pixels[dstRow * header^.Width + x].g := src^.g;
            tex^.Pixels[dstRow * header^.Width + x].r := src^.r;
            tex^.Pixels[dstRow * header^.Width + x].a := src^.a;
            Inc(src);
        end;
    end;

    Parse := tex;
end;

end.