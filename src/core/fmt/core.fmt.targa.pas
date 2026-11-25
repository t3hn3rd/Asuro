unit core.fmt.targa;

interface

uses
    memory.heap, core.gfx.texture, core.gfx.color;

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

{ The reader copies exactly length bytes and returns the number copied. }
type
    TTargaRead = function(context : Pointer; offset : uint32;
                          buffer : PUInt8; length : uint32) : uint32;

function Parse(buffer : PUInt8; len : uint32) : PTexture;
{ Decode with one source row in memory and crop to the output aspect ratio. }
function ParseScaled(reader : TTargaRead; context : Pointer; len, width, height : uint32) : PTexture;

implementation

{$POINTERMATH ON}

function Decode(reader : TTargaRead; context : Pointer; len, destWidth, destHeight : uint32) : PTexture;
var
    header : TTargaHeader;
    width, height, pixelBytes, rowBytes, dataOffset : uint32;
    cropWidth, cropHeight, cropLeft, cropTop : uint32;
    x, y, sourceX, sourceY, previousY : uint32;
    row, pixel : PUInt8;
    texture : PTexture;
    dest : PRGB32;
begin
    Decode := nil;
    if (not Assigned(reader)) or (len < SizeOf(header)) then Exit;
    if reader(context, 0, @header, SizeOf(header)) <> SizeOf(header) then Exit;
    if (header.ImageType <> 2) or (header.ColorMapType <> 0) then Exit;
    if (header.ImageDescriptor and $C0) <> 0 then Exit;
    if (header.PixelDepth <> 24) and (header.PixelDepth <> 32) then Exit;
    width := header.Width;
    height := header.Height;
    if (width = 0) or (height = 0) then Exit;
    if destWidth = 0 then destWidth := width;
    if destHeight = 0 then destHeight := height;
    if (destWidth > $FFFF) or (destHeight > $FFFF) then Exit;
    if destHeight > High(uint32) div SizeOf(TRGB32) div destWidth then Exit;

    pixelBytes := header.PixelDepth div 8;
    rowBytes := width * pixelBytes;
    dataOffset := SizeOf(header) + header.IDLength;
    if dataOffset > len then Exit;
    if height > (len - dataOffset) div rowBytes then Exit;

    cropWidth := width;
    cropHeight := height;
    if width * destHeight > height * destWidth then
        cropWidth := (height * destWidth) div destHeight
    else cropHeight := (width * destHeight) div destWidth;
    if cropWidth = 0 then cropWidth := 1;
    if cropHeight = 0 then cropHeight := 1;
    cropLeft := (width - cropWidth) div 2;
    cropTop := (height - cropHeight) div 2;

    row := PUInt8(kalloc(rowBytes));
    texture := core.gfx.texture.newTexture(destWidth, destHeight);
    dest := texture^.Pixels;
    previousY := High(uint32);
    for y := 0 to destHeight - 1 do begin
        sourceY := cropTop + (y * cropHeight) div destHeight;
        if (header.ImageDescriptor and $20) = 0 then sourceY := height - 1 - sourceY;
        if sourceY <> previousY then begin
            if reader(context, dataOffset + sourceY * rowBytes, row, rowBytes) <> rowBytes then begin
                kfree(void(texture^.Pixels));
                kfree(void(texture));
                kfree(void(row));
                Exit;
            end;
            previousY := sourceY;
        end;
        for x := 0 to destWidth - 1 do begin
            sourceX := cropLeft + (x * cropWidth) div destWidth;
            if (header.ImageDescriptor and $10) <> 0 then sourceX := width - 1 - sourceX;
            pixel := row + sourceX * pixelBytes;
            dest^.B := pixel[0];
            dest^.G := pixel[1];
            dest^.R := pixel[2];
            if pixelBytes = 4 then dest^.A := pixel[3]
            else dest^.A := $FF;
            Inc(dest);
        end;
    end;
    kfree(void(row));
    Decode := texture;
end;

function ReadBuffer(context : Pointer; offset : uint32; buffer : PUInt8;
                    length : uint32) : uint32;
begin
    System.Move((PUInt8(context) + offset)^, buffer^, length);
    ReadBuffer := length;
end;

function Parse(buffer : PUInt8; len : uint32) : PTexture;
begin
    Parse := nil;
    if buffer <> nil then Parse := Decode(@ReadBuffer, buffer, len, 0, 0);
end;

function ParseScaled(reader : TTargaRead; context : Pointer; len, width, height : uint32) : PTexture;
begin
    ParseScaled := nil;
    if (width <> 0) and (height <> 0) then
        ParseScaled := Decode(reader, context, len, width, height);
end;

end.